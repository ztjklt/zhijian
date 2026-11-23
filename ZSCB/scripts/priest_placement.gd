extends RefCounted
## Probe the actual drawing and the artist's approach on the same floor.
const Ground := preload("res://scripts/priest_ground.gd")
const Creature := preload("res://scripts/priest_creature.gd")
const OFFSETS := [0.0, -.35, .35, -.8, .8, -1.35, 1.35, -2.0, 2.0]
const OUTER_OFFSETS := [-2.75, 2.75, -3.5, 3.5, -4.5, 4.5]

static func reason_at(priest, trial, origin: Vector2, x: float) -> String:
	var world = priest.world
	var surface := Ground.trace(world, origin, x)
	if surface.is_empty():
		return "通往出生点的脚面中断"
	var foot := Vector2(x, surface.y)
	trial.beast_x = x
	trial.beast_y = foot.y
	if world.paper_space != null and is_finite(world.paper_space.water_surface(foot + Vector2(0, .12))):
		return "出生点在水里"
	var room := Ground.room_problem(priest, x, foot.y)
	if not room.is_empty():
		return room
	for animal in priest.works:
		if animal.phase != "dead" and foot.distance_to(Vector2(animal.beast_x, animal.beast_y)) < 1.15:
			return "离现有的「%s」太近" % animal.design.name
	var easel := Ground.trace(world, foot, x - 1.47)
	if easel.is_empty():
		return "牧师没有可站的运笔位置"
	var approach := Ground.trace(world, Vector2(priest.priest_x, priest.priest_y), x - 1.47)
	if approach.is_empty() or absf(approach.y - easel.y) > .08:
		return "牧师走不到这层运笔位置"
	var prop := Creature.Obstacles.blocking_prop(trial, foot, trial._slope(), 1)
	if not prop.is_empty():
		return "图纸轮廓碰到" + Ground.obstacle_name(prop.get_slice("-", 0))
	return ""

static func inspect(priest, trial, site: Dictionary, offsets: Array = OFFSETS) -> Dictionary:
	if site.is_empty():
		return {"problem": "原先的脚面已不在可达范围"}
	var problem := Creature.FoodWeb.habitat_problem(site, trial.design)
	if not problem.is_empty():
		return {"problem": problem}
	var origin := Vector2(site.x, site.ground_y)
	var causes := {}
	var details := PackedStringArray()
	for offset in offsets:
		var x := origin.x + float(offset)
		problem = reason_at(priest, trial, origin, x)
		if problem.is_empty():
			var fit := site.duplicate()
			fit.x = x
			fit.ground_y = trial.beast_y
			return {"fit": fit}
		if not causes.has(problem):
			causes[problem] = true
			details.append("%.1f 米处，%s" % [x, problem])
	return {"problem": "。".join(details)}

static func suggestions(priest, trial, sites: Array, requested: Vector2) -> Array:
	var result := []
	for site in sites:
		# Prefer one option per habitat and check its closest candidate first.
		var offsets := OFFSETS + OUTER_OFFSETS
		offsets.sort_custom(func(a, b): return absf(site.x + a - requested.x) < absf(site.x + b - requested.x))
		var fit: Dictionary = inspect(priest, trial, site, offsets).get("fit", {})
		if fit.is_empty():
			continue
		var point := Vector2(fit.x, fit.ground_y)
		var floor_row := Ground.nearby(priest.world, point.x, point.y, .08)
		var label: String = priest.world.paper_nav_label(str(floor_row.get("work_id", fit.surface)), point)
		result.append({"habitat_id": fit.id, "at": point, "label": label, "distance": requested.distance_squared_to(point)})
	result.sort_custom(func(a, b): return a.distance < b.distance)
	var choices := []
	for option in result:
		if choices.is_empty() or choices[0].at.distance_to(option.at) >= 1.15:
			choices.append(option)
			if choices.size() == 2:
				break
	return choices
