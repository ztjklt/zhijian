extends RefCounted

const Senses := preload("res://scripts/companion_senses.gd")
const BRUSH_LENGTH := 1.8
# Leave room for the hand to change sides and for the last step into position.
const PLAN_RADIUS := BRUSH_LENGTH - 0.44

static func observe(game, actor, sites: Array) -> Dictionary:
	var at: Vector2 = actor.player.position
	var hand: Vector2 = actor.hand_world()
	var floor_hit := Senses.floor_at(game,at.x,at.y+0.22,1.5)
	var stations := [{"x":at.x,"grip":Senses.pair(hand)}]
	if not floor_hit.is_empty():
		var hand_height := clampf(hand.y-Vector2(floor_hit.position).y,0.23,0.8)
		for site in sites:
			var foot := Vector2(site.stand[0],site.stand[1])
			stations.append({"x":foot.x,"grip":Senses.pair(foot+Vector2(0,hand_height))})
	return {"radius":PLAN_RADIUS,"stations":stations}

static func observe_paper(game, actor, fine_stations:=false) -> Dictionary:
	var world=game.medieval_world
	var body:Vector2=actor.player.position
	var feet:=body-Vector2(0,.29)
	var hand:Vector2=actor.hand_world()
	var grounded:bool=actor.on_ground and not actor.player.support_bodies().is_empty()
	var stations:= []
	var support:= []
	var blocked_departure:=""
	if grounded:
		stations.append({"feet":Senses.pair(feet),"grip":Senses.pair(Vector2(feet.x,hand.y)),"current":true})
		if fine_stations:
			stations.append({"feet":Senses.pair(feet),"grip":Senses.pair(hand),"current":true,"measured_hand":true,"radius":BRUSH_LENGTH-.12})
		var contact:=Senses.floor_at(game,feet.x,feet.y+.16,.54)
		if not contact.is_empty():support=Senses.pair(contact.position)
	var offsets:=[0.0,-.9,.9,-1.8,1.8,-2.7,2.7,-3.6,3.6]
	if fine_stations:offsets.append_array([-.45,.45,-1.35,1.35])
	for offset in offsets:
		var x:=snappedf(feet.x+float(offset),.01)
		for face in world.paper_surfaces(x,feet.y-4.1,feet.y+2.0):
			if face.face!="floor":continue
			var stand:=Vector2(x,face.y)
			if stand.distance_to(feet)<.32:continue
			if not Senses.clear_circle(game,stand+Vector2(0,.53),.25,9):continue
			var route:Dictionary=world.paper_nav_route(feet,stand)
			if not route.get("ok",false) or point(route.goal).distance_to(stand)>.18:continue
			var blocked:=_blocked_landing(game,route.steps)
			if not blocked.is_empty():
				blocked_departure=blocked
				continue
			stations.append({"feet":Senses.pair(stand),"grip":Senses.pair(stand+Vector2(0,clampf(hand.y-feet.y,.46,1.0))),
				"surface":str(face.work_id)})
	var result:={"hand":Senses.pair(hand),"feet":Senses.pair(feet),"support":support,"reach":BRUSH_LENGTH,"radius":PLAN_RADIUS,
		"grounded":grounded,"stations":stations}
	if not blocked_departure.is_empty():result.blocked_departure=blocked_departure
	return result

static func point(coords:Array) -> Vector2:
	return Vector2(coords[0],coords[1])

static func _blocked_landing(game, steps:Array) -> String:
	for step in steps:
		if step.kind!="drop":continue
		var start:=point(step.from)
		var landing:=point(step.to)
		var hit:=Senses.floor_at(game,landing.x,start.y+.12,start.y-landing.y+.36)
		if not hit.is_empty() and float(hit.position.y)-landing.y>.30:
			return "落点 (%.2f, %.2f) 上方 %.2f 米处还有物理支撑，挡住这条下落路线" % [landing.x,landing.y,hit.position.y]
	return ""

static func paper_plan(lines:Array, brush:Dictionary) -> Dictionary:
	var steps:= []
	var previous:=point(brush.feet)
	for i in lines.size():
		var row:= []
		var line:PackedVector2Array=lines[i]
		for j in range(1,line.size()):
			var nearest:={}
			var picked:={}
			var needed:=INF
			var shortest:=INF
			for station in brush.stations:
				var grip:=point(station.grip)
				var distance:=maxf(grip.distance_to(line[j-1]),grip.distance_to(line[j]))
				if distance<needed:
					nearest=station
					needed=distance
				var radius:=minf(BRUSH_LENGTH,float(station.get("radius",PLAN_RADIUS)))
				if distance>radius:continue
				var walk:=previous.distance_to(point(station.feet))
				if walk<shortest:
					picked=station
					shortest=walk
			if picked.is_empty():
				var hint := "附近未测到可用的站位"
				if not nearest.is_empty():
					hint="最近站位 (%.2f, %.2f)，整段需 %.2f 米" % [nearest.feet[0],nearest.feet[1],needed]
				if brush.has("blocked_departure"):hint+="。"+brush.blocked_departure
				return {"error":"第%d笔第%d段超出笔程。%s，请缩短、抬高或换站位。" % [i+1,j,hint],
					"stroke":i+1,"segment":j,"from":Senses.pair(line[j-1]),"to":Senses.pair(line[j]),
					"nearest_station":nearest,"needed":snappedf(needed,.01) if is_finite(needed) else null}
			row.append(picked)
			previous=point(picked.feet)
		steps.append(row)
	return {"stands":steps}

## Both ends in one disc guarantee that its entire straight segment is in reach.
static func plan(lines: Array, reach: Dictionary, initial_x: float) -> Dictionary:
	var rows := []
	var previous := initial_x
	for i in lines.size():
		var row := PackedFloat32Array()
		var line: PackedVector2Array = lines[i]
		for j in range(1,line.size()):
			var best := INF
			var x := INF
			for station in reach.stations:
				var grip := Vector2(station.grip[0],station.grip[1])
				var distance := maxf(grip.distance_to(line[j-1]),grip.distance_to(line[j]))
				if distance > reach.radius: continue
				var walk := absf(previous-float(station.x))
				if walk<best: best=walk; x=station.x
			if not is_finite(x):
				return {"error":"第%d笔第%d段超出站位笔程，请缩矮或移近，保留原色重画" % [i+1,j],"stroke":i+1,"segment":j}
			row.append(x)
			previous = x
		rows.append(row)
	return {"stands":rows}
