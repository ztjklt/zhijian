extends Node2D

const ROLE := "war_god"
const HOME := 7.4
const Actor := preload("res://scripts/war_god_actor.gd")
const Observer := preload("res://scripts/war_god_senses.gd")
const Autonomy := preload("res://scripts/sandbox_autonomy.gd")
const LocalWalk := preload("res://scripts/local_role_walk.gd")
const Senses := preload("res://scripts/companion_senses.gd")
const Ground := preload("res://scripts/priest_ground.gd")
const Identity := preload("res://scripts/sandbox_identity.gd")
const ORDERS := ["patrol","investigate","protect","intercept"]
const LABEL := {"patrol":"巡路","investigate":"调查","protect":"守护","intercept":"截击"}
const INTERCEPT_HOLD_MS := 45000
var intercept_hold := {}
var native_approach_left := 0.0
var native_approach := {}
const INK := Color("814938")

var game
var world
var actor
var worker
var autonomy := Autonomy.new()
var local_walk := LocalWalk.new(1,8.0)
var action := {}
var memory: Array = []
var visits: Array = []
var messages: Array = []
var last_player_hit := {}
var last_combat := {}
var queued_chat := ""
var queued_at := Vector2.INF
const ChatRoles:=preload("res://scripts/divine_roles.gd")
var held_chat: Array = []
var unsent_draft := ""
var pending := false
var speaking := false
var status := "整装候命"
var chat_notice := ""
var retry_left := .9
var defense_left := 0.0
var down_left := 0.0
var swing_target := ""
var stopped := 0.0
var old_x := INF
var guard_time := 0.0
var travel_plan := {}
var travel_goal := Vector2.INF
var route_jump := false
var route_down := false
var sweep_evidence := {}
var last_swing_blocked := false
var flank := Vector2.INF
var flanked := 0
var _saved := {}
var _font: Font

func _ready() -> void:
	name="SandboxWarGod"
	world=get_parent()
	game=world.game
	z_index=4
	_font=PaperTheme.create().default_font
	worker=preload("res://scripts/east_painter.gd").new()
	worker.actor_role=ROLE
	worker.worker_resource="res://tools/war_god_turn.mjs"
	worker.request_directory="user://war_god_turns"
	worker.use_painter_mailbox=false
	add_child(worker)
	worker.finished.connect(_decide)
	worker.binding_changed.connect(_binding_changed)

func _exit_tree() -> void:
	if is_instance_valid(worker):worker.cancel()

func _arrive() -> void:
	actor=Actor.new()
	actor.sandbox=game
	actor.player_id=ROLE
	actor.display_name="战神"
	add_child(actor)
	actor.relocate(world.safe_spawn_position(HOME))
	if not _saved.is_empty():_take_snapshot(_saved)
	_saved={}

func _binding_changed() -> void:
	local_walk.interrupt()
	if not queued_chat.is_empty():
		held_chat=ChatRoles.snapshot_held_chat(held_chat,queued_chat,unsent_draft)
		if unsent_draft.is_empty():unsent_draft=queued_chat
		queued_chat=""
		chat_notice="连接已变化，原话留在草稿。"
	retry_left=.7

func divine_status() -> Dictionary:
	var route:=ModelConnections.role_status(ROLE)
	var public:=autonomy.status(route)
	var label:=status
	if down_left>0: label="负伤整息"
	elif defense_left>0: label="面对此地的实击者"
	elif pending: label="等待模型判断"
	elif action.is_empty() and not worker.can_request(): label="候命 · "+str(route.message)
	var recent:=str(last_combat.get("source","") if last_combat.get("target")==ROLE else last_combat.get("target",""))
	var target:=str(action.get("id",recent))
	public.merge({"phase":"working" if not action.is_empty() or defense_left>0 else "thinking" if pending else "idle",
		"summary":label,"action_label":"看战神现场","can_start":false,"progress":status,
		"capabilities":"沿实地巡路、守护村民、截击确认敌对的怪物",
		"target_work_id":target if target.begins_with("life-") or target.begins_with("legacy-") else "",
		"decision_source":"引擎防卫" if defense_left>0 else "模型决策 · 执行中" if not action.is_empty() else "等待模型决策"},true)
	if _can_patrol_locally(route):
		public.merge(local_walk.view("本地巡防"),true)
	elif autonomy.paused and down_left<=0.0 and defense_left<=0.0 and not action.get("chat",false) and not action.get("finish_before_pause",false) and not speaking:
		public.decision_source="自主已暂停"
	elif action.is_empty() and not pending and not route.ready and defense_left<=0.0:
		public.decision_source="模型连接暂不可用"
	return public

