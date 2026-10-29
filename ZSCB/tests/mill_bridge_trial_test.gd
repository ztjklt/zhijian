extends SceneTree
var failures: Array[String] = []
var checks := 0
var game
const DT := 4.0/120.0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);print("FAIL MILL TRIAL: ",label)
func ticks(count: int) -> void:
	for i in count:
		game.medieval_world.step(Engine.time_scale/float(Engine.physics_ticks_per_second))
		await physics_frame
func rectangle(center: Vector2, size: Vector2):
	var half:=size*.5
	var object:Dictionary={"kind":"freehand","role":"building","dynamic":true,"x":center.x,"y":center.y,"paths":[{"points":[Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y),Vector2(-half.x,-half.y)],"collision":true}]}
	var body:=BuildObject.new();body.setup(object);game.add_child(body)
	game.objects.append(object);game.object_nodes.append(body)
	return body
func finish() -> void:
	game.queue_free();await process_frame
	print("MILL BRIDGE TRIAL: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func run() -> void:
	Engine.physics_ticks_per_second=60 if OS.get_environment("PAPER_MILL_REALTIME")=="1" else 120
	Engine.time_scale=1 if OS.get_environment("PAPER_MILL_REALTIME")=="1" else 4
	game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	game.set_physics_process(false);game.player.freeze=true
	game.player.position=Vector2(30,0)
	var trial=game.medieval_world.get("bridge_trial")
	check(trial!=null,"medieval world exposes the optional bridge trial")
	if trial==null:await finish();return
	check(trial.phase=="idle" and trial.get_child_count()==0,"old/new untouched worlds gain no automatic collision bodies")
	check(trial.prepare().ok and trial.phase=="ready","explicit preparation creates the trial stands")
	check(trial.start().ok,"cargo starts on the left stand")
	check(not trial.start().ok,"a running trial cannot be restarted or duplicated")
	for i in 240:
		await ticks(1)
		if trial.phase!="running":break
	check(trial.phase=="failed" and not trial.completed,"without a bridge the actual cargo falls and cannot complete")
	var plank=rectangle(Vector2(133.5,5.5),Vector2(7.8,.06))
	await ticks(75)
	check(not plank.freeze,"the player's bridge remains a genuine dynamic body")
	check(trial.start().ok,"retry preserves the player's real bridge")
	for i in 900:
		await ticks(1)
		if i%120==0:print("MILL DIAG ",i," phase=",trial.phase," cargo=",trial.parcel.position if is_instance_valid(trial.parcel) else Vector2.ZERO," v=",trial.parcel.linear_velocity if is_instance_valid(trial.parcel) else Vector2.ZERO," contacts=",trial.parcel.get_colliding_bodies().size() if is_instance_valid(trial.parcel) else 0," board=",plank.position," angle=",plank.rotation)
		if trial.phase!="running":break
	check(trial.phase=="delivered" and trial.completed,"one drawn plank physically carries cargo onto the destination")
	if trial.phase=="delivered":
		var saved:Dictionary=SaveStore.save_game(game.paper,game.objects,game.bag,game.camera_x,game.player.position.x,game.equipped_weapon,game.world_save_state())
		check(saved.ok,"a physically completed trial is accepted by the actual save writer")
		var loaded:Dictionary=SaveStore.load_game("medieval-v1")
		check(loaded.error=="" and loaded.data.world.bridge_trial.completed and loaded.data.world.bridge_trial.phase=="delivered","actual completed progress survives JSON and disk loading")
	check(game.object_nodes.has(plank) and game.objects.size()==1,"success never removes or replaces the player's construction")
	game.object_nodes.erase(plank);game.objects.clear();plank.queue_free();await physics_frame
	var support=rectangle(Vector2(133.5,3.77),Vector2(.8,2.86))
	var left=rectangle(Vector2(131.55,5.5),Vector2(3.9,.06))
	var right=rectangle(Vector2(135.45,5.5),Vector2(3.9,.06))
	await ticks(100)
	check(trial.start().ok,"completed trial can be replayed with a different structure")
	for i in 900:
		await ticks(1)
		if trial.phase!="running":break
	check(trial.phase=="delivered","two independently drawn boards on a drawn central support also carry the cargo")
	check(game.object_nodes.size()==3 and is_instance_valid(support) and is_instance_valid(left) and is_instance_valid(right),"replay retains every separately drawn piece")
	check(trial.start().ok,"a new attempt does not erase the completion record")
	trial.parcel.position=Vector2(137.8,9)
	PhysicsServer2D.body_set_state(trial.parcel.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,trial.parcel.global_transform)
	trial.step(DT)
	check(trial.phase=="running","passing high over the goal without contact is not delivery")
	await finish()
