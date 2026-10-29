extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func frames(count:int)->void:
	for i in count:await physics_frame
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);current_scene=game;game.combat.set_natives(false)
	await frames(40)
	var session=PaperNetSession.new();root.add_child(session)
	session.game=game;game.network_session=session;session.player_id="self";session.epoch="latency"
	session.ready_to_play=true;session.round_trip_ms=300;session.set_process(false)
	var start:Vector2=game.player.position
	var state:={"id":"self","position":start,"velocity":Vector2.ZERO,"facing":1,"pose":"idle","health":100,"dead":0.0,"connected":true}
	session._actor(state)
	Input.action_press("move_right")
	await frames(3)
	check(game.player.position.x>start.x+.04,"right key moves before any server reply (first 50ms)")
	check(game.facing==1 and game.pose=="walk","local walk pose responds to held input")
	# An old standing frame cannot cancel this still-unacknowledged local input.
	session._actor(state)
	await frames(2)
	check(game.player.position.x>start.x+.10,"late standing frame does not rewind fresh movement")
	Input.action_release("move_right");await frames(2)
	check(absf(game.player.linear_velocity.x)<.01,"release stops local movement before server reply")
	Input.action_press("jump");await frames(2);Input.action_release("jump")
	check(game.player.linear_velocity.y>6,"jump launches locally before a server frame")
	check(game.player.position.y>start.y+.05,"predicted jump has actual local physical displacement")
	var airborne:Vector2=game.player.position
	session.apply_snapshot({"epoch":"latency","revision":1,"world_kind":"paper","objects":[],"world":{},"actors":[state]})
	check(game.player.position.distance_to(airborne)<.05,"routine world resync does not rewind an active predicted jump")
	# Drawing has a stable screen-to-world transform even while the player moves.
	game.camera_x=start.x-1;game.camera_y=0
	var camera_before:=Vector2(game.camera_x,game.camera_y)
	var point:=Vector2(500,300);var world_before:Vector2=game.screen_to_world(point)
	game.pointer_down(point);game.pointer_move(point+Vector2(40,10))
	session.tick(1.0/60)
	check(Vector2(game.camera_x,game.camera_y).distance_to(camera_before)<.0001,"camera remains fixed while a stroke is held")
	check(game.screen_to_world(point).distance_to(world_before)<.0001,"network tick does not drag stroke coordinates")
	check(game.active_stroke!=null and game.active_stroke.points.size()>=2,"local ink grows without a network receipt")
	game.pointer_up(point+Vector2(80,10));session.tick(1.0/60)
	check(absf(game.camera_x-camera_before.x)>.001,"camera resumes follow after stroke release")
	# Authoritative death, sync and focus isolation continue to win.
	state.dead=3.0;state.health=0;session._actor(state);await frames(2)
	check(game.player.freeze and not game.character_visual.visible,"authoritative death stops predicted movement")
	state.dead=0.0;state.health=100;state.position=start+Vector2(12,0);session._actor(state);await frames(2)
	check(game.player.position.distance_to(state.position)<.3,"authoritative respawn/teleport discards old predicted position")
	session.focus_active=false;Input.action_press("move_right");await frames(2)
	check(absf(game.player.linear_velocity.x)<.01,"focus loss blocks local prediction immediately")
	Input.action_release("move_right");session.focus_active=true
	session.set_meta("flow_modal",true);Input.action_press("move_left");await frames(2)
	check(absf(game.player.linear_velocity.x)<.01,"room dialog blocks predicted movement")
	Input.action_release("move_left");session.set_meta("flow_modal",false)
	game.network_session=null;session.free();game.free()
	print("ONLINE_LATENCY: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
