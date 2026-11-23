extends Node2D

const Actor := preload("res://scripts/adventurer_actor.gd")
const Senses := preload("res://scripts/companion_senses.gd")
const Witness := preload("res://scripts/village_witness.gd")
const Transport := preload("res://scripts/east_painter.gd")
const Goods := preload("res://scripts/adventurer_goods.gd")
const Identity := preload("res://scripts/sandbox_identity.gd")
const Autonomy := preload("res://scripts/sandbox_autonomy.gd")
const ACTOR_ID := "adventurer-lizhou"
const DISPLAY_NAME := "砾舟"
const IDENTITY_LABEL := "砾舟 · 冒险者"
const INK := Color("465844")
const INVITATIONS := ["chat", "npc", "explore", "goods"]
const TOOLS := ["look", "walk", "talk_player", "talk_npc", "goods_action", "guild_contract"]
const MEMORY := 8
const GOALS := ["","fruit","trade","pattern","contract"]
const MAX_COMMISSION_STEPS := 12
const HOME_X := 5.4

var world
var game
var actor
var worker
var phase := "arrival"
var caption := ""
var destination := ""
var target := Vector2.ZERO
var target_npc := ""
var dialogue: Array = []
var unsent_draft := ""
var recent_results: Array = []
var last_result := {}
var last_observation := {}
var last_command := {}
var invitation := {}
var ticket := ""
var start_at := Vector2.ZERO

var _restore_data := {}
var _cooldown := 0.0
var _walk_left := 0.0
var _best_distance := INF
var _still_for := 0.0
var _previous_x := INF
var autonomy := Autonomy.new()
var autonomous_execution := false
var _company_left := 0.0
var _waiting := false
var _invited_steps := 0
var _words := ""
var _speech := {}
var _speech_left := 0.0
var _receipts: Array = []
var _font: Font

func _ready() -> void:
	name = "SandboxAdventurer"
	world = get_parent()
	game = world.game
	z_index = 3
	_font = PaperTheme.create().default_font
	worker = Transport.new()
	worker.worker_resource = "res://tools/adventurer_turn.mjs"
	worker.request_directory = "user://adventurer_turns"
	worker.use_painter_mailbox = false
	worker.actor_role = ACTOR_ID
	add_child(worker)
	worker.finished.connect(_decision)
	worker.binding_changed.connect(_model_binding_changed)

func _exit_tree() -> void:
	if is_instance_valid(worker): worker.cancel()

func _arrive() -> void:
	actor = Actor.new()
	actor.sandbox = game
	actor.player_id = ACTOR_ID
	actor.display_name = DISPLAY_NAME
	add_child(actor)
	actor.relocate(world.safe_spawn_position(HOME_X))
	phase = "rest"
	_cooldown = 3.0
	if not _restore_data.is_empty():
		_apply_restore(_restore_data)
		_restore_data = {}

func snapshot() -> Dictionary:
	if actor == null: return _restore_data.duplicate(true)
	var saved := {"id":ACTOR_ID, "draft":unsent_draft, "at":[actor.player.position.x,actor.player.position.y],
		"dialogue":dialogue.duplicate(true), "recent_results":recent_results.duplicate(true),
		"receipts":_receipts.duplicate(true),"autonomy":autonomy.snapshot(),"autonomous_execution":autonomous_execution}
	if phase=="walk" and destination in ["site","npc"]:
		saved.local_action={"destination":destination,"at":Senses.pair(target),"left":_walk_left,"command":last_command.duplicate(true),
			"npc":target_npc,"words":_words,"caption":caption,"label":str(_find(last_observation.get("sites",[]),last_command.get("args",{}).get("site")).get("label","落脚处")),"ticket":ticket}
	if invitation.get("kind") == "goods":
		saved.commission = invitation.duplicate()
		saved.commission_steps = _invited_steps
	return saved

