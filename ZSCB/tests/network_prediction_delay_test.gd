extends SceneTree
# Real, separate authority World2D + actual rendered-client scene. Only the wire
# has a controlled delay; locomotion, collisions and actor states are production.
class DelayedSession extends PaperNetSession:
	var wire:Array=[]
	var delay:=150
	func _send(message:Dictionary)->void:
		if message.get("type","")=="command":wire.append({"at":Time.get_ticks_msec()+delay,"message":Codec.decode(Codec.encode(message))})
var failures:Array[String]=[]
var checks:=0
var room
var game
var session
var actor
var incoming:Array=[]
var counter:=0
var reports:Array=[]
var jitter_ms:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func frames(count:int)->void:
	for i in count:
		await physics_frame
		var now:=Time.get_ticks_msec()
		while not session.wire.is_empty() and session.wire.front().at<=now:
			var request:Dictionary=session.wire.pop_front().message
			room.command(session.player_id,request)
		counter+=1
		if counter%3==0:
			var due:=now+int(session.delay)+int(sin(counter*.33)*jitter_ms)
			if not incoming.is_empty():due=maxi(due,int(incoming.back().at)+1)
			incoming.append({"at":due,"frame":PaperNetCodec.decode(PaperNetCodec.encode(room.frame()))})
		while not incoming.is_empty() and incoming.front().at<=now:session.apply_frame(incoming.pop_front().frame)
func setup(rtt:int,hint:int,jitter:int)->void:
	jitter_ms=jitter
	room=PaperNetRoom.new()
	room.configure("FEEDCAFE","paper","test-only",load("res://scripts/net/world_store.gd").new("user://delay-test"),"case-%d"%rtt)
	root.add_child(room)
	var identity:Dictionary=room.join("","latency fixture");room.ready(identity.player_id);actor=room.actors[identity.player_id]
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);current_scene=game;game.combat.set_natives(false)
	session=DelayedSession.new();root.add_child(session);session.set_process(false)
	session.game=game;game.network_session=session;session.player_id=identity.player_id
	session.epoch=room.epoch;session.round_trip_ms=hint;session.delay=rtt/2
	session.apply_snapshot(room.snapshot());session.ready_to_play=true
	incoming.clear();counter=0
	await frames(45)
func run()->void:
	for config in [[0,0,0],[300,300,0],[600,600,0],[600,800,60]]:
		var rtt:int=config[0]
		await setup(rtt,config[1],config[2])
		var begin:Vector2=game.player.position
		var key_at:=Time.get_ticks_msec();var response:=-1
		Input.action_press("move_right")
		var previous:float=game.player.position.x;var largest_backstep:=0.0
		for i in 60:
			await frames(1)
			if response<0 and game.player.position.x>begin.x+.015:response=Time.get_ticks_msec()-key_at
			largest_backstep=maxf(largest_backstep,previous-game.player.position.x)
			previous=game.player.position.x
		check(response>=0 and response<85,"%dms RTT: first visible movement within85ms (got%d)"%[rtt,response])
		check(game.player.position.x>begin.x+3.8,"%dms RTT: held direction advances locally"%rtt)
		check(largest_backstep<.10,"%dms RTT: delayed frames do not pull running player backwards (%.3f)"%[rtt,largest_backstep])
		Input.action_release("move_right");await frames(2)
		check(absf(game.player.linear_velocity.x)<.01,"%dms RTT: key release stops immediately"%rtt)
		await frames(55)
		var stop_error:float=game.player.position.distance_to(actor.player.position)
		check(stop_error<.25,"%dms RTT: stopped position converges with authority (%.3f)"%[rtt,stop_error])
		var floor_y:float=game.player.position.y
		Input.action_press("jump");await frames(3);Input.action_release("jump")
		check(game.player.position.y>floor_y+.09,"%dms RTT: local jump rises during network delay"%rtt)
		await frames(12)
		check(game.player.position.y>floor_y+.6,"%dms RTT: old grounded frames do not cancel jump"%rtt)
		await frames(120)
		var landing_error:float=game.player.position.distance_to(actor.player.position)
		check(landing_error<.25 and game.on_ground,"%dms RTT: jump lands and converges (%.3f)"%[rtt,landing_error])
		# Both worlds must use the same support for local collision prediction.
		var platform:={"id":"fixture-platform","author":session.player_id,"version":1,"health":120.0,"kind":"freehand","dynamic":false,"x":float(actor.player.position.x),"y":1.0,"paths":[{"points":[Vector2(-2,0),Vector2(2,0)],"collision":true}]}
		room.world.objects.append(platform);room.world._rebuild_objects();room.revision+=1
		actor.player.position.y=2.5;actor.player.linear_velocity=Vector2.ZERO
		actor.movement_reset+=1 # This fixture performs an explicit authority teleport.
		PhysicsServer2D.body_set_state(actor.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,actor.player.position))
		incoming.clear();session.apply_snapshot(room.snapshot());session.ready_to_play=true
		await frames(100)
		check(game.player.position.y>1.2 and game.on_ground,"%dms RTT: authoritative frozen platform supports predicted player"%rtt)
		reports.append({"rtt_ms":rtt,"hint_ms":config[1],"jitter_ms":config[2],"first_motion_ms":response,"max_backward_step_m":largest_backstep,"stop_error_m":stop_error,"landing_error_m":landing_error})
		game.network_session=null;session.free();game.free();room.free();await process_frame
	print("DELAY_REPORT: ",JSON.stringify(reports))
	print("ONLINE_PREDICTION_DELAY: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
