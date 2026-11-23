extends Node
## Worker bridge for one actor's session-bound model connection and correlated reply.
signal finished(observation: Dictionary, command: Dictionary, error: String)
signal binding_changed

const WorldSession := preload("res://scripts/world_session.gd")
const WORKER := "res://tools/east_painter.mjs"
const TIMEOUT_MS := 60000
const MAX_REPLY_BYTES := 32768
var worker_resource := WORKER
var request_directory := "user://east_painter"
var actor_role := "companion"
var use_painter_mailbox := true
var last_request_path := ""
var last_reply_path := ""
var rejected_building := {}
var last_error_code := ""
var _observation := {}
var _request_id := ""
var _pid := -1
var _pipes := {}
var _deadline := 0
var _next_poll := 0
var _mailbox := false
var _scope := {}
var _accepted_command := {}

func _ready() -> void:
	ModelConnections.role_changed.connect(_on_role_changed)
	ModelConnections.connection_changed.connect(_on_connection_changed)
	set_process(false)

func _fixture_directory() -> String:
	if not use_painter_mailbox or not OS.is_debug_build(): return ""
	var profile := str(ProjectSettings.get_setting("application/config/name",""))
	if not profile.begins_with("PaperCastleCheck_") and not profile.begins_with("PaperFrontierPlaytest_"): return ""
	var mailbox := OS.get_environment("ZHIJIAN_PAINTER_MAILBOX")
	return mailbox if mailbox.is_absolute_path() else ""

func is_fixture() -> bool:
	return _mailbox

func can_request() -> bool:
	var id: String = _current_world_identity().get("slot_id","")
	return WorldSession.permits(id,actor_role) and (not _fixture_directory().is_empty() or ModelConnections.role_status(actor_role).ready)

func accepts_command(command: Dictionary) -> bool:
	return not command.is_empty() and command==_accepted_command

func request_segment(observation: Dictionary) -> bool:
	if not _request_id.is_empty() or observation.get("busy",false): return false
	var directory := _fixture_directory()
	var grant := {} if not directory.is_empty() else ModelConnections.worker_grant(actor_role)
	return _start(observation,grant,directory)

func request_diagnostic(grant: Dictionary, operation: String) -> bool:
	if not _request_id.is_empty() or operation not in ["models","test"]: return false
	actor_role="diagnostic"
	request_directory="user://connection_checks"
	return _start({"kind":operation},grant,"")

func _current_world_identity() -> Dictionary:
	if actor_role=="diagnostic": return {}
	var actor := get_parent()
	if actor==null or not "game" in actor: return {}
	var game = actor.game
	if not is_instance_valid(game) or not "team_slot" in game or game.team_slot.is_empty(): return {}
	var slot: Dictionary = game.team_slot
	return {"slot_id":slot.slot_id,"team_id":slot.team_id,"world_id":slot.world_id}

