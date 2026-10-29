extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL DUEL ARROWS: ",label)
func run()->void:
	var room=PaperNetRoom.new()
	room.configure("ARROW2","paper","owner",PaperWorldStore.new("user://duel-arrows"),"world")
	root.add_child(room)
	var a:Dictionary=room.join("","甲");var b:Dictionary=room.join("","乙")
	room.ready(a.player_id);room.ready(b.player_id)
	room.set_physics_process(false)
	var left=room.actors[a.player_id];var right=room.actors[b.player_id]
	left.combat.shoot_arrow(Vector2(2,3),Vector2.RIGHT,"player")
	right.combat.shoot_arrow(Vector2(2.4,3),Vector2.LEFT,"player")
	room._physics_process(1.0/60)
	check(left.combat.projectiles.is_empty() and right.combat.projectiles.is_empty(),"opposing real arrows collide during crossing frame")
	left.combat.projectiles.clear();right.combat.projectiles.clear()
	left.combat.shoot_arrow(Vector2(2,3),Vector2.RIGHT,"player")
	left.combat.shoot_arrow(Vector2(2.4,3),Vector2.LEFT,"player")
	room._physics_process(1.0/60)
	check(left.combat.projectiles.size()==2,"arrows from same player do not cancel one another")
	left.combat.projectiles.clear()
	var wall:Dictionary=room.command(a.player_id,{"seq":1,"op":"spawn","object":{"kind":"freehand","x":2.1,"y":3.0,"paths":[{"points":[Vector2(0,-.4),Vector2(0,.4)],"collision":true}]}})
	check(wall.ok,"wall fixture creates real ink geometry")
	left.combat.shoot_arrow(Vector2(2,3),Vector2.RIGHT,"player")
	right.combat.shoot_arrow(Vector2(2.4,3),Vector2.LEFT,"player")
	room._physics_process(1.0/60)
	check(left.combat.projectiles.is_empty() and right.combat.projectiles.size()==1,"earlier wall impact prevents later arrow clash behind wall")
	check(room.world.objects[0].health==96,"wall receives exactly one arrow hit")
	left.combat.projectiles.clear();right.combat.projectiles.clear()
	for i in 100:
		room.world.objects[0].health=120
		left.combat.shoot_arrow(Vector2(2,3),Vector2.RIGHT,"player")
		room._step_shared_arrows(1.0/60)
	check(room.world.combat.effects.size()<=32,"authority does not accumulate invisible damage effects after repeated arrow impacts")
	room.queue_free();await process_frame
	print("NETWORK DUEL ARROWS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