func observation_target() -> Vector2:
	return actor.player.position if is_instance_valid(actor) else Vector2.INF

func foot_position() -> Vector2:
	var at:=observation_target()
	return at-Vector2(0,.29) if at.is_finite() else Vector2.INF

func intercept_on_hold(id:String) -> bool:
	var hold:Dictionary=intercept_hold.get(id,{})
	var revision:int=world.paper_space.navigation_revision if world.paper_space!=null else 0
	return Time.get_ticks_msec()<int(hold.get("until",0)) and revision==hold.get("revision")

func set_autonomy_paused(value: bool) -> void:
	action.erase("finish_before_pause")
	autonomy.set_paused(value)
	if value: local_walk.interrupt()
	if value and pending and not speaking:
		worker.cancel()
		pending=false
	if not value:retry_left=.2

func set_action_budget(value: int) -> void:
	autonomy.set_budget(value)
	retry_left=.2

func _line(speaker: String, text: String) -> void:
	if text.is_empty():return
	messages.append({"speaker":speaker,"text":text.left(600)})
	if messages.size()>20:messages.pop_front()

func divine_chat_status() -> Dictionary:
	var route:=ModelConnections.role_status(ROLE)
	var chat_phase:="queued" if not queued_chat.is_empty() else "sent" if pending and speaking else "executing" if action.get("chat",false) else "ready"
	return {"messages":messages.duplicate(true),"pending":chat_phase!="ready","can_send":is_instance_valid(actor) and worker.can_request() and chat_phase=="ready",
		"chat_phase":chat_phase,"connection_code":route.code,"draft":unsent_draft,"progress":chat_notice if worker.can_request() else route.message}

func submit_divine_chat(text:String,recovered:=false) -> Dictionary:
	if text.strip_edges().is_empty() or text.length()>600:return {"ok":false,"message":"请写下 1 到 600 字的想法。"}
	if not worker.can_request():return {"ok":false,"message":ModelConnections.role_status(ROLE).message}
	if not divine_chat_status().can_send:return {"ok":false,"message":"战神正在处理上一条消息。"}
	queued_chat=text
	queued_at=game.player.position
	unsent_draft=""
	if not recovered or ChatRoles.original_chat_line(messages,text).is_empty():_line("player",text)
	chat_notice="已排队，尚未请求服务商。"
	return {"ok":true,"message":chat_notice,"chat_phase":"queued"}

func _observe(is_chat: bool) -> void:
	var chat: Dictionary={"text":queued_chat,"messages":messages.duplicate(true),"player_at":Senses.pair(queued_at)} if is_chat else {}
	if not worker.request_segment(Observer.view(self,chat)):
		retry_left=3.0
		return
	pending=true
	speaking=is_chat
	if is_chat:
		queued_chat=""
		chat_notice="已发给服务商，等待战神回复。"
	else:autonomy.used+=1
	status="正在核对周围路况"

