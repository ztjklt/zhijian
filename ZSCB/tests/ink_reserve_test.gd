extends SceneTree
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: push_error(label); quit(1)
func _init() -> void: call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://scripts/ink_reserve.gd"):
		print("FAIL: regenerating ink reserve is missing"); quit(1); return
	var ink = load("res://scripts/ink_reserve.gd").new()
	check(ink.amount == 300, "start with generous 300 ink")
	check(ink.spend(300) and ink.amount == 0, "spend exactly available reserve")
	check(not ink.spend(4) and ink.wait == 2, "rejection does not restart recovery delay")
	ink.step(1.5); check(ink.amount == 0, "no early regeneration")
	ink.step(1.5); check(ink.amount == 25, "crossing delay only regenerates actual remaining second")
	ink.step(100); check(ink.amount == 300, "recovery clamps to capacity")
	check(not ink.spend(-10) and not ink.spend(NAN), "invalid prices never create ink")
	var box := {"paths": [{"points": [Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1),Vector2.ZERO]}]}
	var dense := {"paths": [{"points": [Vector2.ZERO,Vector2(.5,0),Vector2(1,0),Vector2.ONE,Vector2(0,1),Vector2.ZERO]}]}
	check(ink.cost(box) == 10 and ink.cost(box) == ink.cost(dense), "sampling density never changes geometric price")
	var near := {"paths":[{"points":[Vector2.ZERO,Vector2(8,0),Vector2(8,6),Vector2(0,6),Vector2(0,.05)]}]}
	check(ink.cost(near)==68, "physically closed outline pays for the filled area")
	print("INK RESERVE: ", checks, " checks passed"); quit()
