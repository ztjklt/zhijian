class_name MedievalEntity
extends RigidBody2D
## Coordinates are metres, with Y up; textures are rendered by the paper canvas.

const PERSON_KINDS := ["villager","driver","general","knight","king","queen"]
const KINDS := ["oak", "pine", "house", "market", "wall", "tower", "gate", "barrel", "crate", "villager", "horse", "wagon", "dragon", "driver", "general", "knight", "king", "queen", "castle_piece"]
var entity_id := ""
var kind := "wall"
var size := Vector2.ONE
var health := 100.0
var max_health := 100.0
var alive := true
var state := "idle"
var facing := 1
var cuts: Array = []
var polygons: Array = []
var render_polygons: Array = []
var age := 0.0
var hurt_timer := 0.0
var patrol_turn_cooldown := 0.0
var patrol_half_width := 3.0
var home_x := 0.0
var ground_y := -2.8
var texture: Texture2D
var companion_id := ""
var reaction_texture: Texture2D
var source_rect := Rect2()
static var source_regions := {}
static var horse_hoof_rows: Array[int] = []
var _fixtures_pending := false
var person_visual: Node2D
var castle_visual: Node2D
var castle_descriptor: Dictionary = {}
var tree_roots: TreeRoots
var tree_mesh: ArrayMesh
const TreeRoots := preload("res://scripts/medieval_tree_roots.gd")
const Catalog := preload("res://scripts/medieval_catalog.gd")
const Fauna := preload("res://scripts/medieval_fauna.gd")
const WalkSurfaces := preload("res://scripts/medieval_walk_surfaces.gd")
const CastleLayout := preload("res://scripts/medieval_castle_layout.gd")
const CastleVisual := preload("res://scripts/medieval_castle_visual.gd")
const PersonScene := preload("res://scenes/character.tscn")
const PersonVisual := preload("res://scripts/medieval_person_visual.gd")

static func supported_kind(category: String) -> bool:
	return category in KINDS or Catalog.has_kind(category)

static func dimensions(category: String) -> Vector2:
	if Catalog.has_kind(category): return Catalog.dimensions(category)
	match category:
		"oak": return Vector2(3.3, 3.0)
		"pine": return Vector2(2.1, 4.5)
		"house": return Vector2(4.2, 3.6)
		"market": return Vector2(3.5, 2.54)
		"wall": return Vector2(3.0, 1.25)
		"tower": return Vector2(2.24, 5.4)
		"gate": return Vector2(4.0, 2.33)
		"barrel": return Vector2(0.7, 0.9)
		"crate": return Vector2(0.85, 0.8)
		"villager", "driver", "general", "knight", "king", "queen": return Vector2(0.5, 1.1)
		"horse": return Vector2(2.2, 1.7)
		"wagon": return Vector2(3.0, 1.04)
		"dragon": return Vector2(4.4, 2.8)
	return Vector2.ONE

static func initial_health(category: String) -> float:
	if Catalog.has_kind(category): return Catalog.health(category)
	match category:
		"wall", "tower", "gate", "castle_piece": return 240.0
		"house", "oak", "pine": return 150.0
		"villager", "driver": return 45.0
		"general", "knight": return 90.0
		"king", "queen": return 65.0
		"horse": return 90.0
		"dragon": return 180.0
	return 80.0

