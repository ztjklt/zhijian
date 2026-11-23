extends RefCounted
## Readable geometry and confirmed footing. The reported profile is not a stroke.
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Market := preload("res://scripts/architecture/market_sites.gd")
const Passage := preload("res://scripts/paper_waterway.gd")
const Channel := preload("res://scripts/paper_channel_survey.gd")
const Senses := preload("res://scripts/companion_senses.gd")
const Reach := preload("res://scripts/companion_pen_reach.gd")

static func _approaches(game,feet:Vector2,left:float,right:float,deck_y:float) -> Array:
	var world=game.medieval_world
	var seen:Array=[]
	for side:int in [-1,1]:
		var edge:=left if side<0 else right
		for i in range(1,25):
			var x:=edge+side*float(i)*.5
			for face:Dictionary in world.paper_surfaces(x,deck_y-6.0,deck_y-Passage.HEADROOM+.25):
				if face.face!="floor":continue
				var stand:=Vector2(x,face.y)
				if stand.distance_to(feet)>28.0 or not Senses.clear_circle(game,stand+Vector2(0,.5),.24,9):continue
				seen.append({"stand":Plans.coords(stand),"score":stand.distance_to(feet)+absf(stand.y-(deck_y-2.65))*.7,
					"side":side,"support":face.work_id})
	var routes:Array=[]
	for side:int in [-1,1]:
		var list:=seen.filter(func(row):return row.side==side)
		list.sort_custom(func(a,b):return a.score<b.score)
		var count:=0
		for row:Dictionary in list.slice(0,24):
			var at:=Plans.point(row.stand)
			var spacing:=.45 if str(row.support).begins_with("companion-") else .92
			if routes.any(func(other):return Plans.point(other.stand).distance_to(at)<spacing):continue
			var route:Dictionary=world.paper_nav_route(feet,at)
			if not route.get("ok",false) or Plans.point(route.goal).distance_to(at)>.25:continue
			row.erase("score")
			row.id="underpass@%.2f,%.2f"%[at.x,at.y]
			row.label="廊下实测低脚面 %.1f 米"%at.x
			row.distance=snappedf(at.distance_to(feet),.01)
			routes.append(row)
			count+=1
			if count==3:break
	return routes

static func _blocked_stands(project:Dictionary) -> Array:
	var misses:Array=[]
	var outcomes:Array=project.get("outcomes",[])
	for index in range(outcomes.size()-1, max(-1,outcomes.size()-10),-1):
		var row:Dictionary=outcomes[index]
		if row.ok and not row.get("work_ids",[]).is_empty():break
		var id:String=str(row.get("id",""))
		if row.get("tool")!="scene_reposition" or row.ok or not id.begins_with("underpass@"):continue
		var parts:=id.trim_prefix("underpass@").split(",")
		if parts.size()!=2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():continue
		misses.append({"id":id,"stand":[float(parts[0]),float(parts[1])],"detail":row.detail})
	return misses

static func _next_lower_edge(game, project:Dictionary, brush:Dictionary, passage:Dictionary, current:Dictionary) -> Dictionary:
	if current.is_empty():return {}
	var feet:=Plans.point(brush.feet)
	var middle:float=(passage.footprint[0]+passage.footprint[1])*.5
	var opposite:int=1 if feet.x<middle else -1
	var stands:Array=passage.reachable_lower_approaches.filter(func(row):
		return row.side==opposite and float(row.stand[1])+Passage.DRAFT+Passage.HEADROOM<float(passage.counter_at[1]))
	if stands.is_empty():return {}
	var lowest:Dictionary=stands[0]
	for stand:Dictionary in stands:
		if float(stand.stand[1])<float(lowest.stand[1]):lowest=stand
	var gauge:=snappedf(float(lowest.stand[1])+Passage.DRAFT,.02)
	var survey:=Channel.observe(game,project,brush,Passage.WIDTH,gauge)
	for layer:Dictionary in survey.get("sections",[]):
		if absf(float(layer.level)-gauge)>.002:continue
		return {"from_current_hand":current.hand,"opposite_reachable_route":lowest.id,"opposite_foot":lowest.stand,
			"proposal_is_measured_only":true,"level":layer.level,"bank_faces":layer.bank_faces,
			"solid_earth":layer.solid_earth,"furniture":layer.furniture,
			"wet_clear":layer.wet_clear,"under_building_wet":layer.under_building_wet,
			"hand_at_waterline":layer.hand_at_waterline}
	return {}

