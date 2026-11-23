extends RefCounted
## Functional pens share the canvas and BuildObject pipeline. Coordinates in a
## command are absolute world metres, with positive Y up.
const WorldPen := preload("res://scripts/paper_world_pen.gd")
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const Palette := preload("res://scripts/pen_palette.gd")
const SCENERY := "draw_scenery"
const TERRAIN := "draw_terrain"
const OBJECT := "draw_object"
const TOOLS := {
	7: {"id":SCENERY, "label":"景物笔", "hint":"画远山或景物，笔迹留在角色身后，可自由穿过"},
	8: {"id":TERRAIN, "label":"地形笔", "hint":"从地表起笔画一道缓坡，确认后固定并承重"},
	9: {"id":OBJECT, "label":"造物笔", "hint":"画出闭合石块，确认后会按轮廓落下，可以推走"}
}
const STYLES := {"ink": Color("343035"), "pencil": Color("627781")}

static func available(game) -> bool:
	return game.medieval_world != null and game.network_session == null and not game.network_headless

static func from_draft(slot: int, style: String, draft: Array) -> Dictionary:
	var strokes := []
	for path in draft:
		var points := []
		for point in path.points:
			points.append([point.x, point.y])
		strokes.append(points)
	var command := {"tool":TOOLS[slot].id, "style":style, "strokes":strokes}
	if slot == 7 or draft.any(func(path): return path.has("brush")):
		command.brushes = draft.map(func(path): return path.get("brush","bold"))
	if draft.any(func(path): return path.has("pigment")):
		command.pigments = draft.map(func(path): return path.get("pigment","inherit"))
	if slot == 7: Brush.add_treatments(command,draft)
	if slot==7 and not draft.is_empty() and draft[0].has("sheet"):
		var sheet: Dictionary = draft[0].sheet.duplicate(true)
		while sheet.layout.layers.size()<draft.size(): sheet.layout.layers.append("detail")
		command.plan=sheet
		command.name=sheet.name
	return command

static func observe(game, slot: int, artist_at := Vector2.INF, autonomous := false) -> Dictionary:
	var ground := []
	var profile: PackedVector2Array = game.medieval_world.terrain.profile
	var size: Vector2 = game.get_viewport_rect().size
	var left := maxf(maxf(profile[0].x, game.player.position.x - 6), game.screen_to_world(Vector2(size.x * 0.07, 0)).x)
	var right := minf(minf(profile[-1].x, game.player.position.x + 6), game.screen_to_world(Vector2(size.x * 0.93, 0)).x)
	# Give a physical painter a reachable patch beside the player. The actual
	# vertices and ink style still come from the model.
	if autonomous:
		left=maxf(profile[0].x,artist_at.x-3.4)
		right=minf(profile[-1].x,artist_at.x+3.4)
	elif artist_at.is_finite() and slot != 7:
		var human_x: float = game.player.position.x
		var west := Vector2(maxf(left, artist_at.x-3.4), minf(right, human_x-.85))
		var east := Vector2(maxf(left, human_x+.85), minf(right, artist_at.x+3.4))
		var patch := east if (east.y-east.x) > (west.y-west.x) else west
		if patch.y-patch.x >= 1.2:
			left = patch.x
			right = patch.y
	for i in 21:
		var x := lerpf(left, right, i / 20.0)
		ground.append([snappedf(x, 0.01), snappedf(game.ground_height_at(x), 0.01)])
	var occupied := []
	for object in game.objects:
		var rect: Rect2 = game.object_bounds(object)
		if rect.end.x >= left and rect.position.x <= right and occupied.size() < 64:
			occupied.append([rect.position.x, rect.position.y, rect.end.x, rect.end.y])
	var tools := []
	for definition in TOOLS.values():
		tools.append({"name":definition.id, "description":definition.hint})
	var view_y := [artist_at.y-3.0,artist_at.y+3.0] if autonomous else [game.screen_to_world(size * 0.76).y, game.screen_to_world(size * 0.20).y]
	return {"task":"functional_pen", "requested":TOOLS[slot].id, "tools":tools, "styles":STYLES.keys(), "brushes":Brush.BRUSHES.keys(),
		"palette_version":Palette.VERSION, "pigments":Palette.LABELS.keys(), "selected_pigment":game.pen_pigment, "selected_brush":game.scenery_brush,
		"view_y":view_y,
		"player":[game.player.position.x, game.player.position.y], "ground":ground, "occupied":occupied}

static func check_marks(cmd: Dictionary, count: int) -> String:
	if not Brush.valid_treatments(cmd,count): return "每笔的墨色处理须与景物笔触相符"
	for field in ["brushes","pigments"]:
		if not cmd.has(field): continue
		var values = cmd[field]
		if not values is Array or values.size() != count: return "每笔需要一一对应的笔触和颜料"
		for value in values:
			if field == "pigments" and not Palette.valid(value): return "颜料不在色板内"
			if field == "brushes" and (not value is String or not Brush.BRUSHES.has(value)): return "无法识别笔触"
	return ""

