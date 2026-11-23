extends Node2D

const Species:=preload("res://scripts/priest_species.gd")
const Form := preload("res://scripts/ink_life_form.gd")
const Creature := preload("res://scripts/priest_creature.gd")
const Ground := preload("res://scripts/priest_ground.gd")
const Ecology := preload("res://scripts/priest_ecology.gd")
const Figure := preload("res://scripts/priest_figure.gd")
var gait := Figure.new()
const Walker := preload("res://scripts/local_role_walk.gd")
var patrol := Walker.new(1)
var patrol_allowed := false
var patrol_evidence := ""
const Transport := preload("res://scripts/east_painter.gd")
const PRIEST_X := -2.95
const REVISIT_SECONDS := 65.0
var world
var game
var worker
var font: Font
var works: Array = []
var blueprints:Array=[]
var revision_offers:Array=[]
const REVISION_STAND_TOLERANCE:=.22
var revision_route:Dictionary={}
var revision_goal:=Vector2.INF
var revision_check:=0.0
var pasture_care:=preload("res://scripts/priest_pasture_care.gd").new()
var feed_run := preload("res://scripts/priest_feed_run.gd").new()
var historical_reviews_read := false
var ecology_log := preload("res://scripts/priest_ecology_log.gd").new()
var memory:Array=[]
var commitments:Array=[]
var focus_animal: Creature
var priest_x := PRIEST_X
var priest_y := 0.0
var destination := PRIEST_X
var clock := 0.0
var next_turn := 3.0
var activity := "idle"
var travel_target:Dictionary={}
var travel_route:Dictionary={}
const Placement:=preload("res://scripts/priest_placement.gd")
var placement_offer:Dictionary={}
var travel_alternatives:Array=[]
var travel_sample:=0.0
var habitat_id := ""
var tending_tree := ""
var protected_tree := ""
var protect_left := 0.0
var goal := "观察林地，决定如何照看这里"
var reason := ""
var progress := "尚未巡看"
var autonomy := preload("res://scripts/sandbox_autonomy.gd").new()
var autonomy_paused: bool:
	get: return autonomy.paused
var pending := false
var generation := 0
var model_reason := ""
var last_eco_call := ""
var surveyed_site := ""
var survey_stamp := ""
var chat_messages: Array = []
var chat_pending := false
var chat_notice := ""
var queued_chat := ""
var queued_scope := {}
const ChatRoles:=preload("res://scripts/divine_roles.gd")
var held_chat: Array = []
var unsent_draft := ""

# Single-work readers (including older saved-manuscript viewers) follow the current animal.
var form:
	get: return focus_animal.form if focus_animal else null
var design: Dictionary:
	get: return focus_animal.design if focus_animal else {}
var phase: String:
	get: return "thinking" if pending else focus_animal.phase if focus_animal else "idle"
var cursor: float:
	get: return focus_animal.cursor if focus_animal else 0.0
var beast_x: float:
	get: return focus_animal.beast_x if focus_animal else priest_x
var eaten: Dictionary:
	get: return focus_animal.eaten if focus_animal else {}
var satiety: float:
	get: return focus_animal.satiety if focus_animal else 0.0
var last_tree: String:
	get: return focus_animal.last_tree if focus_animal else ""
var target_id: String:
	get: return focus_animal.target_id if focus_animal else ""
var call_id: String:
	get: return focus_animal.call_id if focus_animal else ""
var bark_point: Vector2:
	get: return focus_animal.bark_point if focus_animal else Vector2.ZERO

func work_by_id(id:String):
	if id=="":return null
	for a in works:
		if a.work_id==id:return a
	return null

func live_count() -> int:
	return works.filter(func(a):return a.phase!="dead").size()

func can_contact_person(id:String,person_at:Vector2) -> bool:
	var a=work_by_id(id)
	if a==null:return false
	return Creature.Obstacles.contact(world,Vector2(a.beast_x,a.beast_y+.4),person_at+Vector2(0,.35))

func combat_geometry(id:String) -> Array[PackedVector2Array]:
	var a=work_by_id(id)
	if not a or a.phase in ["drawing","dead"] or a.hostile_left<=0 or not a.form:return []
	return a.form.world_parts(Vector2(a.beast_x,a.beast_y),a._slope(),a.face,a.stride,a.phase,a.bite_phase)

func combat_targets(at:Vector2,sight:float) -> Array:
	var found:=[]
	for a:Creature in works:
		if a.phase in ["dead","drawing"] or at.distance_to(Vector2(a.beast_x,a.beast_y))>sight:continue
		found.append({"work_id":a.work_id,"team_id":_scope().team_id,"world_id":_scope().world_id,"name":a.design.name,
			"x":a.beast_x,"y":a.beast_y,"health":a.health,"hostile":a.hostile_left>0,"reason":a.hostile_reason if a.hostile_left>0 else ""})
	return found

func receive_combat_hit(id:String,at:Vector2,damage:float,source_id:String) -> Dictionary:
	var a=work_by_id(id)
	if not a or a.phase in ["dead","drawing"] or a.hostile_left<=0 or not Species.scalar(damage,.01,100) or source_id.is_empty():return {"ok":false}
	var pos:=Vector2(a.beast_x,a.beast_y)
	if pos.distance_to(at)>2.25:return {"ok":false}
	var under:=Ground.nearby(world,at.x,at.y,.95)
	if under.is_empty():return {"ok":false}
	var route:=Ground.trace(world,Vector2(at.x,under.y),pos.x)
	if route.is_empty() or absf(route.y-pos.y)>1.65:return {"ok":false}
	var before:float=a.health
	a.health=maxf(0.0,a.health-damage)
	if a.health<=0:a.phase="dead"
	record_outcome("遭遇战斗",source_id,"%s 生命 %d→%d" % [a.design.name,before,a.health],id)
	return {"ok":true,"before":before,"after":a.health,"killed":a.phase=="dead","work_id":id}

func livestock_near(at:Vector2,radius:float) -> Array:
	var found:=[]
	for a:Creature in works:
		if a.phase=="drawing" or not a.design.get("edible",false) or a.portions<=0:continue
		var dist:=at.distance_to(Vector2(a.beast_x,a.beast_y))
		if dist<=radius:
			found.append({"work_id":a.work_id,"x":a.beast_x,"y":a.beast_y,"portions":a.portions,"alive":a.phase!="dead","distance":dist})
	found.sort_custom(func(a,b):return a.distance<b.distance)
	return found

func hungry_livestock_near(at:Vector2,radius:float) -> Array:
	var rows:=[]
	for a in works:
		if a.phase in ["drawing","dead","takeoff","fly","land"] or not a.has_action("graze_grass") or a.satiety>=65:continue
		var distance:=at.distance_to(Vector2(a.beast_x,a.beast_y))
		if distance<=radius:rows.append({"work_id":a.work_id,"name":a.design.name,"x":a.beast_x,"y":a.beast_y,"satiety":a.satiety,"distance":distance})
	rows.sort_custom(func(a,b):return a.distance<b.distance)
	return rows

func feed_livestock(id:String,at:Vector2,feeder_id:String) -> Dictionary:
	var a=work_by_id(id)
	if not a or not at.is_finite() or feeder_id.is_empty() or feeder_id.length()>128 or a.phase in ["drawing","dead","takeoff","fly","land"] or not a.has_action("graze_grass") or a.satiety>=65:
		return {"ok":false,"error":"这只个体现在不能接草。"}
	var foot:=Vector2(a.beast_x,a.beast_y)
	if foot.distance_to(at)>1.35 or not can_contact_person(id,at):return {"ok":false,"error":"请到这只个体跟前，从没有遮挡的一侧递草。"}
	var floor_row:=Ground.trace(world,foot,at.x)
	if floor_row.is_empty() or absf(at.y-float(floor_row.y))>.65:return {"ok":false,"error":"饲喂者与它不在可接触的脚面。"}
	var before:float=a.satiety
	a.satiety=minf(100,before+23)
	a.hunger_seconds=0
	a.delivered_meals+=1
	ecology_log.record(self,a,"feed",feeder_id,before,a.satiety,"%s 向 %s 递交一份牧草，饱食 %.1f → %.1f。" % [feeder_id,a.design.name,before,a.satiety])
	return {"ok":true,"work_id":id,"before":before,"after":a.satiety}

