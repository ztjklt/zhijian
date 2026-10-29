extends "res://scripts/knowledge_world.gd"

# A bounded alternative playground. Coordinates and all gameplay contracts
# match the textbook world; foliage is decoration, wood and ground are solid.
const HILLS := [Vector2(0,-2.8), Vector2(12,-2.8), Vector2(24,2.0), Vector2(32,6.0), Vector2(40,6.0), Vector2(52,.5), Vector2(66,-2.0), Vector2(78,2.5), Vector2(88,7.5), Vector2(98,7.5), Vector2(110,1.0), Vector2(124,-2.0), Vector2(138,3.5), Vector2(146,3.5), Vector2(156,-2.8)]
const NAMES := ["草地入口", "林间山丘", "溪谷木桥", "高山营地", "林冠栈道", "远山边缘"]
var ground_shapes: Array = []
var trees: Array = []

func map_title() -> String:
	return "自然沙盒（实验备选）"

func navigation_names() -> Array:
	return ["草地", "山丘", "溪谷", "高山", "林冠", "远山"]

func region_title(index: int) -> String:
	return NAMES[clampi(index, 0, 5)]

func extent_summary() -> String:
	return "实验有限样段 156m · 木台至 20m · Home 回地面"

func surface_height(x: float) -> float:
	x = clampf(x, 0, 156)
	for i in range(1, HILLS.size()):
		if x <= HILLS[i].x:
			return lerpf(HILLS[i - 1].y, HILLS[i].y, (x - HILLS[i - 1].x) / (HILLS[i].x - HILLS[i - 1].x))
	return -2.8

func _build_layout() -> void:
	for i in range(6):
		var x: float = i * STEP + 9
		labels.append({"value":"0%d / %s" % [i + 1, NAMES[i]], "p":Vector2(x - 7, surface_height(x) + 2.3), "size":24, "color":COLORS[i]})
		stamps.append({"p":Vector2(x + 2, surface_height(x + 2) + 1), "id":i, "label":NAMES[i]})
	# Low branches lead to two upper routes. Their trunks also support wall
	# climbing, while broad plank tops give a safe place to draw a bridge.
	for x in [7.0, 17.0, 47.0, 60.0, 73.0, 102.0, 119.0, 137.0, 151.0]:
		var base: float = surface_height(x)
		var height: float = 8.0 if x == 17.0 else 6.3
		var trunk := Rect2(Vector2(x - .24, base), Vector2(.48, height))
		raised_tiers.append(trunk)
		trees.append({"x":x, "base":base, "height":height})
		for level in [2.0, 4.1, height]:
			var branch := Rect2(Vector2(x - 2.0, base + level - .22), Vector2(4.8, .22))
			raised_tiers.append(branch)
	# A hand-built camp above the first hill and a canopy route above the
	# second hill are deliberately distinct from the walkable mountain path.
	for data in [[15.5,6.2,7.0], [23.5,8.4,6.5], [31.0,10.6,7.0], [39.0,12.8,7.0], [47.0,15.0,7.0], [55.0,17.0,7.0], [64.0,18.8,8.0], [75.0,20.0,8.0], [85.0,18.4,8.0], [95.0,16.8,8.0], [105.0,15.2,7.0], [114.0,13.6,7.0], [123.0,12.0,7.0], [132.0,10.4,7.0], [141.0,8.8,7.0]]:
		raised_tiers.append(Rect2(Vector2(data[0], data[1] - .24), Vector2(data[2], .24)))
	labels.append({"value":"树干可攀墙 ↑ 枝头可二连跳 · 双 S 返回下层", "p":Vector2(2.0, 9.0), "size":20, "color":INK})
	labels.append({"value":"山顶营地 · 画建筑搭桥继续向上", "p":Vector2(32.0, 13.0), "size":21, "color":INK})
	labels.append({"value":"林冠观景台 20m", "p":Vector2(75.0, 21.0), "size":24, "color":INK})
	labels.append({"value":"左边缘 · 自然地图是有限实验样段", "p":Vector2(.6, -4.0), "size":18, "color":INK})
	labels.append({"value":"右边缘 156m · Home 返回安全地面", "p":Vector2(139.0, -.5), "size":18, "color":INK})

func _build_terrain() -> void:
	# Actual convex trapezoids share their visible sloping cap. Keep a single
	# bounds rectangle for the existing safe spawn/clamping contract only.
	terrain_rects.append(Rect2(0, -5.1, 156, 12.6))
	for i in range(1, HILLS.size()):
		var a: Vector2 = HILLS[i - 1]
		var b: Vector2 = HILLS[i]
		ground_shapes.append(PackedVector2Array([Vector2(a.x,-5.1), Vector2(b.x,-5.1), b, a]))