func _decide(view: Dictionary, command: Dictionary, error:String) -> void:
	if not pending or get_tree().current_scene!=game or world!=game.medieval_world or view.get("scope")!=Autonomy.scope(game):return
	var was_chat:=speaking
	pending=false
	speaking=false
	if not error.is_empty() or not worker.accepts_command(command):
		status=error if not error.is_empty() else "本轮未收到可执行判断"
		if was_chat:
			chat_notice=status
			_line("status",status)
		retry_left=18.0
		return
	var tool:String=command.get("tool","")
	if was_chat:
		_line("god",str(command.get("message","")))
		chat_notice="战神已回复。"
	autonomy.goal=str(command.get("goal","")).left(32)
	autonomy.reason=str(command.get("reason","")).left(80)
	if tool in ["reply","wait"]:
		status="已答复" if tool=="reply" else "留在原处观察"
		_record({"kind":tool,"result":status,"call_id":command.get("call_id",""),"model":command.get("served_model","")})
		retry_left=22.0 if tool=="wait" else 4.0
		return
	if tool not in ORDERS:return
	var rows:Array=view.threats if tool=="intercept" else view.villagers if tool=="protect" else view.routes
	for row in rows:
		if row.get("id")!=command.get("target") or not Autonomy.pair(row.get("at")):continue
		if tool=="intercept" and not row.get("approach",{}).get("ok",true):
			status=str(row.approach.reason)
			if was_chat:
				chat_notice=status
				_line("status",status)
			retry_left=18.0
			return
		var distance:float=absf(row.at[0]-actor.player.position.x)
		action={"tool":tool,"id":row.id,"at":row.at,"name":str(row.get("label",row.get("name","村民"))).left(120),"remaining":clampf(distance/1.75+12,12,50),
			"chat":was_chat,"call_id":command.get("call_id",""),"request_id":worker.last_request_path.get_file().get_slice(".",0),
			"model":str(command.get("served_model","")),"goal":autonomy.goal,"reason":autonomy.reason}
		status=LABEL[tool]+" · "+action.name
		travel_plan={}
		travel_goal=Vector2.INF
		flank=Vector2.INF
		flanked=0
		native_approach={}
		native_approach_left=0.0
		if was_chat:chat_notice=status
		_record({"kind":"accepted","action":tool,"target":action.id,"result":status,"call_id":action.call_id,"request_id":action.request_id,"model":action.model})
		guard_time=0.0
		return
	status="该目标已不可用"
	retry_left=4.0

func _physics_process(delta: float) -> void:
	if get_tree().current_scene!=game or world!=game.medieval_world or is_queued_for_deletion():return
	if actor==null:_arrive()
	if down_left>0:
		local_walk.interrupt()
		down_left=maxf(0,down_left-delta)
		if down_left==0:
			actor.relocate(autonomy.respawn(world,HOME))
			actor.set_active(true)
			actor.combat.health=100
			actor.combat.invulnerable=2.0
		queue_redraw()
		return
	var at:Vector2=actor.player.position
	var move:=0
	var jump:=false
	route_jump=false
	route_down=false
	var patrolling := _can_patrol_locally(ModelConnections.role_status(ROLE))
	if not patrolling: local_walk.interrupt()
	if defense_left>0:
		defense_left=maxf(0,defense_left-delta)
		if at.distance_to(game.player.position)>9.0 or defense_left==0:
			defense_left=0.0
			_record({"kind":"disengaged","source":"player","result":"已脱离，恢复巡护"})
			status="已脱离，恢复巡护"
		else:move=_engage("player",game.player.position+Vector2(0,.12))
	elif not action.is_empty() and (not autonomy.paused or action.chat or action.get("finish_before_pause",false)):
		move=_advance(delta)
	elif action.is_empty() and not pending and worker.can_request() and not queued_chat.is_empty():
		_observe(true)
	elif action.is_empty() and not pending and worker.can_request() and autonomy.available():
		retry_left-=delta
		if retry_left<=0:_observe(false)
	elif patrolling:
		var grounded: bool = actor.on_ground and not actor.player.support_bodies().is_empty()
		var step := local_walk.tick(world,foot_position(),delta,grounded)
		if step.get("arrived",false):
			_note_patrol_stop(str(step.get("site_id","")),"本地巡防")
		move = int(step.get("direction",0))
		route_jump = step.get("jump",false) and grounded
		route_down = step.get("down",false)
	if not patrolling and move!=0 and absf(at.x-old_x)<.009:
		stopped+=delta
		if stopped>.32 and actor.on_ground:
			jump=true
			stopped=0.0
	else:stopped=0.0
	old_x=at.x
	actor.drive(delta,move,jump or route_jump,route_down)
	actor.combat.step(delta,false)
	var limits:Rect2=Autonomy.motion_bounds(world)
	if not limits.grow(.5).has_point(actor.player.position):
		local_walk.interrupt()
		actor.relocate(autonomy.respawn(world,HOME))
		if not action.is_empty():_finish(false,"失足后回到安全落脚点")
	else:autonomy.remember_ground(world,actor)
	queue_redraw()

func _can_patrol_locally(connection: Dictionary) -> bool:
	return actor != null and down_left <= 0.0 and defense_left <= 0.0 and action.is_empty() \
		and not pending and queued_chat.is_empty() and LocalWalk.can_run(connection,autonomy.paused,worker.can_request())

