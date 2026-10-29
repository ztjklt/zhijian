extends SceneTree

# Integration coverage deliberately exercises the real isolated World2D rooms,
# original stickman locomotion and held-model combat. Only lifecycle fixtures
# inject hit() directly; PvP assertions use attack() and actual physics steps.
var checks := 0
var failures: Array[String] = []
var sequence := 0
var room_script: GDScript
var store_script: GDScript
var rooms: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL NETWORK GAMEPLAY: ", label)

func frames(amount: int) -> void:
	for frame in amount: await physics_frame

func command(room, player_id: String, op: String, args: Dictionary = {}) -> Dictionary:
	sequence += 1
	var request := {"op": op, "seq": sequence}
	request.merge(args, true)
	return room.command(player_id, request)

func make_room(code: String, id: String, secret: String = "gameplay-owner-secret"):
	var room = room_script.new()
	room.configure(code, "paper", secret, store_script.new("user://network_gameplay_worlds"), id)
	root.add_child(room)
	rooms.append(room)
	return room

func pose(actor, position: Vector2) -> void:
	actor.player.position = position
	PhysicsServer2D.body_set_state(actor.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, position))
	actor.player.linear_velocity = Vector2.ZERO
	actor.player.reset_movement()
	actor.input_state.clear()
	actor.combat.player_push = 0
	actor.facing = 1
	actor.pose = "idle"

func block(position: Vector2, size: Vector2 = Vector2(0.8, 0.8), dynamic: bool = true) -> Dictionary:
	var half := size * 0.5
	return {"source": "own", "kind": "freehand", "role": "building", "dynamic": dynamic, "x": position.x, "y": position.y,
		"paths": [{"points": [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y), Vector2(-half.x, -half.y)], "collision": true}]}

func run() -> void:
	for name in ["room", "actor", "world_store"]:
		check(ResourceLoader.exists("res://scripts/net/" + name + ".gd"), name + " production module exists")
	if not failures.is_empty():
		finish()
		return
	room_script = load("res://scripts/net/room.gd")
	store_script = load("res://scripts/net/world_store.gd")
	var room = make_room("FIRST1", "first")
	var other = make_room("SECOND", "second", "second-owner-secret")
	check(room.has_method("disconnect_player") and room.has_method("command") and room.has_method("snapshot"), "room exposes current lifecycle and command APIs")
	var a: Dictionary = room.join("", "甲")
	var b: Dictionary = room.join("", "乙")
	var c: Dictionary = other.join("", "丙")
	check(a.ok and b.ok and c.ok and not room.join("", "第三人").ok, "two player capacity is independent of another room")
	if not (a.ok and b.ok and c.ok):
		await cleanup()
		finish()
		return
	room.ready(a.player_id)
	room.ready(b.player_id)
	other.ready(c.player_id)
	await frames(25)
	var actor_a = room.actors[a.player_id]
	var actor_b = room.actors[b.player_id]
	var actor_c = other.actors[c.player_id]
	check(room.world_2d != other.world_2d and actor_a.player.get_world_2d() == room.world_2d and actor_c.player.get_world_2d() == other.world_2d, "actors use distinct actual World2D physics spaces per room")
	var initial_a: Vector2 = actor_a.player.position
	var initial_b: Vector2 = actor_b.player.position
	var initial_c: Vector2 = actor_c.player.position
	check(command(room, a.player_id, "input", {"right": true}).ok, "authoritative input is accepted")
	await frames(15)
	check(actor_a.player.position.x > initial_a.x + 0.4, "real authoritative player physics advances on remote input")
	check(absf(actor_b.player.position.x - initial_b.x) < 0.1 and absf(actor_c.player.position.x - initial_c.x) < 0.1, "input does not move the other actor or another room")
	await frames(45)
	check(actor_a.input_state.is_empty() and absf(actor_a.player.linear_velocity.x) < 0.1, "stale input clears and actual movement stops after half a second")
	var forged := block(Vector2(-2, 0.3), Vector2(0.8, 6))
	forged.merge({"id": "forged-id", "author": b.player_id, "version": 99, "health": 9000.0, "max_health": 9000.0})
	sequence += 1
	var spawn_request := {"op": "spawn", "seq": sequence, "object": forged, "player_id": b.player_id}
	var spawned: Dictionary = room.command(a.player_id, spawn_request)
	check(spawned.ok, "valid full geometry remains usable despite untrusted identity fields")
	if spawned.ok:
		check(spawned.object.id != "forged-id" and spawned.object.author == a.player_id and spawned.object.version == 1 and spawned.object.health == 120 and spawned.object.max_health == 120, "server owns identity author revision and health despite spoofed spawn payload")
		var previous_count: int = room.world.objects.size()
		var repeated: Dictionary = room.command(a.player_id, spawn_request)
		check(repeated.ok and repeated.id == spawned.id and room.world.objects.size() == previous_count, "replayed spawn returns the same stable entity without duplication")
		check(other.world.objects.is_empty(), "spawning cannot add bodies to another room")
		await test_physics_isolation(room, other, actor_a, actor_c)
		await test_edit_and_undo(room, a.player_id, b.player_id, spawned.id)
	var before_abuse: int = room.world.objects.size()
	var too_far: Dictionary = command(room, a.player_id, "spawn", {"object": block(Vector2(1000, 0), Vector2.ONE, false)})
	check(not too_far.ok and room.world.objects.size() == before_abuse, "static flag cannot bypass the 12 meter creation range")
	if too_far.ok: room._remove(room._object_index(too_far.id))
	check(not command(room, a.player_id, "spawn", {"object": block(Vector2.ZERO, Vector2(9, 1))}).ok, "oversized object geometry is rejected by authority")
	check(command(room, a.player_id, "equip", {"weapon": PaperWeaponGrip.practice_sword()}).ok, "actual locally forged sword equips through server validation")
	var old_weapon: Dictionary = actor_a.equipped_weapon.duplicate(true)
	var bad_weapon := PaperWeaponGrip.practice_sword()
	bad_weapon.damage = 999
	check(not command(room, a.player_id, "equip", {"weapon": bad_weapon}).ok and actor_a.equipped_weapon == old_weapon, "forged weapon stats cannot replace valid equipment")
	bad_weapon = {"paths": [{"points": [Vector2.ZERO, Vector2(8, 0)]}], "grip": Vector2.ZERO}
	check(not command(room, a.player_id, "equip", {"weapon": bad_weapon}).ok, "oversized real weapon shape is rejected")
	check(not command(room, a.player_id, "attack", {"direction": Vector2(NAN, 0)}).ok, "nonfinite aim cannot enter authoritative combat")
	await test_sword_pvp(room, a.player_id, b.player_id, actor_c)
	await test_death(room, a.player_id, b.player_id)
	await test_disconnect(room, a, b)
	await test_resume(room, a, b)
	await cleanup()
	finish()