func take_livestock_portion(id:String,at:Vector2,collector_id: String="") -> bool:
	var a=work_by_id(id)
	if not a or a.phase=="drawing" or a.portions<=0 or not a.design.get("edible",false):return false
	var pos:=Vector2(a.beast_x,a.beast_y)
	if pos.distance_to(at)>1.8:return false
	var floor_row:=Ground.trace(world,pos,at.x)
	if floor_row.is_empty() or absf(at.y-floor_row.y)>1.35 or not can_contact_person(id,at):return false
	var source_health: float = a.health
	a.phase="dead"
	a.health=0
	a.portions-=1
	var description := "宰取「%s」，生命 %d → 0" % [a.design.name,source_health] if source_health>0 else "从「%s」遗骸取肉" % a.design.name
	ecology_log.record(self,a,"meat",collector_id,a.portions+1,a.portions,description+"，取走一份，余 %d 份。" % a.portions)
	record_outcome("居民取肉",a.design.name,"取走一份，余 %d 份" % a.portions,id)
	return true

func ecology_records(after_seq := 0, limit := 32) -> Array:
	return ecology_log.since(after_seq,limit)

func record_outcome(action:String,why:String,result:String,id:String="",call:String="") -> void:
	var scope:=_scope()
	memory.append({"role":"priest","team_id":scope.team_id,"world_id":scope.world_id,"action":action.left(64),
		"reason":why.left(220),"result":result.left(240),"work_id":id,"call_id":call})
	if memory.size()>32:memory.pop_front()

func _keep_notes(command:Dictionary) -> void:
	var updates=command.get("memory_updates",[])
	if not updates is Array or updates.size()>10:return
	for update in updates:
		if not update is Dictionary:continue
		var id=str(update.get("note_id",""))
		if id.is_empty() or id.length()>128:continue
		var found=commitments.filter(func(n):return n.note_id==id)
		if update.get("tool")=="remember_priest" and found.is_empty() and commitments.size()<128:
			var n={"note_id":id,"role":"priest","team_id":_scope().team_id,"world_id":_scope().world_id,"status":"open","outcome":"","call_id":command.call_id}
			for key in ["topic","intent","review_when","work_id","blueprint_id"]:n[key]=str(update.get(key,"")).left(220)
			if n.topic.is_empty() or n.intent.is_empty() or n.review_when.is_empty():continue
			if n.work_id!="" and not work_by_id(n.work_id) or n.blueprint_id!="" and _book(n.blueprint_id).is_empty():continue
			commitments.append(n)
		elif update.get("tool")=="review_priest" and not found.is_empty() and update.get("status") in ["open","resolved"]:
			found[0].status=update.status
			found[0].outcome=str(update.get("outcome","")).left(1000)
			found[0].review_call_id=command.call_id
			found[0].review_team_id=_scope().team_id
			found[0].review_world_id=_scope().world_id
			ecology_log.publish_review(self,found[0])

func _book(id:String) -> Dictionary:
	for b in blueprints:
		if b.blueprint_id==id:return b
	return {}

func _file_plan(command:Dictionary) -> Dictionary:
	var scope:=_scope()
	if blueprints.size()>=Species.MAX_PLANS:return {}
	var book:={"blueprint_id":"species-"+Crypto.new().generate_random_bytes(10).hex_encode(),"name":command.design.name,"author_id":"priest","team_id":scope.team_id,
		"goal":command.goal,"reason":command.reason,"origin_work_id":"","world_id":scope.world_id,"design":command.design.duplicate(true),"call_id":command.call_id,"served_model":command.served_model}
	blueprints.append(book)
	return book

func _edible(tree) -> bool:
	return focus_animal != null and focus_animal._edible(tree)

func _ready() -> void:
	name = "SandboxPriest"
	world = get_parent()
	game = world.game
	priest_y=world.travel_height(priest_x)
	font = PaperTheme.create().default_font
	z_index = 3
	worker = Transport.new()
	worker.actor_role = "priest"
	worker.worker_resource = "res://tools/priest_turn.mjs"
	worker.request_directory = "user://priest_turns"
	worker.use_painter_mailbox = false
	add_child(worker)
	worker.finished.connect(_receive)
	worker.binding_changed.connect(_binding_changed)
	_update_patrol_permission()

func _scope() -> Dictionary:
	var slot: Dictionary = game.team_slot if "team_slot" in game else {}
	return {"team_id":str(slot.get("team_id","legacy")),"world_id":str(slot.get("world_id","medieval-v1")),
		"slot_id":str(slot.get("slot_id","legacy")),"generation":generation}

func _cancel_turn() -> void:
	patrol.interrupt()
	patrol_evidence=""
	placement_offer.clear()
	if chat_pending: chat_notice="本轮对话已取消。"
	if not queued_chat.is_empty(): _return_queued("本轮排队已取消，原话可重新发送。")
	chat_pending=false
	generation += 1
	pending = false
	if worker != null: worker.cancel()

func _update_patrol_permission() -> void:
	var connection:=divine_connection_status()
	patrol_allowed=Walker.can_run(connection,false,connection.ready)

func _binding_changed() -> void:
	_cancel_turn()
	_update_patrol_permission()
	next_turn = 3.0

func cancel_pasture_work() -> Dictionary:
	if activity!="plant" or pasture_care.job.is_empty():return {"ok":false,"message":"当前没有移栽工作。"}
	pasture_care.finish(self,"已按玩家指示停止这次移栽。")
	return {"ok":true,"message":progress}

func set_autonomy_paused(value: bool) -> void:
	if value and activity=="plant" and not pasture_care.job.get("chat",false):cancel_pasture_work()
	if value == autonomy_paused: return
	_cancel_turn()
	autonomy.set_paused(value)
	next_turn = 3.0

func set_action_budget(value: int) -> void:
	autonomy.set_budget(value)
	next_turn=3.0

func _exit_tree() -> void:
	_cancel_turn()

func divine_status() -> Dictionary:
	var connection:=divine_connection_status()
	var ready:bool=connection.ready
	var summary := "牧师在林边巡看"
	var label := "去看牧师"
	var display_phase := "idle"
	if pending:
		display_phase = "thinking"
		summary = "等待模型判断林地"
	elif focus_animal != null and focus_animal.phase == "drawing":
		display_phase = "drawing"
		if absf(priest_x-destination)>.04:
			summary = "走向「%s」的落笔处" % design.name
		else:
			summary = "正在绘制「%s」 · %d%%" % [design.name,clampi(floori(100.0*cursor/form.length),0,99)]
		label = "看当前运笔"
	elif activity in ["survey","tend","wait","feed","plant"]:
		summary = progress
	elif focus_animal != null and focus_animal.phase=="dead":
		display_phase="dead"
		summary="「%s」已死亡"%design.name
		label="看「%s」的遗骸"%design.name
	elif focus_animal != null:
		display_phase = "born"
		summary = "「%s」已出生 · %s" % [design.name,focus_animal.action_label()]
		label = "去看「%s」" % design.name
	if not _waiting_revision().is_empty() and activity in ["wait","idle"]:
		summary=progress
		display_phase="following"
	if activity=="travel":
		summary=progress
		display_phase="travel"
		label="去看牧师"
	var control := autonomy.status(connection)
	var state := {"phase":display_phase,"summary":summary,"action_label":label,"name":str(design.get("name","")),
		"can_start":ready and not pending and activity=="idle" and live_count()<Ecology.CAPACITY,
		"capabilities":"拆件步态与拍翼起降 · 采食、逃跑、捕食与护养 · 活体 %d/%d · 物种图纸 %d" % [live_count(),Ecology.CAPACITY,blueprints.size()],"goal":goal,"reason":reason+" "+model_reason if not reason.is_empty() else model_reason,
		"progress":placement_offer.get("message",progress),"autonomy_paused":autonomy_paused,"pause_reason":control.pause_reason,"used":autonomy.used,"budget":autonomy.budget,"work_count":works.size()}

	state.can_cancel_pasture=activity=="plant"
	var foot:="脚点（%.1f，%.1f 米）" % [priest_x,priest_y]
	if display_phase=="following":
		state.person_summary=progress+" · "+foot
		state.decision_source="玩家委托 · 追随原只"
		state.can_start=false
		return state
	if patrol.active:
		state.merge(patrol.view("基础巡林"),true)
		if not patrol_evidence.is_empty():state.reason=patrol_evidence
		var posture:="驻足查看" if patrol.plan.is_empty() else "前往"
		state.person_summary="基础巡林 · %s%s · %s" % [posture,patrol.label,foot]
		return state
	var executing:=activity in ["draw","travel","survey","tend","wait","feed","plant"]
	if pending:state.decision_source="等待模型"
	elif executing:state.decision_source="模型已决定 · 引擎执行"
	elif autonomy_paused:state.decision_source="已暂停自主"
	elif not placement_offer.is_empty():state.decision_source="原稿待选位"
	else:state.decision_source="候命"
	if activity=="travel":state.person_summary=progress if progress.contains("脚点") else progress+" · "+foot
	elif activity=="draw":
		var drawing:="走向运笔处" if absf(priest_x-destination)>.04 else "站定运笔"
		state.person_summary=drawing+" · "+foot
	elif activity in ["survey","tend","wait","feed","plant"]:state.person_summary=progress+" · "+foot
	elif pending:state.person_summary="站定等待模型 · "+foot
	elif progress.begins_with("已到"):state.person_summary="站定 · "+progress
	else:state.person_summary="站定 · "+foot
	return state

