extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL MOVING LADDER: ",label)
func run()->void:
	var room:=PaperNetRoom.new()
	room.configure("LADDER01","paper","fixture",PaperWorldStore.new("user://moving-ladder"),"world")
	root.add_child(room);room.set_physics_process(false)
	var identity:Dictionary=room.join("","甲");room.ready(identity.player_id)
	var actor=room.actors[identity.player_id]
	var ladder:={"id":"ladder","author":identity.player_id,"version":1,"health":120.0,"kind":"ladder","dynamic":true,"x":-5.6,"y":1.0,"paths":[{"points":[Vector2(0,-1),Vector2(0,2)],"collision":true}]}
	room.world.objects.append(ladder);room.world._rebuild_objects()
	actor.player.position=Vector2(-5.6,1.5)
	var support:RigidBody2D=room.world.object_nodes[0]
	support.linear_velocity=Vector2(1.4,.5);support.angular_velocity=.4
	var session:=PaperNetSession.new();root.add_child(session);session.set_process(false)
	session.player_id=identity.player_id;session.epoch=room.epoch
	session.apply_snapshot(room.snapshot());session.game.set_physics_process(false)
	var game=session.game;var replica:RigidBody2D=game.object_nodes[0]
	actor.step_locomotion(1.0/60,{"up":true});game.step_locomotion(1.0/60,{"up":true})
	check(actor.player.linear_velocity.distance_to(Vector2(1.2,3.5))<.001,"authority fixture climbs with translation and rotation")
	check(game.player.linear_velocity.distance_to(Vector2(1.2,3.5))<.001,"joining snapshot immediately carries moving ladder ride velocity")
	support.linear_velocity=Vector2(-1.4,.5);support.angular_velocity=-.4
	session.apply_frame(room.frame());game.step_locomotion(1.0/60,{"up":true})
	check(game.player.linear_velocity.distance_to(Vector2(-1.2,3.5))<.001,"incremental frame reverses both authoritative ladder velocities")
	check(replica.freeze and support.linear_velocity==Vector2(-1.4,.5),"replica stays frozen and cannot simulate or change server ladder")
	# Legacy protocol10 frames lack the optional motion fields. Clear old values
	# rather than continuing an obsolete ride speed after a compatible reconnect.
	var frame:Dictionary=room.frame();frame.tick+=1
	for body in frame.bodies:body.erase("velocity");body.erase("angular_velocity")
	session.apply_frame(frame);game.step_locomotion(1.0/60,{"up":true})
	check(game.player.linear_velocity.distance_to(Vector2(0,3))<.001,"legacy body frame has bounded zero-motion fallback")
	check(not room.world.objects[0].has("velocity") and not room.world.objects[0].has("angular_velocity"),"ephemeral support velocities never enter saved drawing data")
	game.network_session=null;game.free();session.free();room.free();await process_frame
	print("NETWORK MOVING LADDER: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