func _advance(delta:float) -> int:
	action.remaining-=delta
	if action.remaining<=0:
		_finish(false,"当前路线或目标超出可达范围")
		return 0
	var at:Vector2=actor.player.position
	var to:=Vector2(action.at[0],action.at[1])
	if action.tool=="intercept":
		var target:=Observer.threat(self,action.id,19.)
		if target.is_empty():
			_finish(false,"目标已离开视野或解除敌对")
			return 0
		var center:=Vector2(target.at[0],target.at[1])
		if action.id.begins_with(Observer.NATIVE_PREFIX):
			if absf(at.x-center.x)<=1.35 and absf(at.y-center.y)<=1.05:
				return _engage(action.id,center)
			native_approach_left-=delta
			if native_approach_left<=0.0:
				native_approach=Observer.native_approach(self,center)
				native_approach_left=1.1
				if not native_approach.ok:
					_finish(false,str(native_approach.reason))
					return 0
			return _follow_route(Vector2(native_approach.stand[0],native_approach.stand[1]),delta,false,.5)
		if last_swing_blocked and actor.combat.swing<=0 and not flank.is_finite() and flanked<2:
			last_swing_blocked=false
			var far_side:=signf(center.x-at.x)
			var x:=center.x+far_side*1.05
			var floor_row:=Ground.nearby(world,x,center.y-.25,1.8)
			if not floor_row.is_empty():
				var suggested:=Vector2(x,floor_row.y)
				var path:Dictionary=world.paper_nav_route(foot_position(),suggested)
				if path.get("ok",false):
					flank=suggested
					flanked+=1
					travel_plan=path
					travel_goal=suggested
					status="刀路被挡，绕到威胁的另一侧"
		if flank.is_finite():
			if foot_position().distance_to(flank)<.44:
				flank=Vector2.INF
				travel_plan={}
				status="已绕到另一侧，重新确认敌对目标"
			else:return _follow_route(flank,delta,false)
		if absf(at.x-center.x)<1.45 and absf(at.y-center.y)<1.1:return _engage(action.id,center)
		var approach:=Ground.nearby(world,center.x,center.y-.3,2.3)
		if approach.is_empty():approach=Ground.nearby(world,center.x,at.y-.29,1.1)
		if approach.is_empty():
			_finish(false,"目标所在位置没有可确认的接近路线")
			return 0
		return _follow_route(Vector2(center.x,approach.y),delta,false)
	if action.tool=="protect":
		var person=world.entity_by_id(action.id)
		if not is_instance_valid(person) or not person.alive or person.kind!="villager":
			_finish(false,"守护对象已经离开")
			return 0
		to=person.position
		if at.distance_to(to)<1.75:
			guard_time+=delta
			status="站在村民附近守望"
			if guard_time>=3.0:_finish(true,"到场守望，已重新检查附近")
			return 0
	return _follow_route(to,delta,action.tool!="protect")

func _follow_route(goal:Vector2, delta:float, finish_on_arrival:bool, retarget_distance:=1.25) -> int:
	if travel_plan.is_empty() or travel_goal.distance_to(goal)>retarget_distance:
		travel_goal=goal
		travel_plan=world.paper_nav_route(foot_position(),goal)
		if not travel_plan.get("ok",false):
			_finish(false,str(travel_plan.get("error","这里没有实际可达的路线")))
			return 0
	var result:Dictionary=world.paper_nav_steer(travel_plan,foot_position(),delta,actor.on_ground and not actor.player.support_bodies().is_empty())
	if not result.get("ok",false):
		_finish(false,str(result.get("error","现场路线走不通")))
		return 0
	if result.arrived and finish_on_arrival:
		_finish(true,"已到 "+str(action.name))
		return 0
	route_jump=result.jump and actor.on_ground
	route_down=result.get("down",false)
	return int(result.direction)

