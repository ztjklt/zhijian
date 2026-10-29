extends SceneTree
const OUT := "/Users/jitian/Documents/ChatGPT/纸上城堡/logs/ui-redesign-2026-10-25/"
func _init()->void:call_deferred("run")
func shot(name:String)->void:
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);game.onboarding.dismiss();game.feedback.audio_enabled=false
	for i in range(20):await physics_frame
	var entry:=BlueprintBag.add_entry(game.bag,PaperWeaponGrip.practice_sword());game.selected_blueprint_id=entry.entry.id
	game.backpack_panel.refresh()
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(844,390),Vector2i(390,844)]:
		root.min_size=dimensions;root.size=dimensions
		game.activate_draw_mode(2)
		await shot("play-%dx%d"%[dimensions.x,dimensions.y])
		game.toggle_bag()
		await shot("bag-%dx%d"%[dimensions.x,dimensions.y])
		game.toggle_bag()
	game.free();print("CLEAN UI VISUAL: saved ",OUT);quit()
