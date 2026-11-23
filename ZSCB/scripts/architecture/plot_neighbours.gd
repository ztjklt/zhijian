extends RefCounted
## Survey a building's surroundings before committing to the first stroke.
## A river under a bridge and a free place on the approach are distinct facts.
const Plans := preload("res://scripts/architecture/building_plans.gd")
const WATER_RADIUS := 24.0
const FRONTAGE := 2.0
const TOLERANCE := .0001

static func _point(p:Vector2) -> Array:
	return [snappedf(p.x,.001),snappedf(p.y,.001)]

static func _native_rims(world, zone:Dictionary, left:float, right:float) -> Array:
	# Cut the native river's surface at every live soil/ink boundary. Query the
	# liquid just inside each resulting interval, including newly filled ones.
	var level:float=zone.height
	var inside:=level-.001
	var cuts:Array[float]=[left,right]
	for polygon:PackedVector2Array in world.paper_geometry(Rect2(left,inside-.01,right-left,.02)):
		for i in polygon.size():
			var a:=polygon[i]
			var b:=polygon[(i+1)%polygon.size()]
			if (a.y>inside)==(b.y>inside):continue
			var x:=lerpf(a.x,b.x,(inside-a.y)/(b.y-a.y))
			if x>left and x<right:cuts.append(x)
	cuts.sort()
	var spans:Array[Vector2]=[]
	for i in range(1,cuts.size()):
		if cuts[i]-cuts[i-1]<=TOLERANCE:continue
		var probe:=Vector2((cuts[i]+cuts[i-1])*.5,inside)
		if world.paper_space.solid_at(probe) or not is_finite(world.terrain.water_surface(probe)):continue
		if not spans.is_empty() and cuts[i-1]-spans[-1].y<=TOLERANCE:
			spans[-1].y=cuts[i]
		else:
			spans.append(Vector2(cuts[i-1],cuts[i]))
	return spans

static func waters(world, stand:Vector2) -> Array:
	var spans:=[]
	var area:=Rect2(stand-Vector2(WATER_RADIUS,WATER_RADIUS),Vector2.ONE*(2*WATER_RADIUS))
	if world.paper_space==null or not stand.is_finite():return spans
	for index in world.terrain.WATER_ZONES.size():
		var zone:Dictionary=world.terrain.WATER_ZONES[index]
		var left:=maxf(zone.left,area.position.x)
		var right:=minf(zone.right,area.end.x)
		if left>=right or absf(zone.height-stand.y)>WATER_RADIUS:continue
		for span:Vector2 in _native_rims(world,zone,left,right):
			spans.append({"source":"native_river","id":"river-%d"%index,"span":span,"level":zone.height})
	for entry:Dictionary in world.paper_space.nearby(area):
		if entry.record.mode!="water":continue
		for section:Dictionary in world.paper_space.basin_sections(entry.record.work_id):
			for portion:Dictionary in section.spans:
				var left:=maxf(portion.left,area.position.x)
				var right:=minf(portion.right,area.end.x)
				if left<right:
					spans.append({"source":"paper_water","id":entry.record.work_id,"span":Vector2(left,right),"level":section.level})
	return spans

static func _nearest(spans:Array,at:Vector2) -> Dictionary:
	var nearest:Dictionary={}
	var shortest:=WATER_RADIUS
	for rim:Dictionary in spans:
		var wet:=Vector2(clampf(at.x,rim.span.x,rim.span.y),rim.level)
		var distance:=at.distance_to(wet)
		if distance<shortest:
			shortest=distance
			nearest={"source":rim.source,"id":rim.id,"span_x_m":_point(rim.span),"water_point_m":_point(wet),
				"from_stand_m":_point(wet-at),"distance_m":snappedf(distance,.001)}
	return nearest