func _engage(id:String, target:Vector2) -> int:
	var from:Vector2=actor.player.position
	var delta:=target-from
	var small_creature:=id!="player" and not id.begins_with(Observer.NATIVE_PREFIX)
	if actor.combat.swing>0:
		route_down=small_creature and delta.y<.1 and actor.on_ground
		return 0
	var reach_x:=.62 if small_creature else 1.35
	if absf(delta.x)<=reach_x and absf(delta.y)<=1.05:
		route_down=small_creature and delta.y<.1 and actor.on_ground
		if actor.combat.cooldown<=0 and actor.combat.recoil<=0:
			swing_target=id
			last_swing_blocked=false
			actor.combat.melee_motion_override=2 if small_creature else -1
			actor.combat.melee_grip_lowering=clampf((.43-delta.y)*62.,0,30) if small_creature else 0.0
			actor.combat.attack(delta)
		return 0
	return int(signf(delta.x)) if absf(delta.x)>.32 else 0

func _creature_ink(id:String) -> Array:
	var priest=world.get_node_or_null("SandboxPriest")
	return priest.combat_geometry(id) if priest!=null and priest.has_method("combat_geometry") else []

func _record(row:Dictionary) -> void:
	var scope:=Autonomy.scope(game)
	var event:=row.duplicate(true)
	event.team_id=scope.get("team_id","")
	event.world_id=scope.get("world_id","")
	event.at=Senses.pair(actor.player.position)
	memory.append(event)
	if memory.size()>24:memory.pop_front()

func _note_patrol_stop(site_id:String, reason:String) -> void:
	var book = world.get("chronicle")
	if book == null: return
	var feet := foot_position()
	var place: String = world.paper_nav_label(site_id,feet).get_slice("（",0).strip_edges()
	if place.is_empty(): return
	book.record("patrol-stop:"+place, "patrol_arrived", ROLE, "战神巡到"+place.trim_suffix(" · 地表"),
		"%s，已走到此处。" % reason, feet, site_id)

func _finish(ok:bool, description:String) -> void:
	status=description
	if action.get("chat",false):
		chat_notice=description
		_line("status",description)
	if ok and action.get("tool") in ["patrol","investigate"]:
		var point:Vector2=actor.player.position
		visits.append({"id":str(action.id),"x":point.x,"y":point.y-.29})
		if visits.size()>12:visits.pop_front()
		_note_patrol_stop(str(action.id),"查看沿路动静" if action.tool=="investigate" else "依令巡防")
	if not ok and action.get("tool")=="intercept" and str(action.get("id","")).begins_with(Observer.NATIVE_PREFIX):
		intercept_hold[action.id]={"until":Time.get_ticks_msec()+INTERCEPT_HOLD_MS,
			"revision":world.paper_space.navigation_revision if world.paper_space!=null else 0}
	_record({"kind":"outcome","ok":ok,"action":action.get("tool",""),"target":action.get("id",""),"result":description,
		"call_id":action.get("call_id",""),"model":action.get("model","")})
	action={}
	travel_plan={}
	travel_goal=Vector2.INF
	flank=Vector2.INF
	last_swing_blocked=false
	guard_time=0.0
	retry_left=3.0 if ok else 8.0

func incoming_center() -> Vector2:
	return actor.player.position+Vector2(0,.13) if is_instance_valid(actor) and down_left<=0 else Vector2.INF

func receive_enemy_hit(id:String, amount:float, at:Vector2) -> Dictionary:
	if not is_instance_valid(actor) or Observer.threat(self,id,2.2).is_empty():return {"ok":false}
	return _take_hit(id,amount,at,at-actor.player.position,"bite")

# This entry is called only by the player weapon resolver after a confirmed sweep/trace.
func receive_player_hit(amount:float, at:Vector2, direction:Vector2, weapon:String) -> Dictionary:
	return _take_hit("player",amount,at,direction,weapon)

func _take_hit(id:String, amount:float, at:Vector2, direction:Vector2, weapon:String) -> Dictionary:
	if not incoming_center().is_finite() or not at.is_finite() or not direction.is_finite() or not is_finite(amount) or amount<=0 or actor.combat.invulnerable>0:return {"ok":false}
	var combat=actor.combat
	var before:float=combat.health
	combat.health=maxf(0,before-amount)
	combat.invulnerable=.7
	combat.recoil=.20
	combat.swing=0
	combat.cancel_draw()
	actor.player.linear_velocity+=direction.normalized()*1.6
	var event:={"kind":"hit","source":id,"target":ROLE,"before":before,"after":combat.health,"weapon":weapon,"impact":Senses.pair(at)}
	last_combat=event
	_record(event)
	if id=="player":
		last_player_hit=event.duplicate(true)
		defense_left=8.0
	PaperCombatAudio.impact(game.feedback,"hurt",at,weapon)
	game.combat.add_damage_text(at,before-combat.health)
	if combat.health<=0:
		PaperCombatAudio.cry(game.feedback,"player",at)
		down_left=3.0
		defense_left=0.0
		actor.set_active(false)
	return {"ok":true,"before":before,"after":combat.health,"killed":combat.health<=0}

