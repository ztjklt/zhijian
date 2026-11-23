extends RefCounted
## The local action budget, observable facts and public record of a character's current job.

const MEMORY := 8
const Guild := preload("res://scripts/village_guild.gd")

var paused := false
var used := 0
var budget := 0
var goal := ""
var reason := ""
var progress := ""
var history: Array = []
var engineering := {}
var safe_at := Vector2.INF
var revision := ""

func set_paused(value: bool) -> void:
	paused = value
	if not paused and budget>0 and used>=budget: used=0

func set_budget(value: int) -> void:
	budget=clampi(value,0,1000)
	used=0

func available() -> bool:
	return not paused and (budget==0 or used<budget)

func status(connection: Dictionary) -> Dictionary:
	var stop := "玩家已暂停自主行动" if paused else "自主行动预算已用完，可手动续开" if budget>0 and used>=budget else ""
	if stop.is_empty() and not connection.ready: stop = connection.message
	return {"goal":goal,"reason":reason,"progress":progress,"autonomy_paused":paused,
		"pause_reason":stop,"used":used,"budget":budget}

func accept(command: Dictionary, fallback: String) -> void:
	var public: Dictionary = command.get("public_action",{})
	goal = _text(public.get("goal",fallback),32)
	if goal.is_empty(): goal=fallback
	reason = _text(public.get("reason",""),56)
	progress = "刚作出决定"
	if command.get("tool") in ["travel","paint_edge","shape_site","paper_ink"]:
		engineering = {"goal":goal,"reason":reason,"action":command.tool,"stage":"执行中"}

func record(action: String, result: String, ok: bool, at: Vector2) -> void:
	progress = _text(result,78)
	history.append({"action":action,"ok":ok,"result":progress,"x":snappedf(at.x,.1)})
	if history.size()>MEMORY: history.pop_front()
	if engineering.get("action")==action:
		engineering.stage="待调整" if not ok else "已到现场，待查验" if action=="travel" else "已完成"
		engineering.result=progress

func snapshot() -> Dictionary:
	return {"v":1,"paused":paused,"used":used,"budget":budget,"goal":goal,"reason":reason,"progress":progress,
		"history":history.duplicate(true),"engineering":engineering.duplicate(),
		"safe_at":[safe_at.x,safe_at.y] if safe_at.is_finite() else []}

func restore(value: Variant) -> void:
	if not value is Dictionary or value.get("v")!=1: return
	paused = value.get("paused")==true
	var saved_budget = value.get("budget",0)
	var saved_used = value.get("used",0)
	budget = clampi(int(saved_budget),0,1000) if (saved_budget is float or saved_budget is int) and is_finite(saved_budget) else 0
	used = clampi(int(saved_used),0,1000000) if (saved_used is float or saved_used is int) and is_finite(saved_used) else 0
	goal = _text(value.get("goal",""),32)
	reason = _text(value.get("reason",""),56)
	progress = _text(value.get("progress",""),78)
	var project = value.get("engineering",{})
	if project is Dictionary and project.get("action") in ["travel","paint_edge","shape_site","paper_ink"]:
		for key in ["goal","reason","action","stage","result"]: engineering[key]=_text(project.get(key,""),78)
	for row in value.history.slice(-MEMORY) if value.get("history") is Array else []:
		if row is Dictionary and (row.get("x") is float or row.get("x") is int):
			if is_finite(float(row.x)) and absf(row.x)<4000:
				history.append({"action":_text(row.get("action",""),32),"result":_text(row.get("result",""),78),"ok":row.get("ok")==true,"x":row.x})
	var point = value.get("safe_at")
	if pair(point): safe_at=Vector2(point[0],point[1])

static func _text(value: Variant, limit: int) -> String:
	return value.replace("\n"," ").replace("\r"," ").strip_edges().left(limit) if value is String else ""

static func pair(value: Variant) -> bool:
	return value is Array and value.size()==2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int) \
		and is_finite(float(value[0])) and is_finite(float(value[1]))

static func motion_bounds(world) -> Rect2:
	if world.has_method("paper_motion_bounds"):
		var area: Rect2 = world.paper_motion_bounds()
		return Rect2(area.position-Vector2(0,8),area.size+Vector2(0,16))
	return Rect2(-4.0,-11.0,world.east_walk_limit()+4.0,51.0)

