extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL LAB INPUT: ",label)
func key(value:Key)->void:
	var event:=InputEventKey.new();event.keycode=value;event.physical_keycode=value;event.pressed=true;Input.parse_input_event(event)
	await process_frame;await process_frame
	event.pressed=false;Input.parse_input_event(event);await process_frame
func run()->void:
	for scene in ["sandbox","medieval"]:
		var game=load("res://scenes/"+scene+".tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
		game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false)
		game.player.position=Vector2(20,6);PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,game.player.transform)
		game.open_weapon_lab()
		var before:Vector2=game.player.position
		for code in [KEY_M,KEY_HOME,KEY_TAB]:
			await key(code)
			check(game.weapon_lab_panel.visible and game.player.position.is_equal_approx(before),scene+" modal blocks relocation key "+str(code))
			if game.knowledge_world!=null:check(not game.knowledge_world.overview,scene+" modal blocks overview key "+str(code))
		game.weapon_lab_panel.close()
		if game.knowledge_world!=null:
			await key(KEY_M);check(game.knowledge_world.overview,"closing the panel restores actual map key")
		game.queue_free();await process_frame
	print("WEAPON LAB INPUT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