func setup(category: String, at: Vector2, stable_id: String, floor_y: float) -> void:
	kind = category
	patrol_half_width = 1.1 if kind in ["king","queen"] else 3.0
	entity_id = stable_id
	size = dimensions(kind)
	if kind == "castle_piece":
		castle_descriptor = CastleLayout.descriptor(entity_id)
		if not castle_descriptor.is_empty(): size = castle_descriptor.size
	max_health = initial_health(kind)
	health = max_health
	position = at
	home_x = at.x
	ground_y = floor_y
	freeze = not is_actor()
	freeze_mode = FREEZE_MODE_STATIC
	lock_rotation = true
	gravity_scale = 0.0 if kind in ["dragon","driver","bat"] else 1.0
	if Fauna.has_kind(kind): set_meta("fauna_home_y",at.y)
	mass = 2.0 if is_person() else 6.0
	if is_actor():
		var walking_material := Fauna.walk_material() if Fauna.has_kind(kind) else PhysicsMaterial.new()
		walking_material.friction = 0.0
		walking_material.rough = false
		physics_material_override = walking_material
	collision_layer = 64 if is_actor() else (0 if is_foliage() else 128)
	collision_mask = 9 if is_actor() else 0
	linear_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 8
	var asset: String = Catalog.definition(kind).get("path","res://assets/medieval/" + kind + ".png")
	if kind == "castle_piece" and not castle_descriptor.is_empty():
		texture = load(CastleLayout.ATLAS_PATH)
		var source_uv: Rect2 = castle_descriptor.source_uv
		source_rect = Rect2(source_uv.position*Vector2(texture.get_size()),source_uv.size*Vector2(texture.get_size()))
	elif not is_person() and ResourceLoader.exists(asset):
		texture = load(asset)
		if Fauna.has_kind(kind):
			if not source_regions.has(kind): source_regions[kind] = Fauna.regions(kind)
			source_rect = source_regions[kind][0]
			rebuild_geometry()
			return
		if not source_regions.has(kind):
			var image := texture.get_image()
			var cells: Array = []
			var columns := 4 if kind in ["villager","horse","dragon"] else 1
			var rows := 2 if kind in ["villager","horse","dragon"] else 1
			var cell := image.get_size() / Vector2i(columns,rows)
			for row in rows:
				for column in columns:
					var used := Rect2i()
					var found := false
					for y in range(row*cell.y,(row+1)*cell.y,3):
						for x in range(column*cell.x,(column+1)*cell.x,3):
							if image.get_pixel(x,y).a > 0.05:
								if not found: used = Rect2i(x,y,1,1); found = true
								else: used = used.expand(Vector2i(x,y))
					if found: used = used.grow(3).intersection(Rect2i(Vector2i(column,row)*cell,cell))
					else: used = Rect2i(Vector2i(column,row)*cell,cell)
					cells.append(Rect2(used))
			# Walking poses share one cell-local envelope; flight shares all eight.
			# This retains baseline, body scale and wing motion across the sheet.
			if kind in ["villager","horse","dragon"]:
				var shared_count := 8 if kind == "dragon" else 4
				var shared := Rect2()
				for index in shared_count:
					var local_region: Rect2 = cells[index]
					local_region.position -= Vector2((index%4)*cell.x,floori(index/4.0)*cell.y)
					shared = local_region if index == 0 else shared.merge(local_region)
				for index in shared_count:
					cells[index] = Rect2(shared.position+Vector2((index%4)*cell.x,floori(index/4.0)*cell.y),shared.size)
			source_regions[kind] = cells
		source_rect = source_regions[kind][0]
		if kind == "horse" and horse_hoof_rows.is_empty(): _cache_horse_hooves()
	rebuild_geometry()

func is_foliage() -> bool: return Catalog.has_kind(kind) and Catalog.category(kind) == "foliage"

func walk_segments() -> Array: return WalkSurfaces.remaining(self)

func world_walk_segments() -> Array:
	var result: Array = []
	for edge in walk_segments(): result.append([to_global(edge[0]),to_global(edge[1])])
	return result

func is_person() -> bool: return kind in PERSON_KINDS

func _ready() -> void:
	WalkSurfaces.configure_actor(self)
	WalkSurfaces.register_surfaces(self)
	if is_person() and get_parent() != null:
		ensure_person_visual(get_parent().get("game"))
	elif kind == "castle_piece" and get_parent() != null:
		ensure_castle_visual(get_parent().get("game"))

func ensure_person_visual(context) -> void:
	if not is_person() or context == null or not is_inside_tree(): return
	if is_instance_valid(person_visual):
		person_visual.game = context
		return
	person_visual = PersonScene.instantiate()
	person_visual.set_script(PersonVisual)
	person_visual.entity = self
	person_visual.game = context
	person_visual.name = "PersonVisual_"+entity_id
	# Rendering is in canvas pixels, whereas this rigid body is in world metres.
	get_parent().add_child(person_visual)

func ensure_castle_visual(context) -> void:
	if kind != "castle_piece" or context == null or not is_inside_tree(): return
	if is_instance_valid(castle_visual):
		castle_visual.game = context
		return
	castle_visual = CastleVisual.new()
	castle_visual.entity = self
	castle_visual.game = context
	castle_visual.name = "CastleVisual_"+entity_id
	get_parent().add_child(castle_visual)

func _exit_tree() -> void:
	if is_instance_valid(castle_visual):
		castle_visual.hide()
		castle_visual.queue_free()
	castle_visual = null
	if is_instance_valid(person_visual):
		person_visual.hide()
		person_visual.queue_free()
	person_visual = null

