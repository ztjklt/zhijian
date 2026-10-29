extends SceneTree
var failed:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed.append(label);print("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);current_scene=game;game.set_physics_process(false);game.combat.set_natives(false)
	var prediction=load("res://scripts/net/local_prediction.gd").new()
	var start:=Vector2(0,0)
	var state:={"position":start,"velocity":Vector2(4.6,0),"pose":"walk","facing":1,"health":100,"dead":0,"connected":true}
	prediction.receive(game,state,1000,600)
	# Actual steady walking history; ping later temporarily reports only100ms
	# although this position frame still represents 600ms ago.
	for i in 121:
		game.player.position=Vector2(i*4.6/60,0)
		prediction.step(game,1.0/60,{"right":true},true,1000+roundi(i*1000.0/60))
		if i%3==0:
			state.position=Vector2(maxi(0,i-36)*4.6/60,0)
			prediction.receive(game,state,1000+roundi(i*1000.0/60),600)
	var before:Vector2=game.player.position
	state.position=Vector2((120-36)*4.6/60,0)
	prediction.receive(game,state,3000,100)
	prediction.step(game,1.0/60,{"right":true},true,3016)
	var correction_jump:float=before.x-game.player.position.x
	print("RUBBERBAND stale RTT correction backward_m=",correction_jump)
	check(correction_jump<.025,"late frame cannot shove a running player backwards by tens of pixels")
	# A short frame gap may pause prediction; recovery must not snap straight to
	# the delayed position when the unchanged input is still being acknowledged.
	prediction.received_at=3016
	prediction.step(game,1.0/60,{"right":true},true,3817)
	before=game.player.position;state.position=before-Vector2(2.2,0)
	prediction.receive(game,state,3818,600)
	check(before.x-game.player.position.x<.025,"resuming after a frame gap preserves displayed position instead of a2.2m rewind")
	game.free()
	print("ONLINE_RUBBERBAND: ",checks," checks, ",failed.size()," failures")
	quit(0 if failed.is_empty() else 1)
