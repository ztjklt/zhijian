extends Node2D
## One physical companion, one observation stream and one action at a time.
const ChannelPlan := preload("res://scripts/painter_channel_plan.gd")
const Actor := preload("res://scripts/companion_actor.gd")
const Senses := preload("res://scripts/companion_senses.gd")
const Witness := preload("res://scripts/village_witness.gd")
const Transport := preload("res://scripts/east_painter.gd")
const Brush := preload("res://scripts/companion_brush.gd")
const Identity := preload("res://scripts/sandbox_identity.gd")
const Autonomy := preload("res://scripts/sandbox_autonomy.gd")
const SceneProjects := preload("res://scripts/painter_scene_projects.gd")
const AccessRevision = preload("res://scripts/architecture/building_access_revision.gd")
const SceneWaterBody := preload("res://scripts/painter_scene_water_body.gd")
const SceneComponent := preload("res://scripts/painter_scene_component.gd")
const SceneFrame := preload("res://scripts/painter_scene_frame.gd")
const DISTANT_SHEET_PATH := "res://scripts/distant_sheet.gd"
const BUILDING_SURVEY_PATH := "res://scripts/architecture/building_survey.gd"
const BuildingPlans := preload("res://scripts/architecture/building_plans.gd")
const PlantReview := preload("res://scripts/painter_plant_review.gd")
const LocalWalk := preload("res://scripts/local_role_walk.gd")
const WorldPen := preload("res://scripts/paper_world_pen.gd")
const INDIGO := Color("394f85")
const DISPLAY_NAME := "阿靛"
const IDENTITY_LABEL := "阿靛 · 至高神画家"
const PenReach := preload("res://scripts/companion_pen_reach.gd")
const REACH := PenReach.BRUSH_LENGTH
const INK_SPEED := 2.9
const EDGE_SENSOR_REACH := 9.0
const HOME_X := 3.4
var game
var world
var actor
var worker
var phase := "arrival"
var caption := ""
var last_observation := {}
var last_command := {}
var last_result := {}
var dialogue: Array = []
var divine_messages: Array = []
var divine_job := {}
var divine_running := false
var divine_progress := ""
const ChatRoles:=preload("res://scripts/divine_roles.gd")
var held_chat: Array = []
var divine_draft := ""
var divine_work_ids: Array = []
var scene_projects := SceneProjects.new()
const StudyIndex := preload("res://scripts/atlas_study_index.gd")
var study_filters := {}
var study_scope := ""
var scene_trade_poll := 0.0
var plant_draft := {}
var invitation := {}
var queued_frontier := ""
var nib_world := Vector2.INF
var ticket := ""
var start_at := Vector2.ZERO
var target_x := 0.0
var walk_goal := Vector2.INF
var walk_plan := {}
var destination := ""
var clock := 0.0
var wait_for_change := false
var idle_retry_after := 18.0
var autonomy := Autonomy.new()
var local_walk := LocalWalk.new(-1)
var autonomous_execution := false
var company_left := 0.0
var walk_timeout := 7.0
var target_npc := ""
var npc_question := ""
var speech := {}
var speech_time := 0.0
var pen_stands := []
var channel_validation_epochs := {}
var paper_stands := []
var paper_route := {}
var paper_route_goal := Vector2.INF
var paper_settle := 0.0
var last_paper_reach := {}
var pen_invitation := {}
var pen_command := {}
var reference_command := {}
var study_rect := Rect2()
var study_revision := 0
var design_draft := {}
var unfinished_building := {}
var chosen_build_site := {}
var plan_access_target := Vector2.INF
var pen_lines: Array = []
var pen_stroke := 0
var pen_point := 0
var pen_from := Vector2.ZERO
var reach_jump := false
var route_down := false
var stopped_time := 0.0
var last_body_x := INF
var pen_trace: Array = []
var pen_wash_meshes: Dictionary = {}
var active_edge_name := ""
var work_observation := {}
var restore_data := {}
var font: Font

func _ready() -> void:
	world = get_parent()
	game = world.game
	name = "SandboxCompanion"
	z_index = 4
	font = PaperTheme.create().default_font
	worker = Transport.new()
	worker.worker_resource = "res://tools/companion_turn.mjs"
	worker.request_directory = "user://companion_turns"
	add_child(worker)
	worker.finished.connect(_decision)
	worker.binding_changed.connect(_model_binding_changed)

func _exit_tree() -> void:
	if is_instance_valid(worker): worker.cancel()
	if phase == "thinking":
		phase = "rest"
		clock = 0.6

func _arrive() -> void:
	actor = Actor.new()
	actor.sandbox = game
	add_child(actor)
	actor.display_name = DISPLAY_NAME
	actor.character_visual.pencil.self_modulate.a = 0.0
	actor.relocate(world.safe_spawn_position(HOME_X))
	for page in world.companion_blueprints.entries:
		if not page.has("work_id"):
			page.work_id="folio-history-"+str(page.id)+"-"+str(page.name).sha256_text().left(16)
			page.author_id="companion"
			page.work_source="historical"
	phase = "rest"
	clock = 0.7
	if not restore_data.is_empty():
		autonomy.restore(restore_data.get("autonomy",{}))
		scene_projects.restore(restore_data.get("scene_projects",{}),Autonomy.scope(game))
		var pos = restore_data.get("at")
		if _pair(pos):
			var point := Vector2(pos[0],pos[1])
			if Autonomy.in_world(world,point):
				actor.relocate(point)
		var previous = restore_data.get("dialogue", [])
		for item in previous.slice(-8) if previous is Array else []:
			if item is Dictionary and item.get("speaker") is String and item.get("text") is String:
				_remember(item.speaker,item.text)
		var conversation = restore_data.get("divine_chat",{})
		if conversation is Dictionary:
			var messages = conversation.get("messages",[])
			for item in messages.slice(-16) if messages is Array else []:
				if item is Dictionary and item.get("speaker") in ["player","god","status"] and item.get("text") is String:
					_divine_message(item.speaker,item.text)
			var work_ids = conversation.get("work_ids",[])
			if work_ids is Array:
				for id in work_ids.slice(0,5):
					if id is String and id.begins_with("companion-"): divine_work_ids.append(id.left(96))
			if conversation.get("pending")==true:
				divine_progress="上回聊天已随离开结束，可以接着发话。"
			held_chat=ChatRoles.read_held_chat(conversation.get("held",[]))
			var draft = conversation.get("draft","")
			if draft is String and draft.length()<=600: divine_draft=draft
		var pending = restore_data.get("edge_action")
		if pending is Dictionary and not world.east_work_target().is_empty():
			last_command = {"tool":"paint_edge", "call_id":str(pending.get("call_id","")), "geometry_fixes":pending.get("geometry_fixes",[])}
			ticket = str(pending.get("request_id",""))
			var start = pending.get("start")
			start_at = Vector2(start[0],start[1]) if _pair(start) else actor.player.position
		autonomous_execution = restore_data.get("autonomous_execution",false)==true
		_restore_action(restore_data.get("local_action",{}))
		restore_data.clear()
	_resume_work()

func snapshot() -> Dictionary:
	if actor == null: return restore_data.duplicate(true)
	var queued:=str(divine_job.get("text","")) if not divine_running and not divine_job.has("project_id") else ""
	var data := {"at":[actor.player.position.x,actor.player.position.y], "dialogue":dialogue.duplicate(true),
		"autonomy":autonomy.snapshot(),"autonomous_execution":autonomous_execution,
		"scene_projects":scene_projects.snapshot(),
		"divine_chat":{"messages":divine_messages.duplicate(true),"work_ids":divine_work_ids.duplicate(),"pending":not divine_job.is_empty(),
			"held":ChatRoles.snapshot_held_chat(held_chat,queued,divine_draft),
			"draft":queued if divine_draft.is_empty() else divine_draft}}
	if phase == "walk" and destination in ["explore","region","edge","cross","npc"]:
		data.local_action = {"phase":"walk","destination":destination,"target_x":target_x,"left":maxf(0,walk_timeout-clock),
			"caption":caption,"name":active_edge_name,"npc":target_npc,"question":npc_question,"work":work_observation.duplicate(true),
			"command":last_command.duplicate(true),"ticket":ticket,"goal":Senses.pair(walk_goal) if walk_goal.is_finite() else []}
	elif phase == "pen" and autonomous_execution and last_command.get("tool") in ["shape_site","paper_ink"]:
		data.local_action = {"phase":"pen","command":last_command.duplicate(true),"ink":pen_command.duplicate(true),
			"stroke":pen_stroke,"point":pen_point,"from":Senses.pair(pen_from),"ticket":ticket}
	if phase=="walk" and destination=="revise_scene_access" and divine_job.has("access_move"):
		data.local_action={"phase":"walk","destination":destination,"command":last_command.duplicate(true),"ticket":ticket,
			"move":divine_job.access_move.duplicate(true),"brief":divine_job.text,"left":maxf(0,walk_timeout-clock)}
	if world.east_painting():
		data.edge_action = {"call_id":last_command.get("call_id",""), "geometry_fixes":last_command.get("geometry_fixes",[]),
			"request_id":ticket, "start":Senses.pair(start_at)}
	return data

func _restore_action(action: Variant) -> void:
	if not action is Dictionary or not action.get("command") is Dictionary: return
	last_command = action.command.duplicate(true)
	ticket = str(action.get("ticket","")).left(24)
	start_at = actor.player.position
	if action.get("phase")=="walk" and action.get("destination") in ["explore","region","edge","cross","npc"]:
		var x = action.get("target_x")
		var limits := Autonomy.motion_bounds(world)
		if not (x is int or x is float) or not is_finite(x) or x<limits.position.x or x>limits.end.x+.2: return
		if action.destination=="edge" and not action.get("work") is Dictionary: return
		var goal=action.get("goal",[])
		_go(x,action.destination,_words(action.get("caption","继续走")),Vector2(goal[0],goal[1]) if _pair(goal) else Vector2.INF)
		walk_timeout = clampf(float(action.get("left",7)),.1,125.0)
		active_edge_name = _words(action.get("name",""))
		work_observation = action.get("work",{}).duplicate(true)
		target_npc = str(action.get("npc","")).left(100)
		npc_question = _words(action.get("question",""))
	elif action.get("phase")=="walk" and action.get("destination")=="revise_scene_access" and last_command.get("tool")=="revise_scene_access":
		var move=action.get("move")
		if not move is Dictionary or not _pair(move.get("feet")):return
		divine_running=true
		divine_job={"text":str(action.get("brief","")).left(600),"access_move":move.duplicate(true)}
		var check:=AccessRevision.prepare(game,move)
		if check.has("error"):
			_finish(false,check.error)
			return
		var at:=Vector2(move.feet[0],move.feet[1])
		_go(at.x,"revise_scene_access","继续试走本队的新使用位",at)
		walk_timeout=clampf(float(action.get("left",7)),.1,125)
	elif action.get("phase")=="pen" and autonomous_execution and last_command.get("tool") in ["shape_site","paper_ink"] and action.get("ink") is Dictionary:
		_start_pen(action.ink)
		if phase!="pen": return
		var stroke := int(action.get("stroke",0))
		if stroke<0 or stroke>=pen_lines.size(): return
		var point := int(action.get("point",1))
		if point<1 or point>=pen_lines[stroke].size() or not _pair(action.get("from")): return
		var cursor := Vector2(action.from[0],action.from[1])
		if cursor.distance_to(Geometry2D.get_closest_point_to_segment(cursor,pen_lines[stroke][point-1],pen_lines[stroke][point]))>.03: return
		pen_stroke=stroke
		pen_point=point
		pen_from=cursor
		pen_trace.clear()
		pen_wash_meshes.clear()
		for index in stroke: pen_trace.append(pen_lines[index])
		pen_trace.append(pen_lines[stroke].slice(0,point))
		var visible: PackedVector2Array=pen_trace.back()
		visible.append(cursor)
		pen_trace[stroke]=visible

func _resume_work() -> void:
	if world.east_work_target().is_empty(): return
	last_command.tool = "paint_edge"
	active_edge_name = world.east_work_name()
	phase = "work"
	caption = "接着画「%s」" % active_edge_name

func observation_target() -> Vector2:
	return actor.player.position if is_instance_valid(actor) else Vector2.INF

func has_active_brush() -> bool:
	return not queued_frontier.is_empty() or world.east_painting() or phase in ["pen","work"] or (phase == "walk" and destination in ["edge","cross"]) \
		or (phase in ["rest","thinking"] and invitation.get("kind") in ["paint","pen","copy","building_design","building_variant"])

func frontier_blocker() -> String:
	if actor == null: return "等阿靛来到身边"
	if has_active_brush() or (phase in ["thinking","rest"] and not invitation.is_empty()):
		return "等阿靛完成眼前这一轮"
	if not worker.can_request(): return str(ModelConnections.role_status("companion").message)
	if not game.map_controls.at_frontier(): return "先从地图前往东侧纸边"
	if actor.player.position.distance_to(game.player.position) > 10.0: return "按 J 叫阿靛到身边"
	if not _sees_edge(): return "请让阿靛靠近东侧纸边，或按 J 叫到身边"
	if not world.east_has_room(): return "这张纸已画满，可以保存作品"
	return ""

func _refresh_channel_checks(project:Dictionary, force:=false) -> void:
	if project.get("channel_plan",{}).is_empty() or world.paper_space==null:return
	var epoch:int=world.paper_space.epoch
	if not force and channel_validation_epochs.get(project.project_id)==epoch:return
	channel_validation_epochs[project.project_id]=epoch
	ChannelPlan.link_water_works(world,project)
	for item:Dictionary in project.channel_plan.sections:
		if item.get("verified",false):ChannelPlan.measure(world,project,item.id)

func divine_status() -> Dictionary:
	var reason := frontier_blocker()
	var connection := ModelConnections.role_status("companion")
	var status := {"phase":"idle","summary":"候笔" if worker.can_request() else "等连接 · 候笔",
		"can_start":reason.is_empty(),"start_hint":reason,"action_label":"看看阿靛","name":"",
		"decision_source":"等待模型决策" if connection.ready else "模型连接暂不可用"}
	if not queued_frontier.is_empty():
		status.phase = "queued"
		status.summary = "已接下续画，等手头这一轮完成"
	elif phase == "work" or phase == "pen":
		var title := _words(active_edge_name if phase == "work" else pen_command.get("name",""))
		status.phase = "drawing"
		status.name = title
		status.action_label = "看当前运笔"
		status.summary = "正在画「%s」" % title if not title.is_empty() else "正在运笔"
	elif phase == "walk" and destination in ["edge","cross"]:
		status.phase = "crossing" if destination == "cross" else "walking"
		status.name = active_edge_name if destination == "cross" else _words(work_observation.get("name",""))
		status.summary = "正在试走新画的路" if destination == "cross" else "正在走向东侧纸边"
	elif phase == "thinking" or (phase == "rest" and not invitation.is_empty()):
		status.phase = "thinking"
		status.summary = "正在观察四周" if invitation.is_empty() else "正在构思续画" if invitation.get("kind") == "paint" else "正在处理眼前的委托"
	elif phase == "arrival":
		status.summary = "正在进入工地"
	elif phase == "speak":
		status.phase = "speaking"
		status.summary = "正在交谈"
	elif phase == "walk":
		status.phase = "walking"
		status.summary = caption if not caption.is_empty() else "正在走路"
	elif phase == "offline" and not caption.is_empty():
		status.phase = "offline"
		status.summary = caption
	if company_left>0:
		status.phase="company"
		status.summary="暂时与你同行"
	status.merge(autonomy.status(connection))
	if company_left>0:
		status.decision_source="玩家邀请"
	elif _waiting_at_access():
		status.summary="在使用位等你"
		status.progress="正在等候交接"
		status.decision_source="玩家安排"
		status.pause_reason=""
	elif autonomy.paused and (autonomous_execution or phase in ["rest","offline"] and invitation.is_empty()):
		status.decision_source="自主已暂停"
	elif _can_survey_locally(connection):
		status.merge(local_walk.view("本地勘察"),true)
	elif phase in ["work","pen","walk","speak"] and not last_command.get("call_id","").is_empty():
		status.decision_source="模型决策 · 执行中"
	if phase=="pen":
		status.progress="第 %d／%d 笔"%[pen_stroke+1,pen_lines.size()]
	elif phase=="work":
		var ink: Dictionary=world.east_work_target(0)
		if ink.get("phase")=="ground":status.progress="地表已落笔到 %.2f 米"%ink.from.x
		elif ink.has("stroke"):status.progress="正在勾画地标第 %d 笔"%[int(ink.stroke)+1]
	elif phase=="walk" and actor!=null:
		status.progress="离落脚点 %.1f 米"%absf(target_x-actor.player.position.x)
	var project := scene_projects.active()
	_refresh_channel_checks(project)
	if not project.is_empty() and project.stage in ["working","awaiting_trade","paused"]:
		status.goal=project.title
		status.reason=str(scene_projects.step().get("aim","等待摊位成交"))
		if not divine_running and phase=="rest":
			status.summary="工程等候成交" if project.stage=="awaiting_trade" else "工程暂停" if project.stage=="paused" else "工程工序交接"
			if project.stage=="paused" and not project.outcomes.is_empty():
				status.progress=str(project.outcomes.back().get("detail",""))
				if scene_projects.step().get("kind")=="water":status.summary="水域工序未验收 · 工程暂停"
			var sections:Array=project.get("channel_plan",{}).get("sections",[])
			if not sections.is_empty():
				var verified:int=sections.filter(func(row):return row.get("verified",false)).size()
				status.progress="水道 %d／%d 段已验"%[verified,sections.size()]
				for item:Dictionary in sections:
					if item.get("verified",false):continue
					var measure:Dictionary=item.get("measurement",{})
					if not measure.is_empty():
						status.progress+=" · %.2f／%.2f 米已见开口"%[measure.clear_span_m,measure.planned_span_m]
					elif not item.work_ids.is_empty():status.progress+=" · 当前段已落笔，待查验"
					else:status.progress+=" · 当前段待实际落笔"
					break
			var receipt:Dictionary=project.get("trade_receipt",{})
			if not receipt.is_empty():
				status.trade_receipt=receipt.get("detail","柜台已有一笔实际成交")
				if scene_projects.step().get("kind")=="verify":
					status.reason="柜台已成交，待阿靛从留存旧路实走至新柜并验脚。"
	return status

func set_autonomy_paused(value: bool) -> void:
	autonomy.set_paused(value)
	if value: local_walk.interrupt()
	if value and phase=="thinking" and (autonomous_execution or _automatic_scene_turn()) and queued_frontier.is_empty():
		worker.cancel()
		if _automatic_scene_turn():
			invitation={}
			_close_divine_job("已暂停本回合，已落笔稿和项目进度保留。")
		phase = "rest"
	elif not value and phase=="rest" and not _waiting_at_access(): clock=minf(clock,.4)

func set_action_budget(value: int) -> void:
	autonomy.set_budget(value)

func start_creation() -> bool:
	return game.map_controls.request_frontier()

func divine_chat_status() -> Dictionary:
	var progress:=divine_progress
	var active:=not divine_job.is_empty()
	var connection:=ModelConnections.role_status("companion")
	var chat_phase:="ready" if not active else "queued" if not divine_running else "sent" if phase in ["rest","thinking"] else "executing"
	if divine_running and phase=="pen": progress="「%s」· 第 %d／%d 笔"%[pen_command.get("name","接纸"),pen_stroke+1,pen_lines.size()]
	elif divine_running and phase=="work": progress="正在续画「%s」 · 新地表已到 %.1f 米"%[active_edge_name,world.east_walk_limit()]
	elif divine_running and phase=="walk": progress="%s · 还要走 %.1f 米"%[caption,absf(target_x-actor.player.position.x)]
	return {"messages":divine_messages.duplicate(true),"pending":active,"progress":progress,"chat_phase":chat_phase,
		"can_send":not active and is_instance_valid(actor) and worker.can_request(),"connection_code":connection.code,"draft":divine_draft}

