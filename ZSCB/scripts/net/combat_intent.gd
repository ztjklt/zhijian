extends RefCounted
## Only the owner's bow pose is predicted. Never step combat or create a projectile here.
var remaining := 0.0
var cooldown := 0.0
var sequence := -1
var weapon: Dictionary = {}
var direction := Vector2.RIGHT
var toggle_sequence := -1
var trial_bow := false
var authority_bow := false
var bow_attack := false

func begin(game, number: int, aim: Vector2) -> void:
	if game == null or cooldown > 0 or game.combat.recoil > 0:
		return
	var ranged: bool = game.combat.is_bow() or game.combat.is_firearm()
	if ranged and not game.ink.can_spend(PaperInkReserve.ARROW_COST): return
	if not ranged and game.equipped_weapon.get("paths",[]).is_empty(): return
	sequence = number
	bow_attack = game.combat.is_bow()
	remaining = .42 if bow_attack else 0.0
	cooldown = .78 if bow_attack else .75 if game.combat.is_firearm() else PaperWeaponTypes.attack_cooldown(game.equipped_weapon)
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
	if reply.get("op","") == "attack" and number == sequence:
		if not reply.get("ok",false) or not reply.get("attack_started",true):
			cancel(game)
			cooldown = 0

func step(game, delta: float, blocked: bool) -> void:
	cooldown = maxf(0,cooldown-delta)
	if blocked or not game.combat.is_bow() or game.equipped_weapon != weapon:
		cancel(game)
	else:
		remaining = maxf(0,remaining-delta)
		_display(game)

func receive(game, state: Dictionary) -> void:
	if state.has("bow_equipped"):
		authority_bow = bool(state.bow_equipped)
		game.combat.bow_equipped = trial_bow if toggle_sequence >= 0 else authority_bow
	if float(state.get("health",game.combat.health)) < game.combat.health or float(state.get("dead",0)) > 0 or float(state.get("recoil",0)) > 0:
		cancel(game)
	# Authority frames describe an earlier moment. They must never restart or
	# rewind this local pose, including after a panel has closed again.
	_display(game)
	if remaining <= 0 and state.has("bow_direction"):
		game.combat.bow_direction = state.bow_direction

func cancel(game) -> void:
	remaining = 0
	if game != null and game.combat != null: game.combat.bow_charge = 0

func reset(game) -> void:
	cancel(game)
	cooldown = 0
	sequence = -1
	toggle_sequence = -1
	bow_attack = false
	weapon.clear()

func _display(game) -> void:
	game.combat.bow_charge = remaining
	if remaining > 0: game.combat.bow_direction = direction