func paper_activity_points() -> Array:
	var points := [Vector2(priest_x,priest_y)]
	for animal in works: points.append(Vector2(animal.beast_x,animal.beast_y))
	return points

func observation_target() -> Vector2:
	var here:=Vector2(priest_x,priest_y)
	if activity=="travel":return here
	if not pending and activity in ["idle","draw"] and focus_animal:
		var animal_at:=Vector2(beast_x,focus_animal.beast_y)
		if focus_animal.phase!="drawing": return animal_at
		if absf(priest_x-destination)<.1: return here.lerp(animal_at,.5)
	return here

func watch() -> void:
	game.toolbar.navigation_open=false
	game.open_divine_status()
	if game.divine_panel!=null: game.divine_panel.watch("priest")

func start_creation() -> bool:
	if live_count()>=Ecology.CAPACITY: return false
	return _request_turn(false)

func divine_connection_status() -> Dictionary:
	var route:=ModelConnections.role_status("priest")
	for config in ModelConnections.list_connections():
		if config.id==route.id and (config.provider!="deepseek-official" or config.model!="deepseek-flash"):
			return {"ready":false,"code":"official_flash_required","message":"牧师需要玩家为它选择官方 DeepSeek Flash。","id":route.id}
	return route

func divine_chat_status() -> Dictionary:
	var connection := divine_connection_status()
	var notice := chat_notice
	if not connection.ready: notice=str(connection.message)
	elif not queued_chat.is_empty(): notice="已排队，等当前生命收笔后交付改绘；尚未请求服务商。" if _wait_for_brush(queued_chat) else "已排队，尚未请求服务商。"
	elif chat_pending: notice="已发给服务商，正在等牧师回复。"
	elif pending: notice="牧师正在判断林地，现在发送可排入下一回合。"
	elif focus_animal and focus_animal.phase!="dead" and not chat_messages.is_empty() and chat_messages.back().get("work_id","")==focus_animal.work_id:
		notice=progress if focus_animal.phase=="drawing" else "「%s」%s · %s" % [design.name,"已改绘" if not focus_animal.revision.is_empty() else "已出生",focus_animal.action_label()]
	var options:=[]
	for option in placement_offer.get("sites",[]):
		options.append({"id":option.id,"label":option.label})
	if not options.is_empty():notice=placement_offer.message
	var revision_choice:={}
	if not revision_offers.is_empty():
		var offer:Dictionary=revision_offers[0]
		var waiting:bool=offer.get("waiting",false)
		revision_choice={"call_id":offer.call_id,"name":offer.design.name,"waiting":waiting}
		notice=progress if waiting else "「%s」已死亡。可把收到的改笔另存为图纸。" % offer.design.name
	return {"revision_choice":revision_choice,"placement_options":options,"placement_busy":chat_pending or activity=="draw","messages":chat_messages.duplicate(true),"pending":chat_pending or not queued_chat.is_empty(),"progress":notice,
		"can_send":connection.ready and not chat_pending and queued_chat.is_empty(),"connection_code":connection.code,
		"chat_phase":"queued" if not queued_chat.is_empty() else "sent" if chat_pending else "ready","draft":unsent_draft}

func _chat_line(speaker: String, words: String, command: Dictionary = {}, work_id := "") -> void:
	var line := {"speaker":speaker,"text":words}
	if not command.is_empty():
		line.model=str(command.get("served_model",""))
		line.call_id=str(command.get("call_id",""))
		if work_id!="": line.work_id=work_id
	chat_messages.append(line)
	if chat_messages.size()>20: chat_messages.pop_front()

func _diet_text(animal:Creature) -> String:
	var actions:Array=animal.design.get("actions",["graze_bark"])
	var foods:=PackedStringArray()
	if "eat_ground_fruit" in actions:foods.append("同层地上的朱果（含人放下的果）")
	if "graze_grass" in actions:foods.append("牧草")
	if "graze_bark" in actions:foods.append("树皮")
	var habits:=PackedStringArray()
	if not foods.is_empty():habits.append("能采食"+"、".join(foods))
	if "hunt_livestock" in actions:habits.append("能捕食牲畜")
	var detail:="，".join(habits)
	if detail.is_empty():
		detail="尚无可执行的取食动作"
		if "sense_food" in actions:detail+="，只能感知食物"
	if animal.phase=="dead":detail="已死亡，无法进食。原图"+detail
	elif animal.phase=="drawing":detail="正在绘制。图纸"+detail
	return "「%s」%s。%s" % [animal.design.name,detail,"" if "eat_ground_fruit" in actions else "现有动作不支持捡食或接食果实。"]

func _species_reply(command:Dictionary) -> void:
	var subject:=str(command.get("work_id",""))
	var diet_question:bool=command.get("diet_question",false)
	if not diet_question and not str(command.reply).is_empty():_chat_line("god",command.reply,command,subject)
	for id in command.get("diet_work_ids",[]):
		var animal:Creature=work_by_id(id)
		if animal:
			var fact:=_diet_text(animal)
			var quoted:bool=diet_question and str(command.reply).strip_edges()==fact
			_chat_line("god" if quoted else "status",fact,command,animal.work_id)

func _hold_revision(c:Dictionary,target:Creature,waiting:=false) -> void:
	var offer:={}
	for key in ["work_id","source_blueprint_id","call_id","served_model","design","goal","reason","edit_part_id"]:
		if c.has(key):offer[key]=c[key]
	offer.waiting=waiting
	if waiting:offer.reply=c.reply
	if not revision_offers.any(func(item):return item.call_id==c.call_id):
		revision_offers.append(offer.duplicate(true))
	chat_notice=("已收到「%s」的改笔。牧师会走近同一只，等它在可落笔的脚面站稳。" if waiting else "「%s」在落笔前已死亡。可将这笔改稿另存为图纸，母图和遗骸都会保留。") % target.design.name
	progress=chat_notice
	_chat_line("status",chat_notice,c,target.work_id)

func _waiting_revision() -> Dictionary:
	for item in revision_offers:
		if item.get("waiting",false):return item
	return {}

func _near_brush(animal:Creature) -> bool:
	return animal.phase not in ["drawing","takeoff","fly","land","dead"] and absf(priest_x-(animal.beast_x-1.47))<=REVISION_STAND_TOLERANCE and _can_reach_animal(animal)

