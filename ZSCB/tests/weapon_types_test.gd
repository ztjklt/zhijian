extends SceneTree
var failures: Array[String] = []
var count := 0
func check(ok: bool, label: String) -> void:
	count += 1
	if not ok: failures.append(label); push_error("WEAPON TYPES: " + label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.onboarding.dismiss()
	game.set_draw_mode(2)
	var strokes := [{"points":[Vector2(0,0),Vector2(0,1.5)]},{"points":[Vector2(-.4,.3),Vector2(.4,.3)]}]
	game.draft = strokes.duplicate(true)
	game.generate()
	game.select_weapon_grip(Vector2(0,.2))
	game.generate()
	check(game.equipped_weapon.is_empty() and game.draft.size()==2,"grip confirmation opens types without equipping or clearing ink")
	check(game.get("selecting_weapon_type") == true,"third 3 opens type wheel")
	if not game.has_method("select_weapon_type"):
		game.queue_free(); await process_frame
		print("WEAPON TYPE TESTS: ",count," checks, ",failures.size()," failures"); quit(1); return
	game.cancel_weapon_grip()
	check(game.draft.size()==2 and not game.selecting_weapon_type,"cancel leaves full drawing and closes wheel")
	for kind in ["sword","hammer","bow","spear","firearm"]:
		game.ink.amount = game.ink.MAXIMUM
		var previous: Dictionary = game.equipped_weapon.duplicate(true)
		game.draft = strokes.duplicate(true)
		game.generate(); game.select_weapon_grip(Vector2(0,.2)); game.generate()
		game.select_weapon_type(kind)
		check(game.equipped_weapon==previous,"choosing "+kind+" keeps old equipment until final 3")
		game.generate()
		check(game.equipped_weapon.get("weapon_type","")==kind and game.draft.is_empty(),kind+" equips only on fourth 3")
		var entry: Dictionary = game.bag.entries.back()
		check(entry.get("weapon_type","")==kind and BlueprintBag.make_object(entry,0,0).get("weapon_type","")==kind,kind+" survives blueprint reuse")
		var clean := PaperNetValidation.weapon(game.equipped_weapon)
		check(clean.ok and clean.weapon.get("weapon_type","")==kind,kind+" survives authoritative validation")
		check(game.save_game(),kind+" saves")
		var restored := SaveStore.load_game()
		check(restored.error=="" and restored.data.equipped_weapon.get("weapon_type","")==kind,kind+" survives JSON load")
	var forged: Dictionary = game.equipped_weapon.duplicate(true)
	forged.weapon_type = "laser"
	check(not PaperNetValidation.weapon(forged).ok,"authority rejects unsupported types")
	forged.weapon_type = 42
	check(not PaperNetValidation.weapon(forged).ok,"authority rejects non-string types")
	game.draft = strokes.duplicate(true); game.generate(); game.select_weapon_grip(Vector2(0,.2)); game.generate()
	game.set_draw_mode(3)
	check(not game.selecting_weapon_type and not game.weapon_type_wheel.visible,"switching tool closes wheel")
	game.set_draw_mode(2)
	check(game.draft.size()==2,"switching tools keeps weapon drawing")
	game.queue_free(); await process_frame
	print("WEAPON TYPE TESTS: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