static func in_world(world, point: Vector2) -> bool:
	return point.is_finite() and motion_bounds(world).grow(.3).has_point(point)

func remember_ground(world, body) -> void:
	var at: Vector2 = body.player.position
	if body.on_ground and in_world(world,at): safe_at=at

func respawn(world, home: float) -> Vector2:
	return safe_at+Vector2(0,.12) if in_world(world,safe_at) else world.safe_spawn_position(home)

static func scope(game) -> Dictionary:
	var slot = game.get("team_slot")
	var result := {}
	if slot != null:
		for field in ["world_id","team_id","slot_id"]:
			var value = slot.get(field)
			if value is String: result[field]=value
	return result

func sense(game, at: Vector2, role: String) -> Dictionary:
	var world = game.medieval_world
	var edge: Dictionary = world.observe_east_edge()
	var routes := []
	for index in world.SECTIONS.size():
		var section: Dictionary = world.SECTIONS[index]
		routes.append(_route(world,at,section.x,"region-%d"%index,section.name))
	var end: float = world.east_walk_limit()
	if edge.revision<edge.limits.max_segments and not edge.busy:
		routes.append(_route(world,at,end-1.1,"east-frontier","东侧纸边"))
	var paper := {}
	if world.has_method("paper_surfaces") and world.has_method("apply_paper_plan"):
		var cell: Vector2i=world.paper_cell_at(at)
		if world.has_method("paper_nav_sites"):
			for site in world.paper_nav_sites(at-Vector2(0,.29),8):
				if not pair(site.get("at")):continue
				var distance:=at.distance_to(Vector2(site.at[0],site.at[1]+.29))
				if distance>.75:
					routes.append({"id":site.id,"label":site.get("label","附近纸页"),"stand":site.at,"distance":snappedf(distance,.01)})
		var samples := []
		for ox in [-3.0,-1.5,0.0,1.5,3.0]:
			var x := snappedf(at.x+ox,.01)
			samples.append({"x":x,"faces":world.paper_surfaces(x,at.y-4,at.y+4)})
		var bounds := motion_bounds(world)
		paper={"cell":[cell.x,cell.y],"extent":[bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y],"surfaces":samples,
			"modes":["platform","rock","carve","backdrop","scenery","water"]}
		if role == "companion" and world.paper_space != null:
			paper.nearby_waterlines = preload("res://scripts/paper_channel_survey.gd").nearby_waterlines(world, at)
		var foot := _floor_near(world,at-Vector2(0,.48),.44)
		paper.local_gaps=[]
		if foot.is_finite():
			paper.current_floor=_coords(foot)
			for direction in [-1,1]:
				var ahead:float=foot.x+float(direction)*1.8
				if _floor_near(world,Vector2(ahead,foot.y),1.3).is_finite(): continue
				var seam:=foot
				for offset in [.3,.65,1.0,1.35]:
					var floor_at:=_floor_near(world,Vector2(foot.x+offset*direction,seam.y),.36)
					if not floor_at.is_finite(): break
					seam=floor_at
				paper.local_gaps.append({"side":"west" if direction<0 else "east","seam":_coords(seam),
					"probe_x":snappedf(ahead,.01),"no_walkable_floor_within_y":1.3})
		var old_west: float=world.terrain.profile[0].x
		if bounds.position.x<old_west-.5:
			routes.append(_route(world,at,old_west+.2,"west-edge","原村西侧纸边"))
		for record in world.paper_strokes_snapshot():
			if record.get("mode")!="carve" or not str(record.get("work_id","")).begins_with("village:west-gallery"): continue
			var eastmost: float=-INF
			var westmost: float=INF
			for point in record.points:
				eastmost=maxf(eastmost,point[0]);westmost=minf(westmost,point[0])
			var x := eastmost-minf(4.0,(eastmost-westmost)*.25)
			var entry := _route(world,at,x,"west-mouth","村西山洞入口")
			for surface in world.paper_surfaces(x,-INF,INF):
				if surface.face=="floor":
					entry.stand[1]=surface.y
					break
			routes.append(entry)
			break
	var local_ground := []
	for offset in range(-4,5):
		var x := at.x+offset
		var ground := _floor_near(world,Vector2(x,at.y-.48),maxf(1.3,.7*absf(offset)))
		local_ground.append([snappedf(x,.01),snappedf(ground.y,.01) if ground.is_finite() else null])
	var works := []
	if world.paper_space!=null:
		for record in world.paper_space.works:
			if works.size()>=8: break
			var anchor:Array=record.anchor.at
			if at.distance_to(Vector2(anchor[0],anchor[1]))>16: continue
			works.append({"id":record.work_id,"name":record.get("name",record.mode),"kind":record.mode,"author":record.author_id,"at":anchor})
	for object in game.objects:
		if absf(float(object.x)-at.x)>18 or works.size()>=12: continue
		var signed: Dictionary = object.get("built_plan",{})
		works.append({"id":object.get("work_id",object.get("structure_id","")),"x":snappedf(object.x,.1),
			"kind":object.get("pen",object.kind),"author":object.get("author_id",signed.get("owner",object.get("artist",""))),
			"name":object.get("name",object.kind)})
	var survival := {}
	if world.survival != null:
		survival = {"fruit_at_tree":world.survival.fruit_count(),"ore_left":world.survival.ore_left,
			"guild_x":Guild.COUNTER_X,"vein_x":Guild.VEIN_X}
		if world.survival.has_method("decision_facts"):
			survival.merge(world.survival.decision_facts(role,at,16.0),true)
	var landmarks := []
	for segment in world.terrain.east_ink.segments.slice(-6):
		landmarks.append({"id":segment.get("work_id",""),"name":segment.name,"landmark":segment.get("landmark",""),
			"from":segment.points[0][0],"to":segment.points.back()[0]})
	var same_count:=0
	var latest: Dictionary=history.back() if not history.is_empty() else {}
	for index in range(history.size()-1,-1,-1):
		if history[index].action!=latest.action: break
		same_count+=1
	return {"scope":scope(game),"role":role,"local_ground":local_ground,"routes":routes,"paper":paper,
		"frontier":{"x":edge.edge[0],"segments":edge.revision,"busy":edge.busy,
			"previous_name":edge.previous_name,"room":edge.revision<edge.limits.max_segments},
		"landmarks":landmarks,"works":works,"survival":survival,"history":history.duplicate(true),
		"engineering":engineering.duplicate(),"same_action_in_a_row":same_count,
		"world_changed_since_last_observation":not revision.is_empty() and revision!=change_key(game),
		"previous_goal":goal,"budget_remaining":maxi(0,budget-used) if budget>0 else null}