## Allow the author to select one more actual plot near a surveyed bank. The
## usual village, player, here and dry-land choices stay available.
static func bank_plot(game, feet:Vector2, spans:Array, layout:Dictionary, built:Array) -> Dictionary:
	var world=game.medieval_world
	if spans.is_empty():return {}
	var candidates:=[]
	# Several ink basins can split the same river. Survey each floor column
	# once, even when multiple exposed water edges share its two banks.
	var columns:={}
	for rim:Dictionary in spans:
		for side:int in [-1,1]:
			var edge:float=rim.span.x if side<0 else rim.span.y
			for step in range(1,35):
				var column:=roundi(2*edge)+side*step
				var x:=column*.5
				if absf(x-feet.x)>WATER_RADIUS:continue
				columns[column]=true
	for column:int in columns:
		var x:=column*.5
		for face:Dictionary in world.paper_surfaces(x,feet.y-WATER_RADIUS,feet.y+WATER_RADIUS):
			if face.face!="floor":continue
			var stand:=Vector2(x,face.y)
			var from_actor:=feet.distance_to(stand)
			if from_actor>WATER_RADIUS:continue
			var distance_squared:=INF
			for rim:Dictionary in spans:
				# Search for plots on the approach to a bank. A bridge over
				# the river is still measured separately as an existing site.
				if stand.y<rim.level-4.0 or stand.y>rim.level+7.0:continue
				var rim_x:=clampf(stand.x,rim.span.x,rim.span.y)
				distance_squared=minf(distance_squared,stand.distance_squared_to(Vector2(rim_x,rim.level)))
			if distance_squared>=WATER_RADIUS*WATER_RADIUS:continue
			candidates.append({"stand":stand,"distance":sqrt(distance_squared),"from_actor":from_actor})
	candidates.sort_custom(func(a,b):
		if not is_equal_approx(a.distance,b.distance):return a.distance<b.distance
		return a.from_actor<b.from_actor)
	for candidate:Dictionary in candidates:
		var stand:Vector2=candidate.stand
		if world.paper_space.solid_at(stand+Vector2(0,.05)):continue
		var site := {"x":stand.x,"y":stand.y,"width":FRONTAGE}
		if not Plans.interval_occupants(world,site,built,"",true).is_empty():continue
		if not Plans._conflicts(game,layout,stand,built,"",true).is_empty():continue
		# The neutral width checks the three footings. Keep the wet patch out
		# of the reserved interval as well when, e.g., a level pier spans it.
		var wet:=false
		for dx:float in [-FRONTAGE*.45,0.0,FRONTAGE*.45]:
			if is_finite(world.terrain.water_surface(stand+Vector2(dx,.015))):wet=true
		if wet:continue
		var route:Dictionary=world.paper_nav_route(feet,stand)
		if not route.get("ok",false) or Plans.point(route.goal).distance_to(stand)>.25:continue
		return {"id":"bank-plot@%.2f,%.2f"%[stand.x,stand.y],"label":"岸侧空地（距实水 %.1f 米）"%float(candidate.distance),
			"stand":_point(stand),"distance":snappedf(candidate.from_actor,.01)}
	return {}

## An empty square may offer three samples inside the very same shop.
## Look for one independent doorway beside a valid plot when none is listed.
static func second_plot(game,feet:Vector2,plots:Array,layout:Dictionary,built:Array) -> Dictionary:
	if plots.is_empty():return {}
	for i in plots.size():
		for j in range(i+1,plots.size()):
			var delta:=Plans.point(plots[i].stand)-Plans.point(plots[j].stand)
			if absf(delta.x)>=2.5 and delta.length()<=12.0:return {}
	var base:=Plans.point(plots[0].stand)
	var world=game.medieval_world
	for step in range(3,13):
		for direction:int in [-1,1]:
			var x:=base.x+direction*step
			if absf(x-feet.x)>WATER_RADIUS:continue
			for face:Dictionary in world.paper_surfaces(x,base.y-3.0,base.y+3.0):
				if face.face!="floor":continue
				var stand:=Vector2(x,face.y)
				if is_finite(world.terrain.water_surface(stand+Vector2(0,.015))):continue
				if not Plans._conflicts(game,layout,stand,built,"",true).is_empty():continue
				var route:Dictionary=world.paper_nav_route(feet,stand)
				if not route.get("ok",false) or Plans.point(route.goal).distance_to(stand)>.25:continue
				return {"id":"plot@%.2f,%.2f"%[stand.x,stand.y],"label":"另一处门前空地（宽 2 米）",
					"stand":_point(stand),"distance":snappedf(feet.distance_to(stand),.01)}
	return {}

## Relate only plots that have already passed the same real footing,
## occupation and route checks as the ordinary site picker.
static func describe(world, rows:Array) -> void:
	for row:Dictionary in rows:
		var stand:=Plans.point(row.stand)
		row.nearest_water=_nearest(waters(world,stand),stand)
		var other_plots:=[]
		for other:Dictionary in rows:
			if other.id==row.id or not other.frontages.any(func(f):return f.level_site_clear):continue
			var there:=Plans.point(other.stand)
			if is_finite(world.terrain.water_surface(there+Vector2(0,.015))):continue
			var delta:=there-stand
			# Distinct two-metre building pads need a clear gap for a doorway.
			if absf(delta.x)<2.5 or delta.length()>12.0:continue
			other_plots.append({"site":other.id,"stand_m":_point(there),"from_stand_m":_point(delta),"distance_m":snappedf(delta.length(),.001)})
		other_plots.sort_custom(func(a,b):return a.distance_m<b.distance_m)
		row.adjacent_sites=other_plots.slice(0,2)
