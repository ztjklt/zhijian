extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var Entity = load("res://scripts/medieval_entity.gd")
	var house = Entity.new()
	house.setup("house",Vector2.ZERO,"test-house",0)
	root.add_child(house)
	await process_frame
	check(house.collision_layer == 128 and house.collision_mask == 0,"facades are damage proxies, not movement walls")
	check(house.has_method("walk_segments"),"roof/cornice support is independently described")
	if not house.has_method("walk_segments"): finish(); return
	check(house.walk_segments().size() >= 5,"house has a reachable sill-to-roof route")
	var fixtures := 0
	for child in house.get_children():
		if child is StaticBody2D:
			fixtures += 1
			check(child.collision_layer == 1 and child.get_meta("map_drop_allowed",false),"each ledge independently supports drop through")
			check(child.get_meta("medieval_owner",null) == house,"ledge impact resolves back to destructible artwork")
			check(child.get_child(0).one_way_collision,"ledge is passable from below")
	check(fixtures >= 5,"standable ink has actual separate thin bodies")
	var villager = Entity.new()
	villager.setup("villager",Vector2.ZERO,"test-villager",0)
	root.add_child(villager)
	check(villager.collision_layer == 64 and villager.collision_mask == 9,"villagers walk through facades and each other")
	check(Entity.supported_kind("grass_tall"),"generated foliage is registered")
	var grass = Entity.new()
	grass.setup("grass_tall",Vector2.ZERO,"test-grass",0)
	root.add_child(grass)
	check(grass.collision_layer == 0 and grass.collision_mask == 0,"grass never blocks walking")
	grass.damage(100,Vector2(0,.3),Vector2.RIGHT)
	await process_frame
	check(not grass.alive and grass.polygons.is_empty() and not grass.render_polygons.is_empty(),"cut grass leaves short visible stubble without a damage target")
	var before: float = area(house.render_polygons)
	house.damage(15,Vector2(2.08,1.8),Vector2.LEFT)
	await process_frame
	check(area(house.render_polygons) < before and area(house.render_polygons) > before*.85,"damage removes only a local chip of artwork")
	check(house._cut_polygon(house.cuts[0]).size() >= 12,"damage boundary is smooth rather than a jagged wedge")
	for entity in [house,villager,grass]: entity.queue_free()
	finish()
func area(polys: Array) -> float:
	var total := 0.0
	for p in polys:
		for i in p.size(): total += p[i].cross(p[(i+1)%p.size()])*.5
	return absf(total)
func finish() -> void:
	print("TRAVERSAL: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