func submit_divine_chat(text: String, recovered:=false) -> Dictionary:
	if text.strip_edges().is_empty() or text.length()>600:
		return {"ok":false,"code":"length","message":"请写下 1 到 600 字的想法。"}
	if not is_instance_valid(actor) or get_tree().current_scene!=game or world!=game.medieval_world:
		return {"ok":false,"code":"unavailable","message":"阿靛尚未进入本局。"}
	if not divine_job.is_empty(): return {"ok":false,"code":"busy","message":"阿靛正在处理上句话。"}
	if not worker.can_request():
		var status:=ModelConnections.role_status("companion")
		return {"ok":false,"code":status.code,"message":status.message}
	var from:Vector2=game.player.position
	divine_job={"text":text,"player_at":Senses.pair(from),"travel_left":2}
	divine_draft=""
	if not recovered or ChatRoles.original_chat_line(divine_messages,text).is_empty():_divine_message("player",text)
	divine_progress="已排队，尚未请求服务商。"
	return {"ok":true,"message":divine_progress}

func _divine_message(speaker: String, text: String) -> void:
	if text.is_empty() or text.length()>600: return
	divine_messages.append({"speaker":speaker,"text":text})
	if divine_messages.size()>16: divine_messages.pop_front()

func _close_divine_job(text: String, spoken := false) -> void:
	_divine_message("god" if spoken else "status",text)
	divine_progress=text
	divine_job={}
	divine_running=false

func _dispatch_divine_chat() -> void:
	if divine_job.is_empty() or divine_running: return
	if not worker.can_request():
		if not divine_job.has("project_id"):
			held_chat=ChatRoles.snapshot_held_chat(held_chat,divine_job.text,divine_draft)
			if divine_draft.is_empty():divine_draft=divine_job.text
		_close_divine_job(ModelConnections.role_status("companion").message)
		return
	if not invitation.is_empty(): return
	if phase not in ["rest","offline"] and not (phase=="walk" and autonomous_execution and destination not in ["edge","cross"]): return
	company_left=0.0
	reference_command.clear()
	var kind := "building_variant" if divine_job.has("edit_plan") else "building_design" if divine_job.has("project_id") and scene_projects.step().get("kind")=="building" else "divine_chat"
	invitation={"kind":kind,"text":divine_job.text,"slot":int(divine_job.get("edit_plan",0))}
	divine_running=true
	divine_progress="正在整理发给阿靛的现场。"
	phase="rest"
	clock=0.0
	wait_for_change=false

func atlas_projects() -> Array:
	if world!=null:
		for project in scene_projects.entries:
			_observe_scene_trade(project)
			_refresh_channel_checks(project)
	return scene_projects.list()

func resume_scene_project(project_id: String) -> bool:
	if not divine_job.is_empty() or not invitation.is_empty() or not queued_frontier.is_empty() or phase not in ["rest","offline"]:return false
	for project in scene_projects.entries:
		if project.project_id!=project_id or project.stage!="paused":continue
		var previous:=scene_projects.active()
		if previous.get("stage")=="working":previous.stage="paused"
		scene_projects.active_id=project_id
		project.stage="working"
		project.player_resumed=true
		project.attempts=0
		project.moves=0
		local_walk.interrupt()
		phase="rest"
		clock=0.0
		_divine_message("status","接着做「%s」，保留已完成的作品。"%project.title)
		return true
	return false

func _continue_scene_project() -> void:
	if phase!="rest" or clock>0 or not divine_job.is_empty() or not queued_frontier.is_empty() or not invitation.is_empty():return
	var project := scene_projects.active()
	if project.is_empty():return
	if project.stage!="working" or not worker.can_request() or company_left>0:return
	if project.get("origin")=="autonomous" and not project.get("player_resumed",false) and not autonomy.available():return
	if not project.get("surveyed",false):
		var stand:=WorldPen.point(project.site.get("stand"))
		if not stand.is_finite():
			project.stage="paused"
			return
		project.survey_start=Senses.pair(actor.player.position-Vector2(0,.29))
		if stand.distance_to(actor.player.position-Vector2(0,.29))>.55:
			autonomous_execution=false
			_go(stand.x,"scene_survey","走向工程「%s」"%project.title,stand)
			return
		project.surveyed=true
	divine_job={"project_id":project.project_id,"text":project.brief,"player_at":project.site.stand,"travel_left":0}
	if not str(project.get("clarification","")).is_empty():divine_job.text+="\n当前修订要求："+str(project.clarification)
	var step:=scene_projects.step()
	if step.get("kind")=="building":
		var pending:Dictionary=project.get("pending_build",{})
		if pending.is_empty() and project.has("shore_build"):
			pending=project.shore_build
			project.pending_build=pending
			project.erase("shore_build")
		if not pending.is_empty():
			divine_running=true
			last_command=pending.command
			ticket=str(pending.get("request_id",""))
			_start_scene_build_site(pending)
			return
		var stand:=WorldPen.point(project.get("foundation_site",{}).get("stand"))
		if stand.is_finite() and stand.distance_to(actor.player.position-Vector2(0,.29))>.55:
			_go(stand.x,"scene_foundation_walk","走到已经量好的岸上柜位",stand)
			return
		divine_job.text+="\n当前只设计这一项建筑：%s"%step.aim
		var outcomes: Array=project.outcomes
		var draft_start:=0
		for index in range(outcomes.size()-1,-1,-1):
			var prior_outcome:Dictionary=outcomes[index]
			if prior_outcome.get("ok",false) and (prior_outcome.get("tool")=="revise_scene_plan" or
				(prior_outcome.get("phase")=="building" and prior_outcome.has("work_id"))):
				draft_start=index+1
				break
		var recent:=outcomes.slice(draft_start).filter(func(row):return row.phase=="building" and not row.ok and row.has("plan_id"))
		if not recent.is_empty():
			var prior: Dictionary=recent.back()
			var design:=BuildingPlans._source(game,"companion",int(prior.plan_id))
			var footprint:Array=design.get("layout",{}).get("footprint",[])
			var width:=float(project.get("foundation_site",{}).get("frontage",{}).get("width_m",INF))
			if footprint.size()==2 and float(footprint[1])-float(footprint[0])>width+.02:
				divine_job.text+="\n前稿太宽，已留在图纸包。按实地净宽另画紧凑母图。"
			else:
				divine_job.edit_plan=int(prior.plan_id)
				divine_job.text+="\n母图已存，保留结构和用途，按真实场地反馈局部修正支点与使用位。最近失败："+prior.detail

func _scene_receipt_matches(row:Variant, targets:Array, scopes:Array) -> bool:
	if not row is Dictionary or row.get("action")!="stall_trade" or row.get("target") not in targets:return false
	return scopes.any(func(scope):
		return row.get("world_id")==scope.get("world_id") and row.get("team_id")==scope.get("team_id"))

func _observe_scene_trade(project:Dictionary) -> void:
	if project.stage=="complete" or project.trade_targets.is_empty() or world.survival==null or not world.survival.has_method("guild_events"):return
	var targets:Array=project.trade_targets
	var scopes:Array=[project.scope]+project.get("trade_origin_scopes",[])
	var cached:Dictionary=project.get("trade_receipts",{})
	var receipts:Dictionary={}
	var first:Dictionary=project.get("trade_receipt",{})
	var invalid_cache:=false
	if not first.is_empty():
		if _scene_receipt_matches(first,targets,scopes):receipts[first.target]=first
		else:
			first={}
			invalid_cache=true
	for target in cached:
		var row=cached[target]
		if not _scene_receipt_matches(row,targets,scopes) or row.target!=target:
			invalid_cache=true
			continue
		receipts[target]=row
		if first.is_empty():first=row
	if invalid_cache:project.trade_sequence=0
	if receipts.size()<targets.size():
		var ledger:Dictionary=world.survival.guild_events(int(project.get("trade_sequence",0)),200)
		for row:Dictionary in ledger.get("events",[]):
			project.trade_sequence=maxi(int(project.get("trade_sequence",0)),int(row.get("seq",0)))
			if not _scene_receipt_matches(row,targets,scopes) or receipts.has(row.target):continue
			receipts[row.target]=row
			if first.is_empty():first=row
			if receipts.size()==targets.size():break
	project.trade_receipts=receipts
	project.trade_receipt=first
	if not targets.all(func(id): return receipts.has(id)) or project.stage!="awaiting_trade":return
	project.stage="complete"
	var detail:="在新摊位完成实际账本交易" if targets.size()==1 else "各柜口分别完成实际账本交易"
	project.outcomes.append({"phase":"trade","ok":true,"detail":detail,"trade":first})
	if world.chronicle!=null and world.chronicle.has_method("record_scene"):
		world.chronicle.record_scene(project,first.get("at"))
	_divine_message("status","「%s」已实地验走，%s。"%[project.title,detail])

func _verify_scene_project() -> void:
	if not divine_job.has("project_id") or scene_projects.step().get("kind")!="verify":
		_finish(false,"当前没有待试走的工程")
		return
	var project:=scene_projects.active()
	var target:=Vector2.INF
	for index in range(game.objects.size()-1,-1,-1):
		var object:Dictionary=game.objects[index]
		if not object.get("work_id","") in project.work_ids or not object.has("built_plan"):continue
		var built:Dictionary=object.built_plan
		var service_x:=INF
		if project.trade:
			for station in built.layout.get("stations",[]):
				if preload("res://scripts/architecture/stall_goods.gd").is_counter(station):service_x=float(station.x);break
		for access in built.layout.access:
			if project.trade and (not is_finite(service_x) or absf(float(access[0])-service_x)>.001):continue
			var proposed:=WorldPen.point(built.origin)+WorldPen.point(access)
			if proposed.is_finite():
				target=proposed
				break
		if target.is_finite():break
	var structural:Array=[]
	if not target.is_finite() and not project.trade:
		structural=world.paper_strokes_snapshot().filter(func(record):return record.work_id in project.work_ids and record.mode in ["platform","rock","carve"])
		target=_scene_footing(project,structural)
		if not target.is_finite():
			for segment in world.east_segments_snapshot():
				if segment.get("work_id")==project.get("subject") or segment.get("work_id") in project.work_ids:
					var at:=WorldPen.point(segment.points.back())
					target=Vector2(at.x-.45,world.travel_height(at.x-.45))
	if not target.is_finite() and not project.trade and structural.is_empty() and not project.work_ids.is_empty():
		var site:=WorldPen.point(project.site.get("stand"))
		if site.is_finite():
			for face in world.paper_surfaces(site.x,site.y-.35,site.y+.35):
				if face.face=="floor":
					target=Vector2(site.x,face.y)
					break
	var doors:Array=[]
	if project.get("trade_targets",[]).size()>1:
		var markets:=preload("res://scripts/architecture/market_sites.gd")
		for id in project.trade_targets:
			var site:Dictionary={}
			for obj:Dictionary in game.objects:
				if obj.get("structure_id")==id and obj.get("work_id") in project.work_ids:
					var spots:=markets._built_spots(game,obj)
					if not spots.is_empty():site=spots[0]
					break
			if site.is_empty():
				_finish(false,"工程有一处原柜已经没有实际来客位。")
				return
			doors.append({"id":id,"at":Senses.pair(site.at)})
		target=WorldPen.point(doors.front().at)
		divine_job.verify_doors=doors
		divine_job.visited_doors=[]
	if not target.is_finite():
		_finish(false,"工程还没有实地可试走的使用位")
		return
	_refresh_channel_checks(project)
	var sections:Array=project.get("channel_plan",{}).get("sections",[])
	if sections.any(func(section):return not section.get("verified",false)):
		_finish(false,"施工稿还有待验的小段。已画水槽与柜口留存，先实测每段开口再结项。")
		return
	if project.get("water_access",false):
		var water: Dictionary=_scene_water(project)
		if not water.has("wet_foot"):
			_finish(false,"真水尚无可走到的脚面。请查看 scene_water，保留旧水，先打开岸口。")
			return
		divine_job.wet_goal=water.wet_foot
	if project.get("boat",false):
		var passage:=preload("res://scripts/paper_waterway.gd").at_building(game,project,target)
		if not passage.passable:
			_finish(false,"建筑下实测连续湿通道 %.2f 米，需宽 1.80 米、水深 0.12 米、净高 1.25 米。请复查廊面、岸脚与水位。"%passage.clear_width_m)
			return
		if not sections.is_empty():
			var underpass:=preload("res://scripts/painter_underpass_survey.gd")
			var feet:Vector2=actor.player.position-Vector2(0,.29)
			var measurement:=underpass.survey(game,project,PenReach.observe_paper(game,actor),underpass.observe(game,project,feet))
			if not measurement.get("sections",[]).any(func(row):return not row.get("through_both_open_sides",[]).is_empty()):
				_finish(false,"柜下已有连续湿段，尚未量到同一水位接通两头明水。")
				return
	var start:=WorldPen.point(project.get("survey_start"))
	if not start.is_finite():start=WorldPen.point(project.site.get("stand"))
	var route:Dictionary=world.paper_nav_route(start,target)
	if not route.get("ok",false):
		_finish(false,str(route.get("error","旧路到工程还没有连通")))
		return
	divine_job.verify_goal=route.goal
	if (actor.player.position-Vector2(0,.29)).distance_to(start)>.55:
		_go(start.x,"scene_verify_origin","回到旧路核对入口",start)
	else:
		_start_scene_verify_leg()

func _scene_footing(project:Dictionary, structural:Array) -> Vector2:
	var start:=WorldPen.point(project.get("survey_start"))
	if not start.is_finite():start=actor.player.position-Vector2(0,.29)
	structural.reverse()
	for record in structural:
		var range_box:=Rect2(WorldPen.point(record.points[0]),Vector2.ZERO)
		for coordinates in record.points:range_box=range_box.expand(WorldPen.point(coordinates))
		for ratio in [.5,.25,.75]:
			var x:=range_box.position.x+range_box.size.x*float(ratio)
			for floor in world.paper_surfaces(x,range_box.position.y-.10,range_box.end.y+.10):
				if floor.face!="floor" or floor.work_id!=record.work_id:continue
				var at:=Vector2(x,floor.y)
				var route:Dictionary=world.paper_nav_route(start,at)
				if route.get("ok",false) and WorldPen.point(route.get("goal")).distance_to(at)<.20:
					if record.mode in ["platform","rock"]:divine_job.verify_support=record.work_id
					return at
	return Vector2.INF

func _check_scene_contact(delta:float) -> void:
	var supports:Array=actor.player.support_bodies()
	var on_floor:bool=actor.on_ground and not supports.is_empty()
	var expected:String=str(divine_job.get("verify_support",""))
	if not expected.is_empty() and not supports.any(func(body):return body.get_meta("paper_work_id","")==expected):
		var wait:float=float(divine_job.get("verify_support_wait",0))+delta
		divine_job.verify_support_wait=wait
		var feet:Vector2=actor.player.position-Vector2(0,.29)
		var target:=WorldPen.point(divine_job.verify_goal)
		var cadence:=fmod(wait,.32)
		if on_floor and feet.y>target.y+.02 and supports.all(func(body):return body.get_meta("map_drop_allowed",false)):
			route_down=cadence<.035 or cadence>.10 and cadence<.14
		if wait>1.4:
			_finish(false,"走到了附近，但实际脚下仍未命中新作。请复查上层旧路和目标脚面。")
		return
	if on_floor:
		var proof:={"verified":true}
		var doors:Array=divine_job.get("verify_doors",[])
		if not doors.is_empty():
			var door:Dictionary=doors.pop_front()
			var feet:Vector2=actor.player.position-Vector2(0,.29)
			if feet.distance_to(WorldPen.point(door.at))>.27:
				_finish(false,"到了门前但脚没有站到原使用位。",{"visited_doors":divine_job.visited_doors})
				return
			divine_job.visited_doors.append({"id":door.id,"foot":Senses.pair(feet)})
			if not doors.is_empty():
				var next:=WorldPen.point(doors.front().at)
				_go(next.x,"scene_verify","从这间门口沿地面走到下一间",next)
				return
			proof.visited_doors=divine_job.visited_doors
		if not expected.is_empty():proof.support_work_id=expected
		if divine_job.has("water_foot"):proof.water_foot=divine_job.water_foot
		_finish(true,"已从旧路实走过各个柜口。" if proof.has("visited_doors") else "已从旧路实走到工程使用位。",proof)
	elif clock>walk_timeout:_finish(false,"到了使用位的横坐标，但没有站稳。")

func _start_scene_verify_leg() -> void:
	var wet:=WorldPen.point(divine_job.get("wet_goal"))
	if wet.is_finite():
		_go(wet.x,"scene_verify_wet","沿旧岸实走到浅水",wet)
	else:
		var goal:=WorldPen.point(divine_job.verify_goal)
		_go(goal.x,"scene_verify","从旧路试走到新工程",goal)

func _scene_water(project:Dictionary) -> Dictionary:
	var result:={"mouths":[]}
	var body:=SceneWaterBody.observe(world,project)
	if not body.is_empty():result.water_body=body
	var deepest:=0.0
	var repair:bool=scene_projects.step().get("kind")=="water" and int(project.get("return_to",-1))>=0 and \
		project.outcomes.any(func(row):return row.get("phase")=="verify" and not row.get("ok",false))
	var from:=WorldPen.point(project.get("survey_start"))
	if not from.is_finite():from=actor.player.position-Vector2(0,.29)
	for row in world.paper_strokes_snapshot():
		if row.mode!="water" or not row.work_id in project.work_ids:continue
		var bounds:=Rect2(WorldPen.point(row.points.front()),Vector2.ZERO)
		for pair in row.points:bounds=bounds.expand(WorldPen.point(pair))
		var level:=bounds.end.y
		var low_roof:=INF
		var high_roof:=-INF
		var cap_found:=false
		for n in range(1,mini(34,ceili(bounds.size.x/.12))):
			var x:=bounds.position.x+n*.12
			for surface in world.paper_surfaces(x,bounds.position.y-.03,level+.55):
				if surface.face!="floor":continue
				var floor:=Vector2(x,surface.y)
				if surface.y<level-.045 and is_finite(world.paper_space.water_surface(floor+Vector2(0,.035))):
					var clearance: Array=world.paper_surfaces(x,surface.y+.045,surface.y+.72)
					if level-surface.y>deepest and clearance.is_empty() and world.paper_nav_route(from,floor).get("ok",false):
						result.wet_foot=Senses.pair(floor)
						deepest=level-surface.y
				elif surface.y>=level and surface.y<=level+.48:
					cap_found=true
					low_roof=minf(low_roof,surface.y)
					high_roof=maxf(high_roof,surface.y)
		if cap_found and (repair or not result.has("wet_foot")) and bounds.size.x>=.55 and bounds.size.x<=2.8 and high_roof-low_roof<.32:
			result.mouths.append({"id":row.work_id,"span":[bounds.position.x,bounds.end.x],
				"level":level,"cover":[low_roof,high_roof],"cut_top":high_roof+.09,"cut_bottom":level-.065,
				"ramp_mouth":repair})
	result.mouths.sort_custom(func(a,b):return a.span[1]-a.span[0]>b.span[1]-b.span[0])
	return result

