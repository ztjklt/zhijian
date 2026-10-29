extends SceneTree

var count := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("NATIVE COMBAT: " + label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	var battle = game.combat
	check(battle.has_method("shoot_arrow"), "sandbox supports actual arrows outside the training range")
	if not battle.has_method("shoot_arrow"):
		game.queue_free()
		await process_frame
		quit(1)
		return
	battle.set_natives(false)
	game.player.position = Vector2(0, game.GROUND_Y + 0.54)
	var y: float = game.player.position.y
	battle.shoot_arrow(Vector2(-2, y + 2), Vector2.RIGHT, "player")
	battle.shoot_arrow(Vector2(2, y + 2), Vector2.LEFT, "native")
	battle.step(0.2)
	check(battle.projectiles.is_empty(), "opposing fast arrows collide between frames instead of tunneling")
	check(game.feedback.events.any(func(e: Dictionary) -> bool: return e.kind == "clash"), "arrow collision produces a distinct clash cue")
	battle.projectiles.clear()
	battle.shoot_arrow(Vector2(-2, y + 2), Vector2.RIGHT, "player")
	battle.shoot_arrow(Vector2(2, y + 2), Vector2.LEFT, "player")
	battle.step(0.2)
	check(battle.projectiles.size() == 2, "same-team arrows pass rather than self-cancel")
	battle.projectiles.clear()
	var wall: Dictionary = DrawingRules.building([{"points": [Vector2(0, -1), Vector2(0, 1)]}], "wall")
	wall.x = -0.8
	wall.y = y
	game.objects.append(wall)
	game.object_nodes.append(game._build_physics_for_object(wall))
	battle.shoot_arrow(Vector2(-2, y), Vector2.RIGHT, "player")
	battle.shoot_arrow(Vector2(2, y), Vector2.LEFT, "native")
	game.feedback.events.clear()
	battle.step(0.2)
	check(not game.feedback.events.any(func(e: Dictionary) -> bool: return e.kind == "clash"), "a prior wall hit prevents a later phantom arrow clash")
	check(wall.health < 120, "arrow damages the structure it hits first")
	game.objects.clear()
	game._rebuild_objects()
	battle.projectiles.clear()
	battle.set_natives(true)
	check(battle.natives.size() >= 4 and battle.natives.size() <= 8, "bounded roaming population exists")
	var native = battle.natives[0]
	for other in battle.natives:
		other.position.x = 30 + other.get_index()
	native.position = Vector2(2, y)
	native.home_x = 2
	native.weapon_kind = "blade"
	native.state = "wander"
	native.cooldown = 10
	var hp: float = native.health
	battle.shoot_arrow(Vector2(0.6, y), Vector2.RIGHT, "player")
	battle.step(0.1)
	check(native.health < hp and native.stagger > 0, "player arrow wounds and staggers a roaming native")
	check(native.knockback.x > 0, "hit knocks the native away from impact")
	battle.set_natives(false)
	battle.set_natives(true)
	native = battle.natives[0]
	for other in battle.natives: other.position.x = 30 + other.get_index()
	native.position = Vector2(0.95, y)
	native.home_x = 0.95
	native.weapon_kind = "blade"
	native.state = "windup"
	native.action_time = 0.13
	native.cooldown = 10
	native.facing = -1
	game.equipped_weapon = {"paths": [{"points": [Vector2.ZERO, Vector2(1.2, 0)]}], "grip": Vector2.ZERO, "damage": 24.0, "reach": 1.3, "cooldown": 0.38}
	battle.cooldown = 0
	battle.recoil = 0 # This duel is independent of the earlier hostile arrow fixture.
	battle.attack(Vector2.RIGHT)
	var before_hp: float = battle.health
	hp = native.health
	battle.swing = 0.25
	native.action_time = 0.03
	battle.player_paths = [PackedVector2Array([Vector2(0.3, y + 0.2), Vector2(1.2, y + 0.2)])]
	battle.previous_player_paths = battle.player_paths
	native.blade_paths = [PackedVector2Array([Vector2(0.8, y - 0.2), Vector2(0.8, y + 0.6)])]
	native.previous_blade_paths = native.blade_paths
	battle._resolve_blades()
	check(native.health == hp and battle.health == before_hp, "overlapping active blades clash without simultaneous body damage")
	check(native.stagger > 0 and battle.recoil > 0, "clash recoils both combatants")
	var cue_count: int = game.feedback.events.filter(func(e: Dictionary) -> bool: return e.kind == "clash").size()
	battle._resolve_blades()
	check(game.feedback.events.filter(func(e: Dictionary) -> bool: return e.kind == "clash").size() == cue_count, "one blade contact does not spam clash cues")
	# A non-attacking opponent takes only one hit through the entire active window.
	native.state = "wander"
	native.cooldown = 10
	native.stagger = 0
	native.knockback = Vector2.ZERO
	native.position = Vector2(1.0, y)
	battle.recoil = 0
	battle.cooldown = 0
	battle.attack(Vector2.RIGHT)
	hp = native.health
	battle.swing = 0.25
	battle.player_paths = [PackedVector2Array([Vector2(0.3, y + 0.2), Vector2(1.3, y + 0.2)])]
	battle.previous_player_paths = battle.player_paths
	battle._resolve_blades()
	var after_hit: float = native.health
	battle._resolve_blades()
	check(after_hit < hp and native.health == after_hit, "one actual sword contact damages a native exactly once")
	# Native blades can also meet a player's arrow, with no body damage.
	native.position = Vector2(2.0, y)
	native.knockback = Vector2.ZERO
	native.stagger = 0
	native.state = "windup"
	native.action_time = 0.05
	native.facing = -1
	hp = native.health
	battle.swing = 0
	native.blade_paths = [PackedVector2Array([Vector2(1.6, y - 0.3), Vector2(1.6, y + 0.5)])]
	native.previous_blade_paths = native.blade_paths
	battle.shoot_arrow(Vector2(1.0, y), Vector2.RIGHT, "player")
	battle._step_projectiles(0.05)
	check(native.health == hp and native.stagger > 0 and battle.projectiles.is_empty(), "a native can knock a player's arrow away with an active blade")
	native.take_hit(200, Vector2.RIGHT)
	check(native.health == 0 and native.state == "down", "a defeated native stops fighting and enters a visible down state")
	native.step(7.1)
	check(native.health == 65 and native.state == "wander", "defeated natives return after a delay for repeatable impact testing")
	native.position = Vector2(10, game.GROUND_Y + 0.6)
	native.home_x = 10
	native.cooldown = 10
	native.decision_clock = 10
	native.patrol_direction = -1
	native.knockback = Vector2.ZERO
	var start_x: float = native.position.x
	for frame in range(30):
		await physics_frame
		native.step(1.0 / 60.0)
	check(native.position.x < start_x - 0.25, "idle natives physically patrol rather than animate in place")
	check(native.position.y >= game.GROUND_Y + 0.18, "roaming natives collide with the paper ground")
	native.position = Vector2(0.9, y)
	native.state = "strike"
	native.stagger = 0
	native.action_time = 0.12
	native.hit_done = false
	native.facing = -1
	battle.swing = 0
	battle.health = 100
	battle.invulnerable = 0
	native.blade_paths = [PackedVector2Array([Vector2(0.1, y - 0.3), Vector2(0.1, y + 0.5)])]
	native.previous_blade_paths = native.blade_paths
	battle._resolve_blades()
	var wounded: float = battle.health
	battle._resolve_blades()
	check(wounded < 100 and battle.health == wounded, "native sword model damages the player once rather than every frame")
	battle.set_natives(false)
	battle.cooldown = 0
	battle.swing = 0
	battle.recoil = 0
	battle.toggle_bow()
	battle.attack(Vector2.RIGHT)
	check(battle.bow_charge > 0 and battle.projectiles.is_empty(), "bow visibly draws before releasing")
	battle.step(0.40)
	battle.step(0.03)
	check(battle.projectiles.size() == 1 and battle.shot_recoil > 0, "bow releases an arrow after drawing")
	if not battle.projectiles.is_empty(): check(battle.projectiles[0].position.y >= y + 0.35, "released arrow emerges at the drawn bow's hand height")
	battle.cooldown = 0
	battle.attack(Vector2.RIGHT)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(battle.bow_charge == 0, "losing focus cancels an unfinished bow draw")
	battle.cooldown = 0
	battle.attack(Vector2.RIGHT)
	battle.toggle_bow()
	check(battle.bow_charge == 0 and not battle.bow_equipped, "switching to melee cancels the old bow action")
	battle.projectiles.clear()
	battle.recoil = 0
	battle.cooldown = 0
	battle.invulnerable = 0
	battle.health = 100
	battle.attack(Vector2.RIGHT)
	battle.shoot_arrow(Vector2(1.6, y + 0.12), Vector2.LEFT, "native")
	battle.swing = 0.25
	battle.player_paths = [PackedVector2Array([Vector2(0.7, y - 0.3), Vector2(0.7, y + 0.6)])]
	battle.previous_player_paths = battle.player_paths
	battle._step_projectiles(0.10)
	check(battle.health == 100 and battle.projectiles.is_empty() and battle.recoil > 0, "a timed player slash knocks away an incoming arrow before body impact")
	battle.projectiles.clear()
	battle.bow_equipped = false
	battle.invulnerable = 0
	battle.health = 100
	battle.swing = 0
	game.bag_open = true
	battle.shoot_arrow(Vector2(-1.0, y), Vector2.RIGHT, "native")
	battle.step(0.1)
	check(battle.health < 100, "opening the bag does not freeze hostile arrows")
	game.bag_open = false
	check("player_push" in battle and absf(battle.get("player_push")) > 0, "incoming hit retains knockback for the movement controller")
	battle.cooldown = 0
	battle.recoil = 0
	game.backpack_panel.name_field.grab_focus()
	await process_frame
	game.attack()
	check(battle.cooldown == 0, "typing in a text field cannot trigger an attack")
	game.backpack_panel.name_field.release_focus()
	for i in range(100): battle.shoot_arrow(Vector2(10, y), Vector2.RIGHT, "native")
	check(battle.projectiles.size() <= 64, "arrow population is capped")
	battle.set_natives(false)
	check(not battle.projectiles.any(func(p: Dictionary) -> bool: return p.get("team", "") == "native"), "disabling natives also clears hostile arrows")
	check(is_equal_approx(Engine.time_scale, 1.0), "combat presentation never changes global simulation speed")
	game.queue_free()
	await process_frame
	print("NATIVE COMBAT TESTS: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
