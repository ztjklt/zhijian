extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);current_scene=game;game.set_physics_process(false);game.combat.set_natives(false)
	var prediction=load("res://scripts/net/local_prediction.gd").new()
	check(prediction.has_method("sent_input"),"prediction records the actual sequence and local motion associated with a sent input")
	if prediction.has_method("sent_input"):
		var state:={"position":Vector2.ZERO,"velocity":Vector2(4.6,0),"pose":"walk","facing":1,"health":100,"dead":0,"connected":true,"movement_reset":1,"input_ack":0,"input_age":0.0}
		prediction.receive(game,state,1000,600)
		for i in 121:
			game.player.position=Vector2(i*4.6/60,0)
			prediction.step(game,1.0/60,{"right":true},true,1000+roundi(i*1000.0/60))
			prediction.sent_input(i+100,{"right":true})
			prediction.received_at=1000+roundi(i*1000.0/60)
		var before:Vector2=game.player.position
		state.input_ack=184;state.position=Vector2(84*4.6/60,0)
		for ping in [100,1200,0,800]:
			prediction.receive(game,state,3000,ping)
			prediction.step(game,1.0/60,{"right":true},true,3016)
		check(game.player.position.distance_to(before)<.001,"changing ping cannot select a different history for the same actual acknowledged input")
		prediction.sent_input(300,{"left":true})
		state.position=Vector2(-20,0);prediction.receive(game,state,3032,100)
		check(prediction.correction.length()<.001,"pre-reversal ACK cannot overwrite pending reversed input")
		state.movement_reset=2;state.position=Vector2(30,5);prediction.receive(game,state,3048,100)
		check(game.player.position.distance_to(Vector2(30,5))<.001,"explicit server relocation still snaps immediately")
		# A genuine stopped-position error eventually converges using bounded steps.
		prediction.step(game,1.0/60,{},true,3064)
		prediction.sent_input(301,{})
		state.input_ack=301;state.position=Vector2(29,5);state.velocity=Vector2.ZERO
		prediction.receive(game,state,3064,100)
		var biggest:=0.0
		for i in 120:
			before=game.player.position
			prediction.received_at=3064+i*16
			prediction.step(game,1.0/60,{},true,3064+i*16)
			biggest=maxf(biggest,before.distance_to(game.player.position))
		check(biggest<.025,"ordinary correction has bounded per-step displacement")
		check(absf(game.player.position.x-29)<.2,"bounded correction still converges to authority")
	game.free()
	print("ONLINE_ACK_RECONCILE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
