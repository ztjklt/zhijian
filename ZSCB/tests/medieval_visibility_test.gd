extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error("VISIBILITY: "+label)
func run()->void:
	root.size=Vector2i(1440,900)
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss();game.set_physics_process(false)
	game.player.position=game.medieval_world.safe_spawn_position(30)
	game.camera_x=30;game.camera_y=game.camera_target_y()
	var near=game.medieval_world.entity_by_id("villager-0")
	var far=game.medieval_world.entity_by_id("knight-0")
	near.person_visual._process(.016);far.person_visual._process(.016)
	check(near.person_visual.visible,"near person retains original visible rig")
	check(not far.person_visual.visible,"offscreen person hides and skips bone/IK work")
	check(far.alive and far.collision_layer==64,"offscreen visual preserves live physical actor")
	var a=near.person_visual.get_node("Skeleton/Hips/Torso/Head/Ink")
	var b=far.person_visual.get_node("Skeleton/Hips/Torso/Head/Ink")
	check(a.material==b.material,"identical gentle-head shader material is shared")
	game.player.position=far.position+Vector2(0,.54)
	game.camera_x=far.position.x;game.camera_y=game.camera_target_y()
	far.person_visual._process(.016)
	check(far.person_visual.visible,"returning camera restores actual actor visual immediately")
	check(far.person_visual.position.distance_to(game.world_to_screen(far.position+Vector2(0,.54)))<25,"restored person follows current body rather than stale screen pose")
	var tiles:Array=[]
	for entity in game.medieval_world.entities:
		if entity.kind=="castle_piece":tiles.append(entity)
	check(tiles.size()>1,"castle fixture exists")
	if tiles.size()>1:
		game.camera_x=3
		for tile in tiles:tile.castle_visual._process(.016)
		check(not tiles[0].castle_visual.visible,"offscreen castle stops canvas redraw")
		check(tiles[0].castle_visual.material==tiles[1].castle_visual.material,"atlas tiles share same ink shader material")
		var tile=tiles[0]
		var old_cuts:int=tile.cuts.size()
		tile.damage(15,tile.to_global(Vector2(0,tile.size.y*.45)),Vector2.ZERO)
		check(tile.cuts.size()==old_cuts+1,"offscreen castle damage changes actual retained geometry")
		game.camera_x=tiles[0].position.x
		game.camera_y=tiles[0].position.y
		tiles[0].castle_visual._process(.016)
		check(tiles[0].castle_visual.visible,"castle returns at current camera without changing damage geometry")
		for i in 3:await process_frame
		check(tile.castle_visual.cached_cuts==tile.cuts.size() and tile.castle_visual.cached_polygons==tile.render_polygons,"return redraw refreshes damage cache to current local geometry")
		var screen:Vector2=game.world_to_screen(tile.position)
		game.camera_x+=(screen.x+32)/game.PIXELS_PER_UNIT
		check(MedievalVisibility.entity_visible(game,tile),"partly visible silhouette remains included when root lies beyond screen edge")
	game.queue_free();await process_frame
	print("MEDIEVAL VISIBILITY: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