func _cache_collision_geometry() -> void:
	for polygon in ground_shapes:
		var closed := PackedVector2Array(polygon)
		closed.append(polygon[0])
		collision_geometry.append(closed)
	for tier in raised_tiers:
		var a: Vector2 = tier.position
		var b: Vector2 = tier.end
		collision_geometry.append(PackedVector2Array([a,Vector2(b.x,a.y),b,Vector2(a.x,b.y),a]))

func _add_terrain_physics(parent: Node2D, chunk: int) -> void:
	for i in range(1, HILLS.size()):
		var left: float = maxf(HILLS[i - 1].x, chunk * CHUNK)
		var right: float = minf(HILLS[i].x, (chunk + 1) * CHUNK)
		if right <= left: continue
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 3
		body.set_meta("map_drop_allowed", false)
		var fixture := CollisionPolygon2D.new()
		fixture.polygon = PackedVector2Array([Vector2(left,-5.1),Vector2(right,-5.1),Vector2(right,surface_height(right)),Vector2(left,surface_height(left))])
		body.add_child(fixture)
		parent.add_child(body)
	for tier in raised_tiers:
		var left: float = maxf(tier.position.x, chunk * CHUNK)
		var right: float = minf(tier.end.x, (chunk + 1) * CHUNK)
		if right <= left: continue
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 3
		body.set_meta("map_drop_allowed", true)
		var fixture := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(right - left, tier.size.y)
		fixture.shape = box
		fixture.position = Vector2((left + right) * .5, tier.get_center().y)
		body.add_child(fixture)
		parent.add_child(body)

func draw_background(canvas: Node2D, size: Vector2) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO,size), Color("f0f4e9"))
	# Distant mountains are intentionally decorative; the foreground green
	# outline below is the only natural ground collision.
	for x in range(-1, 10):
		var center: Vector2 = game.world_to_screen(Vector2(x * 22 + 8, 6))
		var width: float = game.PIXELS_PER_UNIT * 16
		canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(-width, width * .7), center + Vector2(0, -width * .35), center + Vector2(width, width * .7)]), Color("dfe8dc"))

func draw_landscape(canvas: Node2D, _size: Vector2) -> void:
	var ppu: float = game.PIXELS_PER_UNIT
	for polygon in ground_shapes:
		var points := PackedVector2Array()
		for point in polygon: points.append(game.world_to_screen(point))
		canvas.draw_colored_polygon(points, Color("d2dbc0"))
		canvas.draw_line(game.world_to_screen(polygon[3]), game.world_to_screen(polygon[2]), Color("66825e"), maxf(1.2, ppu * .055), true)
	for tree in trees:
		if not _visible(tree.x - 3, 6): continue
		var at: Vector2 = game.world_to_screen(Vector2(tree.x, tree.base + tree.height))
		canvas.draw_circle(at + Vector2(0,-ppu), ppu * 1.5, Color("c6d4b1"))
		canvas.draw_circle(at + Vector2(-ppu,.0), ppu * 1.25, Color("b3c69c"))
		canvas.draw_circle(at + Vector2(ppu,.0), ppu * 1.25, Color("c3d0a6"))
	for tier in raised_tiers:
		if not _visible(tier.position.x,tier.size.x): continue
		var rect := Rect2(game.world_to_screen(Vector2(tier.position.x,tier.end.y)), tier.size * ppu)
		canvas.draw_rect(rect, Color("a1825c"))
		canvas.draw_rect(rect, Color("745e43"), false, maxf(.7, ppu * .025))
		if tier.size.x > 2:
			canvas.draw_line(rect.position + Vector2(0,rect.size.y * .5), rect.position + Vector2(rect.size.x,rect.size.y * .5), Color("c2a17b"), maxf(.6,ppu * .015))
	for label in labels:
		if _visible(label.p.x, 15):
			canvas.draw_string(serif, game.world_to_screen(label.p), label.value, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(3,roundi(label.size * ppu / 78)), label.color)
	for stamp in stamps:
		if collected.has(stamp.id): continue
		var at: Vector2 = game.world_to_screen(stamp.p)
		canvas.draw_circle(at, maxf(2,ppu * .1), COLORS[stamp.id])
	if collision_view:
		for polygon in collision_geometry:
			var points := PackedVector2Array()
			for point in polygon: points.append(game.world_to_screen(point))
			canvas.draw_polyline(points, Color("c77948"), 1.5, true)