static func valid_snapshot(state: Variant) -> bool:
	if not state is Dictionary: return false
	if state.is_empty(): return true
	if not state.get("draft","") is String or str(state.get("draft","")).length()>120:return false
	if state.get("id") != ACTOR_ID or not _pair(state.get("at")): return false
	for key in ["dialogue","recent_results","receipts"]:
		if not state.get(key) is Array or state[key].size() > MEMORY: return false
	for entry in state.dialogue:
		if not entry is Dictionary or not _short_text(entry.get("speaker"),16) or not _short_text(entry.get("text"),160): return false
	for entry in state.recent_results:
		if not entry is Dictionary or not entry.get("ok") is bool or not _short_text(entry.get("tool"),32) or not _short_text(entry.get("detail"),160): return false
		if JSON.stringify(entry).length() > 2048: return false
	if state.has("commission"):
		var job = state.commission
		if not job is Dictionary or job.get("kind") != "goods" or job.get("goal","") not in GOALS or not _short_text(job.get("text"),120): return false
		var steps = state.get("commission_steps",0)
		if typeof(steps) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(steps)) or steps != floorf(steps) or steps < 0 or steps > MAX_COMMISSION_STEPS: return false
	for receipt in state.receipts:
		if not _short_text(receipt,256): return false
	return true

