extends RefCounted
## A zero-cost route and a short pause, independent of a role's model or tasks.

var heading: int
var patrol_radius: float
var origin := Vector2.INF
var plan := {}
var goal := Vector2.INF
var site_id := ""
var label := ""
var progress := "看看附近哪段实地可走"
var rest_left := 0.55
var route_left := 0.0
var active := false

func _init(initial_heading: int, radius: float = 0.0) -> void:
	heading = initial_heading
	patrol_radius = radius

static func can_run(connection: Dictionary, paused: bool, model_ready: bool) -> bool:
	return not paused and not model_ready and connection.get("code") in ["not_configured", "needs_key"]

func interrupt() -> void:
	if not active: return
	active = false
	plan = {}
	origin = Vector2.INF
	goal = Vector2.INF
	site_id = ""
	label = ""
	rest_left = 0.55
	progress = "看看附近哪段实地可走"

func view(activity: String) -> Dictionary:
	var walking := not plan.is_empty()
	return {"phase":"walking" if walking else "idle",
		"summary":"%s · %s" % [activity, "沿实地行走" if walking else "驻足观察"],
		"goal":label if not label.is_empty() else "查看附近可达地面",
		"reason":"沿当前纸面已确认的脚面行走",
		"progress":progress,"decision_source":"本地行动","pause_reason":""}

func tick(world, feet: Vector2, delta: float, grounded: bool = true, kinematic_speed: float = 0.0, sites: Variant = null) -> Dictionary:
	active = true
	if plan.is_empty():
		rest_left -= delta
		if rest_left > 0.0 or not grounded: return {}
		if not origin.is_finite(): origin = feet
		if sites is Array:
			for site in sites:
				if _route_to(world,feet,_point(site.at),str(site.id),str(site.label),18.0): break
		else:
			_choose_route(world,feet)
		if plan.is_empty():
			label = ""
			progress = "附近没有合适的可达脚面，驻足复查"
			rest_left = 3.0
			return {}
	route_left -= delta
	var step: Dictionary
	if kinematic_speed > 0.0:
		step = world.paper_nav_step(plan, feet, delta, kinematic_speed)
	else:
		step = world.paper_nav_steer(plan, feet, delta, grounded)
	if not step.get("ok",false) or route_left <= 0.0:
		plan = {}
		heading = -heading
		rest_left = 1.7
		progress = "脚面受阻，驻足后换一段路"
		return {}
	if step.get("arrived",false):
		plan = {}
		rest_left = 2.4
		progress = "已到%s，驻足查看" % label
		step.site_id = site_id
		return step
	progress = "距落脚点 %.1f 米" % feet.distance_to(goal)
	return step

func _choose_route(world, feet: Vector2) -> void:
	var preferred := heading
	if patrol_radius > 0.0 and absf(feet.x-origin.x) >= patrol_radius - 1.7:
		preferred = -1 if feet.x > origin.x else 1
	for side in [preferred, -preferred]:
		for stride in [4.0, 2.8, 5.2]:
			var x: float = feet.x + side * stride
			if patrol_radius > 0.0 and absf(x-origin.x) > patrol_radius: continue
			var surfaces: Array = world.paper_surfaces(x, feet.y - 3.5, feet.y + 3.5)
			surfaces.sort_custom(func(a,b): return absf(a.y-feet.y) < absf(b.y-feet.y))
			for surface in surfaces:
				if surface.face != "floor": continue
				if _route_to(world,feet,Vector2(x,surface.y),str(surface.work_id),"",10.5):
					heading = side
					return

func _route_to(world, feet: Vector2, proposed: Vector2, id: String, title: String, limit: float) -> bool:
	if proposed.distance_to(feet) < .65 or proposed.distance_to(feet) > limit: return false
	var route: Dictionary = world.paper_nav_route(feet,proposed)
	if not route.get("ok",false): return false
	var distance := 0.0
	for waypoint in route.steps:
		distance += _point(waypoint.from).distance_to(_point(waypoint.to))
	if distance > limit or absf(proposed.y-_point(route.goal).y) > .24: return false
	goal = _point(route.goal)
	site_id = id
	label = title if not title.is_empty() else world.paper_nav_label(id,goal)
	plan = route
	route_left = maxf(11.0,distance / 1.65 + 5.0)
	return true

static func _point(row: Array) -> Vector2:
	return Vector2(row[0],row[1])