func _scene_basin_measurements(project:Dictionary, feet:Vector2, reach:float) -> Array:
	var ids:Array=project.get("work_ids",[])
	if ids.is_empty():return []
	var basins:Array=[]
	for basin:Dictionary in world.paper_strokes_snapshot():
		if basin.mode!="carve" or basin.work_id not in ids:continue
		var first:=WorldPen.point(basin.points.front())
		var distance:=first.distance_to(feet)
		if distance>reach:continue
		basins.append({"id":basin.work_id,"name":basin.get("name","浅盆"),"points":basin.points,
			"distance":snappedf(distance,.01)})
	basins.sort_custom(func(a,b):return a.distance<b.distance)
	var result:=basins.slice(0,5)
	if world.paper_space.has_method("basin_sections"):
		var levels:Array=[]
		for section:Dictionary in project.get("channel_plan",{}).get("sections",[]):
			if section.get("kind")!="water" or not (section.get("level") is float or section.get("level") is int):continue
			if section.level not in levels:levels.append(section.level)
			if levels.size()>=4:break
		for row:Dictionary in result:
			row.measured_sections=world.paper_space.basin_sections(row.id)
			if not levels.is_empty():
				for exact:Dictionary in world.paper_space.basin_sections(row.id,levels):
					if not row.measured_sections.any(func(other):return is_equal_approx(float(other.level),float(exact.level))):
						row.measured_sections.append(exact)
	return result

func _scene_basin_sites(brush:Dictionary) -> Array:
	return preload("res://scripts/painter_water_sites.gd").nearby(world,brush,scene_projects.active())

func _atlas_supports(atlas, method:String) -> bool:
	return atlas!=null and atlas.get_script_method_list().any(func(row):return row.name==method)

func _scene_shore() -> Dictionary:
	var survey:=preload("res://scripts/architecture/building_survey.gd")
	var project:=scene_projects.active()
	var plans:Array=project.get("plan_ids",[])
	var plan_id:=int(plans.back()) if not plans.is_empty() else -1
	var feet:Vector2=actor.player.position-Vector2(0,.29)
	var works:Array=world.paper_strokes_snapshot()
	for row in works:
		if row.mode=="water" and row.work_id in project.work_ids:
			return survey.shore_sites(game,"companion",plan_id,str(row.work_id),feet,16.0)
	return {}

func _shore_frontage(bank:Dictionary) -> Dictionary:
	var at:=WorldPen.point(bank.stand)
	var survey:=preload("res://scripts/architecture/building_survey.gd")
	var measured:=survey.preview_ground(game,at)
	var frontage:Dictionary={"level_site_clear":true,"width_m":2.0,"conflicts":[]}
	for span:Dictionary in measured.get("frontages",[]):
		if not span.level_site_clear:continue
		var half:float=float(span.width_m)*.5
		if [-half,0.0,half].any(func(dx):return is_finite(world.paper_space.water_surface(at+Vector2(dx,.075)))):continue
		frontage=span
	return {"id":"shore@%.2f,%.2f"%[at.x,at.y],"stand":bank.stand,"surface":bank.surface,"frontage":frontage}

func _scene_foundation() -> Array:
	var feet:Vector2=actor.player.position-Vector2(0,.29)
	var survey:=preload("res://scripts/architecture/building_survey.gd")
	var rows:=[]
	for step in range(13):
		for direction in ([0] if step==0 else [-1,1]):
			var x:float=snappedf(feet.x,.25)+direction*step*.50
			for surface in world.paper_surfaces(x,feet.y-3.0,feet.y+3.0):
				if surface.face!="floor":continue
				var at:=Vector2(x,surface.y)
				var measured:Dictionary=survey.preview_ground(game,at)
				if measured.is_empty():continue
				var frontage:Dictionary=measured.frontages.front()
				for span:Dictionary in measured.frontages:
					if not span.level_site_clear:continue
					var half:float=float(span.width_m)*.5
					if [-half,-.30,0.0,.30,half].any(func(dx):return is_finite(world.paper_space.water_surface(at+Vector2(dx,.075)))):
						span.level_site_clear=false
						span.conflicts.append({"id":"有效水域","reason":"wet_footing"})
					else:frontage=span
				if not frontage.level_site_clear and step>3:continue
				var id:String="foundation@%.2f,%.2f"%[x,at.y]
				if frontage.level_site_clear:
					var route:Dictionary=world.paper_nav_route(feet,at)
					if not route.get("ok",false) or WorldPen.point(route.goal).distance_to(at)>.25:continue
				rows.append({"id":id,"stand":measured.stand,"surface":surface.work_id,"frontage":frontage})
	return rows

func _observe_site_frontages() -> void:
	if not ResourceLoader.exists(BUILDING_SURVEY_PATH):return
	var survey=load(BUILDING_SURVEY_PATH)
	var feet:Vector2=actor.player.position-Vector2(0,.29)
	var candidates:Array=[{"id":"here","label":"阿靛当前可达脚点","stand":Senses.pair(feet),"distance":0.0}]
	var selected:Dictionary=scene_projects.active().get("site",{})
	if divine_running and not selected.is_empty() and selected.get("id")!="here":candidates.append(selected)
	if not divine_running or not divine_job.has("project_id"):
		for plot in survey.nearby_plots(game,feet):
			candidates.append(plot)
			last_observation.autonomy.routes.append(plot)
	var routes:Array=last_observation.autonomy.get("routes",[]).duplicate()
	routes.sort_custom(func(a,b):return float(a.get("distance",INF))<float(b.get("distance",INF)))
	for route in routes:
		if candidates.size()>=7:break
		if route.get("id")=="chat-player" or float(route.get("distance",INF))<=26.0:
			if not candidates.any(func(row):return row.id==route.id):candidates.append(route)
	var facts:=[]
	for site in candidates:
		var stand:=WorldPen.point(site.get("stand"))
		if not stand.is_finite():continue
		var path:Dictionary=world.paper_nav_route(feet,stand)
		if not path.get("ok",false):continue
		var grounded:=WorldPen.point(path.get("goal"))
		if not grounded.is_finite() or grounded.distance_to(stand)>.35:continue
		var view:Dictionary=survey.preview_ground(game,grounded)
		if view.is_empty():continue
		view.id=site.id
		view.label=site.label
		facts.append(view)
	if not divine_job.has("project_id"):
		survey.Neighbours.describe(world,facts)
	last_observation.scene_siting=facts

func _observe_plant_turn() -> void:
	var project:=scene_projects.active()
	var plant:Dictionary=project.get("plant",{})
	last_observation.scene_plant=PlantReview.review(world,project)
	last_observation.scene_plant.expected=PlantReview.expected_kind(scene_projects.step())
	last_observation.scene_plant.batch_limit=PlantReview.MAX_BATCHES
	var old:=[]
	for mark in plant.get("marks",[]).slice(-24):
		old.append({"part":mark.part,"from":mark.points.front(),"to":mark.points.back(),
			"pigment":mark.pigment,"brush":mark.brush,"work_id":mark.work_id})
	last_observation.scene_plant.ink=old

func _study_field() -> String:
	return "plant" if scene_projects.step().get("kind")=="vegetation" else "detail_study"

func _observe_study_turn() -> void:
	var data:Dictionary=scene_projects.active().get(_study_field(),{})
	last_observation.scene_study={"reads":int(data.get("reads",0)),"limit":PlantReview.MAX_STUDY_READS,"study":data.get("study",{})}
	var atlas=load("res://scripts/team_atlas.gd")
	if not _atlas_supports(atlas,"study_catalog"): return
	var project := scene_projects.active()
	var scope := "%s/%s/%s" % [game.team_slot.world_id,project.project_id,project.cursor]
	if study_scope != scope:
		study_scope = scope
		study_filters = {}
	var index := StudyIndex.window(atlas.study_catalog(game),study_filters)
	last_observation.scene_studies = index.rows
	index.erase("rows")
	last_observation.scene_study_index = index

func _admit_plant_batch(plant:Dictionary) -> bool:
	var project:=scene_projects.active()
	var previous:Dictionary=project.get("plant",{})
	var kind:=str(plant.get("kind",""))
	var expected:=PlantReview.expected_kind(scene_projects.step())
	if not kind in ["tree","small_detail"] or not expected.is_empty() and kind!=expected or \
		not str(previous.get("kind","")).is_empty() and previous.kind!=kind:
		_finish(false,"这批笔迹需延续工程声明的同一植被造型。")
		return false
	if int(previous.get("batches",0))>=PlantReview.MAX_BATCHES or not plant.get("roles") is Array or plant.roles.is_empty() or \
		not plant.roles.all(func(part):return part in PlantReview.ROLES):
		_finish(false,"植被笔稿批次已用满，或缺少逐笔用途。")
		return false
	plant_draft=plant.duplicate(true)
	return true

func _read_scene_study(args:Dictionary) -> void:
	var project:=scene_projects.active()
	var atlas=load("res://scripts/team_atlas.gd")
	if not divine_job.has("project_id") or not _atlas_supports(atlas,"study_part"):
		_finish(false,"当前世界没有可读的公共部件。")
		return
	var field:=_study_field()
	var data:Dictionary=project.get(field,{})
	if not scene_projects.step().get("kind") in ["landscape","vegetation"] or int(data.get("reads",0))>=PlantReview.MAX_STUDY_READS:
		_finish(false,"当前工序已用完可读部件批次，请使用已读选件或原创。")
		return
	var part:Dictionary=atlas.study_part(game,args.work,args.part)
	if not part.get("ok",false):
		_finish(false,str(part.get("error","公共部件无效")))
		return
	var offset:=int(args.get("offset",0))
	if offset<0 or offset>=part.strokes.size():
		_finish(false,"部件已到最后一批原笔，请从现有笔号选取。")
		return
	var current:Dictionary=data.get("study",{})
	if current.get("work")==args.work and current.get("part")==args.part and int(current.get("offset",0))==offset:
		_finish(false,"该部件这批原笔已读取，请使用或选择另一组。")
		return
	data.study={"work":args.work,"part":args.part,"bounds":part.bounds,"offset":offset,
		"strokes":part.strokes.slice(offset,offset+24),"total":part.strokes.size()}
	if offset+24<part.strokes.size():data.study.next_offset=offset+24
	data.reads=int(data.get("reads",0))+1
	project[field]=data
	_finish(true,"已读同队公共笔谱部件，尚未落笔。",{"partial":true})

func _compose_scene_study(args:Dictionary) -> void:
	var atlas=load("res://scripts/team_atlas.gd")
	if not divine_job.has("project_id") or not _atlas_supports(atlas,"compose_study"):
		_finish(false,"当前世界没有可用的共笔展开工具")
		return
	var current:Dictionary=scene_projects.active().get(_study_field(),{}).get("study",{})
	if current.get("work")!=args.work or current.get("part")!=args.part:
		_finish(false,"请先读取这份部件，再展开选中的笔。")
		return
	var spec:Dictionary=args.spec.duplicate(true)
	var allowed:Array=current.strokes.map(func(stroke):return int(stroke.stroke))
	if not spec.get("strokes") is Array or not spec.strokes.all(func(stroke):return (stroke is int or stroke is float) and int(stroke)==stroke and int(stroke) in allowed):
		_finish(false,"选笔需要使用当前公开部件的原页编号。")
		return
	var part:Dictionary=atlas.study_part(game,args.work,args.part)
	if not part.get("ok",false):
		_finish(false,str(part.get("error","公共部件无效")))
		return
	spec.batch_id=str(last_command.get("call_id",ticket))
	var draft:Dictionary=atlas.compose_study(game,part.ref,spec)
	if not draft.get("ok",false):
		_finish(false,str(draft.get("error","共笔无法展开")))
		return
	if _study_field()=="plant":
		if draft.strokes.size()!=args.get("plant",{}).get("roles",[]).size():
			_finish(false,"选中公共笔与声明用途不对应")
			return
		if not _admit_plant_batch(args.plant):return
	_start_paper_plan({"name":spec.name,"strokes":draft.strokes})

func _commit_plant_batch(receipt:Dictionary, lines:Array, brushes:Array, pigments:Array, records:Array=[]) -> void:
	if not receipt.get("ok",false) or plant_draft.is_empty():return
	var project:=scene_projects.active()
	var plant:Dictionary=project.get("plant",{})
	if not plant.has("marks"):plant.marks=[]
	plant.kind=plant_draft.kind
	var existing: Array=plant.marks.map(func(mark):return mark.work_id)
	var ink_added:=false
	for i in mini(lines.size(),plant_draft.roles.size()):
		var mark:Dictionary={"part":plant_draft.roles[i],"points":lines[i].duplicate(true),
			"brush":brushes[i],"pigment":pigments[i],"work_id":receipt.get("work_id","")}
		if i<records.size():
			mark.work_id=records[i].work_id
			if records[i].has("source_work_id"):mark.source_work_id=records[i].source_work_id
			if records[i].has("source_stroke"):mark.source_stroke=records[i].source_stroke
		if mark.work_id.is_empty() or mark.work_id in existing:continue
		plant.marks.append(mark)
		ink_added=true
	if ink_added:plant.batches=int(plant.get("batches",0))+1
	project.plant=plant
	receipt.partial=ink_added
	receipt.plant_review=PlantReview.review(world,project)

func _scene_counter_supports(project:Dictionary) -> Dictionary:
	var result:={}
	var targets:Array=project.get("trade_targets",[])
	for obj:Dictionary in game.objects:
		var counter_id:String=str(obj.get("structure_id",""))
		if counter_id not in targets or not obj.has("built_plan"):continue
		var plan:Dictionary=obj.built_plan
		var pins:Array=[]
		for point in plan.layout.get("supports",[]):
			var at:Vector2=game.object_point(obj,WorldPen.point(plan.offset)+WorldPen.point(point))
			var near:Array=world.paper_surfaces(at.x,at.y-1.0,at.y+.25)
			var faces:Array=near.filter(func(row):return row.face=="floor")
			pins.append({"at":BuildingPlans.coords(at),"bearing":BuildingPlans._load_bearing(game,at,BuildingPlans.FOOT_TOLERANCE),"floors":faces})
		result[counter_id]=pins
	return result

func _counter_cut_conflict(records:Array) -> String:
	if not divine_job.has("project_id") and not divine_job.has("chat_paper_project"):return ""
	var cuts:Array=[]
	for record:Dictionary in records:
		if record.mode!="carve":continue
		var polygon:=PackedVector2Array()
		for point in record.points:polygon.append(WorldPen.point(point))
		cuts.append(polygon)
	if cuts.is_empty():return ""
	for pins:Array in _scene_counter_supports(scene_projects.active()).values():
		for i in pins.size():
			var pin:Dictionary=pins[i]
			if not pin.bearing:continue
			var at:=WorldPen.point(pin.at)
			var solid_feet:=false
			var remaining:=false
			for face:Dictionary in pin.floors:
				if absf(float(face.y)-at.y)>BuildingPlans.FOOT_TOLERANCE:continue
				if face.mode=="platform":
					remaining=true
					break
				var under:=Vector2(at.x,float(face.y)-.018)
				if not world.paper_space.solid_at(under):continue
				solid_feet=true
				if not cuts.any(func(cut):return Geometry2D.is_point_in_polygon(under,cut)):
					remaining=true
					break
			if solid_feet and not remaining:
				return "这笔会削掉原柜第 %d 个承重柱的实脚 (%.2f, %.2f)。请绕柱脚收小槽或保留一段承重土。"%[i+1,at.x,at.y]
	return ""

func _scene_counter_sites(project:Dictionary,feet:Vector2) -> Array:
	var targets:Array=project.get("trade_targets",[])
	if targets.is_empty():return []
	var sites:Array=[]
	var market:=preload("res://scripts/architecture/market_sites.gd")
	var supports:=_scene_counter_supports(project)
	for counter:Dictionary in market.known_stalls(game,feet):
		if counter.station not in targets:continue
		var stand:=WorldPen.point(counter.at)
		var distance:=snappedf(stand.distance_to(feet),.01)
		var site:={"work_id":counter.station,"label":counter.name+" · 原柜实脚面","counter_at":counter.at,
			"distance":distance,"supports":supports.get(counter.station,[])}
		if distance>.85:
			var route:Dictionary=world.paper_nav_route(feet,stand)
			if route.get("ok",false) and WorldPen.point(route.goal).distance_to(stand)<=.30:
				site.merge({"id":"counter@"+counter.site,"stand":route.goal})
		sites.append(site)
		if sites.size()==3:break
	return sites

func _chat_stalls() -> Dictionary:
	var from:=WorldPen.point(divine_job.get("player_at"))
	if not from.is_finite() or world.survival==null:return {}
	var markets:=preload("res://scripts/architecture/market_sites.gd")
	var recorded:=markets.known_stalls(game,from)
	var shops:Array=[]
	for row:Dictionary in recorded:
		var at:=WorldPen.point(row.at)
		var gap:=at.distance_to(from)
		if gap>32.0:continue
		var quote:Dictionary=row.offer
		var title:String=row.name
		for obj:Dictionary in game.objects:
			if obj.get("structure_id")==row.station:
				title=str(obj.get("name",title))
				break
		var stall:={"name":title,"at_m":row.at,"distance_m":snappedf(gap,.1),
			"item":quote.name,"direction":quote.direction,"unit_price":quote.unit_price}
		if quote.direction=="buy_from_customer":
			var till=quote.get("coins")
			stall.coins_reserved_for_purchases=till
			stall.status="收购付款能力未确认" if till==null else ("钱匣不足，暂不能支付一份" if till<quote.unit_price else "能付收购款")
		else:
			var stock=quote.get("stock")
			stall.stock=stock
			stall.status="库存未确认" if stock==null else ("当前售罄" if stock==0 else "有现货")
		shops.append(stall)
		if shops.size()==6:break
	var project:=scene_projects.active()
	var job:={"state":"停工" if autonomy.paused else "没有正在落笔","at_m":Senses.pair(actor.player.position-Vector2(0,.29))}
	if not project.is_empty():
		job.project_name=project.title
		job.project_stage=project.stage
		if project.stage=="paused":job.state="当前工程已停工"
		elif project.stage=="awaiting_trade":job.state="当前工程停下等实际成交"
		if project.stage=="paused" and not project.outcomes.is_empty():
			job.last_known_reason=str(project.outcomes.back().get("detail","")).left(120)
	return {"stalls":shops,"radius_m":32,"painter":job}

func _divine_scene() -> Dictionary:
	var scene:=divine_job.duplicate(true)
	scene.messages=divine_messages.duplicate(true)
	if not divine_job.has("project_id"):scene.local_stalls=_chat_stalls()
	if divine_job.travel_left>0: scene.east_frontier=_chat_edge_site()
	scene.last_work=[]
	if not divine_work_ids.is_empty():
		for record in world.paper_strokes_snapshot():
			if record.work_id in divine_work_ids and record.author_id=="companion":
				scene.last_work.append({"id":record.work_id,"name":record.get("name",""),"mode":record.mode,
					"anchor":record.anchor,"points":record.points})
		for segment in world.east_segments_snapshot():
			if segment.get("work_id") in divine_work_ids and segment.get("author_id")=="companion":
				scene.last_work.append({"id":segment.work_id,"name":segment.name,"mode":"east_ground",
					"anchor":{"at":segment.points.back()},"points":segment.points})
	return scene

func _chat_edge_site() -> Dictionary:
	if world.east_painting() or not world.east_has_room():return {}
	var edge:Vector2=Vector2(world.observe_east_edge().edge[0],world.observe_east_edge().edge[1])
	var feet:Vector2=actor.player.position-Vector2(0,.29)
	for setback in [1.1,2.1,3.2]:
		var x:=edge.x-float(setback)
		var stand:=Vector2(x,world.travel_height(x))
		var route:Dictionary=world.paper_nav_route(feet,stand)
		if not route.get("ok",false):continue
		return {"id":"east-frontier","label":"东侧纸边","stand":route.goal,"edge":Senses.pair(edge),
			"distance":snappedf(feet.distance_to(Vector2(route.goal[0],route.goal[1])),.01)}
	return {}