func _follow_revision(offer:Dictionary,delta:float) -> void:
	var animal:Creature=work_by_id(offer.work_id)
	if not animal or animal.blueprint_id!=offer.source_blueprint_id:
		revision_offers.erase(offer)
		_chat_line("status","原只或母图已改变，已停止追随，未应用旧稿。",offer,offer.work_id)
		revision_route.clear()
		return
	if animal.phase=="dead":
		offer.waiting=false
		revision_route.clear()
		chat_notice="「%s」在牧师落笔前已死亡。收到的改笔可另存为图纸。"%animal.design.name
		_chat_line("status",chat_notice,offer,animal.work_id)
		return
	if activity not in ["wait","idle"]:return
	var here:=Vector2(priest_x,priest_y)
	revision_check-=delta
	if revision_check<=0:
		revision_check=.55
		if _near_brush(animal):
			var cmd:=offer.duplicate(true)
			cmd.tool="revise_species"
			cmd.diet_work_ids=[animal.work_id]
			if _accept_species(cmd,true):
				revision_offers.erase(offer)
				revision_route.clear()
				return
			progress="已在「%s」旁等候 · %s" % [animal.design.name,chat_notice]
			return
		var at:=Vector2(animal.beast_x,animal.beast_y)
		var floors:Array=world.paper_surfaces(at.x,at.y-12.0,at.y+.35)
		var new_goal:=Vector2.INF
		for i in range(floors.size()-1,-1,-1):
			if floors[i].face!="floor":continue
			var stand:=Ground.trace(world,Vector2(at.x,floors[i].y),at.x-1.47)
			if not stand.is_empty():new_goal=Vector2(at.x-1.47,stand.y)
			break
		if not new_goal.is_finite():
			revision_route.clear()
		elif revision_route.is_empty() or not revision_route.get("ok",false) or new_goal.distance_to(revision_goal)>REVISION_STAND_TOLERANCE:
			revision_goal=new_goal
			revision_route=world.paper_nav_route(here,new_goal)
	if not revision_route.get("ok",false):
		progress="保留「%s」改笔，等原只附近出现可达脚面。"%animal.design.name
		return
	var step:Dictionary=world.paper_nav_step(revision_route,here,delta,2.0)
	if not step.get("ok",false):
		revision_route.clear()
		return
	priest_x=step.at.x
	priest_y=step.at.y
	if step.arrived:
		progress=("已到「%s」附近，等原只落地。" if animal.phase in ["takeoff","fly","land"] else "已到「%s」附近，正在复核落笔站位。")%animal.design.name
	else:
		progress="正沿地面走近「%s」，等待给同一只改绘。"%animal.design.name

func resolve_revision_offer(call_id:String,keep:bool) -> Dictionary:
	if revision_offers.is_empty() or revision_offers[0].call_id!=call_id:
		return {"ok":false,"message":"这笔待选改稿已处理。"}
	var offer:Dictionary=revision_offers[0]
	var id:=""
	if keep and offer.get("waiting",false):return {"ok":false,"message":"原只仍在场，正在等候现场落笔。"}
	if keep:
		var plan:=_file_plan(offer)
		if plan.is_empty():return {"ok":false,"message":"图纸簿已满，改稿仍在待选。"}
		plan.origin_work_id=offer.work_id
		plan.parent_blueprint_id=offer.source_blueprint_id
		plan.archived_revision=true
		id=plan.blueprint_id
		chat_notice="「%s」改稿已另存。可在图纸与手记中查看或照图再画。"%plan.name
	else:chat_notice="已放弃这笔改稿，原物种图纸仍可查看。"
	revision_offers.pop_front()
	_chat_line("status",chat_notice,offer,offer.work_id)
	return {"ok":true,"message":chat_notice,"blueprint_id":id}

func submit_divine_chat(words: String, recovered:=false) -> Dictionary:
	if words.strip_edges().is_empty() or words.length()>600:
		return {"ok":false,"message":"请写下 1 到 600 字的想法。"}
	var status := divine_chat_status()
	if not status.can_send: return {"ok":false,"message":status.progress}
	if pending or _wait_for_brush(words):
		queued_chat=words
		queued_scope=_scope()
		unsent_draft=""
		_chat_delivery(words,"queued",recovered)
		chat_notice="已排队，尚未请求服务商。"
		return {"ok":true,"message":chat_notice,"chat_phase":"queued"}
	return _send_chat(words,false,recovered)

func _wait_for_brush(words:String) -> bool:
	if activity!="draw" and _waiting_revision().is_empty():return false
	var request:=words.to_lower()
	for cue in ["改","重画","重绘","把","保留同一只","redraw","change","shorten","repaint","revise"]:
		if request.contains(cue):return true
	return false

func _queued_line() -> Dictionary:
	for i in range(chat_messages.size()-1,-1,-1):
		if chat_messages[i].get("delivery")=="queued":return chat_messages[i]
	return {}

func _return_queued(notice: String) -> void:
	held_chat=ChatRoles.snapshot_held_chat(held_chat,queued_chat,unsent_draft)
	if unsent_draft.is_empty():unsent_draft=queued_chat
	queued_chat=""
	queued_scope={}
	chat_notice=notice
	var line:=_queued_line()
	if not line.is_empty():line.delivery="unsent"

func _dispatch_queued() -> void:
	if queued_chat.is_empty() or pending or _wait_for_brush(queued_chat): return
	if queued_scope!=_scope() or not divine_connection_status().ready:
		_return_queued("队伍或连接已变化，原话未发出。")
		return
	var result:=_send_chat(queued_chat,true)
	if not result.ok: _return_queued(result.message)

func _chat_delivery(words:String,delivery:String,recovered:bool) -> void:
	var line:=ChatRoles.original_chat_line(chat_messages,words) if recovered else {}
	if line.is_empty():
		_chat_line("player",words)
		line=chat_messages.back()
	line.delivery=delivery

func _send_chat(words: String, queued: bool,recovered:=false) -> Dictionary:
	var observation := Ecology.observe(self)
	observation.pending_placement=placement_observation(observation.habitats)
	observation.task="priest_chat"
	observation.scope=_scope()
	observation.player_text=words
	observation.messages=chat_messages.duplicate(true)
	if queued: observation.messages=observation.messages.filter(func(line):return line.get("delivery")!="queued")
	observation.brush_busy=activity in ["draw","feed","plant"] or not _waiting_revision().is_empty()
	observation.focus_id=focus_animal.work_id if focus_animal else ""
	observation.editable_works=[]
	observation.diet_facts={}
	for animal in works:
		observation.diet_facts[animal.work_id]=_diet_text(animal)
		if animal.phase in ["dead","drawing"]:continue
		if animal.design.has("schema") or _can_reach_animal(animal):
			observation.editable_works.append({"work_id":animal.work_id,"blueprint_id":animal.blueprint_id,"at_brush":_near_brush(animal),"design":animal.design.duplicate(true)})
	if world.survival and world.survival.has_method("decision_facts"):
		observation.local_life=world.survival.decision_facts("priest",Vector2(priest_x,priest_y),13.0)
	chat_pending=true
	pending=true
	if not worker.request_segment(observation):
		chat_pending=false
		pending=false
		return {"ok":false,"message":"本次对话尚未发出。"}
	if queued:
		var line:=_queued_line()
		if not line.is_empty():line.delivery="sent"
	else:
		_chat_delivery(words,"sent",recovered)
	queued_chat=""
	queued_scope={}
	if not queued:unsent_draft=""
	chat_notice="已发给服务商，正在等牧师回复。"
	return {"ok":true,"message":chat_notice,"chat_phase":"sent"}

func _can_reach_animal(animal: Creature) -> bool:
	var at := Vector2(priest_x,priest_y)
	var foot := Ground.trace(world,at,animal.beast_x)
	if foot.is_empty() or absf(float(foot.y)-animal.beast_y)>.35: return false
	return not Ground.trace(world,Vector2(animal.beast_x,animal.beast_y),animal.beast_x-1.47).is_empty()

func _revise_animal(command: Dictionary) -> bool:
	if activity=="draw" or not Form.valid(command.get("design")): return false
	for animal: Creature in works:
		if animal.phase=="dead" or animal.work_id!=command.get("work_id") or not _can_reach_animal(animal): continue
		var revised_form:=Form.new(command.design)
		if not revised_form.occupancy.is_empty():
			var test_shape:=Creature.new(world)
			test_shape.form=revised_form
			if not Creature.Obstacles.fits(test_shape,Vector2(animal.beast_x,animal.beast_y),animal._slope(),animal.face):return false
		if animal.revision.is_empty():
			animal.revision={"original_design":animal.design.duplicate(true),"original_call_id":animal.call_id,
				"original_model":animal.served_model,"count":0}
		animal.revision.count+=1
		animal.design=command.design.duplicate(true)
		animal.form=revised_form
		animal.fruit_target.clear()
		animal.fruit_bite_id=""
		animal.sense_left=0
		animal.cursor=0.0
		animal.call_id=str(command.call_id)
		animal.served_model=str(command.served_model)
		animal.phase="drawing"
		focus_animal=animal
		destination=animal.beast_x-1.47
		activity="draw"
		goal="按玩家要求改绘「%s」" % animal.design.name
		progress="已收改稿，走向原来的小兽"
		return true
	return false