func _start(observation: Dictionary, grant: Dictionary, directory: String) -> bool:
	rejected_building = {}
	last_error_code = ""
	_accepted_command = {}
	_observation = observation.duplicate(true)
	var identity := _current_world_identity()
	if not identity.is_empty():
		_observation.world_identity = identity
		var game = get_parent().game
		if "medieval_world" in game and is_instance_valid(game.medieval_world) and "chronicle" in game.medieval_world and game.medieval_world.chronicle != null:
			var reports: Dictionary = game.medieval_world.chronicle.role_reports()
			if not reports.is_empty(): _observation.world_reports = reports
	_request_id = Crypto.new().generate_random_bytes(12).hex_encode()
	_mailbox = not directory.is_empty()
	_scope = {}
	if not _mailbox:
		var status := ModelConnections.role_status(actor_role)
		if grant.is_empty():
			_report_failure.call_deferred(_request_id,status.code,status.message)
			return true
		for key in ["id","role","generation","provider","model"]: _scope[key]=grant.get(key)
		_scope.owner_id=get_instance_id()
		directory = ProjectSettings.globalize_path(request_directory)
	last_request_path = directory.path_join(_request_id + ".observation.json")
	last_reply_path = directory.path_join(_request_id + ".reply.json")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(last_request_path + ".tmp", FileAccess.WRITE) if error == OK else null
	if file == null:
		_report_failure.call_deferred(_request_id,"io_error","无法写入角色的观测记录。")
		return true
	file.store_string(JSON.stringify({"request_id":_request_id,"observation":_observation}))
	file.close()
	if DirAccess.rename_absolute(last_request_path+".tmp",last_request_path)!=OK:
		_report_failure.call_deferred(_request_id,"io_error","无法交付本次角色观测。")
		return true
	var building: bool = observation.get("invitation",{}).get("kind","") in ["building_design","building_variant"]
	_deadline = Time.get_ticks_msec() + (600000 if _mailbox else 20000 if actor_role=="diagnostic" else 180000 if building or (actor_role=="priest" and observation.get("priest_protocol")=="species-ink-v1") else TIMEOUT_MS)
	_next_poll = 0
	if not WorldSession.register_call(identity.get("slot_id",""),actor_role,_request_id):
		_report_failure.call_deferred(_request_id,"handoff","该角色正交接世界或有待核对的回合。")
		return true
	if not _mailbox and not _launch(grant):
		_report_failure.call_deferred(_request_id,"runtime_error","无法启动模型运行时，请检查本机 Node.js 或 DeepSeek Harness 的安装。")
		return true
	set_process(true)
	return true

func _launch(grant: Dictionary) -> bool:
	if not FileAccess.file_exists(worker_resource): return false
	var args := PackedStringArray([ProjectSettings.globalize_path(worker_resource),last_request_path,last_reply_path,"--player-connection"])
	if actor_role=="diagnostic": args.append("--diagnostic")
	for runtime in _runtime_options():
		var invocation := PackedStringArray(runtime.args)
		invocation.append_array(args)
		_pipes=OS.execute_with_pipe(runtime.path,invocation,false)
		if _pipes.has("stdio"): break
	if not _pipes.has("stdio"): return false
	_pid=int(_pipes.get("pid",-1))
	var pipe: FileAccess = _pipes.stdio
	if _pid>0 and pipe.store_line(JSON.stringify(grant)):
		pipe.flush()
		return true
	_stop()
	return false

func _runtime_options() -> Array:
	if OS.get_name()=="Windows": return [{"path":"node.exe","args":[]}]
	var options := []
	for path in ["/opt/homebrew/bin/node","/usr/local/bin/node","/usr/bin/node"]:
		if FileAccess.file_exists(path): options.append({"path":path,"args":[]})
	if OS.get_name()=="macOS":
		var suffix := "DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness"
		for folder in ["/Applications",OS.get_environment("HOME").path_join("Applications")]:
			var app: String = folder.path_join(suffix)
			if FileAccess.file_exists(app):
				options.append({"path":"/usr/bin/env","args":["ELECTRON_RUN_AS_NODE=1",app]})
				break
	options.append({"path":"/usr/bin/env","args":["node"]})
	return options

func _reply_matches(reply: Dictionary) -> bool:
	if _mailbox: return true
	if actor_role!="diagnostic" and not ModelConnections.is_current(_scope): return false
	var given = reply.get("connection")
	if not given is Dictionary: return false
	for key in ["id","role","provider","model"]:
		if given.get(key)!=_scope.get(key): return false
	return typeof(given.get("generation")) in [TYPE_FLOAT,TYPE_INT] and given.generation==_scope.generation