static func _pair(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for n in value:
		if not (n is float or n is int) or not is_finite(float(n)): return false
	return true

static func _short_text(value: Variant, limit: int) -> bool:
	return value is String and value.length() <= limit

func restore(state: Dictionary) -> void:
	if not valid_snapshot(state): return
	if actor == null: _restore_data = state.duplicate(true)
	else: _apply_restore(state)

func _apply_restore(state: Dictionary) -> void:
	_reset_turn()
	unsent_draft=state.get("draft","")
	dialogue = state.get("dialogue",[]).duplicate(true)
	recent_results = state.get("recent_results",[]).duplicate(true)
	_receipts = state.get("receipts",[]).duplicate()
	last_result = {} if recent_results.is_empty() else recent_results.back().duplicate(true)
	autonomy.restore(state.get("autonomy",{}))
	autonomous_execution=state.get("autonomous_execution",false)==true
	var at: Vector2 = world.safe_spawn_position(HOME_X)
	if state.has("at"):
		var saved := Vector2(state.at[0],state.at[1])
		if Autonomy.in_world(world,saved):
			at = saved
	actor.relocate(at)
	if state.has("commission"):
		invitation = state.commission.duplicate()
		_invited_steps = int(state.get("commission_steps",0))
	var local = state.get("local_action")
	if local is Dictionary and local.get("destination") in ["site","npc"] and _pair(local.get("at")) and local.get("command") is Dictionary:
		var point := Vector2(local.at[0],local.at[1])
		if Autonomy.in_world(world,point):
			target=point
			last_command=local.command.duplicate(true)
			if last_command.get("args") is Dictionary:
				target_npc=str(local.get("npc","")).left(128)
				_words=_clean(str(local.get("words","")),120)
				ticket=str(local.get("ticket","")).left(24)
				start_at=at
				last_observation.sites=[{"id":last_command.args.get("site",""),"label":str(local.get("label","落脚处")).left(64)}]
				_go(local.destination,str(local.get("caption","继续行路")).left(78))
				_walk_left=clampf(float(local.get("left",8.0)),.1,150.0)
	# Reattach the traveler's actual purchased gear to the fresh visual rig.
	if world.survival != null and world.survival.inventory(ACTOR_ID).economy.sword_equipped:
		world.survival.Guild.equip(world.survival,ACTOR_ID)
	elif actor.equipped_weapon.get("source","") == "guild":
		actor.equipped_weapon = {}
		actor.combat.cancel_draw()
	_cooldown = 1.0

func _reset_turn() -> void:
	worker.cancel()
	phase = "rest"
	ticket = ""
	target_npc = ""
	destination = ""
	invitation = {}
	last_observation = {}
	last_command = {}
	_speech = {}
	_speech_left = 0.0
	_invited_steps = 0
	_company_left = 0.0
	autonomous_execution = false
	_waiting = false
	caption = ""

func recall() -> void:
	if actor == null or phase not in ["rest","walk","offline"] or not invitation.is_empty():
		game.message("砾舟正手上有事，稍后再邀同行")
		return
	_company_left=15.0
	game.message("砾舟应邀同行片刻，之后回自己的路线")

func autonomy_status() -> Dictionary:
	var status := autonomy.status(ModelConnections.role_status(ACTOR_ID))
	status.summary="暂时与你同行" if _company_left>0 else caption if not caption.is_empty() else "在自己的路线候行"
	status.phase="company" if _company_left>0 else phase
	if phase in ["walk","speak"]: status.progress=status.summary
	return status

func set_autonomy_paused(value: bool) -> void:
	autonomy.set_paused(value)
	if value and phase=="thinking" and autonomous_execution:
		worker.cancel()
		phase="rest"
	elif not value: _cooldown=minf(_cooldown,.5)

func set_action_budget(value: int) -> void:
	autonomy.set_budget(value)

func invite(kind: String, text: String, goal := "") -> bool:
	if actor == null or kind not in INVITATIONS or goal not in GOALS or kind != "goods" and goal != "": return false
	if not worker.can_request():
		game.message(ModelConnections.role_status(ACTOR_ID).message)
		return false
	if actor.player.position.distance_to(game.player.position) > 11.0:
		game.message("砾舟离得有些远，可以先叫他回来")
		return false
	_reset_turn()
	var message := _clean(text,120)
	if message.is_empty(): return false
	invitation = {"kind":kind,"text":message}
	if goal != "": invitation.goal = goal
	_remember("你",message)
	_say("你",message,1.3)
	_cooldown = 0.0
	return true

func _physics_process(delta: float) -> void:
	if get_tree().current_scene != game or world!=game.medieval_world or is_queued_for_deletion() or not is_visible_in_tree(): return
	if actor == null: _arrive()
	var direction := 0
	var at: Vector2 = actor.player.position
	_speech_left = maxf(0.0,_speech_left-delta)
	if _company_left>0:
		_company_left=maxf(0,_company_left-delta)
		var gap: float=game.player.position.x-at.x
		direction=int(signf(gap)) if absf(gap)>2.1 else 0
	elif not (autonomy.paused and autonomous_execution and phase in ["walk","speak"]):
		direction=_step_action(delta)
	var survey_step := _walking_survey_seam(at)
	var jump := false
	if not survey_step and direction != 0 and absf(at.x-_previous_x) < 0.009:
		_still_for += delta
		if _still_for > 0.4 and actor.on_ground:
			jump = true
			_still_for = 0.0
	else: _still_for = 0.0
	_previous_x = at.x
	# Surveying uses the ordinary crouched walking input. Each leg is a slow step,
	# not a pair of deliberate down taps to drop through a one-way platform.
	if survey_step:actor.down_tap_timer=0.0
	actor.drive(delta,direction,jump,survey_step)
	var limits: Rect2=Autonomy.motion_bounds(world)
	if at.x < limits.position.x or at.x > limits.end.x:
		actor.relocate(Vector2(clampf(at.x,limits.position.x,limits.end.x),at.y))
	if at.y<limits.position.y:
		actor.relocate(autonomy.respawn(world,HOME_X))
		_finish(false,"失足后回到自己最近的安全落脚点")
	else: autonomy.remember_ground(world,actor)
	queue_redraw()

func _step_action(delta: float) -> int:
	match phase:
		"rest":
			_cooldown -= delta
			if worker.can_request() and _cooldown<=0 and (not invitation.is_empty() or autonomy.available() and
				(not _waiting or autonomy.revision!=Autonomy.change_key(game) or _cooldown< -18)):
				_request()
		"walk":
			return _walk(delta)
		"speak":
			var at: Vector2 = actor.player.position
			var person = _person()
			if person == null or at.distance_to(person.position) > 4.5:
				_finish(false,"居民已经走远了")
			else:
				var distance: float = at.distance_to(person.position)
				if _speech_left <= 0.0:
					_walk_left -= delta
					if distance <= 2.6 or _walk_left <= 0.0: _reply()
				return int(signf(person.position.x-at.x)) if distance>1.35 else 0
		"offline":
			_cooldown-=delta
			if autonomous_execution and worker.can_request() and _cooldown<=0: phase="rest"
	return 0

func observe() -> Dictionary:
	var sensed := Senses.observe(game,actor,last_result,autonomous_execution)
	var sites := []
	for site in sensed.sites:
		sites.append({"id":site.id,"label":"附近的落脚处","stand":site.stand,"slope":site.slope})
	var goods: Dictionary = Goods.observe(game,actor)
	for site in goods.get("destinations",[]):
		if not site is Dictionary or not _pair(site.get("stand")) or not _find(sites,site.id).is_empty(): continue
		var at := Vector2(site.stand[0],site.stand[1])
		if autonomous_execution or invitation.get("kind") == "goods" or game.get_viewport_rect().has_point(game.world_to_screen(at)):
			sites.append({"id":site.id,"label":str(site.get("label",site.id)),"stand":site.stand})
	var context := autonomy.sense(game,actor.player.position,ACTOR_ID) if autonomous_execution else {}
	for route in context.get("routes",[]):
		if route.id!="east-frontier": sites.append(route)
	return {"identity":"砾舟","role":"adventurer","actor_id":ACTOR_ID,"autonomy":context,
		"self":sensed.self,"human":sensed.human,"sites":sites,"nearby_npcs":Senses.people(world,actor.player.position),
		"goods":goods,"invitation":invitation.duplicate(),"recent_dialogue":dialogue.duplicate(true),
		"last_result":last_result.duplicate(true)}

func _request() -> void:
	autonomous_execution=invitation.is_empty()
	last_observation = observe()
	if autonomous_execution: autonomy.revision=Autonomy.change_key(game)
	if worker.request_segment(last_observation):
		if autonomous_execution: autonomy.used+=1
		ticket = worker.last_request_path.get_file().get_slice(".",0)
		phase = "thinking"
		caption = "打量四周"
	else:
		phase = "offline"
		_cooldown=20.0
		caption = "暂时没接通"

func _decision(observation: Dictionary, command: Dictionary, error: String) -> void:
	if phase != "thinking" or get_tree().current_scene != game or world!=game.medieval_world or is_queued_for_deletion() or ticket != worker.last_request_path.get_file().get_slice(".",0): return
	start_at = actor.player.position
	last_command = command.duplicate(true)
	if not error.is_empty():
		_finish(false,error)
		phase = "offline"
		_cooldown=20.0
		return
	var tool: String = str(command.get("tool",""))
	var args = command.get("args")
	if tool not in TOOLS or not args is Dictionary or not worker.accepts_command(command) or not _short_text(command.get("call_id"),128) or command.call_id.is_empty():
		_finish(false,"这不是旅行者会做的动作")
		return
	if not invitation.is_empty(): _invited_steps = mini(MAX_COMMISSION_STEPS,_invited_steps+1)
	if autonomous_execution: autonomy.accept(command,{"walk":"探查实际路线","talk_npc":"询问当地居民","goods_action":"照料行囊或交易","guild_contract":"办理公会合同"}.get(tool,"查看现场变化"))
	match tool:
		"look":
			_finish(true,"看过了附近的路和行人")
		"walk":
			var site := _find(observation.sites,args.get("site"))
			if site.is_empty():
				_finish(false,"这处落脚点不在刚才看到的路上")
				return
			target = Vector2(site.stand[0],site.stand[1])
			_go("site","走向"+str(site.label))
		"talk_player":
			_words = _clean(args.get("text"),120)
			if _words.is_empty():
				_finish(false,"没有收到要说的话")
				return
			target = game.player.position
			_go("player","走近你")
		"talk_npc":
			var person := _find(observation.nearby_npcs,args.get("id"))
			_words = _clean(args.get("text"),120)
			if person.is_empty() or _words.is_empty():
				_finish(false,"身边没有这位可以问路的居民")
				return
			target_npc = person.id
			target = Vector2(person.at[0],person.at[1])
			_go("npc","走向"+str(person.name))
		"goods_action","guild_contract":
			if (tool=="guild_contract")!=str(args.get("id","")).begins_with("contract."):
				_finish(false,"请使用相应的公会或货物操作")
				return
			_goods(observation,args)

static func _find(entries: Array, id: Variant) -> Dictionary:
	for entry in entries:
		if entry is Dictionary and entry.get("id") == id: return entry
	return {}

func _goods(observation: Dictionary, args: Dictionary) -> void:
	var offered := _find(observation.goods.get("actions",[]),args.get("id"))
	if args.size() != 1 or offered.is_empty():
		_finish(false,"眼前没有这项货物操作")
		return
	var current := _find(Goods.observe(game,actor).get("actions",[]),offered.id)
	if current != offered:
		_finish(false,"眼前的货物、数量或报价有了变化")
		return
	var call_id := str(last_command.call_id)
	if call_id in _receipts or ticket in _receipts:
		_finish(false,"这笔操作已经结过")
		return
	# Reserve before applying the synchronous shared-world mutation. Cold loads
	# restore the ledger and receipts together and never resume a pending call.
	_remember_receipt(call_id)
	_remember_receipt(ticket)
	var result: Dictionary = Goods.execute(game,actor,offered.id,{})
	var detail := _clean(result.get("detail",result.get("message",result.get("error",""))),140)
	if detail.is_empty(): detail = str(offered.get("label",offered.id))
	var extra := {"action_id":offered.id}
	for key in ["item","price","quantity","target"]:
		if offered.has(key): extra[key] = offered[key]
	var inventory: Dictionary = result.get("inventory",{})
	for key in ["gold","ore","hide","bounty","cup_pattern","shortsword","sword_equipped","fruit"]:
		if inventory.has(key): extra[key] = inventory[key]
	_finish(result.get("ok",false),detail,extra)

func _remember_receipt(key: String) -> void:
	if key.is_empty(): return
	_receipts.append(key)
	if _receipts.size() > MEMORY: _receipts.pop_front()

func _go(reason: String, label: String) -> void:
	phase = "walk"
	_best_distance = absf(target.x-actor.player.position.x)
	destination = reason
	caption = label
	_walk_left = clampf(absf(target.x-actor.player.position.x)*1.5+7.0,8.0,150.0)

func _walk(delta: float) -> int:
	_walk_left -= delta
	var at: Vector2 = actor.player.position
	var distance:=absf(target.x-at.x)
	if destination=="site" and distance+.25<_best_distance:
		_best_distance=distance
		_walk_left=maxf(_walk_left,8.0)
	if destination == "npc":
		var person = _person()
		if person == null:
			_finish(false,"居民走远了")
			return 0
		target = person.position
		if at.distance_to(target) <= (1.2 if Witness.asks_news(_words) else 1.85):
			_remember("砾舟",_words)
			_say("砾舟",_words,2.1)
			_walk_left = 2.0
			phase = "speak"
			return 0
	elif destination == "player":
		target = game.player.position
		if at.distance_to(target) <= 3.0:
			_remember("砾舟",_words)
			_finish(true,"同你说了话",{"reply":_words})
			_say("砾舟",_words,3.5)
			return 0
	elif _wait_for_escort(at):
		return 0
	elif absf(target.x-at.x) <= 0.24 and absf(target.y-at.y) < 2.25 and actor.on_ground:
		_finish(true,"到了"+str(_find(last_observation.sites,last_command.args.site).get("label","落脚处")),{"site":last_command.args.site})
		return 0
	if _walk_left <= 0.0:
		_finish(false,"这条路暂时走不过去")
		return 0
	return int(signf(target.x-at.x)) if absf(target.x-at.x)>0.08 else 0

func _walking_survey_seam(at:Vector2) -> bool:
	if phase!="walk" or destination!="site" or world.survival==null:return false
	var site:=str(last_command.get("args",{}).get("site",""))
	if not site.begins_with("contract-site."):return false
	var order:Dictionary=world.survival.contracts.card(site.trim_prefix("contract-site."))
	return order.get("owner")==ACTOR_ID and order.get("stage")=="crossing" and absf(at.x-float(order.at[0]))<=2.3

func _wait_for_escort(at:Vector2) -> bool:
	var site:=str(last_command.get("args",{}).get("site",""))
	if not site.begins_with("contract-site.") or world.survival==null:return false
	var c:Dictionary=world.survival.contracts.card(site.trim_prefix("contract-site."))
	if c.get("status")!="active" or c.get("stage")!="escort" or c.get("owner")!="adventurer-lizhou":return false
	var resident=world.entity_by_id(c.target)
	return resident!=null and resident.alive and (at.x-resident.position.x)*signf(target.x-resident.position.x)>1.45 and _walk_left>0.0

func _person():
	var who = world.entity_by_id(target_npc)
	return who if who != null and who.alive and who.is_person() else null

func _reply() -> void:
	var who = _person()
	if who == null or actor.player.position.distance_to(who.position)>2.6:
		_finish(false,"对方已经走出了说话的距离")
		return
	var label: String = Senses.ROLE_NAMES.get(who.kind,"居民")
	var id := target_npc
	if Witness.asks_news(_words):
		var answer:=Witness.ask(world,actor.player.position,id,_words)
		if not answer.ok:
			_finish(false,answer.message)
			return
		_remember(answer.label,answer.message)
		_finish(true,"听到"+answer.label+"的近况",Witness.receipt(answer))
		_say(answer.label,answer.message,4.5,id)
		_cooldown=4.0
		return
	var reply := _directions(who)
	_remember(label,reply)
	_finish(true,"听到"+label+"指的路",{"npc_id":id,"reply":reply})
	_say(label,reply,3.8,id)
	_cooldown = 4.0

func _directions(person) -> String:
	var x: float = person.position.x
	var closest: Dictionary = world.SECTIONS[0]
	for place in world.SECTIONS:
		if absf(x-place.x) < absf(x-closest.x): closest = place
	var offset: float = closest.x-x
	var route := "这儿就是%s。" % closest.name if absf(offset)<2.2 else "往%s约%d米就是%s。" % ["东" if offset>0 else "西",roundi(absf(offset)),closest.name]
	var rise: float = world.travel_height(x+2.0)-world.travel_height(x)
	return route+("朝东是上坡，走慢些。" if rise>0.35 else ("东边往低处走，留神脚下。" if rise < -0.35 else "往东这一小段路还算平。"))

func _finish(ok: bool, detail: String, extra := {}) -> void:
	last_result = {"ok":ok,"tool":str(last_command.get("tool","")).left(32),
		"call_id":str(last_command.get("call_id","")).left(128),"request_id":ticket,
		"start":Senses.pair(start_at),"end":Senses.pair(actor.player.position),"detail":detail.left(160)}
	last_result.merge(extra)
	var pending := false
	if invitation.get("kind") == "goods":
		var fulfilled: bool = ok and last_result.tool in ["goods_action","guild_contract"] and _completes_commission(str(extra.get("action_id","")))
		pending = not fulfilled and last_result.tool in ["look","walk","goods_action","guild_contract"]
		last_result.commission = "active" if pending else "fulfilled" if fulfilled else "unfulfilled"
	var holding_contract:bool=invitation.get("goal")=="contract" and world.survival!=null and world.survival.contracts.state.cards.any(func(c):return c.owner=="adventurer-lizhou" and c.status in ["active","ready"])
	if pending and not holding_contract and _invited_steps >= MAX_COMMISSION_STEPS:
		last_result.ok = false
		last_result.detail = "走过几处，还是没找到能办这笔货物的地方"
		last_result.commission = "unfulfilled"
		pending = false
	recent_results.append(last_result.duplicate(true))
	if recent_results.size() > MEMORY: recent_results.pop_front()
	if not pending: invitation = {}
	if autonomous_execution: autonomy.record(str(last_result.tool),detail,ok,actor.player.position)
	_waiting=autonomous_execution and (not ok or last_result.tool=="look")
	_cooldown = 4.0 if holding_contract and last_result.tool=="look" else 1.0 if pending else 6.0
	destination = ""
	target_npc = ""
	phase = "rest"
	caption = last_result.detail

func _completes_commission(action: String) -> bool:
	match invitation.get("goal",""):
		"fruit": return action == "fruit.pick"
		"trade": return action.begins_with("guild.sell.") or action.begins_with("market.counter.") or action in ["market.sell_fruit","guild.buy_pattern","guild.buy_sword"]
		"pattern": return action == "guild.buy_pattern"
		"contract": return action.begins_with("contract.settle.")
		_: return true

static func _clean(value: Variant, limit: int) -> String:
	return value.strip_edges().replace("\r"," ").replace("\n"," ").left(limit) if value is String else ""

func _remember(speaker: String, words: String) -> void:
	dialogue.append({"speaker":speaker.left(16),"text":words.left(160)})
	if dialogue.size()>MEMORY: dialogue.pop_front()

func _say(who: String, words: String, duration: float, npc_id := "") -> void:
	_speech = {"speaker":who,"text":words,"id":npc_id}
	_speech_left = duration

func _draw() -> void:
	if not is_instance_valid(actor): return
	var at: Vector2 = actor.player.position
	var view: Rect2 = game.get_viewport_rect()
	var tag := Rect2()
	if at.distance_to(game.player.position)<=10.0 or _company_left>0:
		tag = Identity.draw(self,_font,game.world_to_screen(at+Vector2(0,0.88)),view,IDENTITY_LABEL,INK,
			clampi(roundi(game.PIXELS_PER_UNIT*.22),14,19),Identity.vitals_area(game.toolbar))
	var speaker := DISPLAY_NAME
	var text := ""
	if _speech_left > 0.0:
		speaker = _speech.speaker
		text = _speech.text
		if speaker == "你": at = game.player.position
		elif not _speech.id.is_empty():
			var who = world.entity_by_id(_speech.id)
			if who != null: at = who.position+Vector2(0,0.5)
	elif phase != "rest" or _cooldown > 3.5:
		text = caption
	if text.is_empty(): return
	var anchor: Vector2 = game.world_to_screen(at+Vector2(0,0.87))
	if not view.grow(20).has_point(anchor): return
	if speaker == DISPLAY_NAME and tag.has_area(): anchor.y = tag.position.y+6
	var words := text if speaker == DISPLAY_NAME and tag.has_area() else speaker+" · "+text
	var size_px := clampi(roundi(game.PIXELS_PER_UNIT*0.225),14,20)
	var width := minf(295.0,view.size.x-32.0)
	var extent := _font.get_multiline_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,width,size_px)
	var box := Rect2(anchor-Vector2(extent.x*0.5+7,extent.y+14),extent+Vector2(14,7))
	box.position.x = clampf(box.position.x,6.0,view.size.x-box.size.x-6.0)
	draw_rect(box,Color("f6f4e5"))
	draw_line(box.position,Vector2(box.position.x,box.end.y),INK,2.5,true)
	draw_multiline_string(_font,box.position+Vector2(7,3+_font.get_ascent(size_px)),words,HORIZONTAL_ALIGNMENT_LEFT,width,size_px,-1,INK)

func _model_binding_changed() -> void:
	if actor == null or phase not in ["rest","offline"]: return
	if worker.last_error_code=="reconfigured": invitation.clear()
	phase = "rest"
	_cooldown = 2.0
	if not worker.can_request(): caption = ModelConnections.role_status(ACTOR_ID).message
	else: caption = ""