func is_actor() -> bool: return is_person() or kind in ["horse", "dragon"] or Fauna.has_kind(kind)

func is_ground_animal() -> bool: return kind in ["horse", "rabbit", "deer"]

func _outline() -> Array:
	if Fauna.has_kind(kind): return Fauna.outline(self)
	if kind == "castle_piece": return castle_descriptor.get("polygons",[]).duplicate(true)
	var half := size.x * 0.5
	if kind == "wagon":
		return preload("res://scripts/medieval_terrain.gd").wagon_geometry(source_rect,size,facing)
	if kind == "gate":
		# The gate arch stays open to both people and projectiles.
		return [PackedVector2Array([Vector2(-half,0),Vector2(-half+0.62,0),Vector2(-half+0.62,size.y-0.9),Vector2(-half,size.y-0.9)]), PackedVector2Array([Vector2(half-0.62,0),Vector2(half,0),Vector2(half,size.y-0.9),Vector2(half-0.62,size.y-0.9)]), PackedVector2Array([Vector2(-half,size.y-0.9),Vector2(half,size.y-0.9),Vector2(half,size.y),Vector2(-half,size.y)])]
	if kind == "house":
		return [PackedVector2Array([Vector2(-half,0),Vector2(half,0),Vector2(half,2.4),Vector2(0,size.y),Vector2(-half,2.4)])]
	if kind in ["oak", "pine"]:
		# Trunk and individual canopy envelope, not a filled tree bounding box.
		return [PackedVector2Array([Vector2(-0.2,0),Vector2(0.2,0),Vector2(0.2,size.y*0.55),Vector2(-0.2,size.y*0.55)]), PackedVector2Array([Vector2(-half,size.y*0.44),Vector2(half,size.y*0.44),Vector2(half*0.8,size.y*0.82),Vector2(0,size.y),Vector2(-half*0.8,size.y*0.82)])]
	if kind == "market":
		return [PackedVector2Array([Vector2(-half,0),Vector2(half,0),Vector2(half,0.9),Vector2(-half,0.9)]),PackedVector2Array([Vector2(-half,2.1),Vector2(half,2.1),Vector2(half*0.75,size.y),Vector2(-half*0.75,size.y)]),PackedVector2Array([Vector2(-half,0.9),Vector2(-half+0.12,0.9),Vector2(-half+0.12,2.1),Vector2(-half,2.1)]),PackedVector2Array([Vector2(half-0.12,0.9),Vector2(half,0.9),Vector2(half,2.1),Vector2(half-0.12,2.1)])]
	if is_actor():
		var w := half * 0.67
		if not alive:
			return [PackedVector2Array([Vector2(-size.y*0.42,0),Vector2(size.y*0.42,0),Vector2(size.y*0.42,0.23),Vector2(-size.y*0.42,0.23)])]
		var feet := 0.35 if kind == "driver" and companion_id != "" else 0.05
		return [PackedVector2Array([Vector2(-w,feet),Vector2(w,feet),Vector2(w,size.y*0.78),Vector2(w*0.65,size.y*0.94),Vector2(-w*0.65,size.y*0.94),Vector2(-w,size.y*0.78)])]
	return [PackedVector2Array([Vector2(-half,0),Vector2(half,0),Vector2(half,size.y),Vector2(-half,size.y)])]

func _cut_polygon(cut: Dictionary) -> PackedVector2Array:
	# A small round bite touching the artwork boundary. Internal impact points
	# project to the nearest outline so clipping never silently discards a hole.
	var center := Vector2(cut.x,cut.y)
	var closest := center
	var outward := Vector2.UP
	var distance := INF
	for outline in _outline():
		for i in outline.size():
			var point := Geometry2D.get_closest_point_to_segment(center,outline[i],outline[(i+1)%outline.size()])
			if point.distance_squared_to(center) < distance:
				distance = point.distance_squared_to(center)
				closest = point
				var edge: Vector2 = outline[(i+1)%outline.size()]-outline[i]
				outward = Vector2(edge.y,-edge.x).normalized()
				if Geometry2D.is_polygon_clockwise(outline): outward = -outward
	var r: float = cut.radius
	var points := PackedVector2Array()
	var tangent := outward.orthogonal()
	for i in 17:
		var angle := PI*.5+PI*i/16.0
		points.append(closest+outward*cos(angle)*r+tangent*sin(angle)*r)
	var extent := maxf(size.x,size.y)+1.0
	points.append(closest+outward*extent-tangent*r)
	points.append(closest+outward*extent+tangent*r)
	return points

