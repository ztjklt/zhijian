extends RefCounted
## A building may be drawn around an off-centre door. Survey the public-facing
## entrance on a real floor and translate the entire original plan from there.
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Neighbours := preload("res://scripts/architecture/plot_neighbours.gd")
const SITE_STEP := .25
const FRONTAGE_WIDTHS := [2.0,4.0,6.0]

static func _frontage_layout(width: float) -> Dictionary:
	var half := width*.5
	return {"supports":[[-half+.1,0],[half-.1,0]],"access":[[0,0]],"footprint":[-half,half]}

## A neutral frontage check for a multi-step commission. This describes the
## candidate as measured now. A finished author's plan is always checked again.
static func preview_ground(game, stand: Vector2) -> Dictionary:
	var world = game.medieval_world
	if world == null or not stand.is_finite():
		return {}
	var rows: Array = []
	var built := Plans._built(game)
	for width: float in FRONTAGE_WIDTHS:
		var conflicts := Plans._conflicts(game,_frontage_layout(width),stand,built)
		var issues: Array = []
		for hit in conflicts:
			if issues.size()==3:break
			issues.append({"id":hit.id,"reason":hit.reason})
		rows.append({"width_m":width,"level_site_clear":conflicts.is_empty(),"conflicts":issues})
	return {"stand":Plans.coords(stand),"frontages":rows}

## Landmarks tend to sit directly on a tree or a building. Search the actual
## floor on each side for a reachable frontage between those landmarks.
static func nearby_plots(game, feet: Vector2) -> Array:
	if not feet.is_finite(): return []
	var world = game.medieval_world
	var built := Plans._built(game)
	var plots := []
	for direction in [-1,1]:
		var best_width := 0.0
		var best: Dictionary = {}
		for n in range(1,25):
			var x:float = feet.x+direction*n*.5
			var faces: Array = world.paper_surfaces(x,feet.y-12.0,feet.y+12.0)
			faces.sort_custom(func(a,b):return absf(a.y-feet.y)<absf(b.y-feet.y))
			for face in faces:
				if face.face!="floor": continue
				var stand := Vector2(x,face.y)
				if stand.distance_to(feet)>12.0: continue
				for width:float in [6.0,4.0,2.0]:
					if width<=best_width: break
					if not Plans._conflicts(game,_frontage_layout(width),stand,built,"",true).is_empty(): continue
					var route: Dictionary = world.paper_nav_route(feet,stand)
					if not route.get("ok",false) or Plans.point(route.get("goal")).distance_to(stand)>.25: break
					best_width=width
					best={"id":"plot@%.2f,%.2f"%[stand.x,stand.y],"label":"可用门前空地（宽约 %.0f 米）"%width,
						"stand":[stand.x,stand.y],"distance":snappedf(feet.distance_to(stand),.01)}
					break
			if best_width>=6.0: break
		if not best.is_empty(): plots.append(best)
	var neutral:=_frontage_layout(Neighbours.FRONTAGE)
	var bank:=Neighbours.bank_plot(game,feet,Neighbours.waters(world,feet),neutral,built)
	if not bank.is_empty() and not plots.any(func(plot):return Plans.point(plot.stand).distance_to(Plans.point(bank.stand))<.25):
		plots.append(bank)
	var other:=Neighbours.second_plot(game,feet,plots,neutral,built)
	if not other.is_empty():plots.append(other)
	return plots

static func sites(game, owner: String, plan_id: int, focus: Vector2, feet: Vector2, radius: float) -> Array:
	var plan := Plans._source(game,owner,plan_id)
	if plan.is_empty() or not focus.is_finite() or not feet.is_finite() or not is_finite(radius) or radius < 0:
		return []
	var world = game.medieval_world
	var layout: Dictionary = plan.layout
	var entrance := Plans.point(layout.access.front())
	for service in layout.get("stations",[]):
		if preload("res://scripts/architecture/stall_goods.gd").is_counter(service):
			for p in layout.access:
				if is_equal_approx(float(p[0]),float(service.x)):
					entrance = Plans.point(p)
					break
			break
	var built := Plans._built(game)
	var found: Array = []
	for step in range(floori(radius/SITE_STEP)+1):
		for direction in ([0] if step == 0 else [-1,1]):
			var x: float = focus.x+direction*step*SITE_STEP
			if found.any(func(candidate): return absf(float(candidate.stand[0])-x)<1.5):
				continue
			var surfaces: Array = world.paper_surfaces(x,focus.y-radius,focus.y+radius)
			surfaces.sort_custom(func(a,b): return absf(float(a.y)-focus.y)<absf(float(b.y)-focus.y))
			for surface in surfaces:
				if surface.face != "floor":
					continue
				var stand := Vector2(x,surface.y)
				if stand.distance_to(focus)>radius:
					continue
				var origin := stand-entrance
				if not Plans._conflicts(game,layout,origin,built,"",true).is_empty():
					continue
				if not plan.paths.all(func(path): return path.points.all(func(p):
					return (origin+p).distance_to(stand+Vector2(0,.29))<=DrawingRules.BUILD_RANGE)):
					continue
				var route: Dictionary = world.paper_nav_route(feet,stand)
				if not route.get("ok",false) or Plans.point(route.goal).distance_to(stand)>.25:
					continue
				found.append({"stand":Plans.coords(stand),"origin":Plans.coords(origin),"surface":surface.work_id,
					"distance_to_site":snappedf(stand.distance_to(focus),.01)})
				if found.size() == 3:
					return found
				break
	return found

## Measure this design against the surviving shoreline of this water work.
static func shore_sites(game, owner: String, plan_id: int, water_work_id: String, feet: Vector2, radius := 16.0, neutral_width := 2.0) -> Dictionary:
	var frontage := {}
	if plan_id == -1 and is_finite(neutral_width) and neutral_width >= .8 and neutral_width <= 24.0:
		frontage = _frontage_layout(neutral_width)
	return preload("res://scripts/architecture/shore_survey.gd").measure(game,owner,plan_id,water_work_id,feet,radius,frontage)
