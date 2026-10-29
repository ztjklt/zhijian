extends "res://tests/network_prediction_delay_test.gd"
## Actual separate authority/client physics, with ordered message bursts and
## deliberately wrong changing ping. A stall may pause movement, never rewind it.
var physical_frames:=0
var trace:Array=[]
func frames(count:int)->void:
	for i in count:
		physical_frames+=1
		session.delay=1100 if (physical_frames>=65 and physical_frames<80) or (physical_frames>=180 and physical_frames<195) else 150
		session.round_trip_ms=[40,1200,100,800][(physical_frames/40)%4]
		await super.frames(1)
func run()->void:
	await setup(300,300,0)
	var start:float=game.player.position.x
	Input.action_press("move_right")
	var biggest_back:=0.0
	for i in 240:
		var before:float=game.player.position.x
		await frames(1)
		biggest_back=maxf(biggest_back,before-game.player.position.x)
		if i%6==0:trace.append({"frame":physical_frames,"local_x":game.player.position.x,"server_x":actor.player.position.x,"debt":session.prediction.correction.x,"running":session.prediction.was_running})
	Input.action_release("move_right")
	await frames(240)
	var error:float=game.player.position.distance_to(actor.player.position)
	check(biggest_back<.05,"ordered1100ms bursts and wrong ping never cause a large backward frame (%.3fm)"%biggest_back)
	check(game.player.position.x>start+6,"client and server continue walking after both burst recoveries")
	check(error<.3,"stopped position converges after burst recovery (%.3fm)"%error)
	check(session.prediction.has_method("sent_input") and session.prediction.ack_enabled,"actual authority ACK metadata was consumed during the scenario")
	print("BURST_REPORT: ",JSON.stringify({"max_backward_m":biggest_back,"final_error_m":error,"trace":trace}))
	game.network_session=null;session.free();game.free();room.free();await process_frame
	print("ONLINE_JITTER_BURST: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
