extends SceneTree
var checks:=0
var failures:Array[String]=[]
var game
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL WEAPON LAB: ",label)
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.player.position=Vector2(0,0);game.combat.set_natives(false)
	var lab=game.get("weapon_lab")
	check(lab!=null,"core has an optional weapon experiment module")
	if lab==null:game.queue_free();quit(1);return
	check(not lab.active and lab.current.is_empty(),"old worlds gain no automatic targets or results")
	check(lab.start(1.2).ok and lab.active,"explicit action creates a nearby test target")
	check(not lab.start(100).ok,"only the three bounded distances are accepted")
	var weapon=PaperWeaponGrip.practice_sword();weapon.weapon_type="sword";game.equipped_weapon=weapon
	lab.select(weapon)
	var ticket:Dictionary=lab.ticket()
	game.combat.player_paths=[[Vector2(.8,0),Vector2(1.6,.4)]];game.combat.previous_player_paths=game.combat.player_paths
	game.combat.swing_weapon=weapon;game.combat.swing=.2;game.combat.swing_ticket=ticket
	game.combat._resolve_blades()
	check(lab.current.hits==1 and lab.current.last>=5 and lab.current.last<=40,"actual blade geometry records bounded real damage")
	game.combat._resolve_blades()
	check(lab.current.hits==1,"one swing cannot count again on another frame")
	check(lab.keep().ok and lab.baseline.hits==1,"a measured design can be retained as comparison")
	var sword_key:String=lab.current.key
	weapon=weapon.duplicate(true);weapon.weapon_type="firearm";game.equipped_weapon=weapon
	lab.select(weapon);game.combat.reset();game.combat.bow_equipped=false
	game.combat.attack(Vector2.RIGHT);game.combat._step_projectiles(.1)
	check(lab.current.hits==1 and is_equal_approx(lab.current.last,28),"actual fast firearm projectile records28 damage")
	check(lab.current.key!=sword_key and lab.baseline.kind=="sword","new design does not overwrite retained comparison")
	lab.reset();game.combat.cooldown=0;game.combat.attack(Vector2.RIGHT)
	var old:Dictionary=lab.ticket()
	weapon=weapon.duplicate(true);weapon.weapon_type="spear";game.equipped_weapon=weapon;lab.select(weapon)
	game.combat._step_projectiles(.1)
	check(lab.current.hits==0 and lab.last_hit.kind=="firearm","in-flight shot remains attributed to firing design")
	var before:int=lab.current.hits
	lab.start(2.5);lab.hit(old,28,lab.position,game.player.position)
	check(lab.current.hits==before,"moving the target invalidates old attack tickets")
	game.combat.reset();weapon.weapon_type="firearm";game.equipped_weapon=weapon;lab.select(weapon)
	game.combat.attack(Vector2.RIGHT);lab.start(1.2);game.combat._step_projectiles(.1)
	check(game.combat.projectiles.size()==1,"an old shot passes through a new-generation meter without being consumed")
	lab.start(1.2);weapon.weapon_type="firearm";game.equipped_weapon=weapon;lab.select(weapon);lab.reset();game.combat.reset()
	game.objects=[{"role":"building","kind":"wall","paths":[{"points":[Vector2(.6,-1),Vector2(.6,2)],"collision":true}],"x":0.0,"y":0.0,"health":120.0}]
	game.combat.attack(Vector2.RIGHT);game.combat._step_projectiles(.1)
	check(lab.current.hits==0 and game.objects[0].health<120,"earlier wall contact prevents a hidden target score")
	game.objects=[];game.combat.reset();weapon.weapon_type="bow";game.equipped_weapon=weapon;lab.select(weapon);lab.reset()
	game.combat.attack(Vector2.RIGHT);game.combat.cancel_draw();game.combat.step(.5)
	check(lab.current.hits==0 and game.combat.projectiles.is_empty(),"cancelled bow cannot produce a test hit")
	game.combat.reset();game.combat.bow_equipped=false;game.combat.attack(Vector2.RIGHT);game.combat.step(.43);game.combat._step_projectiles(.1)
	check(lab.current.hits==1 and is_equal_approx(lab.current.last,24),"hand-drawn bow uses its actual arrow and24 damage")
	for i in 20:
		weapon=PaperWeaponGrip.practice_sword();weapon.grip+=Vector2(i*.001,0);lab.select(weapon)
	check(lab.samples.size()<=8,"session design history stays bounded")
	var saved:Dictionary=game.world_save_state()
	check(not saved.has("weapon_lab"),"temporary targets and scores do not enter world saves")
	var actor:=RigidBody2D.new();actor.freeze=true;actor.collision_layer=64;actor.collision_mask=0
	var fixture:=CollisionShape2D.new();var circle:=CircleShape2D.new();circle.radius=.3;fixture.shape=circle;actor.add_child(fixture);actor.position=Vector2(2.5,.2);game.add_child(actor)
	await physics_frame
	var position:Vector2=lab.position
	check(not lab.start(2.5).ok and lab.position==position,"occupied map actor space refuses a new target without moving the old one")
	lab.stop();check(not lab.active,"stopping removes only the temporary test target")
	game.queue_free();await process_frame
	print("WEAPON LAB: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