func test_physics_isolation(room, other, actor_a, actor_c) -> void:
	pose(actor_a, Vector2(-2.9, -2.49))
	pose(actor_c, Vector2(-2.9, -2.49))
	await frames(3)
	var ray := PhysicsRayQueryParameters2D.create(Vector2(-3.2, 0), Vector2(-0.8, 0), 9)
	check(not room.world_2d.direct_space_state.intersect_ray(ray).is_empty() and other.world_2d.direct_space_state.intersect_ray(ray).is_empty(), "same world-space segment sees created wall only in its own room")
	for frame in 36:
		if frame % 10 == 0:
			command(room, actor_a.player_id, "input", {"right": true})
			command(other, actor_c.player_id, "input", {"right": true})
		await physics_frame
	check(actor_a.player.position.x < -2.55 and actor_c.player.position.x > -1.75, "actual movement collides with own room wall while other room crosses same coordinates")
	command(room, actor_a.player_id, "input")
	command(other, actor_c.player_id, "input")
	pose(actor_a, Vector2(-4, -2.49))
	pose(actor_c, Vector2(-4, -2.49))

func test_edit_and_undo(room, owner: String, guest: String, id: String) -> void:
	check(not command(room, guest, "lock", {"id": id, "version": 1}).ok and not command(room, guest, "delete", {"id": id, "version": 1}).ok, "guest cannot lock or delete another author entity")
	check(not command(room, owner, "move", {"id": id, "version": 1, "position": Vector2.ZERO}).ok, "moving an entity requires its live edit lock")
	check(command(room, owner, "lock", {"id": id, "version": 1}).ok, "author obtains edit lock")
	check(not command(room, owner, "move", {"id": id, "version": 0, "position": Vector2.ZERO}).ok, "stale entity version cannot move locked object")
	var moved: Dictionary = command(room, owner, "move", {"id": id, "version": 1, "position": Vector2(0, 0.3)})
	check(moved.ok, "author can move locked current entity")
	var index: int = room._object_index(id)
	if index < 0: return
	check(room.world.objects[index].version == 2 and not room.locks.has(id), "successful move advances stable revision and releases lock")
	check(not command(room, owner, "delete", {"id": id, "version": 1}).ok, "stale delete cannot remove a newer entity")
	room.actors[owner].combat.damage_building(index, 20)
	check(not command(room, owner, "undo").ok and room.world.objects[index].health == 100, "undo cannot replace a damaged entity with an earlier full-health move snapshot")
	check(command(room, owner, "delete", {"id": id, "version": room.world.objects[index].version}).ok, "author may intentionally dismantle own damaged entity")
	check(not command(room, owner, "undo").ok and room._object_index(id) < 0, "undo cannot resurrect a damaged dismantled entity")
	await frames(2)