func _request_turn(automatic: bool) -> bool:
	if pending or activity!="idle" or not _waiting_revision().is_empty() or not divine_connection_status().ready or not worker.can_request() or (automatic and not autonomy.available()): return false
	if ProjectSettings.get_setting("paper/divine_demo",false): return false
	var obs := Ecology.observe(self)
	if not automatic and not obs.habitats.any(func(site): return site.room_for_species):
		game.message("附近缺少适宜的空生境，牧师暂缓造生。")
		return false
	if obs.habitats.is_empty() and obs.navigation_sites.is_empty():
		progress="周围没有可达地块，留在原地"
		next_turn=REVISIT_SECONDS
		return false
	obs.pending_placement=placement_observation(obs.habitats)
	obs.survey_is_current = false
	for site in obs.habitats:
		if site.id==surveyed_site and Ecology.evidence(site)==survey_stamp:
			obs.survey_is_current=true
	obs.scope = _scope()
	obs.brush_busy=activity in ["draw","feed","plant"]
	obs.mode = "autonomous" if automatic else "commission"
	obs.at = [snappedf(priest_x,.01),snappedf(priest_y,.01)]
	if world.survival and world.survival.has_method("decision_facts"):
		obs.local_life = world.survival.decision_facts("priest",Vector2(priest_x,priest_y),13.0)
	if not obs.habitats.is_empty():reason=Ecology.evidence(obs.habitats[0])
	pending = true
	if worker.request_segment(obs):
		if automatic: autonomy.used+=1
		return true
	pending = false
	return false

func _receive(obs: Dictionary, command: Dictionary, error: String) -> void:
	if not pending or obs.get("scope")!=_scope() or world!=game.medieval_world: return
	var is_chat := chat_pending
	chat_pending=false
	if not queued_chat.is_empty(): _dispatch_queued.call_deferred()
	pending = false
	next_turn = REVISIT_SECONDS
	var observed_offer:Dictionary=obs.get("pending_placement",{})
	if not observed_offer.is_empty() and not is_chat and observed_offer.id!=placement_offer.get("id",""):
		# A local choice consumed or refreshed this exact draft while the worker was thinking.
		return
	if error!="" or not worker.accepts_command(command):
		progress = "本轮没有执行 · "+(error if error!="" else "回执无效")
		if is_chat: chat_notice=progress
		return
	if activity=="plant" and command.tool!="reply_to_player":
		chat_notice="牧师正在移栽。可在顶栏停止这次工作。"
		return
	if command.tool=="transplant_pasture":
		pasture_care.begin(self,command,obs.get("pasture_care",{}),is_chat)
		return
	if activity=="feed" and command.tool!="reply_to_player":
		chat_notice="牧师正带草照看原个体，当前工序完成后可再委托。"
		return
	if command.tool=="feed_livestock":
		feed_run.begin(self,command,is_chat)
		return
	if command.tool in ["choose_creation_site","set_aside_creation"]:
		if observed_offer.is_empty() or observed_offer.id!=placement_offer.get("id",""):return
		if not is_chat and not observed_offer.get("autonomous",false):return
		if command.tool=="set_aside_creation":
			placement_offer.clear()
			progress="已收起本次未落地的笔稿。"
			chat_notice=progress
		else:
			var outcome:=choose_creation_site(str(command.get("option_id","")))
			if not outcome.ok:return
		_keep_notes(command)
		goal=command.goal
		model_reason=command.reason
		last_eco_call=command.call_id
		var work:=focus_animal.work_id if command.tool=="choose_creation_site" and focus_animal else ""
		record_outcome("选择落点" if work!="" else "收起笔稿",model_reason,progress,work,command.call_id)
		_chat_line("god",command.reply,command,work)
		return
	if command.tool in ["ink_species","file_species","revise_species"]:
		_accept_species(command,is_chat,{},obs.get("mode")=="autonomous")
		return
	_keep_notes(command)
	if command.tool=="travel_to_place":
		_start_travel(command,is_chat)
		return
	if is_chat:
		chat_notice=""
		match command.tool:
			"reply_to_player":
				_species_reply(command)
				chat_notice=str(command.get("capability_note","牧师已回复。"))
				return
			"revise_life":
				if _revise_animal(command):
					_species_reply(command)
					model_reason=obs.player_text.left(180)
					reason="原作「%s」" % focus_animal.design.name
					chat_notice=progress
				else: chat_notice="小兽的位置或笔稿已变化，本轮改稿未落笔。"
				return
			"draw_life": chat_notice="林地条件已变化，本轮未落笔。"
			_: chat_notice="牧师交回的动作无效。"; return
	var id := str(command.get("habitat_id",""))
	var initial: Dictionary = {}
	for item in obs.habitats:
		if item.id==id: initial=item; break
	if initial.is_empty(): return
	var site := Ecology.by_id(self,id)
	if site.is_empty() or site.id!=id:
		progress="原脚面已变化，留在原地"
		return
	habitat_id = id
	goal = str(command.get("goal","按玩家要求画一只小兽"))
	model_reason = str(command.get("reason",obs.get("player_text",""))).left(180)
	reason = Ecology.evidence(site)
	last_eco_call = str(command.call_id)
	if command.tool!="survey_habitat":
		surveyed_site=""
		survey_stamp=""
	destination = float(site.x)
	match command.tool:
		"wait_habitat":
			activity = "wait"
			progress = "留在原地观察，暂缓造生"
		"survey_habitat":
			activity = "survey"
			progress = "前往 %s 实地巡看" % site.get("label",id)
		"tend_habitat":
			var tree = world.entity_by_id(str(command.get("tree_id","")))
			if tree==null or not tree.alive or tree.health>=tree.max_health:
				progress = "目标树况已变，留待再察"
				return
			tending_tree = tree.entity_id
			destination = tree.position.x-1.1
			activity = "tend"
			progress = "前往护养 "+tending_tree
		"draw_life":
			if not initial.can_birth or not site.can_birth or not Form.valid(command.design):
				progress = "落笔前复查：食物或空间不足，本轮收笔"
				return
			var animal := Creature.new(world)
			animal.keeper=self
			animal.work_id = "life-"+Crypto.new().generate_random_bytes(12).hex_encode()
			animal.team_id = obs.scope.team_id
			animal.world_id = obs.scope.world_id
			animal.habitat_id = id
			animal.served_model = str(command.get("served_model",""))
			animal.design = command.design.duplicate(true)
			animal.form = Form.new(animal.design)
			animal.phase = "drawing"
			animal.beast_x = site.x
			animal.beast_y = site.ground_y
			animal.call_id = command.call_id
			works.append(animal)
			focus_animal = animal
			destination = animal.beast_x-1.47
			activity = "draw"
			progress = "已接笔稿，前往"+id
			if is_chat:
				_chat_line("god",command.reply,command,animal.work_id)
				chat_notice=progress

func _placement_failure(message:String,command:Dictionary={}) -> bool:
	progress=message.left(250)
	chat_notice=progress
	_chat_line("status",progress,command)
	return false

func _placement_sites(trial:Creature,sites:Array,requested:Vector2) -> Array:
	return Placement.suggestions(self,trial,sites,requested).filter(func(option):
		return not str(option.habitat_id).begins_with("pocket-") or Ecology.pocket_clear(self,option.at))

func _offer_sites(c:Dictionary,is_chat:bool,trial:Creature,sites:Array,requested:Vector2,why:String,autonomous:bool) -> bool:
	var options:=_placement_sites(trial,sites,requested)
	var message:="「%s」未落笔。%s。" % [c.design.name,why]
	for option in options:
		option.id=Crypto.new().generate_random_bytes(8).hex_encode()
	if options.is_empty():message+="附近试过的位置也没有合适的落点。"
	var instruction:=message if options.is_empty() else message+"可在牧师对话中选附近空地，沿用这次笔稿。"
	placement_offer={"id":Crypto.new().generate_random_bytes(8).hex_encode(),"scope":_scope(),
		"command":c.duplicate(true),"requested":requested,"sites":options,"chat":is_chat,"autonomous":autonomous,"problem":why,"message":instruction}
	return _placement_failure(message,c)

