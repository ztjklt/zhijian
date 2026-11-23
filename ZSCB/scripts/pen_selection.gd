extends Node2D
## Offline editing feedback. Coordinates returned by edge_near are local to the supplied paths.
const Links := preload("res://scripts/structure_links.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const REACH := 0.15
const OUTLINE_LENGTH := 0.48
var game
var pointer := Vector2.INF
var hits := []
var ordinal := 0
var basis := Vector2.INF
var next_update := 0.0

static func edge_near(paths: Array, point: Vector2) -> Dictionary:
	var distance := INF
	var best := PackedVector2Array()
	var edge := -1
	var foot := Vector2.ZERO
	var inside_wash := false
	for path in paths:
		var pts := PackedVector2Array(path.points)
		if Brush.is_wash(path.get("brush","bold")) and pts.size() >= 4 and Geometry2D.is_point_in_polygon(point,pts):
			inside_wash = true
		for i in range(1,pts.size()):
			if pts[i].is_equal_approx(pts[i-1]): continue
			var nearest := Geometry2D.get_closest_point_to_segment(point,pts[i-1],pts[i])
			var gap := point.distance_squared_to(nearest)
			if gap >= distance: continue
			distance = gap
			best = pts
			foot = nearest
			edge = i
	var outline := PackedVector2Array()
	if edge >= 1:
		outline.append(foot)
		for step in [-1,1]:
			var last := foot
			var length := OUTLINE_LENGTH
			var index := edge-1 if step < 0 else edge
			while index >= 0 and index < best.size() and length > 0:
				var end := last.move_toward(best[index],length)
				var walked := last.distance_to(end)
				if walked > 0.0001:
					if step < 0: outline.insert(0,end)
					else: outline.append(end)
					length -= walked
				last = end
				index += step
	return {"distance":sqrt(distance),"edge":outline,"inside_wash":inside_wash}

static func candidates(owner_game, world_point: Vector2, scenery: bool) -> Array:
	var result := []
	for index in range(owner_game.object_nodes.size()-1,-1,-1):
		var body = owner_game.object_nodes[index]
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var obj: Dictionary = body.data
		if (obj.get("pen")=="draw_scenery") != scenery or not owner_game.can_cooperate(obj): continue
		var local: Vector2 = body.to_local(world_point)
		if not body.pick_bounds.grow(REACH).has_point(local): continue
		if not scenery and Links.material_distance(body.damage_prepared,local)>REACH: continue
		var hit := edge_near(body.damage_paths,local)
		if hit.edge.size()<2 or (scenery and hit.distance>REACH and not hit.inside_wash): continue
		result.append({"index":index,"id":obj.get("structure_id",""),"body":body,"edge":hit.edge})
	return result

func active() -> bool:
	return game.medieval_world != null and game.network_session == null and game.draw_mode == 4 and game.connection_tool == "move" and game.drag == null and not game.bag_open and not game.personal_overlay_open()

func refresh(at: Vector2, scenery: bool) -> void:
	var previous: String = hits[ordinal].id if ordinal<hits.size() else ""
	var keep := basis.is_finite() and basis.distance_to(at)<12.0
	hits = candidates(game,game.screen_to_world(at),scenery)
	ordinal = maxi(0,hits.find_custom(func(hit): return hit.id==previous)) if keep else 0
	if not keep: basis = at
	queue_redraw()

func pick(at: Vector2, scenery: bool) -> int:
	refresh(at,scenery)
	return -1 if hits.is_empty() else int(hits[ordinal].index)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse: pointer = event.position

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode!=KEY_V: return
	if event.is_command_or_control_pressed() or not active() or not pointer.is_finite() or game.toolbar.blocks_canvas(pointer): return
	refresh(pointer,event.alt_pressed)
	if hits.size()<2: return
	ordinal = (ordinal+1)%hits.size()
	queue_redraw()
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active() or not pointer.is_finite() or not get_viewport_rect().has_point(pointer) or game.toolbar.blocks_canvas(pointer):
		if not hits.is_empty():
			hits = []
			ordinal = 0
			queue_redraw()
		return
	next_update -= delta
	if next_update <= 0:
		next_update = 0.065
		refresh(pointer,Input.is_key_pressed(KEY_ALT))

func _draw() -> void:
	if ordinal >= hits.size(): return
	var hit: Dictionary = hits[ordinal]
	if not is_instance_valid(hit.body): return
	var line := PackedVector2Array()
	for p in hit.edge: line.append(game.world_to_screen(hit.body.to_global(p)))
	if line.size()<2: return
	draw_polyline(line,Color("#fff9e1d4"),5.5,true)
	draw_polyline(line,Color("#397471ed"),2.1,true)
	if hits.size()>1:
		var note := "%d/%d  V" % [ordinal+1,hits.size()]
		var at := pointer+Vector2(11,-11)
		draw_string_outline(ThemeDB.fallback_font,at,note,HORIZONTAL_ALIGNMENT_LEFT,-1,13,4,Color("#fffae8"))
		draw_string(ThemeDB.fallback_font,at,note,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#305f60"))
