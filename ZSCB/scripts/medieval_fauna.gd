class_name MedievalFauna
extends RefCounted
## Three generated sheets, premeasured once: no image readback during draw/step.
const KINDS := ["rabbit","deer","bat"]
const FRAMES := "res://assets/medieval/fauna/frames.json"
static var _frames: Dictionary = {}
static var _shapes: Dictionary = {}
static var _outlines: Dictionary = {}
static var _walk_material: PhysicsMaterial

static func has_kind(kind: String) -> bool: return kind in KINDS

static func walk_material() -> PhysicsMaterial:
	if _walk_material==null:
		_walk_material=PhysicsMaterial.new()
		_walk_material.friction=0.0
		_walk_material.rough=false
	return _walk_material

static func metadata(kind: String) -> Dictionary:
	if _frames.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(FRAMES))
		if parsed is Dictionary: _frames = parsed
	return _frames.get(kind,{})

static func regions(kind: String) -> Array:
	var data := metadata(kind)
	if data.has("atlas_regions"):
		var atlas: Array = []
		for rect in data.atlas_regions: atlas.append(Rect2(rect[0],rect[1],rect[2],rect[3]))
		return atlas
	var cell := Vector2(data.cell[0],data.cell[1])
	var envelope := Rect2(data.envelope[0],data.envelope[1],data.envelope[2],data.envelope[3])
	var result: Array = []
	for i in 8: result.append(Rect2(Vector2(i%4,i/4)*cell+envelope.position,envelope.size))
	return result

static func outline(entity) -> Array:
	var key: String = entity.kind+("-alive" if entity.alive else "-dead")
	if not _outlines.has(key):
		var half: float = entity.size.x*.335
		var top: float = entity.size.y*.92 if entity.alive else maxf(.18,entity.size.y*.25)
		_outlines[key] = [PackedVector2Array([Vector2(-half,.05),Vector2(half,.05),Vector2(half,top),Vector2(-half,top)])]
	return _outlines[key]

static func fixture(entity) -> CollisionShape2D:
	var key: String = entity.kind+("-alive" if entity.alive else "-dead")
	if not _shapes.has(key):
		var shape := ConvexPolygonShape2D.new()
		shape.points = outline(entity)[0]
		_shapes[key] = shape
	var result := CollisionShape2D.new()
	result.shape = _shapes[key]
	return result

static func step(entity,delta: float) -> void:
	if not entity.alive:
		entity.gravity_scale = 1.0
		if entity.hurt_timer<=0: entity.state="dead"
		return
	if entity.hurt_timer>0: return
	if entity.kind=="bat":
		entity.state="fly"
		var center_y: float = entity.get_meta("fauna_home_y",entity.position.y)
		var target_y: float = center_y+sin(entity.age*1.9)*.45
		entity.linear_velocity.y = clampf((target_y-entity.position.y)*2.5,-1.2,1.2)
		entity.linear_velocity.x = entity.facing*1.05
	else:
		entity.state="walk"
		entity.linear_velocity.x = entity.facing*(.72 if entity.kind=="rabbit" else .82)
	if entity.position.x>entity.home_x+entity.patrol_half_width: entity.facing=-1
	elif entity.position.x<entity.home_x-entity.patrol_half_width: entity.facing=1
	if entity.position.x<.5: entity.facing=1
	elif entity.position.x>179.5: entity.facing=-1
	entity.position.x = clampf(entity.position.x,.5,179.5)

static func frame_index(entity) -> int:
	if entity.state=="dead": return 6
	if not entity.alive or entity.state=="fall": return 5
	if entity.hurt_timer>0: return 4
	return int(entity.age*(9.0 if entity.kind=="bat" else 6.0))%4

static func frame_draw(entity,frame: int) -> Dictionary:
	var source: Rect2 = regions_cached(entity)[clampi(frame,0,7)]
	var data := metadata(entity.kind)
	if data.has("atlas_regions"):
		var pixel_scale: float = minf(entity.size.x/float(data.envelope[2]),entity.size.y/float(data.envelope[3]))
		var index := clampi(frame,0,7)
		var origin := Vector2(data.atlas_origins[index][0],data.atlas_origins[index][1])
		var anchor := origin+Vector2(float(data.envelope[0])+float(data.envelope[2])*.5,float(data.envelope[1])+float(data.envelope[3]))
		var atlas_rect := Rect2((source.position-anchor)*pixel_scale,source.size*pixel_scale)
		if not entity.alive: atlas_rect.position.y=-.05-atlas_rect.size.y
		return {"source":source,"rect":atlas_rect,"mirror":entity.facing,"grounded":false,"pixel_scale":pixel_scale,"anchor":anchor}
	var draw_size := Vector2(entity.size.y*source.size.x/source.size.y,entity.size.y)
	if draw_size.x>entity.size.x: draw_size*=entity.size.x/draw_size.x
	var rect := Rect2(Vector2(-draw_size.x*.5,-draw_size.y),draw_size)
	var grounded := false
	if entity.kind!="bat" and entity.alive and entity.hurt_timer<=0 and frame<4 and absf(entity.linear_velocity.y)<=1 and entity.get_parent()!=null:
		var terrain = entity.get_parent().get("terrain")
		if terrain!=null and terrain.has_method("support_pose"):
			var pose: Dictionary = terrain.support_pose(entity.position.x,entity.size.x*.335,.05)
			grounded = absf(entity.position.y-pose.position_y)<=.22
	# Translate padding only: every pose keeps exactly the same pixel scale.
	if grounded or not entity.alive:
		var bottom: float = float(data.bottoms[clampi(frame,0,7)])-float(data.envelope[1])
		var visible_bottom: float = rect.position.y+bottom/source.size.y*draw_size.y
		rect.position.y += -.05-visible_bottom
	return {"source":source,"rect":rect,"mirror":entity.facing,"grounded":grounded}

static func regions_cached(entity) -> Array:
	return entity.source_regions[entity.kind]
