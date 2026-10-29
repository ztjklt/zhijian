extends SceneTree
class CapturingSession extends PaperNetSession:
	var outgoing: Array = []
	func _send(message: Dictionary) -> void: outgoing.append(message.duplicate(true))
var checks := 0
var failures: Array[String] = []
var game
var session

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL CREATION RECEIPT: ", label)
func setup() -> void:
	game = load("res://scenes/main.tscn").instantiate(); game.onboarding.persist = false
	root.add_child(game); game.set_physics_process(false); game.combat.set_natives(false)
	session = CapturingSession.new(); root.add_child(session); session.set_process(false)
	session.game = game; game.network_session = session; session.ready_to_play = true
	session.epoch = "epoch-A"; session.world_id = "world-A"
func cleanup() -> void:
	game.network_session = null; session.game = null; session.free(); game.free()
func commands(op: String) -> Array:
	return session.outgoing.filter(func(message): return message.get("op", "") == op)
func draw_building() -> Dictionary:
	game.set_draw_mode(3)
	game.draft = [{"points": [game.player.position + Vector2(-0.5, 1), game.player.position + Vector2(0.5, 1)]}]
	game.generate()
	return commands("spawn").back()
func draw_weapon() -> Dictionary:
	game.set_draw_mode(2)
	var at: Vector2 = game.player.position
	game.draft = [{"points": [at, at + Vector2(0, 1.2)]}]
	game.generate(); game.select_weapon_grip(at); game.generate(); game.select_weapon_type("firearm"); game.generate()
	return commands("equip").back()
func full_bag() -> void:
	while game.bag.entries.size() < 128: BlueprintBag.add_entry(game.bag, PaperWeaponGrip.practice_sword())
func reply(request: Dictionary, ok: bool = true) -> void:
	var result := {"op": request.op, "seq": request.seq, "ok": ok, "error": "fixture denied"}
	result["weapon" if request.op == "equip" else "object"] = request.get("weapon", request.get("object", {}))
	session._result(result)

func run() -> void:
	setup()
	var spawn := draw_building(); var original: Array = game.draft.duplicate(true)
	game.generate()
	check(commands("spawn").size() == 1, "repeated generate joins one in-flight spawn")
	reply(spawn, false)
	check(game.draft == original and session.pending.is_empty(), "server rejection keeps full draft and permits explicit retry")
	session.ready_to_play = false; game.generate()
	check(commands("spawn").size() == 1 and game.draft == original, "not Ready does not submit or erase drawing")
	session.ready_to_play = true; session.tick(0.01)
	check(commands("spawn").size() == 1, "Ready does not silently generate a previously rejected click")
	cleanup()

	setup(); spawn = draw_building()
	var picked := BlueprintBag.add_entry(game.bag, spawn.object)
	game.selected_blueprint_id = picked.entry.id; game.equip_blueprint()
	var placement: int = game.placing_blueprint_id
	reply(spawn)
	check(placement > 0 and game.placing_blueprint_id == placement, "older spawn success cannot cancel newly picked blueprint placement")
	cleanup()

	setup(); game.set_draw_mode(1)
	original = [{"points": [Vector2(1, 2), Vector2(2, 2)]}]; game.draft = original.duplicate(true)
	var reused := BlueprintBag.add_entry(game.bag, {"source": "own", "kind": "freehand", "dynamic": true, "paths": [{"points": [Vector2(-.5, 0), Vector2(.5, 0)]}]})
	game.select_blueprint(reused.entry.id); game.equip_blueprint()
	game.place_blueprint(game.player.position.x + 3, game.player.position.y + 4)
	spawn = commands("spawn").back(); reply(spawn)
	check(game.draft == original, "placing an existing freehand blueprint cannot consume unrelated unfinished ink")
	check(game.placing_blueprint_id == -1 and game.bag.entries.size() == 7, "confirmed reuse finishes placement without creating another blueprint")
	cleanup()

	setup(); var equip := draw_weapon()
	game.cancel_weapon_grip(false); game.generate()
	game.select_weapon_grip(game.draft[0].points[0]); game.generate(); game.select_weapon_type("hammer")
	game.refine_model_fill = true
	var newer: Array = game.draft.duplicate(true)
	reply(equip)
	check(game.equipped_weapon.get("weapon_type", "") == "firearm", "actual confirmed equipment remains truthful")
	check(game.selecting_weapon_type and game.selected_weapon_type == "hammer" and game.weapon_type_wheel.visible, "older weapon success cannot close a reopened type wheel even with identical ink")
	check(game.draft == newer and game.refine_model_fill == true, "older weapon success preserves new drawing and fill preference")
	cleanup()

	setup(); spawn = draw_building(); original = game.draft.duplicate(true); full_bag()
	reply(spawn)
	check(game.bag.entries.size() == 128 and game.draft == original, "capacity race keeps complete drawing until its confirmed blueprint can be stored")
	check(game.toolbar.status_text.contains("图纸") and game.toolbar.status_text.contains("保留"), "capacity race explains unarchived blueprint instead of claiming full completion")
	game.generate()
	check(commands("spawn").size() == 1, "retry while bag is full cannot spawn or charge a second object")
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(0.01)
	check(game.bag.entries.size() == 128 and game.bag.entries.back().paths == spawn.object.paths, "freeing one slot archives the already confirmed object locally")
	check(game.draft.is_empty() and commands("spawn").size() == 1, "local archive clears original ink without another network spawn")
	reply(spawn); BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(0.01)
	check(game.bag.entries.size() == 127, "duplicate receipt and later capacity cannot add another blueprint")
	cleanup()

	setup(); spawn = draw_building(); equip = draw_weapon(); original = game.draft.duplicate(true); full_bag()
	reply(spawn); reply(equip)
	check(game.draft == original and game.selecting_weapon_type, "two confirmed capacity races preserve current weapon workflow")
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(0.01)
	check(game.bag.entries.size() == 128 and game.bag.entries.back().paths == spawn.object.paths and game.selecting_weapon_type, "first free slot stores older building without changing weapon wheel")
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(0.01)
	check(game.bag.entries.size() == 128 and game.bag.entries.back().get("weapon_type", "") == "firearm", "second free slot stores confirmed weapon")
	check(not game.selecting_weapon_type and game.draft.is_empty() and commands("equip").size() == 1 and commands("spawn").size() == 1, "both original completions settle with no duplicate network operation")
	cleanup()

	setup(); equip = draw_weapon()
	game.cancel_weapon_grip(false); game.generate(); game.select_weapon_grip(game.draft[0].points[0]); game.generate(); game.select_weapon_type("hammer")
	full_bag(); reply(equip)
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(0.01)
	check(game.selecting_weapon_type and game.selected_weapon_type == "hammer", "capacity recovery preserves a newer weapon workflow")
	check(not game.toolbar.status_text.contains("未保存"), "completed local recovery cannot leave its own stale blueprint-failure notice")
	cleanup()

	setup(); spawn = draw_building(); full_bag(); reply(spawn)
	session.epoch = "epoch-B"; session.world_id = "world-B"
	var other: Array = [{"points": [Vector2(7, 7), Vector2(8, 7)]}]; game.draft = other.duplicate(true)
	game.feedback.events.clear()
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(0.01)
	check(game.bag.entries.size() == 128 and game.draft == other, "confirmed personal blueprint survives scope change without clearing new-world ink")
	check(not game.feedback.events.any(func(event): return event.kind == "create"), "archiving an old-world blueprint cannot replay creation effects in the new world")
	cleanup()
	await process_frame
	print("NETWORK CREATION RECEIPT: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
