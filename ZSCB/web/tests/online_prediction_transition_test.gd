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
	var state:={"position":Vector2(0,10),"velocity":Vector2.ZERO,"facing":1,"pose":"fall","dead":0.0,"health":100.0,"connected":true}
	prediction.receive(game,state,1000,300)
	prediction.step(game,1.0/60,{"right":true},true,1000)
	prediction.step(game,1.0/60,{"right":true},true,1016)
	prediction.step(game,1.0/60,{"left":true},true,1300)
	game.jumps_used=2;game.jump_was_down=true;game.down_was_down=true
	prediction.jump_down=true;Input.action_press("jump");Input.action_press("move_up")
	state.health=75.0;state.velocity=Vector2(4.6,2)
	prediction.receive(game,state,1316,300)
	check(absf(game.combat.player_push)<.01,"hurt after reversal uses historical controls rather than inventing9.2m/s recoil")
	prediction.step(game,1.0/60,{"jump":true,"up":true,"left":true},true,1332)
	check(game.player.linear_velocity.y<3 and game.jumps_used==2,"nonfatal damage never launches a third jump while Space/W remain held")
	check(game.down_was_down==false,"current released down input updates normally after correction")
	Input.action_release("jump");Input.action_release("move_up")
	prediction.step(game,1.0/60,{},false,1348)
	state.position=Vector2(1,11);state.velocity=Vector2(0,5)
	prediction.receive(game,state,1400,300)
	check(game.player.position.distance_to(Vector2(0,10))<.001 and game.player.linear_velocity.distance_to(Vector2(0,5))<.001,"resuming restores authoritative airborne velocity without snapping to delayed position")
	# A real large-error correction preserves held-key edge and aerial budget too.
	prediction.step(game,1.0/60,{},true,1416)
	prediction.jump_down=true;game.jumps_used=2
	state.position=Vector2(4.5,11);state.velocity=Vector2(0,1)
	prediction.receive(game,state,1716,300)
	prediction.step(game,1.0/60,{"jump":true},true,1732)
	check(game.player.linear_velocity.y<6 and game.jumps_used==2,"large historical correction does not launch or replenish a jump")
	# Unknown RTT/focus stall cannot invent a high recoil from current movement.
	prediction.step(game,1.0/60,{},false,1750)
	state.health=50;state.velocity=Vector2(4.6,0);state.pose="walk";state.facing=1
	prediction.receive(game,state,1800,-1)
	check(absf(game.combat.player_push)<=3,"unmatched damage uses bounded recoil fallback")
	game.free()
	print("ONLINE_PREDICTION_TRANSITIONS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
