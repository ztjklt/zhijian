extends SceneTree
var game
const OUT:="/Users/jitian/Documents/ChatGPT/纸上城堡/ZSCB/docs/previews/2026-10-24-medieval-product/damage/"
func _init()->void:call_deferred("run")
func capture(label:String,x:float)->void:
	game.player.freeze=true
	game.camera_x=x
	game.camera_y=game.camera_target_y()
	game.PIXELS_PER_UNIT=85
	for i in 5:
		game.canvas_node.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label+".png"))
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1440,900)
	game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false;root.add_child(game)
	await physics_frame
	game.onboarding.dismiss();game.set_physics_process(false)
	for i in 50:
		game.medieval_world.step(1.0/60)
		await physics_frame
	game.player.position=Vector2(23.6,game.medieval_world.travel_height(23.6)+.3)
	await capture("01-house-intact",24.3)
	var house=game.medieval_world.entity_by_id("house-0")
	game.medieval_world.damage_entity(house,35,house.position+Vector2(-1.8,1.9),Vector2.RIGHT)
	await physics_frame
	await capture("02-house-local-chip-no-outline",24.3)
	game.player.position=Vector2(117.8,game.medieval_world.travel_height(117.8)+.3)
	await capture("03-field-before-cut",119.0)
	for e in game.medieval_world.entities:
		if e.is_foliage() and absf(e.position.x-119.5)<3:
			game.medieval_world.damage_entity(e,100,e.position+Vector2(0,e.size.y*.4),Vector2.RIGHT*2)
	await physics_frame
	await capture("04-field-cut-stubble",119.0)
	game.free()
	game=null
	for i in 3:await process_frame
	print("PRODUCT DAMAGE VISUAL: 4 real Metal captures")
	quit()
