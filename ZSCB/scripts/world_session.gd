extends RefCounted
## Ownership for desktop team slots. The local controller serializes ownership changes with flock.
const Roles = preload("res://scripts/divine_roles.gd")
const SERVICE := "res://tools/world_service.py"
static var held := {}
static var tracked := {}
static var draining := {}
static var blocked := {}
static var live := {}

static func available() -> bool:
	return OS.get_name() in ["macOS","Linux"] and FileAccess.file_exists("/usr/bin/python3") and FileAccess.file_exists(SERVICE) and not ProjectSettings.globalize_path(SERVICE).begins_with("res:")

static func run(action: String, id: String, extra := []) -> Dictionary:
	if not available(): return {"ok":false,"message":"本机未安装后台世界服务。"}
	var args := PackedStringArray([ProjectSettings.globalize_path(SERVICE),action,"--data",OS.get_user_data_dir(),"--slot",id,"--pid",str(OS.get_process_id())])
	args.append_array(extra)
	var out := []
	var result := OS.execute("/usr/bin/python3",args,out)
	if not out.is_empty():
		var row = JSON.parse_string(str(out[0]).strip_edges())
		if row is Dictionary: return row
	return {"ok":false,"message":"无法操作本机世界进程 (%d)。" % result}

static func folder(id: String) -> String:
	return "user://team_worlds_v1".path_join(id).path_join(".runtime")

static func control(id: String) -> Dictionary:
	var file := FileAccess.open(folder(id).path_join("control.json"),FileAccess.READ)
	if file == null: return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}

static func claim(id: String, background := false, generation := "", ticket := "", revision := 0) -> Dictionary:
	if not available(): return {"ok":not background}
	if held.has(id): return {"ok":true}
	var options := ["--kind","background" if background else "foreground","--generation",generation]
	if not ticket.is_empty(): options.append_array(["--ticket",ticket,"--revision",str(revision)])
	var result := run("claim",id,options)
	if result.ok:
		held[id] = true
		tracked[id] = background or result.get("enabled",false)
		blocked[id] = {}
		live[id] = {}
		for entry in DirAccess.get_files_at(folder(id)):
			if entry.ends_with(".pending"):
				blocked[id][entry.get_slice(".",0)] = true
	return result

static func release(id: String) -> void:
	if held.erase(id): run("release",id)
	tracked.erase(id)
	blocked.erase(id)
	live.erase(id)
	draining.erase(id)

static func save_limits(id: String, service) -> bool:
	if not (tracked.get(id,false) or draining.has(id)): return true
	var path := folder(id).path_join("limits.json")
	var encoded := JSON.stringify(service.handoff_limits())
	var previous := FileAccess.open(path,FileAccess.READ)
	if previous != null:
		var unchanged := previous.get_as_text() == encoded
		previous.close()
		if unchanged: return true
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return false
	var ok := file.store_string(encoded)
	file.flush()
	ok = ok and file.get_error() == OK
	file.close()
	return ok and DirAccess.rename_absolute(path+".tmp",path)==OK

static func restore_limits(id: String, service) -> void:
	if not tracked.get(id,false): return
	var file := FileAccess.open(folder(id).path_join("limits.json"),FileAccess.READ)
	if file != null:
		var value = JSON.parse_string(file.get_as_text())
		if value is Dictionary: service.restore_handoff_limits(value)

static func start_background(id: String) -> Dictionary:
	return run("start",id,["--project",ProjectSettings.globalize_path("res://"),"--godot",OS.get_executable_path()])

static func permits(id: String, role: String) -> bool:
	return not draining.has(id) and not blocked.get(id,{}).has(role)

static func register_call(id: String, role: String, request_id: String) -> bool:
	if not permits(id,role): return false
	if not tracked.get(id,false): return true
	var marker := folder(id).path_join("%s.%s.pending" % [role,request_id])
	var file := FileAccess.open(marker,FileAccess.WRITE)
	if file == null: return false
	file.store_line(request_id)
	file.flush()
	file.close()
	live[id][request_id] = marker
	return true

static func finish_call(game, request_id: String) -> void:
	if not is_instance_valid(game) or not game.is_inside_tree() or game.get_tree().current_scene != game or not is_instance_valid(game.medieval_world): return
	var id: String = game.team_slot.get("slot_id","")
	if not live.get(id,{}).has(request_id): return
	# The synchronous actor callback has already applied its receipt. A revision commits all
	# inventories and actions together, before this paid turn can be considered settled.
	if game.save_game():
		DirAccess.remove_absolute(live[id][request_id])
		live[id].erase(request_id)
	else:
		blocked[id][str(live[id][request_id]).get_file().get_slice(".",0)] = true

static func settle_cancelled(game_ref: WeakRef, ticket: String) -> void:
	finish_call(game_ref.get_ref(),ticket)

static func acknowledge(id: String) -> void:
	if not held.has(id): return
	for entry in DirAccess.get_files_at(folder(id)):
		if entry.ends_with(".pending") and blocked.get(id,{}).has(entry.get_slice(".",0)):
			DirAccess.remove_absolute(folder(id).path_join(entry))
	blocked[id] = {}

static func has_requests(game) -> bool:
	for node_name in Roles.NODES.values():
		var actor = game.medieval_world.get_node_or_null(node_name)
		if actor != null and is_instance_valid(actor.worker) and not actor.worker._request_id.is_empty():
			return true
	return false

