extends SceneTree
var failures:Array[String]=[]
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("STRONG IMPACT: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.combat.set_natives(false);game.feedback.audio_enabled=false;game.feedback.set_process(false)
	game.feedback.events.clear()
	var hp:float=game.combat.health
	var time_scale:float=Engine.time_scale
	game.feedback.emit_event("hit",game.player.position)
	game.feedback.step(0)
	check(game.feedback.screen_offset.length()>3,"landed blow has a stronger immediate physical punch")
	check(game.feedback.has_method("impact_flash_strength"),"contact burst has its own brief screen flash")
	if game.feedback.has_method("impact_flash_strength"):
		check(game.feedback.impact_flash_strength()>0,"nearby actual hit gets a brief flash")
		for i in 100:game.feedback.emit_event("break",game.player.position)
		game.feedback.step(0)
		check(game.feedback.events.size()<=24 and game.feedback.impact_flash_strength()<=.12 and game.feedback.screen_offset.length()<=9,"simultaneous impacts stay bounded")
		game.feedback.events.clear();game.feedback.emit_event("hit",game.player.position+Vector2(100,0));game.feedback.step(0)
		check(game.feedback.impact_flash_strength()==0 and game.feedback.screen_offset==Vector2.ZERO,"distant hits cannot flash or shake personal screen")
		game.feedback.step(2)
		check(game.feedback.impact_flash_strength()==0 and game.feedback.events.is_empty(),"impact is brief and fully expires")
	check(game.combat.health==hp and Engine.time_scale==time_scale,"presentation never changes damage or pauses the world")
	game.queue_free();await process_frame
	print("STRONG IMPACT: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