static func submit(game, cmd: Dictionary, artist: String, blueprint_id := -1, builder = null) -> Dictionary:
	if not available(game) or game.objects.size() >= game.MAX_OBJECTS:
		return {"error":"当前地图无法再落笔"}
	var tool = cmd.get("tool")
	var style = cmd.get("style", "ink")
	if tool not in [SCENERY, TERRAIN, OBJECT] or not style is String or not STYLES.has(style):
		return {"error":"无法识别这支笔或墨色"}
	var strokes = cmd.get("strokes")
	if not strokes is Array or strokes.is_empty() or strokes.size() > game.MAX_DRAW_STROKES:
		return {"error":"请画 1–128 笔再确认"}
	var profile: PackedVector2Array = game.medieval_world.terrain.profile
	var mark_error := check_marks(cmd,strokes.size())
	if not mark_error.is_empty(): return {"error":mark_error}
	var brushes: Array = cmd.get("brushes",[])
	var pigments: Array = cmd.get("pigments",[])
	var colored := false
	var paths := []
	var count := 0
	var reach_from: Vector2 = builder.player.position if builder != null else game.player.position
	for stroke in strokes:
		if not stroke is Array or stroke.size() < 2:
			return {"error":"每一笔至少需要两个点"}
		count += stroke.size()
		if count > DrawingRules.MAX_POINTS: return {"error":"笔迹超过 8192 点，请拆开生成"}
		var points := []
		var length := 0.0
		for pair in stroke:
			if not pair is Array or pair.size() != 2 or typeof(pair[0]) not in [TYPE_FLOAT, TYPE_INT] or typeof(pair[1]) not in [TYPE_FLOAT, TYPE_INT]:
				return {"error":"笔迹坐标无效"}
			var point := Vector2(pair[0], pair[1])
			if not point.is_finite() or point.distance_to(reach_from) > DrawingRules.BUILD_RANGE:
				return {"error":"请走近笔迹，在角色 12 米内确认"}
			if (tool == TERRAIN or game.medieval_world.paper_space == null) and (point.x < profile[0].x or point.x > profile[-1].x):
				return {"error":"笔迹超出纸边，可先请画家续画地图"}
			if not points.is_empty(): length += point.distance_to(points.back())
			points.append(point)
		if length < (Brush.MIN_LENGTH if tool == SCENERY else 0.25): return {"error":"笔画太短，请画长一点"}
		var path := {"points":points, "collision":tool != SCENERY}
		if not pigments.is_empty():
			var pigment = pigments[paths.size()]
			if pigment != "inherit":
				path.pigment = pigment
				colored = true
		if not brushes.is_empty():
			var brush = brushes[paths.size()]
			if Brush.is_wash(brush) and Brush.wash_polygon(PackedVector2Array(points)).is_empty():
				return {"error":"淡墨需要沿边缘绕一圈，回到起笔处闭合"}
			path.brush = brush
		if cmd.has("ink_treatments") and cmd.ink_treatments[paths.size()] != "":
			path.ink_treatment = cmd.ink_treatments[paths.size()]
		paths.append(path)
	var first:Vector2=paths[0].points[0]
	var anchor=cmd.get("anchor",{"kind":"free","at":[first.x,first.y]})
	if not anchor is Dictionary: return {"error":"支点格式无效。"}
	var requested:=WorldPen.point(anchor.get("at"))
	if not WorldPen.within_anchor_reach(first,requested): return {"error":"支点应位于笔划的起点。"}
	var contact:=WorldPen.resolve_anchor(game,anchor)
	if not contact.is_finite(): return {"error":"起笔处附近没有可接触的相应表面。"}
	var project := {}
	if cmd.has("plan"):
		project=Plans.inspect_command(game,cmd,artist)
		if project.has("error"): return project
	elif anchor.kind!="free":
		for path in paths:
			for n in path.points.size():
				path.points[n]+=contact-first
				if path.points[n].distance_to(reach_from)>DrawingRules.BUILD_RANGE: return {"error":"请走近选定支点再落笔。"}
	var collect := builder == null and project.is_empty() and colored and blueprint_id < 0
	if collect and game.bag.entries.size() >= BlueprintBag.MAX_ENTRIES:
		return {"error":"图纸已满，请腾出一格再确认彩稿"}
	var bounds := ShapeMatcher.bounds(paths)
	var center := Vector2((bounds.min_x + bounds.max_x) / 2, (bounds.min_y + bounds.max_y) / 2)
	for path in paths:
		for i in path.points.size(): path.points[i] -= center
	var object := {"source":"own", "kind":"freehand", "pen":tool, "ink_style":style, "artist":artist,
		"x":center.x, "y":center.y, "angle":0.0, "paths":paths, "dynamic":tool == OBJECT}
	if artist=="painter":
		object.work_id="companion-"+Crypto.new().generate_random_bytes(12).hex_encode()
		object.author_id="companion"
		object.name=str(cmd.get("name","手稿")).left(56)
		if cmd.get("improves","")!="": object.improves=str(cmd.improves).left(120)
	if not project.is_empty():
		object.built_plan={"owner":project.owner,"id":project.id,"origin":Plans.coords(project.origin),
			"offset":Plans.coords(project.origin-center),"layout":project.design.layout.duplicate(true)}
	object.anchor={"kind":anchor.kind,"at":[contact.x,contact.y]}
	var body: RigidBody2D
	var personal_cost := PaperInkReserve.cost(object) if builder!=null else 0.0
	if builder!=null and not builder.ink.can_spend(personal_cost): return {"error":"阿靛的墨量不足"}
	if tool == SCENERY:
		if builder==null and not game.creation_ink_allowed(object): return {"error":"墨水不足"}
		body = game.build_object_scene.instantiate()
		body.setup(object)
	else:
		body = game._drop_candidate(object,builder)
		if body == null: return {"error":game.toolbar.status_text}
		if anchor.kind!="free" and body.position.distance_to(center)>.015:
			body.free()
			return {"error":"支点已被占用，请换一个可接触的支点。"}
		if anchor.kind!="free":
			# The clearance solver deliberately leaves a six-millimetre air gap.
			# Attached work rests on the contact surface, including after loading.
			body.position=center
			object.x=center.x
			object.y=center.y
			body.set_meta("spawn_adjusted",false)
			body.set_meta("spawn_offset",Vector2.ZERO)
		if tool == TERRAIN and not _keep_foot_on_ground(game, body, object, center,reach_from):
			body.free()
			return {"error":"坡脚的落点被占了，等人走开或换个位置再确认"}
	game.record()
	if not project.is_empty():
		if project.id < 0:
			var stored := Plans.collect(Plans.bag_for(game,project.owner),project.design)
			object.built_plan.id=stored.id
		blueprint_id=int(object.built_plan.id)
		if project.owner=="player": game.selected_blueprint_id=blueprint_id
	if collect:
		var entry: Dictionary = BlueprintBag.add_entry(game.bag, object).entry
		var label: String = {SCENERY:"景物", TERRAIN:"地形", OBJECT:"造物"}[tool]
		entry.name = str(cmd.get("name","")).strip_edges().left(56)
		if entry.name.is_empty(): entry.name = "设色" + label + " " + str(entry.id)
		entry.category = "地形" if tool == TERRAIN else "建筑"
		blueprint_id = entry.id
		game.selected_blueprint_id = entry.id
	if blueprint_id >= 0 and (project.is_empty() or project.owner=="player"): object.blueprint_id = blueprint_id
	if builder!=null: builder.ink.spend(personal_cost)
	else: game.charge_creation_ink(object)
	game.objects.append(object)
	game.object_nodes.append(game._attach_body(body, object))
	if object.has("built_plan") and game.medieval_world.survival!=null:
		preload("res://scripts/architecture/stall_goods.gd").open_accounts(game.medieval_world.survival,object,object.built_plan.owner)
	game.celebrate_creation(object, "CREATED!", false)
	return {"ok":true, "collected":collect or (not project.is_empty() and project.id<0), "id":object.structure_id,
		"work_id":object.get("work_id",""),"adjusted":body.get_meta("spawn_adjusted", false)}

