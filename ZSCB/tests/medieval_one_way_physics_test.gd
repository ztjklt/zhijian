extends SceneTree
var checks := 0
var failures: Array[String] = []
const Entity := preload("res://scripts/medieval_entity.gd")
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func teleport(body,at: Vector2) -> void:
	if body.has_method("reset_movement"): body.reset_movement()
	body.position=at
	PhysicsServer2D.body_set_state(body.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,at))
	body.linear_velocity=Vector2.ZERO
	body.sleeping=false
func ticks(n: int) -> void:
	for i in n: await physics_frame
func run() -> void:
	var floor := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new();rectangle.size=Vector2(40,.2)
	shape.shape=rectangle;shape.position=Vector2(0,-.1);floor.add_child(shape);root.add_child(floor)
	var house := Entity.new();house.setup("house",Vector2.ZERO,"test-house",0);root.add_child(house)
	var player = load("res://scripts/player.gd").new();root.add_child(player)
	await physics_frame
	teleport(player,Vector2(-3,.32))
	for i in 115:
		player.linear_velocity.x=3.0
		await physics_frame
	print("cross ",player.position)
	check(player.position.x>2.0 and player.position.y<.5,"real player crosses the complete house at ground level")
	teleport(player,Vector2(.8,.32));player.linear_velocity=Vector2(0,11.5)
	await ticks(25)
	check(player.position.y>3.2,"ascending player passes through all house ledges from below")
	await ticks(90)
	check(player.position.y>2.5,"falling player lands on the visible pitched roof")
	var supports: Array=player.support_bodies()
	check(not supports.is_empty() and supports[0].get_meta("medieval_owner",null)==house,"roof is a real independent player support")
	var start_y:float=player.position.y
	check(player.begin_drop_through(),"roof permits deliberate drop through")
	player.linear_velocity.y=-3.0
	for i in 60:
		player.update_drop_through(1.0/60)
		await physics_frame
	print("drop ",start_y," -> ",player.position," vel ",player.linear_velocity," sleep ",player.sleeping," ignores ",player.get_collision_exceptions())
	check(player.position.y<start_y-.6 and player.position.y>.8,"dropping from roof lands on a lower sill rather than bypassing whole building")
	# Drop from a high roof point, remove that exact support, and verify falling.
	teleport(player,Vector2(.95,4.5));await ticks(55)
	var resting:float=player.position.y
	house.damage(55,Vector2(.95,3.4),Vector2.DOWN)
	await ticks(65)
	print("damage ",resting," -> ",player.position," vel ",player.linear_velocity," sleep ",player.sleeping," segments ",house.walk_segments())
	check(player.position.y<resting-.4,"local roof damage removes the support directly beneath the player")
	var npc:=Entity.new();npc.setup("villager",Vector2(-3,.04),"test-villager",0);root.add_child(npc)
	for i in 170:
		npc.linear_velocity.x=2.3
		await physics_frame
	print("npc ",npc.position)
	check(npc.position.x>2.8 and npc.position.y<.25,"real villager also crosses the complete house without climbing the facade")
	for node in [npc,player,house,floor]:node.queue_free()
	print("ONE WAY PHYSICS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