func _begin_divine_travel(route: Dictionary, after_arrival: String, message: String) -> void:
	if not Autonomy.pair(route.get("stand")) or divine_job.travel_left<=0:
		_finish(false,"此处未测到可走的落脚点")
		return
	divine_job.travel_left-=1
	divine_job.selected_site={"at":route.stand,"label":route.label,"after_arrival":after_arrival}
	_divine_message("god",message)
	_go(float(route.stand[0]),"divine_site","前往"+route.label,Vector2(route.stand[0],route.stand[1]))

func _divine_route(id: String, label: String, point: Variant) -> Dictionary:
	if not Autonomy.pair(point): return {}
	var at:=Vector2(point[0],point[1])
	var nearest:=Vector2.INF
	for offset in [0.0,-.55,.55,-1.1,1.1]:
		for floor in world.paper_surfaces(at.x+offset,at.y-2.0,at.y+.6):
			if floor.face!="floor":continue
			var candidate:=Vector2(at.x+offset,floor.y)
			if at.distance_to(candidate+Vector2(0,.5))<at.distance_to(nearest+Vector2(0,.5)):nearest=candidate
	if not nearest.is_finite():return {}
	var distance:float=actor.player.position.distance_to(nearest+Vector2(0,.48))
	return {"id":id,"label":label,"stand":Senses.pair(nearest),"distance":snappedf(distance,.01)}

func _sees_edge() -> bool:
	return absf(actor.player.position.x-world.east_walk_limit()) < EDGE_SENSOR_REACH

func _start_queued_frontier() -> void:
	if not divine_job.is_empty(): return
	if queued_frontier.is_empty() or phase in ["thinking","pen"]: return
	var text := queued_frontier
	queued_frontier = ""
	if phase == "work" or (phase == "walk" and destination in ["edge","cross"]):
		# The current observation already sent this artist to work on the same sheet.
		return
	var reason := frontier_blocker()
	if reason.is_empty(): invite("paint",text)
	else: game.message("续画未发出 · "+reason)

func recall() -> void:
	if actor == null or phase not in ["rest","walk","offline"] or has_active_brush() or not invitation.is_empty():
		game.message("阿靛手上有事，等他空下来再邀同行")
		return
	company_left=15.0
	game.message("阿靛应邀同行片刻，之后回自己的路线")

func invite(kind: String, text: String, slot: int = 0) -> bool:
	if actor == null: return false
	if not divine_job.is_empty():
		game.message("阿靛正在处理顶栏对话。")
		return false
	if kind == "paint":
		var reason := frontier_blocker()
		if not reason.is_empty():
			game.message(reason)
			return false
		if phase == "thinking":
			queued_frontier = text.left(120)
			return true
	elif not queued_frontier.is_empty():
		game.message("阿靛已接下续画，请等这一轮完成")
		return false
	if not worker.can_request():
		game.message(ModelConnections.role_status("companion").message)
		return false
	if phase in ["work","pen"] or destination == "edge" and phase == "walk":
		game.message("阿靛正在运笔，等这一笔画完再交谈")
		return false
	if actor.player.position.distance_to(game.player.position) > 10:
		game.message("阿靛离得有些远，按 J 叫它到身边")
		return false
	worker.cancel()
	company_left=0.0
	autonomous_execution=false
	nib_world = Vector2.INF
	actor.active_stroke = null
	_remember("你", text)
	invitation = {"kind":kind, "text":text.left(120), "slot":slot}
	reference_command.clear()
	if kind == "copy":
		reference_command = game.FunctionalPens.from_draft(7,game.pen_style,game.draft)
		study_revision += 1
	_say("你",text,0.9)
	phase = "rest"
	clock = 0.0
	wait_for_change = false
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or get_tree().current_scene != game or not event is InputEventKey or not event.pressed or event.echo: return
	if event.is_command_or_control_pressed() or event.alt_pressed or event.shift_pressed: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or game.bag_open or game.personal_overlay_open(): return
	if event.keycode == KEY_J:
		recall()
	elif event.keycode == KEY_T:
		game.map_controls.open_chat()
	else: return
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if (get_tree().current_scene != game and not game.manuscript_preview) or world!=game.medieval_world or is_queued_for_deletion() or not is_visible_in_tree(): return
	if actor == null: _arrive()
	var direction := 0
	reach_jump = false
	route_down = false
	actor.brush_target = Vector2.INF
	speech_time = maxf(0.0,speech_time-delta)
	_start_queued_frontier()
	scene_trade_poll-=delta
	if scene_trade_poll<=0.0:
		scene_trade_poll=.75
		for entry in scene_projects.entries:_observe_scene_trade(entry)
	_continue_scene_project()
	_dispatch_divine_chat()
	var surveying := _can_survey_locally(ModelConnections.role_status("companion"))
	if not surveying: local_walk.interrupt()
	if company_left>0:
		company_left=maxf(0,company_left-delta)
		var gap: float=game.player.position.x-actor.player.position.x
		direction=int(signf(gap)) if absf(gap)>2.1 else 0
	elif surveying:
		var grounded: bool = actor.on_ground and not actor.player.support_bodies().is_empty()
		var step := local_walk.tick(world,actor.player.position-Vector2(0,.29),delta,grounded)
		direction = int(step.get("direction",0))
		reach_jump = step.get("jump",false) and grounded
		route_down = step.get("down",false)
	elif not (autonomy.paused and (autonomous_execution or _automatic_scene_turn()) and phase in ["work","pen","walk","speak"]):
		direction=_step_action(delta)
	var body_x: float = actor.player.position.x
	if direction != 0 and (phase=="walk" or phase=="pen" and paper_stands.is_empty() or company_left>0) and absf(body_x-last_body_x)<0.009:
		stopped_time += delta
		if stopped_time > 0.35 and actor.on_ground:
			reach_jump = true
			stopped_time = 0.0
	else:
		stopped_time = 0.0
	last_body_x = body_x
	actor.drive(delta,direction,reach_jump,route_down)
	var limits := Autonomy.motion_bounds(world)
	if actor.player.position.x > limits.end.x or actor.player.position.x < limits.position.x:
		actor.relocate(Vector2(clampf(actor.player.position.x,limits.position.x,limits.end.x),actor.player.position.y))
	if actor.player.position.y < limits.position.y:
		local_walk.interrupt()
		actor.relocate(autonomy.respawn(world,HOME_X))
		if phase!="work": _finish(false,"失足后回到自己最近的安全落脚点")
	else: autonomy.remember_ground(world,actor)
	queue_redraw()

func _can_survey_locally(connection: Dictionary) -> bool:
	return actor != null and phase in ["rest","offline"] and company_left <= 0.0 and invitation.is_empty() \
		and queued_frontier.is_empty() and divine_job.is_empty() and not _waiting_at_access() \
		and scene_projects.active().get("stage")!="working" \
		and LocalWalk.can_run(connection,autonomy.paused,worker.can_request())

func _scene_opportunity(segments:Array) -> Dictionary:
	var at:Vector2=actor.player.position-Vector2(0,.29)
	var frontier := _sees_edge()
	if not frontier and not actor.on_ground:
		return {}
	for entry in scene_projects.entries:
		var site:=WorldPen.point(entry.site.get("stand"))
		if site.is_finite() and site.distance_to(at)<12:return {}
	var works:=[]
	for index in range(segments.size()-1,-1,-1):
		var segment:Dictionary=segments[index]
		var start:=WorldPen.point(segment.points.front())
		var end:=WorldPen.point(segment.points.back())
		if Geometry2D.get_closest_point_to_segment(at,start,end).distance_to(at)>24:
			continue
		var high:=start.y
		var low:=start.y
		for point in segment.points:
			high=maxf(high,float(point[1]))
			low=minf(low,float(point[1]))
		works.append({"id":segment.get("work_id",""),"name":segment.name,"landmark":segment.get("landmark",""),
			"style":segment.get("style",""),"from":segment.points.front(),"to":segment.points.back(),
			"relief_m":snappedf(high-low,.01),"width_m":snappedf(absf(end.x-start.x),.01)})
		if works.size()==6:break
	works.reverse()
	return {"recent":works,"at":Senses.pair(at),"at_frontier":frontier,
		"studio_memory":scene_projects.studio_memory(world.chronicle),
		"need":"根据脚下的地形、身边的人和实测可用地，自行决定是否在这里营造、换地点、接纸或探索。已有作品可以继续使用。"}

func _waiting_at_access() -> bool:
	return phase=="rest" and clock>0.0 and last_result.get("tool")=="walk_to_access" and last_result.get("ok",false)

func _automatic_scene_turn() -> bool:
	var project:=scene_projects.active()
	return divine_job.has("project_id") and project.get("origin")=="autonomous" and not project.get("player_resumed",false)

func _step_action(delta: float) -> int:
	match phase:
		"rest":
			clock -= delta
			if worker.can_request() and clock <= 0 and (not invitation.is_empty() or autonomy.available() and scene_projects.active().get("stage")!="working" and
				(not wait_for_change or autonomy.revision!=_paper_revision() or clock < -idle_retry_after)):
				_request()
		"walk":
			return _walk(delta)
		"work":
			return _work(delta)
		"pen":
			return _functional_stroke(delta)
		"speak":
			clock -= delta
			if clock <= 0:
				if not target_npc.is_empty(): _npc_reply()
				else: phase = "rest"
		"offline":
			clock -= delta
			if autonomous_execution and worker.can_request() and clock<=0:
				phase="rest"
	return 0

func _paper_revision() -> String:
	return str([world.terrain.east_ink.segments.size(),world.paper_space.epoch if world.paper_space!=null else 0,game.objects.size()])

func _request() -> void:
	autonomous_execution=invitation.is_empty()
	var chatting:bool=divine_running and (invitation.get("kind")=="divine_chat" or divine_job.has("project_id") or divine_job.has("edit_plan"))
	last_observation = Senses.observe(game,actor,last_result,autonomous_execution or chatting)
	last_observation.identity = "阿靛"
	last_observation.recent_dialogue = dialogue.duplicate(true)
	last_observation.invitation = invitation.duplicate()
	last_observation.nearby_npcs = Senses.people(world,actor.player.position)
	if autonomous_execution or chatting:
		last_observation.autonomy = autonomy.sense(game,actor.player.position,"companion")
		if not last_observation.autonomy.paper.is_empty():
			var paper:Dictionary=last_observation.autonomy.paper
			paper.brush=PenReach.observe_paper(game,actor,chatting and not scene_projects.active().get("channel_plan",{}).is_empty())
			if chatting and divine_job.has("project_id"):
				for station in paper.brush.stations:
					if station.get("current",false):continue
					var stand:=PenReach.point(station.feet)
					var site:={"id":"brush@%.2f,%.2f"%[stand.x,stand.y],"label":"实测握笔点 %.2f 米"%stand.x,
						"stand":station.feet,"grip":station.grip,"radius":paper.brush.radius,
						"distance":snappedf(stand.distance_to(actor.player.position-Vector2(0,.29)),.01)}
					last_observation.autonomy.routes.push_front(site)
			if not last_paper_reach.is_empty() and PenReach.point(last_paper_reach.feet).distance_to(actor.player.position)<6.0:
				paper.last_reach_failure=last_paper_reach
		if autonomous_execution:
			last_observation.site_pen = game.FunctionalPens.observe(game,8,actor.player.position,true)
			autonomy.revision=_paper_revision()
			var frontier:=_chat_edge_site()
			var arrived:bool=last_result.get("tool")=="survey_frontier" and last_result.get("ok",false) and _sees_edge()
			var segments:Array=world.east_segments_snapshot()
			var expanded:bool=segments.any(func(row):return row.get("author_id")=="companion")
			var recent_works:bool=autonomy.history.any(func(row):return row.ok and row.action in ["paper_ink","shape_site"])
			if not recent_works:
				recent_works=world.paper_strokes_snapshot().any(func(row):return row.get("author_id")=="companion")
			last_observation.autonomy.frontier=frontier
			last_observation.autonomy.frontier_arrival=arrived
			last_observation.autonomy.frontier_priority=not expanded and recent_works and not frontier.is_empty() and not _sees_edge()
			last_observation.autonomy.scene_opportunity=_scene_opportunity(segments)
			if not last_observation.autonomy.scene_opportunity.is_empty():
				last_observation.scene_revisions=last_observation.autonomy.scene_opportunity.recent
				_observe_site_frontages()
		if chatting:
			last_observation.divine_chat=_divine_scene()
			var distant=load(DISTANT_SHEET_PATH) if ResourceLoader.exists(DISTANT_SHEET_PATH) else null
			if _atlas_supports(distant,"frames") and _atlas_supports(distant,"reframe"):
				last_observation.scene_distant_frames=distant.frames(game,"companion").filter(func(row):return row.get("in_range",false)).slice(0,16)
			var active_project:=scene_projects.active()
			_refresh_channel_checks(active_project)
			last_observation.scene_project=scene_projects.observe()
			var channel:Dictionary=active_project.get("channel_plan",{}).duplicate(true)
			for item:Dictionary in channel.get("sections",[]):
				if item.get("verified",false) or item.work_ids.is_empty():continue
				item.measured_now=ChannelPlan.measure(world,active_project,item.id,false)
				item.measured_now.current_hand_can_cut=ChannelPlan.current_cut_reach(item.measured_now,
					last_observation.autonomy.get("paper",{}).get("brush",{}))
				break
			if not channel.is_empty():last_observation.scene_project.channel_plan=channel
			if divine_job.has("project_id") and scene_projects.step().get("form")=="foundation":
				last_observation.scene_foundation=_scene_foundation()
			if divine_job.has("project_id") and scene_projects.step().get("kind") in ["landscape","building"]:
				var shore:Dictionary=_scene_shore()
				if not shore.is_empty():
					last_observation.scene_shore=shore
					var feet:Vector2=actor.player.position-Vector2(0,.29)
					for bank:Dictionary in shore.get("sites",[])+shore.get("banks",[]):
						var at:=WorldPen.point(bank.get("stand"))
						if not at.is_finite():continue
						var id:="shore@%.2f,%.2f"%[at.x,at.y]
						bank.site_id=id
						if shore.get("scope")=="frontage" and bank.get("frontage_ready",false) and last_observation.has("scene_foundation"):
							last_observation.scene_foundation.push_front(_shore_frontage(bank))
						var distance:=snappedf(at.distance_to(feet),.01)
						if distance>28.0 or distance<=.8:continue
						bank.route_id=id
						last_observation.autonomy.routes.push_front({"id":id,"stand":bank.stand,"distance":distance,
							"label":"同工程实测岸脚 %.2f 米"%at.x})
			var scene_feet:Vector2=actor.player.position-Vector2(0,.29)
			var seen_project:=scene_projects.active()
			if not seen_project.is_empty():
				last_observation.scene_project.frame_measurements=SceneFrame.measure(game,seen_project,scene_feet)
				last_observation.scene_counters=_scene_counter_sites(seen_project,scene_feet)
				for site:Dictionary in last_observation.scene_counters:
					if site.has("id"):last_observation.autonomy.routes.push_front(site)
			var scene_kind:String=scene_projects.step().get("kind","")
			var brush:Dictionary=last_observation.autonomy.get("paper",{}).get("brush",{})
			if divine_job.has("project_id") and scene_kind in ["water","verify"]:
				last_observation.scene_water=_scene_water(seen_project)
				if scene_kind=="water":
					last_observation.scene_water.basins=_scene_basin_sites(brush)
			if not divine_job.has("project_id") or scene_kind in ["landscape","water","verify"]:
				var underpass:=preload("res://scripts/painter_underpass_survey.gd")
				var passage:=underpass.observe(game,seen_project,scene_feet)
				if not passage.is_empty():
					last_observation.scene_underpass=passage
					if not last_observation.has("scene_water"):last_observation.scene_water={}
					last_observation.scene_water.channel_survey=underpass.survey(game,seen_project,brush,passage)
					for approach:Dictionary in passage.reachable_lower_approaches:
						if approach.distance>.45:last_observation.autonomy.routes.push_front(approach)
			var scene_components:Array=[]
			if not divine_job.has("project_id"):
				scene_components=SceneComponent.catalogue(game,seen_project,scene_feet,str(divine_job.text))
				for item:Dictionary in scene_components:
					if not item.editable:continue
					var found:int=game.objects.find_custom(func(o):return o.get("work_id")==item.work_id)
					if found>=0:item.use_positions=AccessRevision.describe(game,game.objects[found])
				last_observation.scene_components=scene_components
			var geometry:=preload("res://scripts/painter_scene_layers.gd").snapshot(game,seen_project,scene_components.map(func(row):return row.work_id))
			if not geometry.is_empty():last_observation.scene_geometry=geometry
			last_observation.scene_plans=BuildingPlans.list_plans(game,"companion")
			if scene_kind in ["vegetation","landscape"] and seen_project.get("stage") in ["working","paused"]:
				last_observation.scene_distant=ResourceLoader.exists(DISTANT_SHEET_PATH)
				if last_observation.scene_distant:
					var span:Array=[]
					for dx:float in [-10.,-8.,-6.,-4.,-2.,0.,2.,4.,6.,8.,10.]:
						var x:float=scene_feet.x+dx
						var bands:Array=[]
						for surface:Dictionary in world.paper_surfaces(x,scene_feet.y-9.,scene_feet.y+5.):
							if surface.face=="floor":bands.append(snappedf(float(surface.y),.01))
						if not bands.is_empty():span.append({"x":snappedf(x,.01),"floor_y":bands})
					last_observation.scene_project.frame_measurements.ground_profile_m=span
				if divine_job.has("project_id"):
					_observe_study_turn()
					if scene_kind=="vegetation":_observe_plant_turn()
			if (divine_job.has("project_id") and scene_kind=="water") or (not divine_job.has("project_id") and scene_kind in ["landscape","water","verify"]):
				last_observation.scene_basins=_scene_basin_measurements(seen_project,scene_feet,18.0 if divine_job.has("project_id") else 10.0)
			last_observation.scene_revisions=[]
			for segment in world.east_segments_snapshot().slice(-8):
				var start:=WorldPen.point(segment.points.front())
				var end:=WorldPen.point(segment.points.back())
				var id:String=str(segment.get("work_id",""))
				if id.is_empty():continue
				var middle:float=(start.x+end.x)*.5
				var site:=_divine_route("work:"+id,segment.name,[middle,world.travel_height(middle)+.29])
				if not site.is_empty():
					last_observation.autonomy.routes.append(site)
				last_observation.scene_revisions.append({"id":id,"name":segment.name,"start":Senses.pair(start),"end":Senses.pair(end),"site":site.get("id","")})
			var local:=_divine_route("chat-player","你发话时所在处",divine_job.player_at)
			if not local.is_empty(): last_observation.autonomy.routes.push_front(local)
			var works:Array=last_observation.divine_chat.last_work
			if not works.is_empty():
				var prior:=_divine_route("chat-work","上件作品「%s」"%works[0].name,works[0].anchor.at)
				if not prior.is_empty(): last_observation.autonomy.routes.push_front(prior)
			_observe_site_frontages()
	last_observation.edge = world.observe_east_edge() if _sees_edge() else {}
	if not last_observation.edge.is_empty() and last_observation.edge.revision >= last_observation.edge.limits.max_segments:
		last_observation.edge = {}
	if invitation.get("kind") == "paint" and last_observation.edge.is_empty():
		invitation.clear()
		clock = 2.8
		caption = "阿靛已经离开可落笔的纸边，靠近后可以重试"
		game.message(caption)
		return
	last_observation.pen = game.FunctionalPens.observe(game,invitation.slot,actor.player.position) if invitation.get("kind") in ["pen","copy"] else {}
	if invitation.get("kind") == "pen":
		last_observation.pen.reach = PenReach.observe(game,actor,last_observation.sites)
	if invitation.get("kind") == "copy":
		last_observation.pen.reference = {"revision":study_revision,"strokes":reference_command.strokes.size(),"brushes":reference_command.brushes,"pigments":reference_command.get("pigments",[])}
	if invitation.get("kind") in ["building_design","building_variant"]:
		var site:=Vector2.INF
		if divine_job.has("project_id"):
			site=WorldPen.point(scene_projects.active().get("foundation_site",{}).get("stand"))
			if not site.is_finite():site=actor.player.position
		var building := building_observation(site)
		if building.has("error"):
			invitation.clear()
			_finish(false,building.error)
			game.message(building.error)
			return
		building.site.shore=last_observation.get("scene_shore",{})
		last_observation.building = building
	if worker.request_segment(last_observation):
		if autonomous_execution or chatting and _automatic_scene_turn():
			autonomy.used+=1
		if chatting: divine_progress="已发给服务商，等待阿靛回复。"
		ticket = worker.last_request_path.get_file().get_slice(".",0)
		phase = "thinking"
		caption = "看看纸边" if not last_observation.edge.is_empty() else "环顾四周"
	else:
		if chatting:
			_close_divine_job("这句话没能发出。"+str(ModelConnections.role_status("companion").message))
			invitation={}
		phase = "offline"
		clock = 20.0
		caption = "暂时没接通"