## When clearance would lift a walk-on stroke into the air, look beside the
## obstruction on the same surface. Translate the whole contour rigidly.
static func _keep_foot_on_ground(game, body: RigidBody2D, object: Dictionary, center: Vector2, reach_from: Vector2) -> bool:
	var offset: Vector2 = body.position-center
	if offset.is_zero_approx(): return true
	var foot := Vector2.INF
	for path in object.paths:
		for end: Vector2 in [path.points.front(), path.points.back()]:
			var p := center+end
			if absf(p.y-game.ground_height_at(p.x)) <= 0.20 and absf(p.y+offset.y-game.ground_height_at(p.x+offset.x)) > 0.20:
				foot = p
				break
		if foot.is_finite(): break
	if not foot.is_finite(): return true

	var ground: float = game.ground_height_at(foot.x)
	var preferred := 1.0 if center.x >= reach_from.x else -1.0
	for distance in [.35, .70, 1.05, 1.40, 1.75, 2.10]:
		for side in [preferred, -preferred]:
			var dx: float = distance*side
			var dy: float = game.ground_height_at(foot.x+dx)-ground
			# Leave a paper-width margin for the foot fixture at ground level.
			var lift := maxf(0, .045-(foot.y-ground))
			body.position = center+Vector2(dx,dy+lift)
			if body.position.distance_to(reach_from) > DrawingRules.BUILD_RANGE: continue
			if not PaperSpawnClearance._contacts(game,body,Vector2.ZERO).is_empty(): continue
			var fit := PaperSpawnClearance.resolve(game,body,object)
			if not fit.valid or not Vector2(fit.offset).is_zero_approx(): continue
			object.x=body.position.x
			object.y=body.position.y
			body.set_meta("spawn_offset",body.position-center)
			body.set_meta("spawn_adjusted",true)
			return true
	return false
