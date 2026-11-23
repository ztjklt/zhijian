extends RefCounted
## Read-only field measurements for a saved drawing at an actual ink shoreline.
const Plans := preload("res://scripts/architecture/building_plans.gd")
const STEP := .25

static func _floor(world, x: float, y: float, reach: float) -> Dictionary:
	var best := {}
	var distance := INF
	for face in world.paper_surfaces(x,y-reach,y+reach):
		if face.face != "floor" or world.paper_space.solid_at(Vector2(x,face.y+.04)):
			continue
		var delta := absf(float(face.y)-y)
		if delta < distance:
			distance = delta
			best = face
	return best

static func _pins(world, points: Array, origin: Vector2) -> Array:
	var samples := []
	for p in points:
		var at := origin + Plans.point(p)
		var hit := _floor(world,at.x,at.y,3.0)
		var sample := {"at":Plans.coords(at)}
		if not hit.is_empty():
			sample.floor_y = hit.y
			sample.surface = hit.work_id
			sample.gap_m = at.y-float(hit.y)
		samples.append(sample)
	return samples

static func _customer(layout: Dictionary) -> Vector2:
	for station in layout.get("stations",[]):
		if station.get("service","") in ["fruit_market","market_counter"]:
			for p in layout.access:
				if is_equal_approx(float(p[0]),float(station.x)):
					return Plans.point(p)
	return Plans.point(layout.access[0])

static func _in_reach(plan: Dictionary, entrance: Vector2) -> bool:
	var hand := entrance+Vector2(0,.29)
	for path in plan.paths:
		for p: Vector2 in path.points:
			if hand.distance_to(p)>DrawingRules.BUILD_RANGE:
				return false
	return true

## Walk along adjoining pieces of exposed floor. A slit between two different
## levels or submerged columns cannot enlarge the reported dry frontage.
static func _next_floor(world, previous: Vector2, dx: float, built: Array) -> Vector2:
	var x := previous.x + dx
	var hit := _floor(world,x,previous.y,.30)
	if hit.is_empty(): return Vector2.INF
	var next := Vector2(x,hit.y)
	if is_finite(world.paper_space.water_surface(next+Vector2(0,.01))): return Vector2.INF
	var strip := {"x":(x+previous.x)*.5,"width":STEP,"y":(next.y+previous.y)*.5}
	if not Plans.interval_occupants(world,strip,built,"",true).is_empty(): return Vector2.INF
	return next

static func _dry_frontage(world, stand: Vector2, built: Array, radius: float, links: Array) -> Array:
	var ends := [stand.x,stand.x]
	for side in 2:
		var previous := stand
		var memo: Dictionary = links[side]
		for n in range(ceili(radius/STEP)):
			if not memo.has(previous):
				memo[previous] = _next_floor(world,previous,STEP if side==1 else -STEP,built)
			var next: Vector2 = memo[previous]
			if not next.is_finite(): break
			ends[side] = next.x
			previous = next
	return ends

static func _distance(x: float, spans: Array) -> float:
	var nearest := INF
	for span in spans:
		nearest = minf(nearest,absf(x-clampf(x,span.left,span.right)))
	return nearest

static func measure(game, owner: String, plan_id: int, water_id: String, feet: Vector2, radius: float, frontage_layout: Dictionary) -> Dictionary:
	var world = game.medieval_world
	var neutral := plan_id == -1
	var result := {"plan_id":plan_id,"scope":"frontage" if neutral else "saved_plan","water":{},"sites":[],"banks":[]}
	if world == null or world.paper_space == null or not feet.is_finite() or not is_finite(radius) or radius <= 0: return result
	var plan := {} if neutral else Plans._source(game,owner,plan_id)
	var water_entry: Dictionary = world.paper_space.entries.get(water_id,{})
	if (frontage_layout.is_empty() if neutral else plan.is_empty()) or water_entry.get("record",{}).get("mode") != "water": return result
	var sections: Array = world.paper_space.basin_sections(water_id)
	if sections.is_empty(): return result
	var spans: Array = sections[0].spans
	var level := float(sections[0].level)
	result.water = {"work_id":water_id,"level":level,"spans":spans}
	if spans.is_empty(): return result
	var search := minf(radius,24.0)
	var layout: Dictionary = frontage_layout if neutral else plan.layout
	var entrance := _customer(layout)
	var fits_pen := neutral or _in_reach(plan,entrance)
	var built := Plans._built(game)
	var links := [{},{}]
	# Survey the water segment nearest this artist. Retain split channels in water.spans.
	var channel: Dictionary = spans[0]
	for span in spans:
		if _distance(feet.x,[span]) < _distance(feet.x,[channel]): channel = span
	for sign_x: int in [-1,1]:
		var edge := float(channel.left if sign_x < 0 else channel.right)
		var options := []
		for step in range(1,floori(search/STEP)+1):
			var x := edge + sign_x*step*STEP
			for face in world.paper_surfaces(x,level-search,level+search):
				if face.face != "floor": continue
				var stand := Vector2(x,face.y)
				if world.paper_space.solid_at(stand+Vector2(0,.04)) or is_finite(world.paper_space.water_surface(stand+Vector2(0,.01))): continue
				var origin := stand-entrance
				var conflicts := Plans._conflicts(game,layout,origin,built)
				var occupied := 0
				for hit in conflicts:
					if hit.reason not in ["unsupported","unwalkable"]: occupied += 1
				# Prefer a place for the exact drawing, then the least obstructed actual bank.
				var score := 100.0*occupied + 2.0*conflicts.size() + stand.distance_to(Vector2(edge,level))
				var frontage: Array = []
				if occupied == 0 and not conflicts.is_empty():
					frontage = _dry_frontage(world,stand,built,search,links)
					var missing_left := maxf(0.0,frontage[0]-origin.x-float(layout.footprint[0]))
					var missing_right := maxf(0.0,origin.x+float(layout.footprint[1])-frontage[1])
					score += 20.0*(missing_left+missing_right)
				options.append({"stand":Plans.coords(stand),"origin":Plans.coords(origin),"surface":face.work_id,
					"bank":"west" if sign_x<0 else "east","distance_to_water_m":_distance(x,spans),
					"height_above_water_m":stand.y-level,"within_pen_range":fits_pen,
					"conflicts":conflicts,"score":score,"dry_clear_interval":frontage})
		options.sort_custom(func(a,b):return a.score<b.score)
		var contributed := {"sites":0,"banks":0}
		var selected := []
		for row in options:
			var group := "sites" if row.conflicts.is_empty() and fits_pen else "banks"
			if contributed[group] >= 2: continue
			var stand := Plans.point(row.stand)
			if selected.any(func(p):return p.distance_to(stand)<1.0): continue
			var route: Dictionary = world.paper_nav_route(feet,stand)
			if not route.get("ok",false) or Plans.point(route.goal).distance_to(stand)>.25: continue
			row.erase("score")
			var origin := Plans.point(row.origin)
			row.supports = _pins(world,layout.supports,origin)
			row.access = _pins(world,layout.access,origin)
			row.footprint = [origin.x+float(layout.footprint[0]),origin.x+float(layout.footprint[1])]
			if row.dry_clear_interval.is_empty():
				row.dry_clear_interval = _dry_frontage(world,stand,built,search,links)
			row.dry_clear_width_m = row.dry_clear_interval[1]-row.dry_clear_interval[0]
			row.frontage_ready = group=="sites"
			row.can_build_now = not neutral and group=="sites"
			if neutral: row.erase("within_pen_range")
			result[group].append(row)
			contributed[group] += 1
			selected.append(stand)
	return result