func _decision(observation: Dictionary, command: Dictionary, error: String) -> void:
	if phase != "thinking" or get_tree().current_scene != game or world!=game.medieval_world or is_queued_for_deletion(): return
	# Local mailbox clients written for the first experiment send the terrain
	# or functional-pen payload directly; bind it to this actor's current turn.
	var external: bool = worker.is_fixture()
	if external and not command.has("args") and not command.is_empty():
		if invitation.get("kind") == "pen" and command.get("tool") == observation.pen.get("requested"):
			command = {"tool":"functional_pen","args":{"command":command},"provider":"local-mailbox","call_id":ticket}
		elif invitation.get("kind") == "paint" and command.get("revision",-1) == observation.edge.get("revision",-2):
			command = {"tool":"paint_edge","args":command,"provider":"local-mailbox","call_id":ticket}
	last_command = command.duplicate(true)
	start_at = actor.player.position
	if not error.is_empty():
		if divine_running:
			invitation={}
			if divine_job.has("project_id"):
				scene_projects.outcome({"ok":false,"detail":error},false)
			_close_divine_job(error)
			phase="rest"
			clock=2.8
			wait_for_change=true
			return
		if observation.has("building") and worker.last_error_code == "invalid_response":
			unfinished_building = {"kind":str(observation.invitation.kind),"text":str(observation.invitation.text),"slot":int(observation.invitation.slot),"prior":worker.rejected_building.duplicate(true)}
		var recoverable_autonomy: bool = autonomous_execution and invitation.is_empty() and worker.last_error_code in ["no_tool_action","request_rejected"]
		phase = "rest" if recoverable_autonomy else "offline"
		clock = 0.0 if recoverable_autonomy else 20.0
		if recoverable_autonomy:wait_for_change=false
		caption = "图稿未完成 · 打开图纸包再试" if observation.has("building") and worker.last_error_code=="invalid_response" else error
		if autonomous_execution: autonomy.record("observation",error,false,actor.player.position)
		game.message(error)
		return
	var tool := str(command.get("tool",""))
	var args = command.get("args")
	var intent := str(invitation.get("kind",""))
	invitation = {}
	if not args is Dictionary or (not worker.accepts_command(command) and not external):
		_finish(false,"没有收到有效的动作")
		return
	if autonomous_execution:
		autonomy.accept(command,{"travel":"考察可达地点","survey_frontier":"亲往纸边勘察","paint_edge":"接通纸边道路","shape_site":"整理可达用地",
			"talk_npc":"询问当地居民","paper_ink":"在选定方向接纸"}.get(tool,"查看现场变化"))
	match tool:
		"survey_frontier":
			var survey:Dictionary=observation.get("autonomy",{}).get("frontier",{})
			var at:=WorldPen.point(survey.get("stand"))
			if not autonomous_execution or not at.is_finite():
				_finish(false,"这一轮没有已验证的外沿脚面")
				return
			_go(at.x,"region","自主走向真实东侧纸边",at)
		"plan_scene":
			var authoring:bool=autonomous_execution and not observation.get("autonomy",{}).get("scene_opportunity",{}).is_empty()
			if not authoring and (not divine_running or intent!="divine_chat" or divine_job.has("project_id")):
				_finish(false,"这次没有可登记的工程委托")
				return
			var selection := {}
			if args.site=="here":
				selection={"id":"here","label":"阿靛当前脚下","stand":Senses.pair(actor.player.position-Vector2(0,.29))}
			else:
				for route in observation.get("autonomy",{}).get("routes",[]):
					if route.id==args.site and _pair(route.get("stand")):
						selection=route
						break
			var brief:String="阿靛的自主工程《%s》，在%s施工。保留原有走位，按所选用途实走或验用。"%[args.title,selection.get("label","选定地点")] if authoring else divine_job.text
			args.origin="autonomous" if authoring else "player"
			var planned:Dictionary=scene_projects.add(args,brief,Autonomy.scope(game),selection) if not selection.is_empty() else {}
			if planned.is_empty():
				_finish(false,"所选地点或工程阶段不可用")
				return
			planned.planning={"request_id":ticket,"call_id":command.get("call_id",""),
				"model":command.get("model",""),"provider":command.get("provider","")}
			_finish(true,"已登记长工程「%s」，先去核对选址。"%args.title)
		"revise_scene_plan":
			if not divine_running or divine_job.has("project_id") or not scene_projects.revise(args.get("remaining"),str(divine_job.text)):
				_finish(false,"原工程还不能按这份余下工序修改，已完成的工序和成果都保留。")
				return
			var project:=scene_projects.active()
			project.outcomes.append({"phase":scene_projects.step().kind,"tool":tool,"ok":true,
				"detail":args.message,"call_id":last_command.get("call_id","")})
			_finish(true,"已在同一工程调整余下工序。")
		"clarify_scene_checks":
			var project:=scene_projects.active()
			var index:=int(args.get("phase",-1))
			if not divine_running or divine_job.has("project_id") or project.is_empty() or index<0 or index>=project.phases.size() or \
				not project.phases[index].kind in ["water","verify"]:
				_finish(false,"找不到这份工程的原水岸查验工序")
				return
			project.boat=args.boat
			project.water_access=args.water_access
			project.clarification=divine_job.text
			var previous:int=int(project.cursor)
			if index<previous and previous<project.phases.size():project.return_to=previous
			project.cursor=index
			project.stage="working"
			project.attempts=0
			project.moves=0
			project.outcomes.append({"phase":project.phases[index].kind,"tool":tool,"ok":true,"detail":args.message,
				"call_id":command.get("call_id","")})
			_finish(true,"已按你这次的说明调整原工程的查验目标。")
		"resume_scene":
			var project:=scene_projects.active()
			if project.get("stage")!="paused":
				_finish(false,"当前没有暂停的工程")
				return
			project.stage="working"
			project.attempts=0
			project.moves=0
			_finish(true,"接着做「%s」，保留已完成的作品。"%project.title)
		"revise_scene_access":
			if not divine_running or intent!="divine_chat" or divine_job.has("project_id"):
				_finish(false,"请先说明要改哪处已建使用位置。")
				return
			var seen:Array=observation.get("scene_components",[]).filter(func(row):return row.editable and row.work_id==args.get("work_id"))
			if seen.is_empty():
				_finish(false,"原建筑不在这次现场观察里。")
				return
			var move:Dictionary=AccessRevision.selected(seen[0],args)
			if move.has("error"):
				_finish(false,move.error)
				return
			var edit:=AccessRevision.prepare(game,move)
			if edit.has("error"):
				_finish(false,edit.error)
				return
			divine_job.access_move=move
			var at:=BuildingPlans.point(move.feet)
			_go(at.x,"revise_scene_access","去新使用位试脚",at)
		"revise_scene_component":
			if not divine_running or intent!="divine_chat" or divine_job.has("project_id"):
				_finish(false,"目前没有玩家委托的局部改绘。")
				return
			var candidates:Array=observation.get("scene_components",[]).filter(func(row):return row.editable and row.work_id==args.get("work_id"))
			if candidates.is_empty():
				_finish(false,"请先选本次确实看到、能够原位改画的建筑。")
				return
			args=args.merged({"expected_plan_id":candidates[0].plan_id,"expected_origin":candidates[0].origin_world},true)
			var edit:=SceneComponent.prepare(game,actor.player.position-Vector2(0,.29),args)
			if edit.has("error"):
				_finish(false,edit.error)
				return
			_start_pen(edit.command)
			if phase=="pen":pen_command.scene_component=args.duplicate(true)
		"reuse_scene_plan","redraw_scene_plan":
			var sheet:int=int(args.get("plan",-1))
			if not divine_running or not BuildingPlans.list_plans(game,"companion").any(func(row):return int(row.id)==sheet):
				_finish(false,"本队找不到这张母图")
				return
			if tool=="redraw_scene_plan":
				divine_job.edit_plan=sheet
				divine_running=false
				phase="rest"
				clock=0.2
				return
			_place_scene_plan(BuildingPlans,sheet,actor.player.position)
		"paint_scene_detail":
			var current:=scene_projects.step()
			var detail_stage:bool=current.get("kind")=="vegetation" or current.get("kind")=="landscape" and (current.get("form")=="scenery" or not str(scene_projects.active().get("subject","")).is_empty())
			if not divine_job.has("project_id") or not detail_stage or not args.get("command") is Dictionary:
				_finish(false,"没有可画的景物工序")
				return
			if current.get("kind")=="vegetation" and not _admit_plant_batch(args.get("plant",{})):return
			_start_pen(args.command)
		"finish_vegetation":
			if not divine_job.has("project_id") or scene_projects.step().get("kind")!="vegetation":
				_finish(false,"目前没有待查验的植被")
				return
			var review:=PlantReview.review(world,scene_projects.active())
			var missing:=PackedStringArray(review.missing)
			_finish(review.ok,"已核实接地与冠团，自此可以推进工序。" if review.ok else "植被还缺："+ "、".join(missing),
				{"vegetation_verified":review.ok,"plant_review":review})
		"paint_distant_sheet":
			_start_distant_sheet(args)
		"reframe_distant_sheet", "revise_distant_wash":
			_edit_distant_sheet(args, tool=="revise_distant_wash")
		"finish_distant_sheet":
			var ids:=scene_projects.distant_ids()
			var present:bool=not ids.is_empty() and world.paper_strokes_snapshot().any(func(mark):
				return mark.has("projection") and mark.work_id in ids)
			_finish(present,"已核实本工序纸上原笔和远景投影。" if present else "当前工序还没有实际落地的远景纸。",
				{"distant":present,"finish_distant":present})
		"search_scene_studies":
			if not divine_job.has("project_id") or not observation.has("scene_study_index") or not scene_projects.step().get("kind") in ["landscape","vegetation"]:
				_finish(false,"当前工序尚未打开本世界的公共笔谱。")
				return
			if not StudyIndex.valid_filters(args):
				_finish(false,"请用文字检索名称、作者和部件，并使用非负的目录起点。")
				return
			study_filters = args.duplicate()
			_finish(true,"已翻查公共笔谱，下一次观察可见匹配的图页与部件。",{"partial":true})
		"read_scene_study":
			_read_scene_study(args)
		"compose_scene_study":
			_compose_scene_study(args)
		"reuse_shore_plan":
			if not divine_job.has("project_id") or scene_projects.step().get("form")!="foundation":
				_finish(false,"当前没有待查验的柜台地基。")
				return
			var shore:=_scene_shore()
			if int(shore.get("plan_id",-1))<0:
				_finish(false,"这里只验了干岸，须先设计母图。")
				return
			var at:=WorldPen.point(args.get("stand"))
			for site:Dictionary in shore.get("sites",[]):
				if not at.is_finite() or WorldPen.point(site.stand).distance_to(at)>.06:continue
				var project:=scene_projects.active()
				var next:int=int(project.cursor)+1
				if next>=project.phases.size() or project.phases[next].kind!="building":break
				project.shore_build={"plan":shore.plan_id,"at":site.origin,"stand":site.stand,
					"command":{"tool":tool,"call_id":command.get("call_id","")},"request_id":ticket}
				_finish(true,"原图支点和柜位在实岸查验通过，带图前往原生落笔。")
				return
			_finish(false,"原图和来客位还没有同一可达的实岸。")
		"finish_scene_foundation":
			var found:=false
			if divine_job.has("project_id") and scene_projects.step().get("form")=="foundation":
				var id:=str(args.get("site",""))
				var sites: Array=[]
				if id.begins_with("shore@"):
					var shore:=_scene_shore()
					if shore.get("scope")=="frontage":
						for bank:Dictionary in shore.get("sites",[]):
							if bank.get("frontage_ready",false):sites.append(_shore_frontage(bank))
				else:
					sites=_scene_foundation()
				for site:Dictionary in sites:
					if site.id!=id or not site.frontage.level_site_clear:continue
					scene_projects.active().foundation_site=site.duplicate(true)
					found=true
					break
			_finish(found,"已复核柜前两米干地的实地柱脚和来路。" if found else "原地基已保留，尚无两米连续、干燥且可达的立柜位。")
		"verify_scene":
			_verify_scene_project()
		"pause_scene":
			if not divine_job.has("project_id"):
				_finish(false,"没有可暂停的工程")
				return
			scene_projects.outcome({"tool":tool,"ok":false,"detail":args.reason,"call_id":command.get("call_id","")},false)
			scene_projects.active().stage="paused"
			_close_divine_job("工程暂停："+str(args.reason))
			_finish(false,str(args.reason))
		"plan_channel_sections":
			var project:=scene_projects.active()
			if not divine_running or project.get("stage") not in ["paused","working"] or \
				not scene_projects.step().get("kind") in ["landscape","water","verify"] or \
				not ChannelPlan.draft(project,args.get("sections",[])):
				_finish(false,"原工程没有可存的分段稿。请保留已验段，并在所选短段范围内给有效床形。")
				return
			_refresh_channel_checks(project,true)
			project.channel_plan.last_edit={"provider":command.get("provider",""),"model":command.get("model",""),
				"call_id":command.get("call_id",""),"request_id":ticket}
			if args.get("start",false):
				project.stage="working"
				project.moves=0
				project.attempts=0
			_finish(true,"分段施工稿已保存。未落笔位置仍待实际到岸。",{"partial":true})
		"verify_channel_section":
			var project:=scene_projects.active()
			if not divine_running or project.get("stage") not in ["paused","working"]:
				_finish(false,"当前没有可验的同队水道工程。")
				return
			var proof:=ChannelPlan.measure(world,project,str(args.get("id","")))
			if proof.is_empty():
				_finish(false,"找不到这一段已登记的施工稿。")
				return
			_finish(proof.ok,"这段实际连续开口 %.2f 米，施工稿跨度 %.2f 米。"%[proof.clear_span_m,proof.planned_span_m],
				{"partial":proof.ok,"verified_channel_section":proof.ok})
		"scene_reposition":
			if not divine_job.has("project_id"):
				_finish(false,"没有待调整站位的工程")
				return
			for site in observation.get("autonomy",{}).get("routes",[]):
				if site.id==args.site and _pair(site.get("stand")):
					var to:=WorldPen.point(site.stand)
					_go(to.x,"scene_adjust","换站 · "+site.label,to)
					return
			_finish(false,"该处没有已观测的施工站位")
		"rework_scene":
			var project:=scene_projects.active()
			var redo:int=int(args.get("phase",-1))
			if project.is_empty() or not divine_job.has("project_id") or redo<0 or redo>=project.cursor or int(project.get("reworks",0))>=2:
				_finish(false,"这个工序不能再退回")
				return
			project.cursor=redo
			project.attempts=0
			project.moves=0
			project.reworks=int(project.get("reworks",0))+1
			_close_divine_job("已退回需要修正的工序，旧作品继续保留。")
			_finish(true,"将按原用途修补现有工程")
		"divine_reply":
			if not divine_running or intent!="divine_chat" or not args.get("message") is String:
				_finish(false,"未得到有效的聊天回复")
				return
			if divine_job.has("project_id"):
				scene_projects.outcome({"tool":tool,"ok":false,"detail":args.message},false)
				scene_projects.active().stage="paused"
			_close_divine_job(args.message,true)
			_finish(true,"已回应")
		"travel_frontier":
			var edge_site:Dictionary=observation.get("divine_chat",{}).get("east_frontier",{})
			if not divine_running or intent!="divine_chat" or edge_site.is_empty():
				_finish(false,"本轮没有可走的东侧纸边")
				return
			_begin_divine_travel(edge_site,"expand",str(args.get("message","")))
		"travel":
			for route in observation.get("autonomy",{}).get("routes",[]):
				if route.id==args.get("id"):
					if divine_running:
						var after:String=args.get("after_arrival","create")
						if route.id=="east-frontier" and after=="create":
							_begin_divine_travel(observation.divine_chat.get("east_frontier",{}),"expand",str(args.get("message","")))
						else:
							_begin_divine_travel(route,after,str(args.get("message","")))
						return
					var dest:=Vector2(route.stand[0],route.stand[1]) if _pair(route.stand) else Vector2.INF
					_go(float(route.stand[0]),"region","走向"+route.label,dest if route.id!="east-frontier" else Vector2.INF)
					return
			_finish(false,"刚才的观察没有这个地点")
		"shape_site":
			if not autonomous_execution or not args.get("command") is Dictionary or args.command.get("tool")!="draw_terrain":
				_finish(false,"这处用地没有可执行的地形笔稿")
				return
			_start_pen(args.command)
		"paper_ink":
			if autonomous_execution or (divine_running and intent=="divine_chat"):
				if divine_running: _divine_message("god",str(args.get("message","")))
				_start_paper_plan(args)
			else: _finish(false,"这项笔画须依据现场独立选址")
		"talk_player", "greet":
			var words := _words(args.get("text"))
			if words.is_empty(): _finish(false,"没听清"); return
			_remember("阿靛",words)
			_finish(true,words)
			_say("阿靛",words,3.1)
			phase = "speak"
			clock = 3.1
		"talk_npc":
			target_npc = str(args.get("id",""))
			npc_question = _words(args.get("text"))
			var seen: bool = observation.nearby_npcs.any(func(p): return p.id == target_npc)
			var person = world.entity_by_id(target_npc)
			if not seen or person == null or not person.alive or npc_question.is_empty():
				target_npc = ""
				_finish(false,"刚才那位居民已经走远了")
				return
			_go(person.position.x,"npc","去问问"+Senses.ROLE_NAMES.get(person.kind,"居民"))
		"walk":
			for site in observation.sites:
				if site.id == args.get("site"):
					_go(site.stand[0],"explore","往那边走走",Vector2(site.stand[0],site.stand[1]))
					return
			_finish(false,"这个落脚点已不在眼前")
		"paint_edge":
			if observation.edge.is_empty() or int(observation.edge.revision) != int(world.observe_east_edge().revision):
				_finish(false,"纸边已经变了"); return
			work_observation = args.duplicate(true)
			if divine_running and intent=="divine_chat":
				_divine_message("god",str(args.get("message","")))
			work_observation.erase("message")
			work_observation.revision = observation.edge.revision
			work_observation.work_id="companion-"+Crypto.new().generate_random_bytes(12).hex_encode()
			work_observation.author_id="companion"
			work_observation.merge(Autonomy.scope(game),true)
			_go(world.east_walk_limit()-0.05,"edge","去纸边画「%s」" % _words(args.get("name")))
		"design_building","variant_building":
			var parent_id := int(observation.invitation.get("slot",-1))
			var is_variant := intent == "building_variant"
			if intent not in ["building_design","building_variant"] or (tool == "variant_building") != is_variant or int(args.get("parent_id",-2)) != (parent_id if is_variant else -1):
				_finish(false,"这张图的母图编号与本次委托不一致")
				return
			if not observation.has("building") or not _pair(args.get("origin")) or not _pair(observation.building.get("origin")):
				_finish(false,"图上缺少底部定位点")
				return
			var assigned: Array = observation.building.origin
			if Vector2(args.origin[0],args.origin[1]).distance_to(Vector2(assigned[0],assigned[1])) > 0.0001:
				_finish(false,"图稿偏离了本次委托的定位点")
				return
			if not args.get("layout") is Dictionary or not args.get("command") is Dictionary or args.command.get("tool") != "draw_scenery":
				_finish(false,"图稿缺少公共笔迹或使用位置")
				return
			design_draft = args.duplicate(true)
			_start_pen(args.command,true)
			if phase == "pen": caption = "改画「%s」" % args.name if is_variant else "设计「%s」" % args.name
		"copy_scenery":
			if intent != "copy" or args.get("revision",-1) != study_revision or not _reference_current():
				_finish(false,"草稿已换，请再递一次")
				return
			_start_pen(reference_command, true)
		"functional_pen":
			var cmd = args.get("command")
			if intent != "pen" or not cmd is Dictionary or cmd.get("tool") != observation.pen.get("requested"):
				_finish(false,"请告诉我想用哪支笔"); return
			pen_invitation = observation.invitation.duplicate(true)
			_start_pen(cmd)
		"walk_and_draw":
			for site in observation.sites:
				if site.id == args.get("site") and observation.can_draw:
					var origin := Vector2(site.paper[0],site.paper[1])
					var points := []
					var outline = args.get("outline",[])
					if not outline is Array or outline.size() < 4 or outline.size() > 18: break
					for p in outline:
						if not _pair(p): _finish(false,"笔迹超出纸面"); return
						var delta := Vector2(p[0],p[1])
						if absf(delta.x)>0.65 or delta.y<0 or delta.y>1.05: _finish(false,"笔迹超出纸面"); return
						points.append([origin.x+delta.x,origin.y+delta.y])
					points[-1] = points.front()
					_start_pen({"tool":game.FunctionalPens.OBJECT,"name":args.get("name","手稿"),"strokes":[points],"style":"ink"})
					return
			_finish(false,"这里没有合适的落笔点")
		_:
			_finish(true,"歇一会儿")
			wait_for_change = true