static func _coords(point:Vector2) -> Array:
	return [snappedf(point.x,.01),snappedf(point.y,.01)]

static func _floor_near(world, point: Vector2, tolerance: float) -> Vector2:
	var best := Vector2.INF
	for surface in world.paper_surfaces(point.x,point.y-tolerance,point.y+tolerance):
		if surface.face=="floor" and absf(surface.y-point.y)<absf(best.y-point.y): best=Vector2(point.x,surface.y)
	return best

static func _route(world, at: Vector2, x: float, id: String, label: String) -> Dictionary:
	var cursor := at.x
	var rise := 0.0
	var step := .5*signf(x-cursor)
	var continuous := true
	while absf(x-cursor)>.5:
		var next := cursor+step
		var from_y:float=world.travel_height(cursor)
		var to_y:float=world.travel_height(next)
		if not is_finite(from_y) or not is_finite(to_y): continuous=false
		else: rise=maxf(rise,absf(to_y-from_y))
		cursor = next
	var height:float=world.travel_height(x)
	return {"id":id,"label":label,"stand":[snappedf(x,.01),snappedf(height,.01) if is_finite(height) else null],
		"distance":snappedf(absf(x-at.x),.1),"largest_half_metre_rise":snappedf(rise,.01) if continuous else null}

static func change_key(game) -> String:
	var world = game.medieval_world
	var s = world.survival
	return str([world.terrain.east_ink.segments.size(),world.paper_space.epoch if world.paper_space!=null else 0,
		game.objects.size(),s.fruit_count() if s!=null else 0,
		s.ore_left if s!=null else 0])