func test_sword_pvp(room, owner: String, guest: String, outsider) -> void:
	var a = room.actors[owner]
	var b = room.actors[guest]
	pose(a, Vector2(4, -2.49))
	pose(b, Vector2(4.7, -2.49))
	a.combat.cooldown = 0
	a.combat.swing = 0
	a.combat.player_paths.clear()
	a.combat.previous_player_paths.clear()
	b.combat.invulnerable = 0
	await frames(3)
	var before: float = b.combat.health
	var outsider_health: float = outsider.combat.health
	var attack: Dictionary = command(room, owner, "attack", {"direction": Vector2.RIGHT})
	check(attack.ok and b.combat.health == before, "attack starts the real sword motion without instant invisible damage")
	var changes := 0
	var previous := before
	var sampled_full_model := false
	for frame in 27:
		await physics_frame
		if a.combat.player_paths.size() == 2 and a.combat.player_paths[0].size() >= 6: sampled_full_model = true
		if b.combat.health != previous:
			changes += 1
			previous = b.combat.health
	check(sampled_full_model, "server samples the actual multi-path held sword model")
	check(b.combat.health < before and before - b.combat.health <= 40 and changes == 1 and a.combat.hit_ids.has("player_" + guest), "real nearby sword sweep damages other player exactly once with bounded damage")
	check(outsider.combat.health == outsider_health, "real sword combat never damages actor in another room")
	await frames(65)
	pose(a, Vector2(4, -2.49))
	pose(b, Vector2(4.7, -2.49))
	await frames(3)
	before = b.combat.health
	command(room, owner, "attack", {"direction": Vector2.RIGHT})
	await frames(27)
	check(b.combat.health < before, "later valid swing can damage same target again after cooldown and protection")
	await frames(50)
	pose(a, Vector2(4, -2.49))
	pose(b, Vector2(7, -2.49))
	await frames(3)
	before = b.combat.health
	command(room, owner, "attack", {"direction": Vector2.RIGHT})
	await frames(27)
	check(b.combat.health == before, "actual sword model cannot damage distant player")
	await frames(35)
	var wall: Dictionary = command(room, owner, "spawn", {"object": block(Vector2(9.9, -2.2), Vector2(0.08, 1.2), false)})
	check(wall.ok, "real collidable wall can be placed for sword occlusion fixture")
	if wall.ok:
		pose(a, Vector2(9.5, -2.49))
		pose(b, Vector2(10.25, -2.49))
		await frames(3)
		before = b.combat.health
		command(room, owner, "attack", {"direction": Vector2.RIGHT})
		await frames(27)
		var index: int = room._object_index(wall.id)
		check(index < 0 or room.world.objects[index].health < 120, "real sword sweep actually contacts and damages intervening wall")
		check(b.combat.health == before, "earlier real wall contact blocks sword damage to player behind it")