func _clip_cuts(geometry: Array) -> Array:
	var result := geometry
	for cut in cuts:
		var remaining: Array = []
		for polygon in result:
			for piece in Geometry2D.clip_polygons(polygon, _cut_polygon(cut)):
				if piece.size() >= 3 and not Geometry2D.is_polygon_clockwise(piece): remaining.append(piece)
		result = remaining
	return result

func rebuild_geometry() -> void:
	polygons = _clip_cuts(_outline())
	if tree_roots != null:
		for i in polygons.size(): polygons[i] = tree_roots.fit_polygon(polygons[i])
	# Original transparent art may extend beyond its simple physical silhouette.
	# Only actual damage cuts may crop that art; an initial collider never does.
	var half := size.x * 0.5
	render_polygons = _clip_cuts([PackedVector2Array([Vector2(-half,0),Vector2(half,0),Vector2(half,size.y),Vector2(-half,size.y)])])
	if not alive and not is_actor():
		polygons.clear()
		render_polygons.clear()
		if is_foliage():
			var stubble := minf(.085,size.y*.18)
			render_polygons.append(PackedVector2Array([Vector2(-half,0),Vector2(half,0),Vector2(half,stubble),Vector2(-half,stubble)]))
	if tree_roots != null: tree_mesh = tree_roots.build_mesh(self)
	if is_inside_tree():
		if not _fixtures_pending:
			_fixtures_pending = true
			_rebuild_fixtures.call_deferred()
	else: _rebuild_fixtures()

func _rebuild_fixtures() -> void:
	_fixtures_pending = false
	for child in get_children():
		if child is CollisionShape2D:
			remove_child(child)
			child.queue_free()
	if Fauna.has_kind(kind): add_child(Fauna.fixture(self))
	else:
		for polygon in polygons:
			for piece in Geometry2D.decompose_polygon_in_convex(polygon):
				var fixture := CollisionShape2D.new()
				var shape := ConvexPolygonShape2D.new()
				shape.points = piece
				fixture.shape = shape
				add_child(fixture)
	collision_layer = (64 if is_actor() else (0 if is_foliage() else 128)) if alive else 0
	WalkSurfaces.rebuild(self)
	if not cuts.is_empty() or not alive: _wake_nearby_bodies.call_deferred()

func _wake_nearby_bodies() -> void:
	if not is_inside_tree() or is_actor(): return
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size+Vector2(1.4,1.4)
	query.shape = shape
	query.transform = Transform2D(rotation,to_global(Vector2(0,size.y*.5)))
	query.collision_mask = 75
	for hit in get_world_2d().direct_space_state.intersect_shape(query,64):
		var body = hit.collider
		if body is RigidBody2D and not body.freeze:
			body.sleeping = false
			# Removing a frozen support does not wake a sleeping body in Godot.
			# This tiny downward nudge lets gravity resume on the next tick.
			body.linear_velocity.y = minf(body.linear_velocity.y,-.08)

