extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _init()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,900)
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false;root.add_child(game)
	await physics_frame
	game.onboarding.dismiss();game.set_physics_process(false);game.player.freeze=true
	for cycle in 12:
		for i in 35:
			game.medieval_world.step(1.0/60)
			await physics_frame
		for e in game.medieval_world.entities:
			if not e.is_person() or e.kind in ["king","queen","driver"]:continue
			game.player.position=e.position+Vector2(0,.54)
			game.camera_x=e.position.x
			game.camera_y=game.camera_target_y()
			var visual=e.person_visual
			visual._process(.1)
			for leg in ["FrontLeg","BackLeg"]:
				var foot=visual.get_node("Skeleton/Hips/"+leg+"/Shin/Foot")
				var screen:Vector2=foot.to_global(Vector2(2.4,4.25))
				var point:Vector2=game.screen_to_world(screen)
				var gap:float=point.y-game.medieval_world.travel_height(point.x)
				checks+=1
				if absf(gap)>.04:
					failures.append(e.entity_id+leg)
					print("GAP ",e.entity_id," ",leg," gap=",gap," pos=",e.position," ground=",game.medieval_world.travel_height(e.position.x)," velocity=",e.linear_velocity," visualrot=",visual.rotation)
	game.queue_free();await process_frame
	print("GROUND PEOPLE CONTACT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