func resolve_guard_swing(combat, wall:Dictionary) -> void:
	var id:=swing_target
	if id.is_empty() or combat.hit_ids.has(id):return
	var body = null
	var contact := {}
	var blocked:=false
	if id=="player":
		if defense_left<=0 or game.combat.invulnerable>0:return
		contact=PaperBladeSweep.circle_contact(combat.previous_player_paths,combat.player_paths,game.player.position+Vector2(0,.2),.25 if game.crouching else .33,true)
		blocked=not contact.is_empty() and wall.get("time",INF)<=contact.time
	elif id==action.get("id") and action.get("tool")=="intercept":
		var target:=Observer.threat(self,id,2.8)
		if target.is_empty():return
		body=target.get("body")
		if body!=null:
			if wall.get("entity")!=body:return
			contact=wall
		else:
			var grip:Vector2=combat._held_blade_origin()
			if not grip.is_finite():return
			contact=combat._blade_geometry_contact(combat.previous_player_paths,combat.player_paths,_creature_ink(id),grip)
			var cover:Dictionary={}
			if not contact.is_empty():
				# The swept tip touching some other object does not block a different part
				# of the blade. Test the actual grip-to-contact segment against world ink.
				cover=combat.first_structure(grip,contact.position)
				blocked=not cover.is_empty() and grip.distance_to(cover.position)+.025<grip.distance_to(contact.position)
			var key:="miss" if contact.is_empty() else "blocked" if blocked else "traced"
			sweep_evidence[key]=int(sweep_evidence.get(key,0))+1
			if key=="blocked":
				last_swing_blocked=true
				var blocker=cover.get("entity")
				sweep_evidence.last_blocker=str(blocker.entity_id) if is_instance_valid(blocker) else "terrain"
	if contact.is_empty() or blocked:return
	var speed:=PaperBladeSweep.motion_distance(combat.previous_player_paths,combat.player_paths)/maxf(.0001,combat.blade_delta)
	var amount:=PaperWeaponTypes.damage(combat.swing_weapon,speed)
	var weapon:=PaperWeaponTypes.kind(combat.swing_weapon)
	var result:={}
	if id=="player":
		var hp:float=game.combat.health
		game.combat.hurt_player(amount,combat.swing_direction,contact.position,weapon)
		result={"ok":true,"before":hp,"after":game.combat.health if game.combat.health<hp else 0.0,"killed":game.combat.health>=hp}
		if result.killed:defense_left=0.0
	elif body!=null:
		var hp:float=body.health
		world.damage_entity(body,amount,contact.position,combat.swing_direction*2.4,weapon)
		result={"ok":body.health<hp,"before":hp,"after":body.health,"killed":not body.alive}
	else:
		var priest=world.get_node_or_null("SandboxPriest")
		if priest!=null and priest.has_method("receive_combat_hit"):
			result=priest.receive_combat_hit(id,contact.position,amount,ROLE)
			if not result.get("ok",false):sweep_evidence.rejected=int(sweep_evidence.get("rejected",0))+1
	if not result.get("ok",false):return
	combat.hit_ids[id]=true
	last_combat={"kind":"hit","source":ROLE,"target":id,"before":result.before,"after":result.after,"weapon":weapon,"impact":Senses.pair(contact.position)}
	_record(last_combat)
	if id!="player" and result.get("killed",false):
		var title: String = "已击退威胁 · "+str(action.name)
		var chronicle = world.get("chronicle")
		if chronicle != null and chronicle.has_method("record"):
			chronicle.record("war-god-defeat:"+id,"threat_defeated",ROLE,title,
				"原生武器实际命中，目标生命归零。",contact.position,id)
		if body==null and world.survival!=null and world.survival.has_method("guild_guard_result"):
			world.survival.guild_guard_result(id,ROLE)
		_finish(true,title)