func _go(x: float, reason: String, text: String, goal := Vector2.INF) -> void:
	target_x = x
	walk_goal=goal
	walk_plan={}
	destination = reason
	phase = "walk"
	clock = 0
	walk_timeout=clampf(absf(x-actor.player.position.x)/2.0+7.0,7.0,125.0) if reason in ["revise_scene_access","region","divine_site","scene_survey","scene_adjust","scene_foundation_walk","scene_verify","scene_verify_origin","scene_verify_wet","scene_build_site"] else 7.0
	caption = text

func _walk(delta: float) -> int:
	clock += delta
	if destination == "npc":
		var npc = world.entity_by_id(target_npc)
		if npc == null or not npc.alive: _finish(false,"居民离开了"); return 0
		target_x = npc.position.x
		if actor.player.position.distance_to(npc.position) < (1.2 if Witness.asks_news(npc_question) else 3.1):
			_remember("阿靛",npc_question)
			_say("阿靛",npc_question,2.1)
			phase = "speak"
			clock = 2.1
			return 0
	var dx: float = target_x-actor.player.position.x
	var stop_distance := .085 if destination == "plan_access" else .19
	var arrived:=absf(dx)<stop_distance and destination!="npc"
	if walk_goal.is_finite() and world.has_method("paper_nav_route"):
		var foot:Vector2=actor.player.position-Vector2(0,.29)
		if destination=="scene_verify" and divine_job.has("verify_support") and absf(foot.x-walk_goal.x)<.21 and absf(foot.y-walk_goal.y)<.34:
			_check_scene_contact(delta)
			return 0
		if walk_plan.is_empty():
			walk_plan=world.paper_nav_route(foot,walk_goal)
			if not walk_plan.get("ok",false):
				_finish(false,str(walk_plan.get("error","没有可达的实地路线")))
				return 0
		var step:Dictionary=world.paper_nav_steer(walk_plan,foot,delta,actor.on_ground and not actor.player.support_bodies().is_empty())
		if not step.get("ok",false) or clock>walk_timeout:
			_finish(false,str(step.get("error","没有走通这条实地路线")))
			return 0
		arrived=step.arrived
		if not arrived:
			reach_jump=step.jump and actor.on_ground
			route_down=step.get("down",false)
			return int(step.direction)
	if arrived:
		if destination == "plan_access" and absf(actor.player.linear_velocity.x) > .25: return 0
		if destination=="scene_survey":
			scene_projects.active().surveyed=true
			phase="rest"
			destination=""
			caption="到达工程现场，查看可落笔的地层"
			clock=.45
		elif destination=="revise_scene_access":
			if AccessRevision.standing_contact(game,actor,walk_goal).is_empty():
				var elapsed:=float(divine_job.get("access_settle",0))+delta
				divine_job.access_settle=elapsed
				if elapsed<.8:return 0
			var receipt:=AccessRevision.install(game,actor,divine_job.access_move,{"artist":"companion","tool":last_command.tool,"request_id":ticket,"call_id":last_command.get("call_id",""),"provider":last_command.get("provider",""),"model":last_command.get("model","")})
			var moved:bool=receipt.get("ok",false)
			_finish(moved,"阿靛已站到改后位置「%s」，原柜与旧图保存在本队。"%receipt.use if moved else receipt.error,receipt)
			if moved:game.save_game()
		elif destination=="scene_foundation_walk":
			divine_job.clear()
			destination=""
			phase="rest"
			caption="到了已量好的干岸，准备画柜"
			clock=.35
		elif destination=="scene_adjust":
			_finish(true,"已换到另一脚位，再量当下可及处。")
		elif destination=="scene_build_site":
			var project:=scene_projects.active()
			var pending:Dictionary=project.get("pending_build",{})
			project.erase("pending_build")
			_build_scene_at(int(pending.get("plan",-1)),WorldPen.point(pending.get("at")))
		elif destination=="scene_verify_origin":
			_start_scene_verify_leg()
		elif destination=="scene_verify_wet":
			var feet:Vector2=actor.player.position-Vector2(0,.29)
			var inside:bool=is_finite(world.paper_space.water_surface(feet+Vector2(0,.008)))
			var elapsed:=float(divine_job.get("wet_settle",0))+delta
			divine_job.wet_settle=elapsed
			if not inside or not actor.on_ground:
				if elapsed<.8:return 0
				_finish(false,"到达岸口附近，实停脚点还没有碰到水；请扩大可走岸口。")
				return 0
			divine_job.water_foot=Senses.pair(feet)
			divine_job.erase("wet_goal")
			_start_scene_verify_leg()
		elif destination=="scene_verify":
			_check_scene_contact(delta)
		elif destination=="divine_site":
			var stand: Array=divine_job.selected_site.at
			if absf(actor.player.position.y-float(stand[1])-.48)>1.35:
				_finish(false,"到了相同横坐标，但当前在另一层，没找到通往施工点的路。")
				return 0
			if divine_job.selected_site.get("after_arrival")=="report":
				_finish(true,"已到%s，脚下有可行走的实地。"%divine_job.selected_site.label)
				return 0
			divine_job.arrived_at=Senses.pair(actor.player.position)
			divine_job.travel_left=0
			divine_running=false
			phase="rest"
			destination=""
			divine_progress="已到现场，正在复查落笔位置。"
		elif destination == "edge":
			var result: Dictionary = world.submit_east_segment(work_observation,true)
			if not result.ok: _finish(false,result.error); return 0
			active_edge_name = work_observation.name
			caption = "画「%s」" % active_edge_name
			var fixes = last_command.get("geometry_fixes",[])
			if fixes is Array and not fixes.is_empty(): game.message("阿靛调整了 %d 处笔段，开始落笔" % fixes.size())
			phase = "work"
		elif destination == "plan_access":
			if actor.player.position.distance_to(plan_access_target+Vector2(0,.65))>1.5:
				_finish(false,"这个使用位与脚下地面有落差，走不到棚下")
				game.message(last_result.detail)
				return 0
			_finish(true,"我在这里接果子")
			last_result.stand_delta = absf(actor.player.position.x-plan_access_target.x)
			last_result.stand_target = Senses.pair(plan_access_target)
			wait_for_change = true
			clock = 35.0
		elif destination == "cross":
			var edge:Dictionary=world.observe_east_edge()
			var grounded:bool=actor.on_ground and not actor.player.support_bodies().is_empty()
			if divine_running and not grounded:
				if clock>walk_timeout:_finish(false,"新地表已经接出，阿靛还没能站稳试路")
				return 0
			var detail:="走上了「%s」" % active_edge_name
			if divine_running:
				divine_work_ids=[work_observation.work_id]
				detail="已接出「%s」，东边界到 %.1f 米。我已经走过接缝并站上新地表。" % [active_edge_name,edge.edge[0]]
			var extras := {"work_ids":[work_observation.work_id]} if divine_job.has("project_id") else {}
			_finish(true,detail,extras)
			last_result.edge = edge.edge
			last_result.name = active_edge_name
			last_result.grounded = grounded
		else:
			_finish(true,"走到了")
			wait_for_change = last_observation.get("edge",{}).is_empty() and last_result.tool == "walk" and not dialogue.is_empty()
		return 0
	if clock > walk_timeout:
		_finish(false,"这里走不过去，换个位置")
		return 0
	return int(signf(dx))

func _npc_reply() -> void:
	var npc = world.entity_by_id(target_npc)
	if npc == null or not npc.alive or actor.player.position.distance_to(npc.position)>5:
		_finish(false,"居民走远了")
		return
	var who: String = Senses.ROLE_NAMES.get(npc.kind,"居民")
	if Witness.asks_news(npc_question):
		var answer:=Witness.ask(world,actor.player.position,target_npc,npc_question)
		if not answer.ok:
			_finish(false,answer.message)
			return
		_remember(answer.label,answer.message)
		_finish(true,"听到"+answer.label+"的近况",Witness.receipt(answer))
		_say(answer.label,answer.message,4.5,answer.npc_id)
		clock=4.5
		return
	var words := Senses.answer(world,npc)
	var id := target_npc
	_remember(who,words)
	_finish(true,"听到"+who+"的回话")
	last_result.npc_id = id
	last_result.reply = words
	_say(who,words,3.3,id)
	clock = 3.4

func _work(delta: float) -> int:
	var next: Dictionary = world.east_work_target(delta*INK_SPEED)
	if next.is_empty():
		actor.active_stroke = null
		nib_world = Vector2.INF
		_go(world.east_walk_limit()-0.4,"cross","去踩踩新画的路")
		return 0
	var point: Vector2 = next.nib
	actor.brush_target = point
	var dx: float = point.x-actor.player.position.x
	var grip := hand_world()
	actor.facing = 1 if dx>=0.0 else -1
	# Walk on the last inked surface while keeping the bunched bristles in reach.
	var high: bool = point.y - world.travel_height(point.x) > 1.25
	var stand: float = minf(point.x - (0.10 if high else 0.63),world.east_walk_limit()-0.03)
	var move: float = stand-actor.player.position.x
	var direction := int(signf(move)) if absf(move)>0.10 else 0
	if grip.distance_to(point) <= REACH and absf(dx)<1.65 and (not nib_world.is_finite() or nib_world.distance_to(point)<0.45):
		if world.advance_east_nib(point,grip,REACH):
			nib_world = point
			actor.active_stroke = {"points":[point]} if direction==0 else null
	else:
		nib_world = Vector2.INF
		actor.active_stroke = null
		reach_jump = high and direction==0 and grip.distance_to(point)>REACH and actor.on_ground
	return direction

func hand_world() -> Vector2:
	return actor.hand_world() if actor != null else Vector2.INF

static func _pair(p: Variant) -> bool:
	if not p is Array or p.size()!=2: return false
	for n in p:
		if typeof(n) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(n)): return false
	return true

func _reference_current() -> bool:
	return game.draw_mode == 7 and game.active_stroke == null and reference_command == game.FunctionalPens.from_draft(7,game.pen_style,game.draft)

func _start_paper_plan(args: Dictionary) -> void:
	if not world.has_method("apply_paper_plan") or not args.get("strokes") is Array or args.strokes.is_empty() or args.strokes.size()>5:
		_finish(false,"这里暂无可提交的接纸笔划")
		return
	var project_id:String=str(args.get("project_id",""))
	if not project_id.is_empty():
		var selected:=scene_projects.active()
		if not divine_running or divine_job.has("project_id") or selected.get("project_id")!=project_id or \
			not selected.get("stage") in ["working","paused"] or not scene_projects.step().get("kind") in ["landscape","water","verify"]:
			_finish(false,"这笔所属的工程已经切换或结束。")
			return
		divine_job.chat_paper_project=project_id
	var actual := []
	var preview := []
	var lines := []
	var scope := Autonomy.scope(game)
	for row in args.strokes:
		if not row is Dictionary or not WorldPen.MODES.has(row.get("mode")) or not row.get("anchor") is Dictionary or not row.get("points") is Array:
			_finish(false,"笔划的类型、支点或点列缺失")
			return
		var stroke: Dictionary = row.duplicate(true)
		if last_command.get("tool")!="compose_scene_study":
			stroke.work_id = "companion-"+Crypto.new().generate_random_bytes(12).hex_encode()
			stroke.name = _words(args.get("name","接纸"))
		stroke.author_id="companion"
		stroke.team_id=scope.get("team_id","")
		stroke.world_id=scope.get("world_id","")
		if stroke.mode in ["rock","water","carve","backdrop"] and not stroke.points.is_empty() and stroke.points.back()!=stroke.points.front():
			stroke.points.append(stroke.points.front())
		var hit := WorldPen.resolve_anchor(game,stroke.anchor)
		var first := WorldPen.point(stroke.points.front()) if not stroke.points.is_empty() else Vector2.INF
		if not hit.is_finite() or not first.is_finite():
			var detail:="声明的支点或首笔附近没有可用表面"
			if stroke.anchor.kind=="ground":
				var requested:=WorldPen.point(stroke.anchor.at)
				if requested.is_finite():
					var surfaces:Array=world.paper_surfaces(requested.x,requested.y-1.50,requested.y+1.50)
					var nearest:=Vector2.INF
					for surface:Dictionary in surfaces:
						if surface.face!="floor":continue
						var candidate:=Vector2(requested.x,surface.y)
						if candidate.distance_squared_to(requested)<nearest.distance_squared_to(requested):nearest=candidate
					if nearest.is_finite():
						detail+="；同一横坐标的实测脚面 %.2f、%.2f 米，请从脚面起笔，握笔点只计算够不够远。"%[nearest.x,nearest.y]
			_finish(false,detail+"。")
			return
		var placed := stroke.duplicate(true)
		if stroke.anchor.kind!="free":
			var request := WorldPen.point(stroke.anchor.at)
			if not WorldPen.within_anchor_reach(first,request):
				_finish(false,"首笔要从声明的支点起笔")
				return
			placed.anchor.at=[hit.x,hit.y]
			if WorldPen.should_align(stroke.mode):
				var shifted := []
				for point in stroke.points:
					var translated := WorldPen.point(point)+hit-first
					if not translated.is_finite():
						_finish(false,"无法预览无效笔迹坐标")
						return
					shifted.append([translated.x,translated.y])
				shifted[0]=[hit.x,hit.y]
				placed.points=shifted
		actual.append(stroke)
		preview.append(placed)
		lines.append(placed.points)
	var segment:String=str(args.get("segment_id",""))
	if not segment.is_empty() and (not divine_job.has("project_id") and not divine_job.has("chat_paper_project") or \
		not ChannelPlan.permits(scene_projects.active(),segment,preview)):
		_finish(false,"这批笔与本工程已登记的小段没有落点重合，或该段已经查验。")
		return
	if not segment.is_empty():
		var section:=ChannelPlan.section(scene_projects.active(),segment)
		var declared=section.get("level")
		if (section.has("grade_for_water") or section.get("kind")=="water") and (declared is float or declared is int):
			for stroke:Dictionary in preview:
				if stroke.mode!="water":continue
				var top:float=-INF
				for point in stroke.points:top=maxf(top,float(point[1]))
				if absf(top-float(declared))>.002:
					_finish(false,"这一段的共同水尺是 %.3f 米，新笔水面为 %.3f 米。保留旧水，请按同一实际高度接。"%[float(declared),top])
					return
	if divine_job.has("project_id") and scene_projects.step().get("kind")=="water" and not scene_projects.active().get("boat",false):
		var status:=SceneWaterBody.observe(world,scene_projects.active())
		var issue:=SceneWaterBody.check(preview,status)
		if not issue.is_empty():
			_finish(false,issue)
			return
	var conflict:=_counter_cut_conflict(preview)
	if not conflict.is_empty():
		_finish(false,conflict)
		return
	var trial: Dictionary = world.apply_paper_plan(preview,false)
	if not trial.get("ok",false):
		_finish(false,trial.get("error","接纸位置需要重选"))
		return
	_start_pen({"tool":"paper_ink","name":_words(args.get("name","接纸")),"style":"ink","strokes":lines,"paper_records":actual,"opened_bank":args.get("opened_bank",false),"cut_basin":args.get("cut_basin",false),"channel_section":segment,
		"measured_channel":args.get("measured_channel",false) and scene_projects.active().get("boat",false)})

func _edit_distant_sheet(args:Dictionary, wash:bool) -> void:
	var known:Array=last_observation.get("scene_distant_frames",[])
	var index:=known.find_custom(func(row):return row.work_id==args.get("work_id"))
	var scope:=Autonomy.scope(game)
	if not divine_running or index<0 or not ResourceLoader.exists(DISTANT_SHEET_PATH):
		_finish(false,"本轮没有可修改的本人远景纸。")
		return
	var frame:Dictionary=known[index]
	if frame.team_id!=scope.get("team_id") or frame.world_id!=scope.get("world_id") or frame.revision!=args.get("expected_revision"):
		_finish(false,"这张原纸已换队或换版，请重看现场。")
		return
	var distant=load(DISTANT_SHEET_PATH)
	var method:="revise_washes" if wash else "reframe"
	if not _atlas_supports(distant,method):
		_finish(false,"当前游戏还不能执行这项远景纸修改。")
		return
	var call_id:String=str(last_command.get("call_id",""))
	if call_id.is_empty():
		_finish(false,"本次原纸修改没有可核的调用编号。")
		return
	var spec:={"team_id":frame.team_id,"world_id":frame.world_id,"work_id":frame.work_id,
		"expected_revision":frame.revision,"request_id":call_id}
	if wash:spec.edits=args.get("edits",[])
	else:
		spec.origin=args.get("origin")
		spec.size=args.get("size")
	var result:Dictionary=distant.revise_washes(game,"companion",spec) if wash else distant.reframe(game,"companion",spec)
	if not result.get("ok",false):
		_finish(false,result.get("error","原远景纸无法修改。"))
		return
	var detail:="已在原纸上重摆「%s」，耗墨零。"%frame.name
	var field:="sheet_reframe"
	if wash:
		detail="已在「%s」原纸改远景晕洗，实际耗墨%d。"%[frame.name,int(result.get("ink_spent",0))]
		field="sheet_wash_revision"
	var receipt:={"partial":true}
	receipt[field]=result
	_finish(true,detail,receipt)

