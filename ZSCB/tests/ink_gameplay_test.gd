extends SceneTree
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: push_error(label); quit(1)
func _init() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game); await process_frame
	game.set_physics_process(false); game.player.freeze = true
	game.onboarding.dismiss(); game.combat.set_natives(false)
	var p: Vector2 = game.player.position + Vector2(2, 2)
	game.draft = [{"points":[p,p+Vector2(1,0)]}]
	game.ink.amount = 0
	game.generate()
	check(game.objects.is_empty() and game.draft.size()==1 and game.bag.entries.size()==6, "no ink retains draft without object or phantom blueprint")
	game.ink.amount=300
	game.generate()
	check(game.objects.size()==1 and game.ink.amount==294, "successful local creation commits geometric price")
	game.undo()
	check(game.ink.amount==294, "undo cannot refund ink")
	var battle = game.combat
	battle.bow_equipped=true; battle.cooldown=0
	game.ink.amount=3
	battle.attack(Vector2.RIGHT)
	check(battle.bow_charge==0 and battle.projectiles.is_empty(), "insufficient ink blocks drawing bow")
	game.ink.amount=4; battle.attack(Vector2.RIGHT)
	check(game.ink.amount==4 and battle.bow_charge>0, "starting bow draw does not charge")
	battle.cancel_draw(); battle.step(0.5)
	check(game.ink.amount==4 and battle.projectiles.is_empty(), "cancelled bow costs nothing")
	battle.cooldown=0; battle.attack(Vector2.RIGHT); battle.step(0.43)
	check(game.ink.amount==0 and battle.projectiles.size()==1, "actual arrow release costs exactly four")
	battle.projectiles.clear(); battle.bow_equipped=false; battle.cooldown=0
	game.equipped_weapon=PaperWeaponGrip.practice_sword()
	battle.attack(Vector2.RIGHT)
	check(battle.swing>0 and game.ink.amount==0, "empty reserve never blocks melee")
	check(game.vitals_hud!=null and game.vitals_hud.mouse_filter==Control.MOUSE_FILTER_IGNORE, "personal HUD is passive and always allocated")
	game.queue_free(); await process_frame
	print("INK GAMEPLAY: ",checks," checks passed"); quit()
