extends RefCounted
## The owner's attack pose can start before the server reply. Combat stays on the server.
var remaining := 0.0
var cooldown := 0.0
var sequence := -1
var weapon: Dictionary = {}
var direction := Vector2.RIGHT
var toggle_sequence := -1
var trial_bow := false
var authority_bow := false
var attack_kind := ""
var motion := 0
var combo_time := 0.0
var instant_feedback := bool(ProjectSettings.get_setting("paper/network/instant_attack_feedback", false))
var displayed_attacks: Dictionary = {}
var confirmed_start := false
var next_echo := ""
var hide_swing := false
var hide_shot := false
var last_swing := 0.0
var last_shot := 0.0

func begin(game, number: int, aim: Vector2) -> void:
	if game == null or cooldown > 0 or game.combat.recoil > 0:
		return
	var ranged: bool = game.combat.is_bow() or game.combat.is_firearm()
	if ranged and not game.ink.can_spend(PaperInkReserve.ARROW_COST): return
	if not ranged and game.equipped_weapon.get("paths",[]).is_empty(): return
	sequence = number
	attack_kind = "bow" if game.combat.is_bow() else "firearm" if game.combat.is_firearm() else "melee"
	remaining = .42 if attack_kind == "bow" else 0.0
	cooldown = .78 if attack_kind == "bow" else .75 if attack_kind == "firearm" else PaperWeaponTypes.attack_cooldown(game.equipped_weapon)
	if instant_feedback and attack_kind != "bow":
		if attack_kind == "melee":
			var kind := PaperWeaponTypes.kind(game.equipped_weapon)
			motion = PaperCombat.melee_motion(kind, motion, combo_time > 0 and game.equipped_weapon == weapon)
			remaining = PaperWeaponTypes.duration(game.equipped_weapon)
			combo_time = remaining + PaperCombat.MELEE_CHAIN_WINDOW
		else:
			remaining = PaperCombat.SHOT_RECOIL_DURATION
		displayed_attacks[number] = attack_kind
		if displayed_attacks.size() > 8:
			displayed_attacks.erase(displayed_attacks.keys().front())
	weapon = game.equipped_weapon.duplicate(true)
	direction = aim.normalized() if aim.length_squared() >= .01 else Vector2(game.facing,0)
	_display(game)

func toggle(game, number: int) -> void:
	cancel(game)
	toggle_sequence = number
	trial_bow = not game.combat.bow_equipped
	game.combat.bow_equipped = trial_bow

func result(game, reply: Dictionary) -> void:
	var number := int(reply.get("seq",-1))
	if reply.get("op","") == "bow" and number == toggle_sequence:
		toggle_sequence = -1
		if not reply.get("ok",false):
			game.combat.bow_equipped = authority_bow
			cancel(game)
	if reply.get("op","") == "attack":
		var started: bool = reply.get("ok", false) and reply.get("attack_started", true)
		# The reliable result comes before the state frames for this attack.
		if instant_feedback and started:
			confirmed_start = true
			next_echo = displayed_attacks.get(number, "")
		displayed_attacks.erase(number)
		if number == sequence and not started:
			cancel(game)
			cooldown = 0

func step(game, delta: float, blocked: bool) -> void:
	cooldown = maxf(0,cooldown-delta)
	combo_time = maxf(0, combo_time - delta)
	if blocked or game.equipped_weapon != weapon or (attack_kind == "bow" and not game.combat.is_bow()):
		cancel(game)
	elif remaining > 0:
		remaining = maxf(0,remaining-delta)
		_display(game)

func receive(game, state: Dictionary) -> void:
	if state.has("bow_equipped"):
		authority_bow = bool(state.bow_equipped)
		game.combat.bow_equipped = trial_bow if toggle_sequence >= 0 else authority_bow
	if float(state.get("health",game.combat.health)) < game.combat.health or float(state.get("dead",0)) > 0 or float(state.get("recoil",0)) > 0:
		cancel(game)
	if instant_feedback:
		_receive_attack_pose(state)
	# Authority frames describe an earlier moment. They must never restart or
	# rewind this local pose, including after a panel has closed again.
	_display(game)
	if game.combat.bow_charge <= 0 and state.has("bow_direction"):
		game.combat.bow_direction = state.bow_direction

func _receive_attack_pose(state: Dictionary) -> void:
	var swing := float(state.get("swing", last_swing))
	var shot := float(state.get("shot_recoil", last_shot))
	if confirmed_start:
		hide_swing = next_echo == "melee" and swing > 0
		hide_shot = next_echo == "firearm" and shot > 0
		confirmed_start = false
		next_echo = ""
	else:
		# A new authority animation can start without a second receipt, for example a buffered combo.
		if swing <= 0 or swing > last_swing + .04: hide_swing = false
		if shot <= 0 or shot > last_shot + .04: hide_shot = false
	last_swing = swing
	last_shot = shot

func showing(kind: String) -> bool:
	return instant_feedback and attack_kind == kind and remaining > 0

func cancel(game) -> void:
	remaining = 0
	attack_kind = ""
	combo_time = 0
	if game != null and game.combat != null: game.combat.bow_charge = 0

func reset(game) -> void:
	cancel(game)
	cooldown = 0
	sequence = -1
	toggle_sequence = -1
	motion = 0
	displayed_attacks.clear()
	confirmed_start = false
	next_echo = ""
	hide_swing = false
	hide_shot = false
	last_swing = 0
	last_shot = 0
	weapon.clear()

func _display(game) -> void:
	game.combat.bow_charge = remaining if attack_kind == "bow" else 0.0
	if game.combat.bow_charge > 0: game.combat.bow_direction = direction