func _process(_delta: float) -> void:
	if _observation.has("world_identity") and _observation.world_identity != _current_world_identity():
		cancel()
		return
	var now := Time.get_ticks_msec()
	if now < _next_poll: return
	_next_poll = now + 100
	if FileAccess.file_exists(last_reply_path):
		var file := FileAccess.open(last_reply_path, FileAccess.READ)
		var reply: Variant = null
		if file != null and file.get_length()<=MAX_REPLY_BYTES: reply=JSON.parse_string(file.get_as_text())
		if not reply is Dictionary or reply.get("request_id")!=_request_id:
			_finish({},"invalid_response","本次模型回执无法识别。")
		elif not _reply_matches(reply):
			_finish({},"invalid_response","模型回执与本次角色连接不一致。")
		elif not reply.get("command") is Dictionary or not _mailbox and (reply.command.get("provider")!=_scope.provider or reply.command.get("model")!=_scope.model):
			if _observation.has("building"): _remember_rejected(reply)
			_finish({},str(reply.get("error_code","invalid_response")),str(reply.get("error","模型未交付可以执行的动作。")).left(120))
		else:
			_finish(reply.command,"","")
	elif now >= _deadline:
		_finish({},"timeout","模型回应超时，请稍后重试。")
	elif not _mailbox and not OS.is_process_running(_pid) and not FileAccess.file_exists(last_reply_path):
		_finish({},"runtime_error","模型进程已结束，尚未收到本次回执。")

func _remember_rejected(reply: Dictionary) -> void:
	var drafts = reply.get("rejected_drafts",[])
	var evidence = reply.get("evidence_file","")
	if drafts is Array and drafts.is_empty() and evidence==last_reply_path.get_file()+".evidence.json":
		var sidecar := FileAccess.open(last_reply_path+".evidence.json",FileAccess.READ)
		if sidecar!=null and sidecar.get_length()<=524288:
			var full = JSON.parse_string(sidecar.get_as_text())
			if full is Dictionary and full.get("request_id")==_request_id and _reply_matches(full): drafts=full.get("rejected_drafts",[])
	if not drafts is Array or drafts.is_empty() or not drafts.back() is Dictionary: return
	var previous: Dictionary = drafts.back()
	var call = previous.get("tool_call")
	if call is Dictionary and call.get("arguments") is Dictionary:
		rejected_building={"reason":str(previous.get("reason","")).left(500),"tool":str(call.get("name","")),
			"call_id":str(call.get("id","")),"args":call.arguments}

func _report_failure(request_id: String, code: String, error: String) -> void:
	if request_id==_request_id: _finish({},code,error)

func _finish(command: Dictionary, code: String, error: String) -> void:
	if not _scope.is_empty():
		if code.is_empty(): ModelConnections.note_success(_scope)
		else: ModelConnections.note_failure(_scope,code)
	var settled_id := _request_id
	var game = get_parent().get("game") if not _current_world_identity().is_empty() else null
	_stop()
	last_error_code=code
	_accepted_command=command.duplicate(true)
	finished.emit(_observation,command,error)
	WorldSession.finish_call(game,settled_id)

func _stop() -> void:
	set_process(false)
	if _pid>0 and OS.is_process_running(_pid): OS.kill(_pid)
	_pid=-1
	_pipes.clear()
	_request_id=""
	_scope.clear()

func cancel() -> void:
	var cancelled_id := _request_id
	var game = get_parent().get("game") if not _current_world_identity().is_empty() else null
	_stop()
	if not cancelled_id.is_empty() and is_instance_valid(game):
		# An explicit binding change or pause cancels this ticket. Let its owner finish
		# updating local state before checkpointing. Disappearing worlds keep their marker.
		WorldSession.settle_cancelled.call_deferred(weakref(game),cancelled_id)
	_accepted_command.clear()

func _on_role_changed(role: String) -> void:
	if role!=actor_role: return
	if not _request_id.is_empty() and not _mailbox:
		_finish({},"reconfigured","角色连接已变化，本次请求已停止。")
	binding_changed.emit()

func _on_connection_changed(id: String) -> void:
	if actor_role=="diagnostic" and id==_scope.get("id") and not _request_id.is_empty():
		_finish({},"reconfigured","设置已变化，本次连接检查已停止。")

func _exit_tree() -> void:
	ModelConnections.clear_owner_delay(actor_role,get_instance_id())
	cancel()
