extends RefCounted

const Reach := preload("res://scripts/companion_pen_reach.gd")
const Pen := preload("res://scripts/paper_world_pen.gd")

static func nearby(world, brush: Dictionary, project: Dictionary) -> Array:
	var stations: Array = brush.get("stations",[])
	if stations.is_empty():
		return []
	var protected: Array = []
	for work: Dictionary in world.paper_strokes_snapshot():
		if work.work_id not in project.get("work_ids",[]) or work.mode not in ["rock","platform","water"]:
			continue
		var bounds := Rect2(Pen.point(work.points[0]),Vector2.ZERO)
		for p in work.points:
			bounds = bounds.expand(Pen.point(p))
		protected.append(bounds)
	var feet := Pen.point(brush.feet)
	var candidates := []
	for station: Dictionary in stations:
		var stand := Pen.point(station.feet)
		for width: float in [2.0,1.55,1.2,.85]:
			for side: float in [-1.0,1.0]:
				for offset: float in [width*.5+.18,.28]:
					var center := snappedf(stand.x+side*offset,.05)
					var row := sample(world,brush,stand,center,width,protected)
					if row.is_empty():
						continue
					row.distance=stand.distance_to(feet)
					candidates.append(row)
	candidates.sort_custom(func(a,b):return a.score-a.distance*.10>b.score-b.distance*.10)
	var sites := []
	for candidate: Dictionary in candidates:
		var center:float = candidate.samples[1][0]
		if sites.any(func(row):return absf(float(row.samples[1][0])-center)<.52):
			continue
		candidate.erase("score")
		candidate.erase("distance")
		candidate.id="basin-%d"%sites.size()
		sites.append(candidate)
		if sites.size()>=6:
			break
	return sites

static func sample(world, brush: Dictionary, stand: Vector2, center: float, width: float, protected: Array) -> Dictionary:
	var survey := []
	var min_y := INF
	var max_y := -INF
	for n in range(5):
		var x := snappedf(center+width*(n*.25-.5),.01)
		var highest := -INF
		for face: Dictionary in world.paper_surfaces(x,stand.y-2.2,stand.y+1.5):
			if face.face=="floor" and face.mode!="platform" and world.paper_space.solid_at(Vector2(x,face.y-.04)):
				highest=maxf(highest,face.y)
		if not is_finite(highest):
			return {}
		survey.append([x,snappedf(highest,.001)])
		min_y=minf(min_y,highest)
		max_y=maxf(max_y,highest)
	var left: Array = survey.front()
	var right: Array = survey.back()
	var lip_low:=minf(left[1],right[1])
	var lip_high:=maxf(left[1],right[1])
	var open_top:=ceilf((max_y+.075)*100.0)/100.0
	if lip_high-lip_low>.72 or open_top-lip_low>.9:
		return {}
	var pocket:=Rect2(Vector2(left[0],min_y-.56),Vector2(right[0]-left[0],open_top-min_y+.56))
	if protected.any(func(box):return box.grow(.05).intersects(pocket)):
		return {}
	var max_depth:=0.0
	var safe:=INF
	# Verify the same routes and pen radius used by the actor, including both
	# extreme possible positions of an artist-selected deepest point.
	for depth: float in [.52,.43,.34,.25,.18]:
		var workable:=true
		for ratio: float in [.35,.65]:
			var trench:=Vector2(lerpf(left[0],right[0],ratio),min_y-depth)
			var path:=PackedVector2Array([Vector2(left[0],open_top),Vector2(right[0],open_top),
				Vector2(right[0],right[1]-.04),trench,Vector2(left[0],left[1]-.04),Vector2(left[0],open_top)])
			var steps:=PackedVector2Array([path[0]])
			for i in range(1,path.size()):
				var pieces:=maxi(1,ceili(path[i-1].distance_to(path[i])/.65))
				for part in range(1,pieces+1):
					steps.append(path[i-1].lerp(path[i],float(part)/pieces))
			if Reach.paper_plan([steps],brush).has("error"):
				workable=false
				break
		if workable:
			max_depth=depth
			safe=snappedf(lip_low-.08,.001)
			break
	if max_depth==0.0:
		return {}
	return {"stand":[stand.x,stand.y],"samples":[left,survey[2],right],"shore_samples":survey,
		"open_top":open_top,"max_depth":max_depth,"bed_reference":snappedf(min_y,.001),
		"span":[left[0],right[0]],"banks":[left[1],right[1]],"below_lower_bank":safe,
		"score":width*(.55+max_depth)-absf(lip_high-lip_low)*.5}