func contains_world_point(point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(to_local(point), polygon): return true
	return false

func world_polygons() -> Array:
	var result: Array = []
	for polygon in polygons:
		var points := PackedVector2Array()
		for point in polygon: points.append(to_global(point))
		result.append(points)
	return result

func damage(amount: float, point: Vector2, impulse: Vector2) -> void:
	if not alive or not is_finite(amount) or amount <= 0: return
	health = maxf(0, health - minf(amount, 1000))
	hurt_timer = 0.6
	state = "hurt"
	if is_actor():
		if kind == "driver": detach_carriage()
		linear_velocity += impulse.limit_length(18)
		if absf(impulse.x) > 0.1: facing = 1 if impulse.x > 0 else -1
	elif health > 0 and cuts.size() < 12:
		var local := local_to_art(to_local(point))
		local.x = clampf(local.x, -size.x*0.5, size.x*0.5)
		local.y = clampf(local.y, 0, size.y)
		var distances := [absf(local.x+size.x*0.5),absf(size.x*0.5-local.x),absf(local.y),absf(size.y-local.y)]
		var side: int = distances.find(distances.min())
		cuts.append({"x": local.x, "y": local.y, "radius": clampf(0.25 + amount*0.01,0.3,0.8), "side": side})
	if health <= 0:
		alive = false
		state = "fall" if is_actor() else "destroyed"
		if kind=="bat": gravity_scale=1.0
	if not Fauna.has_kind(kind) or not alive: rebuild_geometry()

func detach_carriage() -> void:
	companion_id = ""
	if is_inside_tree() and freeze: _enable_carriage_physics.call_deferred()
	else: _enable_carriage_physics()

func _enable_carriage_physics() -> void:
	# Body mode changes must wait until an ink-impact query has finished flushing.
	var launch_velocity := linear_velocity
	freeze = false
	collision_layer = 64 if alive else 0
	gravity_scale = 1.0
	collision_mask = 9
	linear_velocity = launch_velocity

func step(delta: float) -> void:
	age += delta
	patrol_turn_cooldown = maxf(0,patrol_turn_cooldown-delta)
	hurt_timer = maxf(0, hurt_timer-delta)
	if Fauna.has_kind(kind):
		Fauna.step(self,delta)
		return
	if not is_actor(): return
	if kind == "driver" and alive and companion_id != "": return
	if not alive:
		if hurt_timer <= 0: state = "dead"
		if kind == "dragon": gravity_scale = 1.0
		return
	if hurt_timer > 0: return
	state = "walk" if kind != "dragon" else "fly"
	if kind == "dragon":
		linear_velocity = Vector2(cos(age*0.37)*1.5,cos(age*0.9)*0.65)
		facing = 1 if linear_velocity.x > 0 else -1
	else:
		if position.x > home_x+patrol_half_width: facing = -1
		elif position.x < home_x-patrol_half_width: facing = 1
		linear_velocity.x = facing * (0.4 if is_person() else 0.55)
	position.x = clampf(position.x, 0.5, Catalog.WORLD_LENGTH-0.5)

func frame_index() -> int:
	if Fauna.has_kind(kind): return Fauna.frame_index(self)
	if kind == "dragon": return int(age * 8) % 8 if alive else 7
	if kind not in ["villager", "horse", "driver"]: return 0
	if kind == "driver" and companion_id != "" and alive: return 0
	if state == "dead": return 6
	if state == "fall": return 5
	if hurt_timer > 0: return 4
	return int(age * 6) % 4

func bounds() -> Rect2:
	return Rect2(position + Vector2(-size.x*0.5,0),size)

func texture_uv(local: Vector2) -> Vector2:
	var u := local.x/size.x+0.5
	if kind == "wagon" and facing > 0: u = 1.0-u
	return (source_rect.position + Vector2(u,1-local.y/size.y)*source_rect.size) / Vector2(texture.get_size())

func art_to_local(point: Vector2) -> Vector2:
	return tree_roots.fit(point) if tree_roots != null else point

func local_to_art(point: Vector2) -> Vector2:
	return tree_roots.unfit(point) if tree_roots != null else point

func _cache_horse_hooves() -> void:
	var image := texture.get_image()
	for frame in 4:
		var source: Rect2 = source_regions["horse"][frame]
		var bottom := int(source.end.y)
		for y in range(int(source.end.y)-1,int(source.position.y)-1,-1):
			var found := false
			for x in range(int(source.position.x),int(source.end.x)):
				if image.get_pixel(x,y).a > 0.05:
					bottom = y+1
					found = true
					break
			if found: break
		horse_hoof_rows.append(bottom)

func raster_actor_frame_draw(frame: int) -> Dictionary:
	if Fauna.has_kind(kind): return Fauna.frame_draw(self,frame)
	var source: Rect2 = source_regions[kind][clampi(frame,0,7)]
	var draw_size := Vector2(size.y*source.size.x/maxf(1,source.size.y),size.y)
	if draw_size.x > size.x: draw_size *= size.x/draw_size.x
	if not alive:
		draw_size.x = maxf(size.x,size.y)*1.05
		draw_size.y = draw_size.x*source.size.y/maxf(1,source.size.x)
		if kind == "dragon": draw_size.y *= 0.42
	var rect := Rect2(Vector2(-draw_size.x*0.5,-draw_size.y),draw_size)
	var grounded := false
	if kind == "horse" and alive and hurt_timer <= 0 and frame < 4 and absf(linear_velocity.y) <= 1.0 and get_parent() != null:
		var terrain = get_parent().get("terrain")
		if terrain != null and terrain.has_method("support_pose"):
			var support: Dictionary = terrain.support_pose(position.x,size.x*0.335,0.05)
			grounded = absf(position.y-support.position_y) <= 0.22
	if grounded and horse_hoof_rows.size() == 4:
		# Preserve the shared source envelope and constant horse dimensions; move
		# only the tiny transparent hoof padding, never rescale individual poses.
		var hoof_y: float = rect.position.y+float(horse_hoof_rows[frame]-source.position.y)/source.size.y*rect.size.y
		rect.position.y += -0.05-hoof_y
	return {"source":source,"rect":rect,"mirror":-facing if kind == "horse" else facing,"grounded":grounded}

func _draw_raster_actor(canvas: Node2D, game, frame: int, tint: Color) -> void:
	var draw := raster_actor_frame_draw(frame)
	var rect: Rect2 = draw.rect
	rect.position *= game.PIXELS_PER_UNIT
	rect.size *= game.PIXELS_PER_UNIT
	# Mirroring belongs to the pivot transform. Negative texture rectangles are
	# normalized by Canvas drawing and can shift the horse a full width downhill.
	canvas.draw_set_transform(game.world_to_screen(position),-rotation,Vector2(draw.mirror,1))
	canvas.draw_texture_rect_region(texture,rect,draw.source,tint,false,true)
	canvas.draw_set_transform(Vector2.ZERO)

func draw_entity(canvas: Node2D, game) -> void:
	if kind == "castle_piece":
		ensure_castle_visual(game)
		return
	if is_person():
		ensure_person_visual(game)
		return
	if texture == null or (not alive and not is_actor() and not is_foliage()): return
	var screen_scale: float = game.PIXELS_PER_UNIT
	var tint := Color(1,1,1,0.45 if hurt_timer > 0 and int(age*18)%2 == 0 else 1.0)
	if is_actor():
		var frame := frame_index()
		if kind in ["horse","dragon"] or Fauna.has_kind(kind):
			_draw_raster_actor(canvas,game,frame,tint)
			return
		var reaction := kind == "driver" and companion_id == "" and reaction_texture != null
		var actor_texture: Texture2D = reaction_texture if reaction else texture
		var sheet_kind := "villager" if reaction else kind
		var frame_size := Vector2(actor_texture.get_size()) / Vector2(4,2)
		var source: Rect2 = source_regions[sheet_kind][frame] if source_regions.has(sheet_kind) else Rect2(Vector2(frame%4,frame/4)*frame_size,frame_size)
		var target_size := Vector2(size.y * source.size.x / maxf(1,source.size.y),size.y)
		if target_size.x > size.x: target_size *= size.x / target_size.x
		if not alive:
			target_size.x = maxf(size.x,size.y)*1.05
			target_size.y = target_size.x * source.size.y / maxf(1,source.size.x)
			if kind == "dragon": target_size.y *= 0.42
		var rect := Rect2(game.world_to_screen(position+Vector2(-target_size.x*0.5,target_size.y)),target_size*screen_scale)
		if facing * (-1 if kind in ["horse","driver"] and not reaction else 1) < 0:
			rect.position.x += rect.size.x
			rect.size.x *= -1
		canvas.draw_texture_rect_region(actor_texture,rect,source,tint,false,true)
	else:
		if tree_mesh != null:
			if tree_mesh.get_surface_count()>0:
				canvas.draw_set_transform(game.world_to_screen(position),-rotation,Vector2.ONE*screen_scale)
				canvas.draw_mesh(tree_mesh,texture,Transform2D.IDENTITY,tint)
				canvas.draw_set_transform(Vector2.ZERO)
			return
		# UV clipping preserves the original generated art while exposing paper at cuts.
		# Triangulate in local units. A tangent cut can become self-touching after
		# float32 screen translation/rotation, even when its local polygon is valid.
		canvas.draw_set_transform(game.world_to_screen(global_position),-global_rotation,global_scale*screen_scale)
		for polygon in render_polygons:
			var points := PackedVector2Array()
			var uvs := PackedVector2Array()
			for p in polygon:
				points.append(Vector2(p.x,-p.y))
				uvs.append(texture_uv(p))
			canvas.draw_polygon(points,PackedColorArray([tint]),uvs,texture)
		canvas.draw_set_transform(Vector2.ZERO)
func save_record() -> Dictionary:
	return {"id":entity_id,"kind":kind,"x":position.x,"y":position.y,"home_x":home_x,"health":health,"alive":alive,"state":state,"facing":facing,"vx":linear_velocity.x,"vy":linear_velocity.y,"cuts":cuts.duplicate(true),"companion":companion_id}
