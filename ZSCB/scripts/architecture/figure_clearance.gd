extends Node2D
## Feather just the ink behind a nearby silhouette. The paper rim is confined
## to the figure and appears only where scenery or an object really overlaps.
var world
var contacts := []
var masks := {}
var next_probe := 0.0
var feather: ArrayMesh

func _ready() -> void:
	world = get_parent()
	z_index = 2
	feather = _paper_rim()

func _process(delta: float) -> void:
	next_probe -= delta
	if next_probe <= 0:
		next_probe = .09
		contacts.clear()
		var game = world.game
		if not is_instance_valid(game.player): return
		var figures := [{"body":game.player,"lift":0.12}]
		for role in ["SandboxCompanion","SandboxAdventurer","SandboxPriest"]:
			var agent = world.get_node_or_null(role)
			if agent != null and "actor" in agent and agent.actor != null:
				figures.append({"body":agent.actor.player,"lift":0.12})
		for entity in world.entities:
			if entity.alive and entity.is_person() and absf(entity.position.x-game.view_camera().x)<10.0:
				figures.append({"body":entity,"lift":.47})
		for figure in figures:
			var center: Vector2 = figure.body.position + Vector2(0,figure.lift)
			if _over_ink(center): contacts.append(figure)
	queue_redraw()

func _over_ink(center: Vector2) -> bool:
	# Reject by bounds first, then test real pigment to keep archways transparent.
	for entity in world.entities:
		if entity.texture == null or not entity.alive or entity.is_actor(): continue
		if absf(entity.position.x-center.x) > entity.size.x*.65+.65: continue
		for step in [Vector2.ZERO,Vector2(-.14,.22),Vector2(.16,.33),Vector2(0,-.26)]:
			var p: Vector2 = entity.local_to_art(entity.to_local(center+step))
			if absf(p.x)>entity.size.x*.5 or p.y<0 or p.y>entity.size.y: continue
			if not entity.cuts.is_empty() and not entity.render_polygons.any(func(poly):return Geometry2D.is_point_in_polygon(p,poly)): continue
			var key: String = entity.texture.resource_path
			if not masks.has(key):
				var mask := BitMap.new()
				mask.create_from_image_alpha(entity.texture.get_image(),0.13)
				masks[key] = mask
			var pixel := Vector2i(entity.texture_uv(p)*entity.texture.get_size())
			var limit: Vector2i = masks[key].get_size()
			if Rect2i(Vector2i.ZERO,limit).has_point(pixel) and masks[key].get_bitv(pixel): return true
	# The guild is a village service painted directly onto the street canvas.
	# Its counter shares the same local fade as a player-drawn scenery object.
	var village = world.survival
	if village != null and absf(center.x-village.Guild.COUNTER_X)<1.35 and village.has_meta("guild_porch_ink"):
		var hit := preload("res://scripts/pen_selection.gd").edge_near(village.get_meta("guild_porch_ink"),center)
		if hit.inside_wash or hit.distance<.25: return true
	for body in world.game.object_nodes:
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var p: Vector2 = body.to_local(center)
		if not body.pick_bounds.grow(.22).has_point(p): continue
		if body.data.get("pen") == "draw_scenery":
			var hit := preload("res://scripts/pen_selection.gd").edge_near(body.damage_paths,p)
			if hit.inside_wash or hit.distance<.22: return true
		elif preload("res://scripts/structure_links.gd").material_distance(body.damage_prepared,p)<.22: return true
	return false

func _draw() -> void:
	if world == null or feather == null: return
	for figure in contacts:
		if not is_instance_valid(figure.body): continue
		var center: Vector2 = figure.body.position+Vector2(0,figure.lift)
		draw_set_transform(world.game.world_to_screen(center),0,Vector2.ONE*world.game.PIXELS_PER_UNIT)
		draw_mesh(feather,null)
		if figure.body==world.game.player and world.terrain.in_water(figure.body.position):
			_draw_swimming_arms()
	draw_set_transform(Vector2.ZERO)

## Swimming hands rise outside the standing silhouette. Feather the drawn ink
## immediately behind the actual forearm joints when passing a pier.
func _draw_swimming_arms() -> void:
	var visual:Node2D=world.game.character_visual
	if not is_instance_valid(visual):return
	for arm in ["BackArm","FrontArm"]:
		var forearm:Node2D=visual.get_node("Skeleton/Hips/Torso/"+arm+"/Forearm")
		var hand:Node2D=forearm.get_node("Hand")
		var a:=forearm.global_position
		var b:=hand.global_position
		var center:=(a+b)*.5
		var length:=a.distance_to(b)
		draw_set_transform(center,(b-a).angle()-PI/2,Vector2(23,(length+16)/1.44))
		draw_mesh(feather,null)

static func _paper_rim() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var paper := Color("faf7eb")
	var radii := [.015,.56,1.0]
	var opacity := [.85,.78,0.0]
	for ring in radii.size():
		for i in 24:
			var a := TAU*i/24
			vertices.append(Vector2(cos(a)*.40,sin(a)*.72)*radii[ring])
			colors.append(Color(paper,opacity[ring]))
			if ring<2:
				var k := ring*24+i
				var next := ring*24+(i+1)%24
				indices.append_array(PackedInt32Array([k,next,k+24,next,next+24,k+24]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