func snapshot() -> Dictionary:
	if not is_instance_valid(actor):return _saved.duplicate(true)
	return {"version":1,"at":[actor.player.position.x,actor.player.position.y],"health":actor.combat.health,"autonomy":autonomy.snapshot(),
		"action":action.duplicate(true),"memory":memory.duplicate(true),"visits":visits.duplicate(true),"messages":messages.duplicate(true),
		"held_chat":ChatRoles.snapshot_held_chat(held_chat,queued_chat,unsent_draft),"draft":queued_chat if unsent_draft.is_empty() else unsent_draft,"last_player_hit":last_player_hit.duplicate(true),"last_combat":last_combat.duplicate(true)}

static func valid_snapshot(value:Variant) -> bool:
	if not value is Dictionary:return false
	if value.is_empty():return true
	if value.get("version")!=1 or not Autonomy.pair(value.get("at")) or not value.get("autonomy") is Dictionary:return false
	var health=value.get("health")
	if not (health is int or health is float) or not is_finite(health) or health<0 or health>100:return false
	var draft=value.get("draft","")
	if not draft is String or draft.length()>600:return false
	for key in ["last_player_hit","last_combat"]:
		if not value.get(key,{}) is Dictionary or JSON.stringify(value.get(key,{})).length()>1500:return false
	for key in ["memory","visits","messages"]:
		var rows=value.get(key)
		if not rows is Array or rows.size()>(24 if key=="memory" else 12 if key=="visits" else 20):return false
		for row in rows:
			if not row is Dictionary or JSON.stringify(row).length()>1600:return false
			if key=="visits" and not Autonomy.pair([row.get("x"),row.get("y")]):return false
			if key=="messages" and (row.get("speaker") not in ["god","player","status"] or not row.get("text") is String or row.text.length()>600):return false
	var order=value.get("action")
	if not order is Dictionary:return false
	if not order.is_empty():
		if order.get("tool") not in ORDERS or not Autonomy.pair(order.get("at")) or not order.get("chat") is bool:return false
		for key in ["id","name","goal","reason","call_id","request_id","model"]:
			if not order.get(key) is String or order[key].length()>160:return false
		var left=order.get("remaining")
		if not (left is int or left is float) or not is_finite(left) or left<=0 or left>50:return false
	return true

func restore(value:Dictionary) -> void:
	if not valid_snapshot(value):return
	worker.cancel()
	pending=false
	queued_chat=""
	speaking=false
	if is_instance_valid(actor):_take_snapshot(value)
	else:_saved=value.duplicate(true)

func _take_snapshot(value:Dictionary) -> void:
	if value.is_empty():return
	autonomy.restore(value.autonomy)
	var point:=Vector2(value.at[0],value.at[1])
	if Autonomy.in_world(world,point):actor.relocate(point)
	actor.combat.health=float(value.health)
	if actor.combat.health<=0:
		down_left=3
		actor.set_active(false)
	defense_left=0.0
	memory=value.memory.duplicate(true)
	visits=value.visits.duplicate(true)
	messages=value.messages.duplicate(true)
	held_chat=ChatRoles.read_held_chat(value.get("held_chat",[]))
	unsent_draft=value.get("draft","")
	last_player_hit=value.get("last_player_hit",{}).duplicate(true)
	last_combat=value.get("last_combat",{}).duplicate(true)
	action=value.action.duplicate(true)
	if action.get("tool") in ["patrol","investigate"] and world.has_method("paper_nav_label"):
		action.name=world.paper_nav_label(action.id,Vector2(action.at[0],action.at[1]))
	travel_plan={}
	travel_goal=Vector2.INF
	if not action.is_empty():status="续行 · "+str(LABEL.get(action.tool,"巡护"))+" · "+str(action.name)

func _draw() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(game.toolbar):return
	var anchor:Vector2=game.world_to_screen(actor.player.position+Vector2(0,.96))
	var view:=get_viewport_rect()
	var rect:=Identity.draw(self,_font,anchor,view,"战神 · 至高神",INK,14,Identity.vitals_area(game.toolbar))
	if rect.has_area() and actor.combat.health<100:
		var bar:=Rect2(Vector2(rect.position.x,rect.end.y+2),Vector2(rect.size.x,3.0))
		draw_rect(bar,Color("ded0ba"))
		draw_rect(Rect2(bar.position,Vector2(bar.size.x*float(actor.combat.health)/100.,bar.size.y)),INK)