func placement_observation(habitats:Array) -> Dictionary:
	if placement_offer.is_empty() or placement_offer.scope!=_scope():return {}
	var draft:Dictionary=placement_offer.command
	var trial:=Creature.new(world)
	trial.design=draft.design
	trial.form=Form.new(draft.design)
	var latest:=_placement_sites(trial,habitats,placement_offer.requested)
	for site in latest:
		for previous in placement_offer.sites:
			if previous.habitat_id==site.habitat_id and previous.at.distance_to(site.at)<.01:
				site.id=previous.id
				break
		if not site.has("id"):site.id=Crypto.new().generate_random_bytes(8).hex_encode()
	placement_offer.sites=latest
	var notice:="「%s」未落笔。%s。" % [draft.design.name,placement_offer.problem]
	placement_offer.message=notice+("复查时附近没有合适的落点。" if latest.is_empty() else "可在牧师对话中选附近空地，沿用这次笔稿。")
	var options:=[]
	for site in placement_offer.sites:
		options.append({"id":site.id,"at":[site.at.x,site.at.y],"label":site.label,"habitat_id":site.habitat_id})
	return {"id":placement_offer.id,"autonomous":placement_offer.autonomous,"problem":placement_offer.problem,
		"source_call":draft.call_id,"design":draft.design.duplicate(true),"goal":draft.goal,"options":options}

func choose_creation_site(id:String) -> Dictionary:
	if placement_offer.is_empty() or placement_offer.scope!=_scope() or world!=game.medieval_world:
		return {"ok":false,"message":"这次换位已失效。"}
	if chat_pending or activity=="draw":
		return {"ok":false,"message":"正在处理另一件事，完成后可再次选位。"}
	for option in placement_offer.sites:
		if option.id!=id:continue
		var offer:=placement_offer
		placement_offer={}
		var ok:=_accept_species(offer.command,offer.chat,option,offer.autonomous)
		return {"ok":ok,"message":chat_notice}
	return {"ok":false,"message":"这个位置已更新，请选择当前显示的空地。"}

func _accept_species(c:Dictionary,is_chat:bool,chosen:Dictionary={},autonomous:=false) -> bool:
	if not Species.valid(c.get("design")):
		progress="图纸的部件、线条或行为没有通过现场检查。"
		chat_notice=progress
		return false
	var plan:Dictionary={}
	var site:Dictionary={}
	var target:Creature
	var reuse:=str(c.get("blueprint_id","draft"))!="draft"
	if c.tool=="ink_species":
		placement_offer.clear()
		if activity=="draw":return _placement_failure("牧师正在画另一只生命，尚不能同时落笔。")
		if live_count()>=Ecology.CAPACITY:return _placement_failure("本世界已有 %d 只活体，已到造生上限。" % Ecology.CAPACITY)
		if works.size()>=Species.MAX_WORKS:return _placement_failure("本世界的作品收藏已满，本轮未落笔。")
		if reuse:
			plan=_book(c.blueprint_id)
			if plan.is_empty() or plan.design!=c.design:return _placement_failure("原图编号已找不到匹配的图纸。")
		elif blueprints.size()>=Species.MAX_PLANS:return _placement_failure("本世界物种图纸簿已满。")
		var habitats:Array=Ecology.observe(self).habitats
		var wanted:String=chosen.get("habitat_id",c.get("habitat_id",""))
		for h in habitats:
			if h.id==wanted:site=h;break
		if site.is_empty() and wanted.begins_with("pocket-"):site=Ecology.by_id(self,wanted)
		var trial:=Creature.new(world)
		trial.design=c.design
		trial.form=Form.new(c.design)
		var offsets:Array=[0.0] if wanted.begins_with("pocket-") else Placement.OFFSETS
		if not chosen.is_empty() and not site.is_empty():offsets=[chosen.at.x-site.x]
		var result:=Placement.inspect(self,trial,site,offsets)
		if result.has("fit") and wanted.begins_with("pocket-") and not Ecology.pocket_clear(self,Vector2(result.fit.x,result.fit.ground_y)):
			result={"problem":"运笔位或通往这片干地的脚面已被挡住"}
		if result.has("fit") and not chosen.is_empty() and absf(result.fit.ground_y-chosen.at.y)>.08:
			result={"problem":"所选位置的脚面高度已经改变"}
		if not result.has("fit"):
			var requested:Vector2=chosen.get("at",Vector2(site.get("x",priest_x),site.get("ground_y",priest_y)))
			return _offer_sites(c,is_chat,trial,habitats,requested,result.problem,autonomous)
		site=result.fit
	elif c.tool=="revise_species":
		target=work_by_id(c.get("work_id",""))
		if c.has("source_blueprint_id") and (not target or c.source_blueprint_id!=target.blueprint_id):return _placement_failure("这只生命的图纸已改变，请从当前原稿重看。")
		if c.has("edit_part_id") and (not target or not Species.only_part_changed(target.design,c.design,c.edit_part_id)):return _placement_failure("局部改绘须只改变所选的原部件。")
		if target and target.phase=="dead" and is_chat and c.get("source_blueprint_id","")==target.blueprint_id:
			_hold_revision(c,target)
			return false
		if is_chat and target and target.phase not in ["drawing","dead"] and c.has("source_blueprint_id") and not _near_brush(target):
			_hold_revision(c,target,true)
			return true
		if not target or target.phase in ["drawing","dead"] or not _can_reach_animal(target):chat_notice="原作品现在无法改绘。";return false
	if plan.is_empty():
		plan=_file_plan(c)
		if plan.is_empty():chat_notice="本世界物种图纸簿已满。";return false
	goal=c.goal
	model_reason=c.reason
	last_eco_call=c.call_id
	if c.tool=="ink_species":
		target=Creature.new(world)
		target.keeper=self
		target.work_id="life-"+Crypto.new().generate_random_bytes(12).hex_encode()
		target.team_id=_scope().team_id
		target.world_id=_scope().world_id
		target.habitat_id=site.id
		target.design=plan.design.duplicate(true)
		target.form=Form.new(target.design)
		target.phase="drawing"
		target.beast_x=site.x
		target.beast_y=site.ground_y
		target.served_model=c.served_model
		target.call_id=c.call_id
		target.portions=3 if target.design.edible else 0
		works.append(target)
		focus_animal=target
		destination=target.beast_x-1.47
		activity="draw"
		habitat_id=site.id
		reason=Ecology.evidence(site)
		progress="正在现场绘制「%s」的 %d 个部件" % [plan.name,plan.design.parts.size()]
	elif c.tool=="revise_species":
		var previously_edible:bool=target.design.get("edible",false)
		if not _revise_animal(c):
			blueprints.erase(plan)
			if is_chat and c.has("source_blueprint_id"):
				if not revision_offers.any(func(item):return item.call_id==c.call_id):
					_hold_revision(c,target,true)
				chat_notice="「%s」仍在场，原改笔已保留，等现场腾出运笔空间。"%target.design.name
			else:chat_notice="现场变化，未应用改稿。"
			return false
		target.portions=(mini(3,target.portions) if previously_edible else 3) if c.design.edible else 0
	else:progress="物种图纸「%s」已收入图纸簿" % plan.name
	if target:
		target.blueprint_id=plan.blueprint_id
		if plan.get("origin_work_id","")=="":plan.origin_work_id=target.work_id
	for note in c.get("memory_updates",[]):
		if note.get("blueprint_id")=="draft":note.blueprint_id=plan.blueprint_id
		if note.get("work_id")=="draft":note.work_id=target.work_id if target else ""
	_keep_notes(c)
	record_outcome(c.tool,c.reason,progress,target.work_id if target else "",c.call_id)
	if not chosen.is_empty():_chat_line("status","已选 "+str(chosen.label)+"，沿用原稿开始绘制。",c,target.work_id)
	elif is_chat and c.tool=="revise_species":_species_reply(c)
	elif is_chat:_chat_line("god",c.reply,c,target.work_id if target else "")
	chat_notice=progress
	return true

func _place_label(id:String,at:Vector2,display:String) -> String:
	if not id.is_empty() and world.has_method("paper_nav_label"):
		var name_at:String=world.paper_nav_label(id,at)
		if not name_at.is_empty():return name_at.left(80)
	if "@" not in display and not display.is_empty():return display.left(80)
	return "纸面地点 (%.1f, %.1f)" % [at.x,at.y]