func test_death(room, owner: String, guest: String) -> void:
	var a = room.actors[owner]
	var b = room.actors[guest]
	a.combat.health = 35
	a.combat.invulnerable = 0
	a.hit(40, Vector2.RIGHT)
	check(a.dead_time > 2.99 and a.combat.health == 0 and a.player.freeze and a.player.collision_layer == 0, "lethal validated hit starts three second death and removes physics presence")
	check(not command(room, owner, "spawn", {"object": block(Vector2.ZERO)}).ok, "dead actor cannot create world objects")
	var other_x: float = b.player.position.x
	for frame in 90:
		if frame % 10 == 0: command(room, guest, "input", {"left": true})
		await physics_frame
	check(a.dead_time > 1.3 and a.player.freeze, "dead actor stays absent through first half of respawn delay")
	check(b.player.position.x < other_x - 1, "other player continues actual movement during death")
	command(room, guest, "input")
	var waited := 0
	while a.dead_time > 0 and waited < 110:
		await physics_frame
		waited += 1
	check(a.dead_time == 0 and a.combat.health == 100 and not a.player.freeze and a.player.collision_layer == 2, "actor respawns after three real simulation seconds with full health")
	check(a.combat.invulnerable > 1.9 and not a.equipped_weapon.is_empty(), "respawn grants two seconds protection and retains equipment")
	a.hit(20, Vector2.LEFT)
	check(a.combat.health == 100, "fresh respawn protection rejects damage")
	await frames(60)
	a.hit(20, Vector2.LEFT)
	check(a.combat.health == 100 and a.combat.invulnerable > 0.8, "protection remains effective one second after respawn")
	await frames(70)
	a.hit(20, Vector2.LEFT)
	check(a.combat.health == 80, "damage resumes after two seconds protection expires")

func test_disconnect(room, owner: Dictionary, guest: Dictionary) -> void:
	var a = room.actors[owner.player_id]
	var b = room.actors[guest.player_id]
	var created: Dictionary = command(room, owner.player_id, "spawn", {"object": block(Vector2(-3, -2.2))})
	check(created.ok, "author can create another entity after respawn")
	if created.ok:
		check(command(room, owner.player_id, "lock", {"id": created.id, "version": 1}).ok, "author can acquire lock before disconnect")
	a.preview = [{"points": [Vector2.ZERO, Vector2.ONE]}]
	room.disconnect_player(owner.player_id)
	check(not a.connected and not a.ready_to_play and a.player.freeze and a.player.collision_layer == 0 and a.input_state.is_empty() and a.preview.is_empty(), "disconnect immediately removes physics input and draft preview")
	check(not created.ok or not room.locks.has(created.id), "disconnect immediately releases editing lock")
	var health: float = a.combat.health
	a.hit(40, Vector2.LEFT)
	check(a.combat.health == health and not command(room, owner.player_id, "attack", {"direction": Vector2.RIGHT}).ok, "disconnected actor cannot take damage or issue attacks")
	check(not room.join("forged-player-token", "假冒").ok, "unknown token cannot steal disconnected identity")
	var restored: Dictionary = room.join(owner.token, "甲")
	check(restored.ok and restored.player_id == owner.player_id and room.actors[owner.player_id] == a, "reconnect credential restores same stable actor")
	check(a.player.freeze and not a.ready_to_play, "reconnected actor waits for complete snapshot ready before simulation")
	room.ready(owner.player_id)
	check(not a.player.freeze and a.ready_to_play, "ready acknowledgement resumes reconnected actor")
	check(b.connected and b.ready_to_play, "guest remains active throughout owner short disconnect")

func test_resume(room, owner: Dictionary, guest: Dictionary) -> void:
	check(not command(room, guest.player_id, "save").ok, "guest cannot save using room owner permission")
	var saved: Dictionary = command(room, owner.player_id, "save")
	check(saved.ok, "owner can persist actual authoritative world after gameplay")
	if not saved.ok:
		print("NETWORK GAMEPLAY SAVE ERROR: ", saved.get("error", ""))
		return
	var identity: String = room.owner_id
	var count: int = room.world.objects.size()
	var id_counter: int = room.next_id
	room.queue_free()
	rooms.erase(room)
	await process_frame
	var denied = make_room("BADKEY", "first", "wrong-owner-secret")
	check(denied.closed and not denied.join("", "假主人").ok, "saved world cannot reopen with a different owner credential")
	var resumed = make_room("RESUME", "first")
	check(not resumed.closed and resumed.owner_id == identity and resumed.next_id == id_counter and resumed.world.objects.size() == count, "verified owner resumes stable world identity entities and ID counter")
	var joined: Dictionary = resumed.join("gameplay-owner-secret", "甲")
	check(joined.ok and joined.owner and joined.player_id == identity, "reopened world recognizes same permanent owner identity")
	var has_owned := false
	for object in resumed.world.objects:
		if object.author == identity: has_owned = true
	check(has_owned, "persisted building ownership survives service-style room recreation")

func cleanup() -> void:
	for room in rooms:
		if is_instance_valid(room): room.queue_free()
	rooms.clear()
	await process_frame

func finish() -> void:
	print("NETWORK GAMEPLAY TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
