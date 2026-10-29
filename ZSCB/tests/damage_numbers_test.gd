extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; print("FAIL: ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game); await process_frame
	game.set_physics_process(false); game.player.freeze=true
	game.combat.set_natives(false)
	var battle=game.combat
	game.equipped_weapon=DrawingRules.weapon([{"points":[Vector2.ZERO,Vector2(2,0)]}])
	var at:Vector2=game.player.position+Vector2(1,.06)
	battle.targets=[{"position":at,"health":2.0,"flash":0.0,"respawn":0.0}]
	battle.attack(Vector2.RIGHT)
	for frame in range(12): battle.step(1.0/60)
	check(battle.targets[0].health==0 and battle.effects.any(func(e):return e.text=="−2"),"melee practice target reports actual lethal loss")
	battle.targets=[{"position":at,"health":2.0,"flash":0.0,"respawn":0.0}]
	battle.effects.clear()
	battle.shoot_arrow(at-Vector2(.2,0),Vector2.RIGHT,"player")
	battle._step_projectiles(.03)
	check(battle.targets[0].health==0 and battle.effects.any(func(e):return e.text=="−2"),"arrow practice target reports actual lethal loss")
	game.queue_free(); await process_frame
	var room=PaperNetRoom.new()
	room.configure("DMG001","medieval-v1","owner",PaperWorldStore.new("user://damage-test"),"world")
	root.add_child(room)
	var npc=room.world.medieval_world.entities.filter(func(e):return e.kind=="villager").front()
	npc.health=5
	room.world.medieval_world.damage_entity(npc,40,npc.position,Vector2.ZERO)
	check(room.combat_events.any(func(e):return e.amount==5),"online NPC actual loss is present in numbered feedback")
	check(room.combat_events.filter(func(e):return e.kind in ["hit","break"]).size()==1 and room.combat_events.filter(func(e):return e.kind=="voice" and e.amount==0).size()==1,"one lethal NPC impact has one damage event plus one separate death cry without duplicate damage")
	room.queue_free(); await process_frame
	print("DAMAGE NUMBERS: ",checks," checks, ",failures," failures"); quit(1 if failures else 0)