func _start_distant_sheet(args:Dictionary) -> void:
	var step:=scene_projects.step()
	var selected:=scene_projects.active()
	var direct:=str(args.get("project_id",""))
	var same:bool=not direct.is_empty() and direct==selected.get("project_id") and selected.get("stage") in ["working","paused"]
	if not divine_running or (not divine_job.has("project_id") and not same) or not step.get("kind") in ["landscape","vegetation"] or not ResourceLoader.exists(DISTANT_SHEET_PATH):
		_finish(false,"请先选本队要补远景的原工程。")
		return
	if same and not divine_job.has("project_id"):divine_job.chat_paper_project=direct
	var distant=load(DISTANT_SHEET_PATH)
	var spec:=args.duplicate(true)
	spec.sheet_id="scene-"+str(last_command.get("call_id",ticket))
	var draft:Dictionary=distant.prepare(game,"companion",spec)
	if not draft.get("ok",false):
		_finish(false,str(draft.get("error","远景小纸未通过公共校验")))
		return
	var marks:Array=spec.strokes
	_start_pen({"tool":"distant_sheet","name":spec.name,"style":"ink","strokes":draft.hand_lines,
		"paper_records":draft.records,"distant_origin":spec.origin,"finish_distant":step.get("form")=="distant" and spec.get("finish",false),
		"brushes":marks.map(func(mark):return "wash" if mark.brush=="mist" else mark.brush),"pigments":marks.map(func(mark):return mark.pigment)})

func _complete_paper_plan() -> void:
	var records:Array=pen_command.get("paper_records",[])
	var conflict:=_counter_cut_conflict(records)
	if not conflict.is_empty():
		_finish(false,conflict)
		return
	var result := WorldPen.submit(game,records,"companion")
	var detail: String = "完成「%s」" % pen_command.get("name","接纸") if result.get("ok",false) else result.get("error","未完成接纸")
	if divine_running and result.get("ok",false):
		divine_work_ids=pen_command.paper_records.map(func(row):return row.work_id)
		var site: Dictionary=divine_job.get("selected_site",{})
		var first:PackedVector2Array=pen_lines[0]
		var at:Vector2=WorldPen.point(pen_command.get("distant_origin")) if pen_command.has("distant_origin") else first[0]
		var location: String="远景落点" if pen_command.has("distant_origin") else site.get("label","阿靛的施工点")
		detail="%s，%s，坐标 %.2f 米、%.2f 米。"%[detail,location,at.x,at.y]
	var receipt:=result.duplicate(true)
	if result.get("ok",false):
		receipt.work_ids=pen_command.paper_records.map(func(row):return row.work_id)
		receipt.modes=pen_command.paper_records.map(func(row):return row.mode)
		receipt.opened_bank=pen_command.get("opened_bank",false)
		receipt.cut_basin=pen_command.get("cut_basin",false)
		var segment:String=pen_command.get("channel_section","")
		if not segment.is_empty():
			ChannelPlan.record(scene_projects.active(),segment,receipt.work_ids)
			receipt.channel_section=segment
		var scene_water:bool=divine_job.has("chat_paper_project") or (divine_job.has("project_id") and scene_projects.step().get("kind")=="water")
		if scene_water and "water" in receipt.modes and world.paper_space.has_method("basin_sections"):
			receipt.water_sections=[]
			for stroke:Dictionary in pen_command.paper_records:
				if stroke.mode=="water":
					receipt.water_sections.append_array(world.paper_space.basin_sections(stroke.work_id))
			receipt.water_open=receipt.water_sections.any(func(row):
				return row.spans.any(func(span):return span.right-span.left>=.35 and span.depth>=.075))
			if not receipt.water_open:
				detail="水笔已保留，岩土扣除后还没有连续开口。请按实测两岸与水位改暗盆或在原作旁开新口。"
		if pen_command.has("distant_origin"):
			receipt.distant=true
			receipt.finish_distant=pen_command.get("finish_distant",false)
		_commit_plant_batch(receipt,pen_command.strokes,pen_command.paper_records.map(func(row):return row.get("brush","wash" if row.mode=="backdrop" else "fine")),
			pen_command.paper_records.map(func(row):return row.get("pigment","inherit")),pen_command.paper_records)
	_finish(result.get("ok",false),detail,receipt)

func _start_pen(cmd: Dictionary, copying := false) -> void:
	var strokes = cmd.get("strokes")
	if not strokes is Array or strokes.is_empty() or strokes.size()>(game.MAX_DRAW_STROKES if copying else 20): _finish(false,"手稿笔数不合适"); return
	var mark_error: String = game.FunctionalPens.check_marks(cmd,strokes.size())
	if not mark_error.is_empty():
		_finish(false,mark_error)
		return
	pen_lines.clear()
	for stroke in strokes:
		if not stroke is Array or stroke.size()<2 or stroke.size()>(DrawingRules.MAX_POINTS if copying else 128): _finish(false,"手稿缺少落点"); return
		var line := PackedVector2Array()
		for p in stroke:
			if not _pair(p): _finish(false,"笔迹坐标有误"); return
			var point := Vector2(p[0],p[1])
			var reach_from: Vector2=actor.player.position if autonomous_execution or divine_running else game.player.position
			if point.distance_to(reach_from)>12: _finish(false,"这笔超出作画者的落笔范围"); return
			line.append(point)
		pen_lines.append(line)
	pen_stands.clear()
	paper_stands.clear()
	paper_route.clear()
	paper_route_goal=Vector2.INF
	paper_settle=0.0
	if cmd.get("tool")=="paper_ink" or last_command.get("tool") in ["paint_scene_detail","revise_scene_component"]:
		var fine_stands:bool=cmd.get("measured_channel",false) or not str(cmd.get("channel_section","")).is_empty()
		var brush:=PenReach.observe_paper(game,actor,fine_stands)
		var placement:=PenReach.paper_plan(pen_lines,brush)
		if placement.has("error"):
			_reject_paper_reach(placement,brush)
			return
		paper_stands=placement.stands
	if not pen_invitation.is_empty() and not copying:
		var live_sites: Array = Senses.observe(game,actor,last_result).sites
		var reach := PenReach.observe(game,actor,live_sites)
		var plan := PenReach.plan(pen_lines,reach,actor.player.position.x)
		if plan.has("error"):
			_redraw_pen(plan.error)
			return
		pen_stands = plan.stands
	study_rect = Rect2()
	if copying:
		# Large architecture is copied at a hand-sized scale on the paper the
		# player handed over. The original metre-space command goes to the pen.
		var bounds := Rect2(pen_lines[0][0], Vector2.ZERO)
		for line in pen_lines:
			for point in line: bounds = bounds.expand(point)
		var ratio := minf(1.35/maxf(bounds.size.x,0.01),1.05/maxf(bounds.size.y,0.01))
		var center: Vector2 = actor.player.position + Vector2(0.7*actor.facing,0.77)
		study_rect = Rect2(center-bounds.size*ratio*0.5,bounds.size*ratio).grow(0.07)
		for i in pen_lines.size():
			var line: PackedVector2Array = pen_lines[i]
			for j in line.size(): line[j] = center + (line[j]-bounds.get_center())*ratio
			pen_lines[i] = line
	elif cmd.get("tool")=="distant_sheet":
		study_rect=Rect2(pen_lines[0][0],Vector2.ZERO)
		for line in pen_lines:
			for point in line:study_rect=study_rect.expand(point)
		study_rect=study_rect.grow(.06)
	pen_command = cmd
	pen_stroke = 0
	pen_point = 1
	pen_from = pen_lines[0][0]
	pen_trace = [PackedVector2Array([pen_from])]
	pen_wash_meshes.clear()
	phase = "pen"
	clock = 0.0
	caption = "誊绘建筑笔稿" if copying else "在小纸上画「%s」" % _words(cmd.name) if cmd.get("tool")=="distant_sheet" else "画「%s」" % _words(cmd.get("name","手稿"))

func _redraw_pen(reason: String) -> void:
	var order := pen_invitation.duplicate(true)
	_finish(false,reason)
	game.message(reason)
	if order.is_empty() or order.get("reach_retry",0) >= 1: return
	order.reach_retry = 1
	order.correction = reason
	invitation = order
	caption = "换个够得到的落点，重新起稿"
	clock = 0.0

func _reject_paper_reach(failure: Dictionary, brush: Dictionary) -> void:
	var repeated:bool=last_paper_reach.get("from")==failure.from and last_paper_reach.get("to")==failure.to
	last_paper_reach=failure.merged(brush)
	_finish(false,str(failure.error))
	last_result.paper_reach=last_paper_reach
	if not repeated:wait_for_change=false

func _advance_paper_stand(station: Dictionary, a:Vector2, b:Vector2, delta:float) -> Dictionary:
	var target:=PenReach.point(station.feet)
	var feet:Vector2=actor.player.position-Vector2(0,.29)
	var grounded:bool=actor.on_ground and not actor.player.support_bodies().is_empty()
	var hand:=hand_world()
	if grounded and maxf(hand.distance_to(a),hand.distance_to(b))<=REACH:
		paper_settle=0.0
		return {"ready":true}
	var error:=""
	if not station.get("current",false) or target.distance_to(feet)>.25:
		if paper_route_goal!=target:
			paper_route_goal=target
			paper_route=world.paper_nav_route(feet,target)
			paper_settle=0.0
		if paper_route.get("ok",false):
			var step:Dictionary=world.paper_nav_steer(paper_route,feet,delta,grounded)
			error=str(step.get("error",""))
			if step.get("ok",false) and clock<8.0:
				if not step.get("arrived",false):
					reach_jump=step.jump and grounded
					route_down=step.get("down",false)
					return {"direction":int(step.direction)}
				paper_settle+=delta
				if not grounded and paper_settle<1.25:return {}
		else:error=str(paper_route.get("error",""))
	if clock<.45 and error.is_empty():return {}
	var hint:="第%d笔第%d段从 (%.2f, %.2f) 到 (%.2f, %.2f)，手位 (%.2f, %.2f)，实际笔长 %.1f 米。"%[
		pen_stroke+1,pen_point,a.x,a.y,b.x,b.y,hand.x,hand.y,REACH]
	if error.is_empty():
		error="在这个点无法站稳，请先换到有真实支撑的位置。" if not grounded else "站稳后真实手位仍够不到，请缩短、抬高或换站位。"
	hint+=error
	_reject_paper_reach({"error":hint,"stroke":pen_stroke+1,"segment":pen_point,"from":Senses.pair(a),"to":Senses.pair(b),
		"nearest_station":station,"needed":snappedf(maxf(hand.distance_to(a),hand.distance_to(b)),.01)},PenReach.observe_paper(game,actor))
	return {}

func _functional_stroke(delta: float) -> int:
	clock += delta
	if not pen_stands.is_empty() and clock>2.0:
		_redraw_pen("第%d笔的站位已走不通，请把新稿移到身边" % (pen_stroke+1))
		return 0
	if pen_stands.is_empty() and clock > 25: _finish(false,"画笔够不到，那儿换个落点吧"); return 0
	var line: PackedVector2Array = pen_lines[pen_stroke]
	var to: Vector2 = pen_from.move_toward(line[pen_point],delta*INK_SPEED)
	if not paper_stands.is_empty():
		var step:=_advance_paper_stand(paper_stands[pen_stroke][pen_point-1],pen_from,line[pen_point],delta)
		if not step.get("ready",false):
			nib_world=Vector2.INF
			actor.active_stroke=null
			return int(step.get("direction",0))
	actor.brush_target = to
	var dx: float = to.x-actor.player.position.x
	var direction := int(signf(dx)) if absf(dx)>1.0 and not study_rect.has_area() else 0
	actor.facing = 1 if dx>=0 else -1
	if not pen_stands.is_empty() or not paper_stands.is_empty():
		direction = 0
	if hand_world().distance_to(to)>REACH:
		if not pen_stands.is_empty():
			var move: float = pen_stands[pen_stroke][pen_point-1] - actor.player.position.x
			direction = int(signf(move)) if absf(move) > 0.09 else 0
		reach_jump = direction == 0 and to.y > hand_world().y and actor.on_ground
		nib_world = Vector2.INF
		return direction
	nib_world = to
	if study_rect.has_area() or not pen_stands.is_empty() or not paper_stands.is_empty(): clock = 0.0
	actor.active_stroke = {"points":[to]}
	var trace: PackedVector2Array = pen_trace[-1]
	if trace.size()<2: trace.append(to)
	else: trace[-1] = to
	pen_trace[-1] = trace
	pen_from = to
	if to == line[pen_point]:
		pen_point += 1
		if pen_point == line.size():
			pen_stroke += 1
			if pen_stroke == pen_lines.size():
				if pen_command.has("scene_component"):
					var edit:=SceneComponent.install(game,actor,pen_command.scene_component,
						{"artist":"companion","tool":last_command.tool,"provider":last_command.get("provider",""),
							"model":last_command.get("model",""),"call_id":last_command.get("call_id",""),
							"request_id":ticket,"brief":divine_job.text})
					var success:bool=edit.get("ok",false)
					_finish(success,"已原位改绘「%s」的 %d 笔。原支点与使用位保留。"%[edit.name,edit.changed_strokes.size()] if success else edit.get("error","原建筑未改动"),edit)
					if success:game.save_game()
					return 0
				if not design_draft.is_empty():
					_store_design()
					return 0
				var copying: bool = last_command.get("tool","") == "copy_scenery"
				if copying and not _reference_current():
					_finish(false,"草稿已改动，请递给我新稿")
					return 0
				if pen_command.has("paper_records"):
					last_paper_reach.clear()
					_complete_paper_plan()
					return 0
				var in_scene:bool=divine_job.has("project_id")
				var ink: Dictionary = game.FunctionalPens.submit(game,pen_command,"painter",-1,actor if autonomous_execution or in_scene or last_command.get("tool")=="reuse_scene_plan" else null)
				if ink.get("ok",false) and not plant_draft.is_empty():
					_commit_plant_batch(ink,pen_command.strokes,pen_command.brushes,pen_command.pigments)
				if in_scene and pen_command.has("plan"):
					ink.plan_id=pen_command.plan.id
					ink.service_work=pen_command.plan.layout.get("stations",[]).any(func(s):return preload("res://scripts/architecture/stall_goods.gd").is_counter(s))
				if copying and ink.get("ok",false):
					game.draft = []
					game.mode_drafts[7] = []
					game.refresh_buttons()
				_finish(ink.get("ok",false),"画好了" if ink.get("ok",false) else ink.get("error","落笔失败"),ink)
				if last_command.get("tool") == "build_from_plan":
					last_result.placement = chosen_build_site.duplicate(true)
					last_result.ink_after = game.ink.amount
					game.message("「%s」已经建好" % pen_command.get("name","建筑") if ink.get("ok",false) else last_result.detail)
				return 0
			pen_point = 1
			pen_from = pen_lines[pen_stroke][0]
			pen_trace.append(PackedVector2Array([pen_from]))
		else:
			trace.append(to)
			pen_trace[-1] = trace
	return direction

func _finish(ok: bool, text: String, extras: Dictionary = {}) -> void:
	if destination=="scene_build_site":
		var project:=scene_projects.active()
		var pending:Dictionary=project.get("pending_build",{})
		project.erase("pending_build")
		if not ok and pending.has("plan"):extras["plan_id"]=pending.plan
	design_draft.clear()
	plant_draft.clear()
	pen_invitation.clear()
	pen_stands.clear()
	paper_stands.clear()
	paper_route.clear()
	paper_route_goal=Vector2.INF
	paper_settle=0.0
	last_result = {"ok":ok,"tool":last_command.get("tool",""),"call_id":last_command.get("call_id",""),
		"request_id":ticket,"start":Senses.pair(start_at),"end":Senses.pair(actor.player.position),"detail":text}
	last_result.merge(extras)
	if not ok and last_result.tool=="scene_reposition":
		last_result.id=str(last_command.get("args",{}).get("site",""))
	if divine_job.has("project_id"):
		_record_scene_stage(last_result)
	elif ok and last_result.get("work_ids",[]).size()>0 and divine_job.has("chat_paper_project"):
		var project:=scene_projects.active()
		var stage:String=str(project.get("stage",""))
		if project.get("project_id")==divine_job.chat_paper_project and stage in ["working","paused"]:
			project.stage="working"
			scene_projects.outcome(last_result.merged({"partial":true}),false)
			project.stage=stage
	elif not ok and destination=="scene_survey":
		scene_projects.outcome(last_result,false)
		scene_projects.active().stage="paused"
	if ok and "water" in extras.get("modes",[]) and (divine_job.has("project_id") or divine_job.has("chat_paper_project")):
		_refresh_channel_checks(scene_projects.active(),true)
	if divine_running: _close_divine_job(text if ok else "这次没能完成。"+text)
	if autonomous_execution: autonomy.record(str(last_result.tool),text,ok,actor.player.position)
	if last_result.tool == "paint_edge":
		last_result.geometry_fixes = last_command.get("geometry_fixes",[])
		last_result.execution_status = "completed" if ok else "failed"
		if not ok: game.message(text)
	target_npc = ""
	destination = ""
	reference_command = {}
	study_rect = Rect2()
	pen_trace.clear()
	pen_wash_meshes.clear()
	pen_lines.clear()
	nib_world = Vector2.INF
	actor.active_stroke = null
	caption = text
	phase = "rest"
	clock = 2.8 if ok else 3.4
	wait_for_change = autonomous_execution and (not ok or last_result.tool=="look")
	idle_retry_after=18.0
	if wait_for_change and last_result.tool=="look":
		var repeats:=0
		for i in range(autonomy.history.size()-1,-1,-1):
			var row:Dictionary=autonomy.history[i]
			if row.action!="look" or absf(row.x-actor.player.position.x)>.5:break
			repeats+=1
		idle_retry_after=[18.0,45.0,90.0,180.0][mini(repeats,4)-1]

