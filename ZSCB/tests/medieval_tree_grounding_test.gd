extends SceneTree
## Regressions: horizontal PNG roots on slopes, stale saved roots, lost cuts.
var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ",label)

func mesh_point(arrays: Array, uv: Vector2) -> Vector2:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in range(0,vertices.size(),3):
		var a := uvs[i]
		var b := uvs[i+1]
		var c := uvs[i+2]
		if uv.x<minf(a.x,minf(b.x,c.x))-.000001 or uv.x>maxf(a.x,maxf(b.x,c.x))+.000001: continue
		var denominator := (b-a).cross(c-a)
		if absf(denominator)<.000000000001: continue
		var beta := (uv-a).cross(c-a)/denominator
		var gamma := (b-a).cross(uv-a)/denominator
		if minf(beta,minf(gamma,1-beta-gamma))<-.00001: continue
		var point := vertices[i]*(1-beta-gamma)+vertices[i+1]*beta+vertices[i+2]*gamma
		return Vector2(point.x,-point.y)
	return Vector2.INF

func check_roots(world, tree, label: String) -> void:
	var image: Image = tree.texture.get_image()
	var source: Rect2 = tree.source_rect
	var min_gap := INF
	var max_gap := -INF
	var samples := 0
	var mesh: ArrayMesh = tree.get("tree_mesh")
	var arrays: Array = mesh.surface_get_arrays(0) if mesh!=null and mesh.get_surface_count()>0 else []
	check(not arrays.is_empty(),label+" has fitted rendering")
	# Independently read visible feet, not the crop's transparent bottom edge.
	for x in range(int(source.position.x),int(source.end.x),5):
		# The lowest 8% contains the root flare; low side branches are not feet.
		for y in range(int(source.end.y)-1,int(source.end.y-source.size.y*.08),-1):
			if image.get_pixel(x,y).a < .12: continue
			var local: Vector2 = Vector2((float(x)-source.position.x)/source.size.x-.5,1-(float(y)-source.position.y)/source.size.y)*tree.size
			var fitted: Vector2 = tree.art_to_local(local) if tree.has_method("art_to_local") else local
			if not arrays.is_empty():
				fitted = mesh_point(arrays,(source.position+Vector2(float(x)-source.position.x,float(y)-source.position.y))/Vector2(image.get_size()))
				if not fitted.is_finite() and not tree.cuts.is_empty(): break
				if not fitted.is_finite():
					check(false,label+" rendered mesh covers visible roots")
					return
			var point: Vector2 = tree.to_global(fitted)
			var ground: float = world.surface_height(point.x)
			var query := PhysicsRayQueryParameters2D.create(Vector2(point.x,ground+.12),Vector2(point.x,ground-.12),1)
			var hit: Dictionary = world.get_world_2d().direct_space_state.intersect_ray(query)
			# A nearby haystack/fence can have a landing just above the soil.
			# This regression measures the terrain, rather than those platforms.
			while not hit.is_empty() and hit.collider.name!="MountainRiverSoil":
				var excluded := query.exclude
				excluded.append(hit.collider.get_rid())
				query.exclude = excluded
				hit = world.get_world_2d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				check(false,label+" has physical soil under its roots")
				return
			var gap: float = point.y-hit.position.y
			min_gap = minf(min_gap,gap)
			max_gap = maxf(max_gap,gap)
			samples += 1
			break
	check(samples>8,label+" measures actual root ink")
	check(min_gap>=-.025 and max_gap<=.025,label+" root/soil gaps ["+str(min_gap)+", "+str(max_gap)+"]")
	check(absf(tree.rotation)<.00001,label+" keeps trunk upright")
	var upper := Vector2(.1,tree.size.y*.6)
	var upper_fitted: Vector2 = tree.art_to_local(upper) if tree.has_method("art_to_local") else upper
	check(upper.is_equal_approx(upper_fitted),label+" preserves canopy and upper trunk")

func run() -> void:
	var world := MedievalWorld.new()
	root.add_child(world)
	await physics_frame
	for tree in world.entities:
		if tree.kind in ["oak","pine","orchard_tree"]:
			check_roots(world,tree,tree.entity_id)
	# A real opaque bark pixel in the uphill orchard used to drift 8.7cm
	# inside a tall, simplified strip even though its root contact row was exact.
	var orchard = world.entity_by_id("orchard_tree-103")
	var original := Vector2(.829854,.826667)
	var bark_uv: Vector2 = (orchard.source_rect.position+Vector2(original.x/orchard.size.x+.5,1-original.y/orchard.size.y)*orchard.source_rect.size)/Vector2(orchard.texture.get_size())
	var bark := mesh_point(orchard.tree_mesh.surface_get_arrays(0),bark_uv)
	check(bark.distance_to(orchard.art_to_local(original))<.006,"interior bark render matches collision deformation")
	check(orchard.local_to_art(bark).distance_to(original)<.012,"interior bark hit resolves to its source pixel")
	# The same large tree must fit level soil, either slope, and a terrain knot.
	for x in [30.0,5.0,13.0,10.0]:
		var tree = world._spawn("oak",x,200)
		tree.size *= 2
		world._place_ground_prop(tree)
		await physics_frame
		check_roots(world,tree,"large oak at "+str(x))
		world.entities.erase(tree)
		world.remove_child(tree)
		tree.queue_free()
	var damaged = world.entity_by_id("oak-0")
	damaged.damage(20,damaged.position+Vector2(0,1),Vector2.ZERO)
	var source: Rect2 = damaged.source_rect
	var uv: Vector2 = (source.position+Vector2(.5,1-.4/damaged.size.y)*source.size)/Vector2(damaged.texture.get_size())
	var drawn_root := mesh_point(damaged.tree_mesh.surface_get_arrays(0),uv)
	damaged.damage(1,damaged.to_global(drawn_root),Vector2.ZERO)
	check(absf(damaged.cuts[-1].y-.4)<.015,"root hit uses rendered position and stores original art coordinates")
	var saved := world.save_state()
	var saved_cuts: Array = damaged.cuts.duplicate(true)
	for record in saved:
		if record.id=="oak-0": record.y += 1.5
	check(world.restore_state(saved),"old world with stale root height still loads")
	await physics_frame
	check_roots(world,world.entity_by_id("oak-0"),"loaded damaged oak")
	check(world.entity_by_id("oak-0").cuts==saved_cuts,"ground repair preserves saved damage")
	check(is_equal_approx(world.entity_by_id("oak-0").health,129),"ground repair preserves health")
	var y: float = world.entity_by_id("oak-0").position.y
	check(world.restore_state(world.save_state()),"corrected world can load again")
	await physics_frame
	check(is_equal_approx(world.entity_by_id("oak-0").position.y,y),"repeat load does not drift tree height")
	world.queue_free()
	await process_frame
	print("MEDIEVAL TREE GROUNDING: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