static func _grade_stands(brush:Dictionary,approaches:Array,level:float,window:Array) -> Array:
	var grip:=Plans.point(brush.hand)
	var feet:=Plans.point(brush.feet)
	var grip_height:=clampf(grip.y-feet.y,.46,1.0)
	var result:Array=[]
	for route:Dictionary in approaches:
		var stand:=Plans.point(route.stand)
		var grip_y:=stand.y+grip_height
		var keel:=level-Passage.DRAFT
		var crown:=level+Passage.HEADROOM
		var drop:=maxf(absf(grip_y-keel),absf(grip_y-crown))
		if drop>=Reach.PLAN_RADIUS:continue
		var side:=sqrt(Reach.PLAN_RADIUS*Reach.PLAN_RADIUS-drop*drop)
		var left:=maxf(stand.x-side,float(window[0]))
		var right:=minf(stand.x+side,float(window[1]))
		if right-left<.08:continue
		result.append({"route":route.id,"bank":route.bank,"foot":route.stand,"reach_estimate":[left,right],
			"from_keel_to_clearance_top":[keel,crown]})
	return result

static func _water_seams(layer:Dictionary) -> Array:
	var wet:Array=layer.wet_clear
	var result:Array=[]
	for i in range(1,wet.size()):
		var left:float=wet[i-1][1]
		var right:float=wet[i][0]
		if right-left<=Passage.EPS or right-left>2.0:continue
		var in_hand:bool=layer.hand_at_keel.any(func(span):return span[0]<=left and span[1]>=right) and \
			layer.hand_at_waterline.any(func(span):return span[0]<=left and span[1]>=right)
		var blockers:Array=layer.all_obstructions.filter(func(span):return span[0]<right-Passage.EPS and span[1]>left+Passage.EPS)
		result.append({"span":[left,right],"length_m":right-left,"level":layer.level,
			"keel":float(layer.level)-Passage.DRAFT,"in_hand":in_hand,"obstructions":blockers})
	return result.slice(0,6)

static func survey(game,project:Dictionary,brush:Dictionary,passage:Dictionary) -> Dictionary:
	var current:=Channel.observe(game,project,brush)
	if current.is_empty():return current
	current.opposite_bank_preview=_next_lower_edge(game,project,brush,passage,current)
	var plans:Array=project.get("channel_plan",{}).get("sections",[])
	var planned:=plans.filter(func(row):return row.get("kind")=="water" and (row.get("level") is float or row.get("level") is int))
	if not planned.is_empty():
		var level:float=planned[0].level
		var gauge:=Channel.observe(game,project,brush,Passage.WIDTH,level)
		for layer:Dictionary in gauge.get("sections",[]):
			if not is_equal_approx(float(layer.level),level):continue
			current.planned_water_profile={"section_id":planned[0].id,"level":layer.level,
				"window":gauge.window,"solid_earth":layer.solid_earth,"furniture":layer.furniture,
				"dry_clear":layer.dry_clear,"wet_clear":layer.wet_clear,"wet_seams":_water_seams(layer),"under_building_wet":layer.under_building_wet,
				"open_water_mouths":layer.open_water_mouths,"through_both_open_sides":layer.through_both_open_sides,
				"hand_at_keel":layer.hand_at_keel,"hand_at_waterline":layer.hand_at_waterline,"hand_at_crown":layer.hand_at_crown,
				"candidate_grade_stands":_grade_stands(brush,passage.reachable_lower_approaches,level,gauge.window)}
			break
	return current

static func observe(game,project:Dictionary,feet:Vector2) -> Dictionary:
	if not project.get("boat",false) or project.get("trade_targets",[]).is_empty():return {}
	for obj:Dictionary in game.objects:
		if not obj.get("structure_id","") in project.trade_targets or not obj.get("work_id","") in project.work_ids:continue
		var spots:=Market._built_spots(game,obj)
		if spots.is_empty():continue
		var stand:Vector2=spots[0].at
		var native:=Passage.at_building(game,project,stand)
		if not native.has("frontage"):continue
		var left:float=native.frontage[0]
		var right:float=native.frontage[1]
		var blocked:=_blocked_stands(project)
		var approaches:=_approaches(game,feet,left,right,stand.y).filter(func(route):
			var bank:=Plans.point(route.stand)
			return not blocked.any(func(row):return bank.distance_to(Plans.point(row.stand))<1.02))
		for route:Dictionary in approaches:
			route.bank="west" if route.side<0 else "east"
			route.label=("西岸" if route.side<0 else "东岸")+" · "+route.label
			route.towards_cabinet_x=1 if route.side<0 else -1
		var meta:Dictionary=obj.built_plan
		var supports:Array=meta.layout.supports.map(func(point):
			return Senses.pair(game.object_point(obj,Plans.point(meta.offset)+Plans.point(point))))
		return {"counter":obj.name,"counter_work_id":obj.work_id,"counter_at":Senses.pair(stand),"original_footings":supports,
			"as_built_clearance":native,"reachable_lower_approaches":approaches,"recent_blocked_approaches":blocked,
			"footprint":[left,right],"requirement":{"width":Passage.WIDTH,"draft":Passage.DRAFT,"headroom":Passage.HEADROOM}}
	return {}