func _route_choices(result:Dictionary) -> String:
	travel_alternatives.clear()
	var labels:=PackedStringArray()
	for site in result.get("alternatives",[]):
		if travel_alternatives.size()>=3:break
		var at:Array=site.at
		var label:=_place_label(site.id,Vector2(at[0],at[1]),str(site.get("label","")))
		travel_alternatives.append({"id":str(site.id),"at":at.duplicate(),"label":label})
		labels.append(label)
	return "；可改去 "+"、".join(labels) if not labels.is_empty() else ""

func _start_travel(c:Dictionary,is_chat:bool) -> void:
	if activity=="draw" or not world.has_method("paper_nav_route"):return
	var at=c.get("at")
	if not at is Array or at.size()!=2 or not Form.number(at[0],-1000000,1000000) or not Form.number(at[1],-1000000,1000000):return
	var place_id:=str(c.get("place_id",""))
	var label:=_place_label(place_id,Vector2(at[0],at[1]),str(c.get("label","")))
	var route:Dictionary=world.paper_nav_route(Vector2(priest_x,priest_y),Vector2(at[0],at[1]))
	if not route.get("ok",false):
		progress=("到不了 "+label+" · "+str(route.get("error","当前无通路"))+_route_choices(route)).left(250)
		if is_chat:chat_notice=progress
		record_outcome("寻路",c.reason,progress,"",c.call_id)
		return
	travel_target={"place_id":place_id,"at":at.duplicate(),"label":label,"chat":is_chat}
	travel_route=route
	travel_alternatives.clear()
	travel_sample=0.0
	destination=float(at[0])
	activity="travel"
	goal=c.goal
	model_reason=c.reason
	last_eco_call=c.call_id
	progress="正在前往 "+label
	if is_chat:_chat_line("god",c.reply,c)
	chat_notice=progress

func _travel_step(delta:float) -> void:
	var at:Vector2=Vector2(priest_x,priest_y)
	var dest=travel_target.get("at",[])
	if dest.size()!=2 or not world.has_method("paper_nav_step"):
		activity="idle"
		progress="当前路线不可用，重新观察地形"
		travel_target.clear()
		return
	if travel_route.is_empty():travel_route=world.paper_nav_route(at,Vector2(dest[0],dest[1]))
	var step:Dictionary=world.paper_nav_step(travel_route,at,delta,2.0) if travel_route.get("ok",false) else travel_route
	if not step.get("ok",false):
		progress=("去 "+str(travel_target.label)+" 的路线已中断 · "+str(step.get("error","地面已变"))+_route_choices(step)).left(250)
		record_outcome("寻路",model_reason,progress,"",last_eco_call)
		activity="idle"
		travel_target.clear()
		travel_route.clear()
		return
	var moved:Vector2=step.at
	priest_x=moved.x
	priest_y=moved.y
	travel_sample-=delta
	if travel_sample<=0 and world.survival:
		travel_sample=3.0
		var facts:Dictionary=world.survival.decision_facts("priest",moved,13.0)
		reason="沿途可见 %d 棵树、%d 位村民、%d 片草地" % [facts.get("trees",[]).size(),facts.get("villagers",[]).size(),facts.get("pastures",[]).size()]
	progress="前往 %s · 脚点 (%.1f, %.1f)" % [travel_target.label,priest_x,priest_y]
	if step.get("arrived",false):
		progress="已到 "+str(travel_target.label)
		record_outcome("到达",model_reason,progress+" · "+reason,"",last_eco_call)
		if travel_target.get("chat",false):
			_chat_line("status",progress+" · "+reason)
			chat_notice=progress
		travel_target.clear()
		travel_route.clear()
		activity="idle"

func _local_patrol_step(delta:float) -> void:
	if not patrol_allowed or autonomy_paused or activity!="idle" or pending or chat_pending or not queued_chat.is_empty() or not placement_offer.is_empty() or not travel_target.is_empty() or world.survival==null:
		patrol.interrupt()
		return
	var here:=Vector2(priest_x,priest_y)
	var sites: Array=[]
	if patrol.plan.is_empty() and patrol.rest_left<=delta:
		sites=Ecology.patrol_sites(self,here,patrol.site_id)
		patrol_evidence=""
	var step:=patrol.tick(world,here,delta,true,2.0,sites)
	for site in sites:
		if site.id==patrol.site_id and not patrol.plan.is_empty():patrol_evidence=site.evidence;break
	if step.has("at"):
		priest_x=step.at.x
		priest_y=step.at.y
	if step.get("arrived",false):
		var facts:Dictionary=world.survival.decision_facts("priest",step.at,8)
		patrol_evidence="现场可见 %d 棵树、%d 片草地" % [facts.trees.size(),facts.pastures.size()]

func _physics_process(delta: float) -> void:
	if get_tree().current_scene!=game or not is_visible_in_tree(): return
	clock += delta
	protect_left = maxf(0.0,protect_left-delta)
	if protect_left<=0: protected_tree=""
	var waiting:=_waiting_revision()
	if waiting.is_empty():_local_patrol_step(delta)
	else:
		patrol.interrupt()
		_follow_revision(waiting,delta)
	if activity=="travel": _travel_step(delta)
	if activity=="feed":feed_run.step(self,delta)
	if activity=="plant":pasture_care.step(self,delta)
	if activity in ["draw","survey","tend"]:
		var step:=move_toward(priest_x,destination,delta*2.0)
		if step!=priest_x:
			var surface:=Ground.trace(world,Vector2(priest_x,priest_y),step)
			var blocked:=surface.is_empty()
			if not blocked and habitat_id.begins_with("pocket-") and activity in ["draw","survey"]:
				blocked=not Ecology.dry_walk(self,Vector2(priest_x,priest_y),Vector2(step,surface.y))
			if blocked:
				progress="前往现场的脚面受阻"
				if activity!="draw": activity="idle"
			else:
				priest_x=step
				priest_y=surface.y
	gait.advance(world,Vector2(priest_x,priest_y),delta)
	var arrived := absf(priest_x-destination)<.04
	if arrived and activity=="tend":
		var tree = world.entity_by_id(tending_tree)
		if tree!=null and tree.alive:
			var previous: float = protect_left if protected_tree==tending_tree else 0
			protected_tree=tending_tree
			protect_left=90
			ecology_log.record(self,null,"tend",protected_tree,previous,protect_left,"牧师到树旁巡护，%s 的保护时间为 90 秒。" % protected_tree)
			record_outcome("护养",model_reason,"受护树："+protected_tree,"",last_eco_call)
			progress="护养 "+protected_tree+"，食皮兽暂避该树"
		else: progress="树已不在，结束巡护"
		activity="idle"
	elif arrived and activity=="survey":
		var site:=Ecology.by_id(self,habitat_id)
		var report:=Ecology.survey_report(self,site)
		reason=report.text
		if not site.is_empty():
			surveyed_site=habitat_id
			survey_stamp=Ecology.evidence(site)
		progress=reason
		record_outcome("巡看",model_reason,reason,report.id,last_eco_call)
		activity="idle"
	for animal in works:
		var drawing: bool = animal.phase=="drawing"
		animal.advance(delta,arrived and animal==focus_animal,protected_tree)
		if drawing and animal.phase!="drawing":
			progress="「%s」已改绘，继续在林中活动" % animal.design.name if not animal.revision.is_empty() else "「%s」已出生，本图在世 %d 只，全世界在世 %d 只。" % [animal.design.name,works.filter(func(a):return a.blueprint_id==animal.blueprint_id and a.phase not in ["drawing","dead"]).size(),live_count()]
			var revised: bool = not animal.revision.is_empty()
			var version_number := int(animal.revision.get("count",0))+1
			ecology_log.record(self,animal,"revision" if revised else "birth",animal.call_id,version_number-1,version_number,progress)
			record_outcome("收笔",model_reason,progress,animal.work_id,animal.call_id)
			if revised:
				_chat_line("status","同一只「%s」已收笔。%s"%[animal.design.name,_diet_text(animal)],{"served_model":animal.served_model,"call_id":animal.call_id},animal.work_id)
			activity="idle"
		elif drawing and arrived:
			progress="正在落笔 · %d%%" % floori(100.0*animal.cursor/animal.form.length)
	if not pending and not queued_chat.is_empty() and activity!="draw":_dispatch_queued()
	if not pending and queued_chat.is_empty() and _waiting_revision().is_empty() and autonomy.available() and not ProjectSettings.get_setting("paper/divine_demo",false):
		next_turn=maxf(0.0,next_turn-delta)
		if next_turn<=0 and activity in ["wait","idle"]:
			if activity=="wait": activity="idle"
			next_turn=3.0
			if worker.can_request(): _request_turn(true)
	queue_redraw()