func _record_scene_stage(result:Dictionary) -> void:
	var project:=scene_projects.active()
	var kind:String=scene_projects.step().get("kind","")
	var completed:=false
	if result.ok:
		var channel_work:bool=project.get("boat",false) and not project.get("trade_targets",[]).is_empty() and \
			result.get("changed",false) and result.get("modes",[]).any(func(mode):return mode in ["carve","rock","water"])
		if channel_work and kind in ["landscape","water"]:
			result.partial=true
			project.moves=0
		match kind:
			"landscape":
				completed=result.tool=="paint_edge" or result.get("modes",[]).any(func(m):return m in ["rock","platform","carve"]) \
					or (scene_projects.step().get("form")=="scenery" or not str(project.get("subject","")).is_empty()) and (result.tool=="paint_scene_detail" and result.has("work_id") or result.tool=="compose_scene_study")
				if scene_projects.step().get("form")=="foundation":
					completed=result.tool in ["finish_scene_foundation","reuse_shore_plan"]
					result.partial=not completed and result.tool!="scene_reposition"
				elif result.tool=="compose_scene_study" and not completed:result.partial=true
			"water":
				completed="water" in result.get("modes",[]) and result.get("water_open",true)
				if result.get("opened_bank",false):completed=true
				if result.get("cut_basin",false):result.partial=true
				var saved_sections:Array=project.get("channel_plan",{}).get("sections",[])
				var plan_ready:=saved_sections.is_empty() or saved_sections.all(func(row):return row.get("verified",false))
				if result.get("verified_channel_section",false) and plan_ready:completed=true
				if not saved_sections.is_empty() and not plan_ready:
					completed=false
					if result.has("channel_section"):result.partial=true
				if not project.get("water_body",{}).is_empty() and not project.get("boat",false) and result.get("modes",[]).any(func(m):return m in ["carve","water"]):
					var body:=SceneWaterBody.observe(world,project)
					var built_probe:=project.duplicate()
					built_probe.work_ids=project.work_ids+result.get("work_ids",[])
					var actual:=SceneWaterBody.observe(world,built_probe)
					if not actual.is_empty():
						completed=actual.ready
						if not completed:
							result.partial=float(actual.connected_width_m)>float(body.get("connected_width_m",0.0)) or 										float(actual.excavated_width_m)>float(body.get("excavated_width_m",0.0))
							result.detail+=" 同岸连续水 %.2f／%.2f 米。"%[actual.connected_width_m,actual.target_width_m]
				if project.get("boat",false) and not project.get("trade_targets",[]).is_empty() and (channel_work or completed):
					completed=false
					var feet:Vector2=actor.player.position-Vector2(0,.29)
					var passage:=preload("res://scripts/painter_underpass_survey.gd")
					var facts:=passage.observe(game,project,feet)
					if not facts.is_empty():
						var brush:=PenReach.observe_paper(game,actor)
						var geometry:=passage.survey(game,project,brush,facts)
						completed=plan_ready and geometry.get("sections",[]).any(func(section):return not section.get("through_both_open_sides",[]).is_empty())
						if not completed:
							result.detail+=" 两岸真水尚未连成可通船的一段，留在水道工序。"
			"vegetation":
				completed=result.tool=="finish_vegetation" and result.get("vegetation_verified",false)
			"building":
				completed=result.has("work_id") and (not project.trade or result.get("service_work",false))
			"verify":
				completed=result.get("verified",false)
	if kind=="building" and completed:
		project.erase("foundation_site")
	if result.get("distant",false):
		completed=result.ok and result.get("finish_distant",false)
		result.partial=result.ok and not completed
	var prior_stage:String=str(project.get("stage",""))
	scene_projects.outcome(result,completed)
	if prior_stage=="working" and kind=="verify" and completed and project.get("stage")=="complete":
		if world.chronicle!=null and world.chronicle.has_method("record_scene"):
			world.chronicle.record_scene(project,actor.player.position-Vector2(0,.29))
	if project.get("stage")=="awaiting_trade":
		_observe_scene_trade(project)
		if project.stage=="awaiting_trade":
			var received:int=project.get("trade_receipts",{}).size()
			_divine_message("status","「%s」已走通，柜口实交 %d / %d。"%[project.title,received,project.trade_targets.size()])

func _words(value: Variant) -> String:
	return value.strip_edges().replace("\n"," ").replace("\r"," ").left(54) if value is String else ""

func _remember(speaker: String, text: String) -> void:
	dialogue.append({"speaker":speaker.left(12),"text":text.left(120)})
	if dialogue.size()>8: dialogue.pop_front()

func _say(who: String, text: String, duration: float, id := "") -> void:
	speech = {"speaker":who,"text":text,"id":id}
	speech_time = duration

func _draw() -> void:
	if actor == null or not is_instance_valid(actor): return
	if study_rect.has_area():
		var top_left: Vector2 = game.world_to_screen(Vector2(study_rect.position.x,study_rect.end.y))
		var paper := Rect2(top_left,study_rect.size*game.PIXELS_PER_UNIT)
		draw_rect(paper, Color("f8f3df"))
		draw_rect(paper, Color("a69a82"), false, 1.2)
	for i in pen_trace.size():
		var trace: PackedVector2Array = pen_trace[i]
		if trace.size()<2: continue
		var line := PackedVector2Array()
		for sample in trace: line.append(game.world_to_screen(sample))
		var inks: Array = pen_command.get("pigments",[])
		var brushes: Array = pen_command.get("brushes",[])
		var brush: String = brushes[i] if i < brushes.size() else "bold"
		var pigment: String = inks[i] if i < inks.size() and game.FunctionalPens.Palette.valid(inks[i]) else "inherit"
		var tint: Color = game.FunctionalPens.Palette.resolve(pigment,game.FunctionalPens.STYLES.get(pen_command.get("style","ink"),INDIGO))
		if brush == game.FunctionalPens.Brush.POOL and i < pen_stroke:
			if not pen_wash_meshes.has(i):
				# Bake in local metres once. The paper camera only moves the mesh.
				var local := PackedVector2Array()
				for p in trace: local.append(p - trace[0])
				pen_wash_meshes[i] = game.FunctionalPens.Brush.mesh_for(
					[{"points":local,"brush":brush,"pigment":pigment}],
					game.FunctionalPens.STYLES.get(pen_command.get("style","ink"),INDIGO))
			draw_set_transform(game.world_to_screen(trace[0]),0,Vector2(1,-1)*game.PIXELS_PER_UNIT)
			draw_mesh(pen_wash_meshes[i],null)
			draw_set_transform(Vector2.ZERO)
		elif brush == "wash" and i < pen_stroke:
			var polygon: PackedVector2Array = game.FunctionalPens.Brush.wash_polygon(trace)
			if not polygon.is_empty():
				var screen := PackedVector2Array()
				for p in polygon: screen.append(game.world_to_screen(p))
				draw_colored_polygon(screen,Color(tint,0.19 if pigment=="inherit" else 0.32))
		else: draw_polyline(line,Color(tint,0.73 if brush=="fine" else 0.88),1.6 if brush!="bold" else 2.8,true)
	if nib_world.is_finite() or phase in ["work","pen"] or (phase == "walk" and destination == "edge"):
		var hand := hand_world()
		var visible_tip := nib_world if nib_world.is_finite() else hand + Vector2(0.55*actor.facing,0.84)
		Brush.draw(self,game.world_to_screen(hand),game.world_to_screen(visible_tip),game.PIXELS_PER_UNIT)
	var location: Vector2 = actor.player.position
	var view: Rect2 = game.get_viewport_rect()
	var near: float = location.distance_to(game.player.position)
	var tag := Rect2()
	if near <= 10.0 or (phase == "rest" and near < 30.0) or has_active_brush():
		var head: Vector2 = game.world_to_screen(location+Vector2(0,0.88))
		var traveller = world.get_node_or_null("SandboxAdventurer")
		if traveller != null and is_instance_valid(traveller.actor):
			var other: Vector2 = game.world_to_screen(traveller.actor.player.position+Vector2(0,0.88))
			if absf(other.x-head.x)<120 and absf(other.y-head.y)<24: head.y -= 26
		tag = Identity.draw(self,font,head,view,IDENTITY_LABEL,INDIGO,clampi(roundi(game.PIXELS_PER_UNIT*.22),14,19),Identity.vitals_area(game.toolbar))
	var who := DISPLAY_NAME
	var text := caption
	if speech_time > 0.0 and not speech.is_empty():
		who = speech.speaker
		text = speech.text
		if who == "你": location = game.player.position
		elif not speech.id.is_empty():
			var npc = world.entity_by_id(speech.id)
			if npc != null: location = npc.position + Vector2(0,0.45)
	elif phase in ["rest","arrival"] and caption in ["","跟上你","我在这儿"]:
		return
	var anchor: Vector2 = game.world_to_screen(location + Vector2(0,0.82))
	if not view.grow(34).has_point(anchor): return
	if who == DISPLAY_NAME and tag.has_area(): anchor.y = tag.position.y+6
	var size_px := clampi(roundi(game.PIXELS_PER_UNIT*0.235),14,20)
	var ui := clampf(game.PIXELS_PER_UNIT/60.0,0.8,1.5)
	var words := text if who == DISPLAY_NAME and tag.has_area() else who + (" · "+text if not text.is_empty() else "")
	if words.is_empty(): return
	var max_width := minf(view.size.x-32,325.0*ui)
	var extent := font.get_multiline_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,max_width,size_px)
	var rect := Rect2(Vector2(anchor.x-extent.x*0.5-8,anchor.y-extent.y-15),extent+Vector2(16,8))
	rect.position.x = clampf(rect.position.x,8,view.size.x-rect.size.x-8)
	var paper := Color("fffaeb")
	draw_colored_polygon(PackedVector2Array([Vector2(anchor.x-4,rect.end.y-1), Vector2(anchor.x+4,rect.end.y-1), anchor-Vector2(0,2)]),paper)
	draw_rect(rect,paper)
	draw_line(rect.position,Vector2(rect.position.x,rect.end.y),INDIGO,2.8,true)
	draw_multiline_string(font,rect.position+Vector2(8,4+font.get_ascent(size_px)),words,HORIZONTAL_ALIGNMENT_LEFT,max_width,size_px,-1,INDIGO)

func available_for_plan() -> bool:
	if actor == null: return false
	if phase in ["work","pen"] or phase == "walk" and destination == "edge":
		game.message("请等阿靛画完眼前这一笔")
		return false
	if actor.player.position.distance_to(game.player.position) > 10.0:
		game.message("按 J 叫阿靛到身边，再打开它的图纸包")
		return false
	return true

func building_observation(center := Vector2.INF) -> Dictionary:
	var x: float = snappedf(center.x if center.is_finite() else game.player.position.x,.01)
	var y: float = snappedf(world.travel_height(x),.01)
	var ground := []
	for offset in range(-4,5):
		ground.append([offset,snappedf(world.travel_height(x+offset)-y,.01)])
	var view := {"origin":[x,y],"site":{"ground":ground,"brushes":game.FunctionalPens.Brush.BRUSHES.keys(),
		"pigments":game.FunctionalPens.Palette.LABELS.keys()}}
	if divine_job.has("project_id"):
		if scene_projects.active().get("trade",false) and world.survival!=null:
			var maker:Dictionary=world.survival.inventory("companion")
			var visitor:Dictionary=world.survival.inventory("player")
			view.site.counter_context={"maker_coins":int(maker.economy.coins),"visitor_coins":int(visitor.economy.coins),
				"maker_ink":floori(actor.ink.amount),"paper_lantern_ink":8,
				"maker_lanterns":int(maker.get("paper_lantern",0)),"visitor_reed_leaves":int(visitor.get("reed_leaf",0))}
		var foundation:Dictionary=scene_projects.active().get("foundation_site",{})
		if not foundation.is_empty():
			view.site.foundation=foundation.duplicate(true)
			var stand:=WorldPen.point(foundation.get("stand"))
			if stand.is_finite():
				view.site.foundation=_shore_frontage({"stand":foundation.stand,"surface":foundation.surface})
				y=snappedf(stand.y,.01)
				view.origin=[x,y]
		view.site.supports=[]
		for offset in range(-12,13):
			var sample_x: float=x+offset*.5
			var surfaces: Array=world.paper_surfaces(sample_x,y-2.0,y+2.5)
			view.site.supports.append({"x":offset*.5,"floors":surfaces.filter(func(f):return f.face=="floor").map(func(f):return snappedf(f.y-y,.01))})
	if invitation.get("revise_last",false) and not unfinished_building.get("prior",{}).is_empty():
		view.previous_draft = unfinished_building.prior.duplicate(true)
	if invitation.kind == "building_variant":
		var plans = game.map_controls.painter_folio.plans()
		var id: int = invitation.slot
		var parent: Dictionary = plans.command_at(game,"companion",id,Vector2.ZERO)
		if parent.get("tool","") != "draw_scenery": return {"error":"母图已不在阿靛的图纸包"}
		var layout: Dictionary = parent.get("plan",{}).get("layout",{})
		if layout.is_empty(): return {"error":"未找到母图上的结构和使用位置"}
		view.parent = {"name":parent.get("name",""),"id":id,"command":parent,"layout":layout}
	return view

func _store_design() -> void:
	var draft := design_draft.duplicate(true)
	var plans = game.map_controls.painter_folio.plans()
	var origin := Vector2(draft.origin[0],draft.origin[1])
	var price: float = game.ink.amount
	draft.layout.authorship = {"artist":"companion","tool":last_command.tool,"provider":last_command.get("provider",""),
		"model":last_command.get("model",""),"call_id":last_command.get("call_id",""),"request_id":ticket,
		"brief":last_observation.get("invitation",{}).get("text","")}
	var out: Dictionary = plans.store(game,"companion",draft.name,draft.command,origin,draft.layout,int(draft.parent_id))
	if out.get("ok",false): unfinished_building.clear()
	if out.get("ok",false):
		for entry in world.companion_blueprints.entries:
			if entry.id!=out.id: continue
			entry.work_id="companion-"+Crypto.new().generate_random_bytes(12).hex_encode()
			entry.author_id="companion"
			break
	var note := "图 %d「%s」已收入阿靛的图纸包" % [int(out.get("id",-1)),draft.name] if out.get("ok",false) else str(out.get("error","未能存图"))
	if out.get("ok",false) and divine_job.has("project_id"):
		design_draft.clear()
		_place_scene_plan(plans,int(out.id),origin)
		return
	_finish(out.get("ok",false),note)
	last_result.merge({"owner":"companion","name":draft.name,"parent_id":draft.parent_id,"plan_id":out.get("id",-1),"strokes":draft.command.strokes.size(),"ink_before":price,"ink_after":game.ink.amount})
	game.message(note)

func _place_scene_plan(plans, id:int, origin:Vector2) -> void:
	var feet:Vector2=actor.player.position-Vector2(0,.29)
	var survey:=preload("res://scripts/architecture/building_survey.gd")
	var options:Array=survey.sites(game,"companion",id,origin,feet,10.0)
	if not options.is_empty():
		var site:Dictionary=options.front()
		var stand:=WorldPen.point(site.stand)
		var paper_origin:=WorldPen.point(site.origin)
		if feet.distance_to(stand)>.30:
			var pending:={"plan":id,"at":site.origin,"stand":site.stand,
				"command":{"tool":last_command.get("tool",""),"call_id":last_command.get("call_id","")},"request_id":ticket}
			scene_projects.active().pending_build=pending
			_start_scene_build_site(pending)
		else:
			_build_scene_at(id,paper_origin)
		return
	var layout:Dictionary=plans.command_at(game,"companion",id,Vector2.ZERO).get("plan",{}).get("layout",{})
	var conflicts:Array=[]
	if not layout.is_empty():
		var entrance:=WorldPen.point(layout.access.front())
		var nearest:Dictionary=plans.preview(game,"companion",id,origin-entrance)
		conflicts=nearest.get("conflicts",[])
	var reasons:=PackedStringArray()
	for hit in conflicts.slice(0,3):
		var reason:String={"unsupported":"支点无地表","unwalkable":"人物不能站稳","access":"遮挡使用位","footprint":"与实物重叠"}.get(hit.reason,hit.reason)
		reasons.append("%s (%.2f, %.2f) %s"%[hit.id,hit.x,hit.y,reason])
	var detail:="母图已存，近处没有已验证且能走到的落位。" if reasons.is_empty() else "母图已存，按落地反馈局部改绘："+"；".join(reasons)
	_finish(false,detail,{"plan_id":id,"conflicts":conflicts.slice(0,6)})

func _start_scene_build_site(pending:Dictionary) -> void:
	var at:=WorldPen.point(pending.get("stand",pending.get("at")))
	if not at.is_finite():
		scene_projects.active().erase("pending_build")
		_finish(false,"原图已存，施工点未能从存档恢复。",{"plan_id":pending.get("plan",-1)})
		return
	_go(at.x,"scene_build_site","带着已存母图前往实测落位",at)

func _build_scene_at(id:int,at:Vector2) -> void:
	var test:=BuildingPlans.preview(game,"companion",id,at)
	if not test.get("ok",false):
		_finish(false,str(test.get("error","已有母图的实位刚发生变化")),{"plan_id":id})
		return
	var command:=BuildingPlans.command_at(game,"companion",id,at)
	_start_pen(command,true)
	if phase=="pen":caption="施工「%s」"%command.name

func build_from_plan(id: int, requested: Vector2) -> Dictionary:
	if not available_for_plan(): return {"error":"阿靛暂时无法接过图纸"}
	var plans = game.map_controls.painter_folio.plans()
	var preview: Dictionary = plans.preview(game,"companion",id,requested)
	var at := requested
	var rejected: Array = preview.get("conflicts",[])
	if not preview.get("ok",false):
		var found := false
		for alt in preview.get("alternatives",[]):
			if not _pair(alt): continue
			var candidate := Vector2(alt[0],alt[1])
			if candidate.distance_to(game.player.position)>9.0: continue
			if plans.preview(game,"companion",id,candidate).get("ok",false):
				at = candidate
				found = true
				break
		if not found: return {"error":"这块地被占用或柱脚无法贴地。请到开阔平地重新选址","requested":Senses.pair(requested),"preview":preview}
	var cmd: Dictionary = plans.command_at(game,"companion",id,at)
	if cmd.get("tool") != "draw_scenery": return {"error":"没有找到这张图纸"}
	worker.cancel()
	invitation.clear()
	pen_invitation.clear()
	autonomous_execution=false
	last_command = {"tool":"build_from_plan","provider":"blueprint_bag","plan_id":id}
	ticket = Crypto.new().generate_random_bytes(12).hex_encode()
	start_at = actor.player.position
	chosen_build_site = {"plan_id":id,"requested":Senses.pair(requested),"origin":Senses.pair(at),"conflicts":rejected,
		"ink_before":game.ink.amount,"owner":"companion","request_id":ticket}
	_start_pen(cmd,true)
	if phase != "pen": return {"error":last_result.get("detail","无法落笔")}
	caption = "照图 %d 建「%s」" % [id,cmd.get("name","建筑")]
	game.message("原处有占用，阿靛在附近空地按图动笔" if requested != at else caption)
	return {"ok":true,"placement":chosen_build_site.duplicate(true)}

func wait_at_plan_access(at: Vector2, station: Dictionary) -> bool:
	if not available_for_plan(): return false
	worker.cancel()
	invitation.clear()
	autonomous_execution=false
	last_command = {"tool":"walk_to_access","plan_id":station.plan_id,"structure_id":station.id}
	ticket = Crypto.new().generate_random_bytes(12).hex_encode()
	start_at = actor.player.position
	plan_access_target = at
	_go(at.x,"plan_access","到使用位等你")
	return true

func retry_building() -> bool:
	if unfinished_building.is_empty(): return false
	if not invite(unfinished_building.kind,unfinished_building.text,unfinished_building.slot): return false
	invitation.revise_last = true
	return true

func _model_binding_changed() -> void:
	local_walk.interrupt()
	queued_frontier = ""
	if not divine_job.is_empty() and not (divine_running and phase=="pen"):
		if not divine_running and not divine_job.has("project_id"):
			held_chat=ChatRoles.snapshot_held_chat(held_chat,divine_job.text,divine_draft)
			if divine_draft.is_empty():divine_draft=divine_job.text
		_close_divine_job("角色连接已变化，待处理的对话已结束。")
		if destination=="divine_site":
			phase="rest"
			destination=""
	if actor == null or phase not in ["rest","offline"] or _waiting_at_access(): return
	invitation.clear()
	phase = "rest"
	wait_for_change = false
	clock = 2.0
	if not worker.can_request(): caption = ModelConnections.role_status("companion").message
	else: caption = ""