func snapshot() -> Dictionary:
	var records := []
	for animal in works: records.append(animal.snapshot())
	return {"version":2,"revision_offers":revision_offers.duplicate(true),"pasture_job":pasture_care.job.duplicate(true),"feed_run":{"carried":feed_run.carried,"job":feed_run.job.duplicate(true)},"ecology_records":ecology_log.rows.duplicate(true),"historical_reviews_read":historical_reviews_read,"travel_alternatives":travel_alternatives.duplicate(true),"travel_target":travel_target.duplicate(true) if activity=="travel" else {},"commitments":commitments.duplicate(true),"blueprints":blueprints.duplicate(true),"memory":memory.duplicate(true),"works":records,"chat":chat_messages.duplicate(true),"held_chat":ChatRoles.snapshot_held_chat(held_chat,queued_chat,unsent_draft),"chat_draft":queued_chat if unsent_draft.is_empty() else unsent_draft,"focus_id":focus_animal.work_id if focus_animal else "",
		"x":priest_x,"y":priest_y,"gait":gait.snapshot(),"destination":destination,"activity":activity,"habitat_id":habitat_id,
		"surveyed_site":surveyed_site,"survey_stamp":survey_stamp,"goal":goal,"reason":reason,"model_reason":model_reason,"progress":progress,"eco_call":last_eco_call,
		"autonomy_paused":autonomy_paused,"used":autonomy.used,"budget":autonomy.budget,"next_turn":maxf(REVISIT_SECONDS,next_turn) if pending else next_turn,"tending_tree":tending_tree,
		"protected_tree":protected_tree,"protect_left":protect_left}

func restore(data: Dictionary) -> void:
	_cancel_turn()
	var saved_gait = data.get("gait",{})
	gait.restore(saved_gait if saved_gait is Dictionary else {})
	chat_messages=data.get("chat",[]).duplicate(true)
	held_chat=ChatRoles.read_held_chat(data.get("held_chat",[]))
	unsent_draft=str(data.get("chat_draft",""))
	chat_notice="有一段尚未发送的草稿。" if unsent_draft!="" else ""
	var prior_line:=_queued_line()
	if not prior_line.is_empty():prior_line.delivery="unsent"
	if not chat_messages.is_empty() and chat_messages.back().get("delivery")=="sent":
		chat_notice="上次对话已发送，回执未收存；如需继续请重新发送。"
	blueprints=data.get("blueprints",[]).duplicate(true)
	revision_offers=data.get("revision_offers",[]).duplicate(true)
	revision_route.clear()
	revision_goal=Vector2.INF
	revision_check=0
	ecology_log.rows=data.get("ecology_records",[]).duplicate(true)
	historical_reviews_read=data.get("historical_reviews_read",false)
	feed_run.restore(data.get("feed_run",{}))
	pasture_care.restore(data.get("pasture_job",{}))
	memory=data.get("memory",[]).duplicate(true)
	commitments=data.get("commitments",[]).duplicate(true)
	travel_alternatives=data.get("travel_alternatives",[]).duplicate(true)
	travel_target=data.get("travel_target",{}).duplicate(true)
	travel_route.clear()
	works.clear()
	focus_animal=null
	priest_x=PRIEST_X
	priest_y=world.travel_height(priest_x)
	destination=PRIEST_X
	activity="idle"
	next_turn=3.0
	goal="观察林地，决定如何照看这里"
	reason=""
	progress="尚未巡看"
	model_reason=""
	last_eco_call=""
	surveyed_site=""
	survey_stamp=""
	protected_tree=""
	tending_tree=""
	habitat_id=""
	protect_left=0
	autonomy.set_budget(0)
	autonomy.set_paused(false)
	if data.is_empty(): return
	if data.version==1:
		var record := data.duplicate(true)
		var scope := _scope()
		record.work_id="legacy-"+str(record.call_id if not str(record.call_id).is_empty() else JSON.stringify(record.design)).sha256_text().left(24)
		record.team_id=scope.team_id
		record.world_id=scope.world_id
		record.habitat_id="grove-0"
		var animal := Creature.new(world)
		animal.keeper=self
		animal.restore(record)
		works.append(animal)
		focus_animal=animal
		activity="draw" if animal.phase=="drawing" else "idle"
		destination=animal.beast_x-1.47 if activity=="draw" else PRIEST_X
		progress="接着画「%s」" % animal.design.name if activity=="draw" else "历史小兽已回到林地"
		next_turn=REVISIT_SECONDS
		return
	for record in data.works:
		var animal := Creature.new(world)
		animal.keeper=self
		animal.restore(record)
		works.append(animal)
		if animal.work_id==data.focus_id: focus_animal=animal
	priest_x=data.x
	priest_y=data.get("y",world.travel_height(priest_x))
	destination=data.destination
	activity=data.activity
	habitat_id=data.habitat_id
	goal=data.goal
	reason=data.reason
	model_reason=data.model_reason
	progress=data.progress
	if activity=="travel" and travel_target.get("at",[]).size()==2:
		var at:Array=travel_target.at
		var original_label:=str(travel_target.get("label",""))
		travel_target.place_id=str(travel_target.get("place_id",original_label if "@" in original_label else ""))
		travel_target.label=_place_label(travel_target.place_id,Vector2(at[0],at[1]),original_label)
		progress="前往 "+str(travel_target.label)
	last_eco_call=data.eco_call
	surveyed_site=data.get("surveyed_site","")
	survey_stamp=data.get("survey_stamp","")
	autonomy.paused=data.autonomy_paused
	autonomy.budget=int(data.get("budget",0))
	autonomy.used=int(data.get("used",0))
	next_turn=maxf(3.0,data.next_turn)
	tending_tree=data.tending_tree
	protected_tree=data.protected_tree
	protect_left=data.protect_left
	if not historical_reviews_read and "chronicle" in world and world.chronicle:
		for note in commitments:ecology_log.publish_review(self,note,true)
		historical_reviews_read=true

func _label(at: Vector2, words: String, color: Color) -> void:
	var px := clampi(roundi(game.PIXELS_PER_UNIT*.205),13,19)
	var text_size := font.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,px)
	var rect := Rect2(at-Vector2(text_size.x*.5+7,text_size.y+6),text_size+Vector2(14,5))
	draw_rect(rect,Color("fff7e8f2"))
	draw_line(rect.position,Vector2(rect.position.x,rect.end.y),color,2.4,true)
	draw_string(font,rect.position+Vector2(7,2+font.get_ascent(px)),words,HORIZONTAL_ALIGNMENT_LEFT,-1,px,color)

func _draw() -> void:
	var ppu: float = game.PIXELS_PER_UNIT
	var foot: Vector2 = game.world_to_screen(Vector2(priest_x,priest_y))
	var nib := foot+Vector2(gait.facing*(.33+sin(clock*1.5)*.025),-1.47)*ppu
	var writing := activity=="draw" and absf(priest_x-destination)<.04
	for animal in works:
		var tip: Vector2 = animal.paint(self)
		if writing and tip.is_finite(): nib=tip
	if game.get_viewport_rect().grow(ppu*2.5).has_point(foot):
		gait.draw(self,foot,nib,ppu,clock,writing)
		var caption:="观察林地中" if pending else progress.left(25)
		if patrol.active:caption="本地巡林 · "+("驻足查看" if patrol.plan.is_empty() else "前往"+patrol.label)
		elif autonomy_paused and activity=="idle":caption="自主已暂停"
		_label(foot-Vector2(0,ppu*1.73),"至高神 · 牧师　"+caption,Color("78483a"))
	if protect_left>0:
		var tree = world.entity_by_id(protected_tree)
		if tree!=null and tree.alive:
			_label(game.world_to_screen(tree.position+Vector2(0,1.6)),"牧师护养 · 暂缓啃食",Color("516a45"))
