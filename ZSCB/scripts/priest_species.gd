extends RefCounted
## Joint frames are local metres. Parents precede children in the sheet.
const SCHEMA := "species-ink-v1"
const ACTIONS := ["ground_walk","sense_food","graze_bark","graze_grass","eat_ground_fruit","avoid_people","flee","hunt_livestock","threaten_people","guard_food","fly"]
const MAX_LIVE := 8
const MAX_WORKS := 128
const MAX_PLANS := 96

static func scalar(n, low: float, high: float) -> bool:
	return (n is float or n is int) and is_finite(float(n)) and n>=low and n<=high

static func pair(p, limit: float) -> bool:
	return p is Array and p.size()==2 and scalar(p[0],-limit,limit) and scalar(p[1],-limit,limit)

static func vec(p: Array) -> Vector2:
	return Vector2(p[0],p[1])

## Control points are in the same metre coordinates as the numbered anchors.
## Mouth tips and joint references keep their original anchor numbers.
static func contour(part: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var anchors: Array = part.outline
	var controls := {}
	var bends = part.get("edge_bends", [])
	if not bends is Array or bends.size() > anchors.size(): return points
	for bend in bends:
		if not bend is Dictionary or not scalar(bend.get("edge"),0,anchors.size()-1) or not pair(bend.get("control"),2.5): return points
		var edge := int(bend.edge)
		if edge != bend.edge or controls.has(edge): return points
		controls[edge] = vec(bend.control)
	for i in anchors.size():
		var start := vec(anchors[i])
		points.append(start)
		if not controls.has(i): continue
		var finish := vec(anchors[(i+1) % anchors.size()])
		var control: Vector2 = controls[i]
		var sag := (start - 2*control + finish).length()/4.0
		var slices := clampi(ceili(sqrt(sag/.006)),1,16)
		for j in range(1,slices):
			var t := float(j)/slices
			points.append(start.lerp(control,t).lerp(control.lerp(finish,t),t))
	return points

static func _on_segment(point: Vector2, start: Vector2, finish: Vector2) -> bool:
	if start == finish: return point.distance_squared_to(start) <= 1e-12
	var nearest := Geometry2D.get_closest_point_to_segment(point,start,finish)
	return point.distance_squared_to(nearest) <= 1e-12

static func _simple_curve(shape: PackedVector2Array) -> bool:
	for i in shape.size():
		var a:=shape[i]
		var b:=shape[(i+1)%shape.size()]
		var previous:=shape[(i+shape.size()-1)%shape.size()]
		if a.distance_squared_to(b)<=1e-12 or _on_segment(b,previous,a) or _on_segment(previous,a,b): return false
		for j in range(i+2,shape.size()):
			if i==0 and j==shape.size()-1: continue
			var c:=shape[j]
			var d:=shape[(j+1)%shape.size()]
			if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return false
			if _on_segment(a,c,d) or _on_segment(b,c,d) or _on_segment(c,a,b) or _on_segment(d,a,b): return false
	return true

static func mark_bounds(part: Dictionary) -> Rect2:
	if part.get("edge_bends",[]).is_empty(): return Rect2()
	var bounds:=Rect2(vec(part.outline[0]),Vector2.ZERO)
	for anchor in part.outline: bounds=bounds.expand(vec(anchor))
	return bounds

static func valid(d: Variant) -> bool:
	if not d is Dictionary or d.get("schema")!=SCHEMA or not d.get("name") is String or d.name.strip_edges()=="" or d.name.length()>24: return false
	if not d.get("edible") is bool or not scalar(d.get("pace"),.5,3.5) or not scalar(d.get("sight"),3,18): return false
	if d.get("favorite","oak") not in ["oak","pine","orchard_tree"]: return false
	if not d.get("actions") is Array or d.actions.size()>ACTIONS.size(): return false
	var seen:={}
	for a in d.actions:
		if a not in ACTIONS or seen.has(a): return false
		seen[a]=true
	if seen.is_empty():return false
	if (seen.has("eat_ground_fruit") or seen.has("graze_grass") or seen.has("graze_bark") or seen.has("hunt_livestock")) and not seen.has("sense_food"):return false
	if (seen.has("hunt_livestock") or seen.has("flee") or seen.has("avoid_people")) and not seen.has("ground_walk"):return false
	if not d.get("parts") is Array or d.parts.size()<3 or d.parts.size()>16:return false
	var pivots:={}
	var bounds:=Rect2()
	var actuated:=false
	var wings:=0
	if not scalar(d.get("flight_height",1.7),.8,3.0):return false
	for part in d.parts:
		if not part is Dictionary or not part.get("id") is String or not part.id.is_valid_identifier() or part.id.length()>32 or pivots.has(part.id):return false
		if not part.get("parent") is String or (part.parent!="" and not pivots.has(part.parent)) or (part.parent=="")!=pivots.is_empty():return false
		if not pair(part.get("joint"),2.5) or part.get("motion") not in ["fixed","stride","sway","jaw","flap"] or not scalar(part.get("phase"),0,1):return false
		if part.has("study") and (not part.study is String or not part.study.is_valid_identifier() or part.study.length()>48):return false
		if part.has("study_scale") and (not part.has("study") or not pair(part.study_scale,2.5) or part.study_scale[0]<.2 or part.study_scale[1]<.2):return false
		if part.get("depth","body") not in ["far","body","near"] or not scalar(part.get("wash",0),0,1):return false
		if not part.get("pigment") is String or part.pigment.length()!=7 or not part.pigment.begins_with("#") or not part.pigment.substr(1).is_valid_hex_number(false):return false
		if not part.get("outline") is Array or part.outline.size()<3 or part.outline.size()>12:return false
		var origin:Vector2=pivots.get(part.parent,Vector2.ZERO)+vec(part.joint)
		for xy in part.outline:
			if not pair(xy,2.5):return false
		var shape:=contour(part)
		if shape.size()<3:return false
		if part.has("edge_bends") and not part.edge_bends.is_empty() and not _simple_curve(shape): return false
		for point in shape: bounds=bounds.expand(origin+point)
		if Geometry2D.triangulate_polygon(shape).size()!=(shape.size()-2)*3:return false
		if part.has("marks") and not preload("res://scripts/priest_part_marks.gd").valid(part.marks,shape,mark_bounds(part)): return false
		pivots[part.id]=origin
		if not scalar(part.get("rate",1),.5,3) or not scalar(part.get("amplitude",.4),0,1.1):return false
		if part.motion in ["stride","sway"] and part.get("amplitude",.4)>.02:actuated=true
		if part.motion=="flap" and part.get("amplitude",.55)>=.15:wings+=1
	if seen.has("eat_ground_fruit"):
		var bite=d.get("fruit_bite")
		if not bite is Dictionary or not bite.get("part_id") is String or not bite.get("pivot_id") is String or not scalar(bite.get("dip"),-1.4,1.4) or not scalar(bite.get("vertex"),0,11) or floorf(bite.vertex)!=bite.vertex:return false
		var mouth:Array=d.parts.filter(func(p):return p.id==bite.get("part_id"))
		if mouth.is_empty() or bite.vertex>=mouth[0].outline.size() or not pivots.has(bite.get("pivot_id")):return false
		var parents:={}
		for part in d.parts:parents[part.id]=part.parent
		var ancestor:String=mouth[0].id
		while ancestor!="" and ancestor!=bite.pivot_id:ancestor=parents[ancestor]
		if ancestor=="":return false
		var rest:=frames(d.parts,0,"rest",0)
		var floor_y:=INF
		for part in d.parts:
			for point in contour(part):
				var tip:Vector2=rest[part.id]*point
				floor_y=minf(floor_y,tip.y)
		var feeding:=frames(d.parts,0,"pickup",.5,bite)
		var tip:Vector2=feeding[bite.part_id]*vec(mouth[0].outline[int(bite.vertex)])
		if tip.y-floor_y<-.035 or tip.y-floor_y>.235:return false
	elif d.has("fruit_bite"):return false
	return (not seen.has("fly") or wings>=2) and (actuated or not seen.has("ground_walk")) and bounds.size.x>=.25 and bounds.size.x<=4.5 and bounds.size.y>=.2 and bounds.size.y<=3.0

static func only_part_changed(before: Dictionary, after: Dictionary, part_id: String) -> bool:
	if not before.has("parts") or not after.has("parts") or before.parts.size()!=after.parts.size():return false
	var merged:=before.duplicate()
	merged.parts=before.parts.duplicate()
	for i in before.parts.size():
		if before.parts[i].id!=part_id:continue
		if after.parts[i].id!=part_id or before.parts[i]==after.parts[i]:return false
		merged.parts[i]=after.parts[i]
		return merged==after
	return false

# A planted animal sights along the authored muzzle, lowers to the measured
# vertex, and lifts it clear before returning to its resting silhouette.
static func fruit_head_angle(dip:float, fraction:float) -> float:
	var t:=clampf(fraction,0.0,1.0)
	var lifted:float=clampf(-dip*.26,-.25,.25)
	if t<.16:return lerpf(0.0,lifted,smoothstep(0.0,.16,t))
	if t<.48:return lerpf(lifted,dip,smoothstep(.16,.48,t))
	if t<.56:return dip
	if t<.86:return lerpf(dip,lifted,smoothstep(.56,.86,t))
	return lerpf(lifted,0.0,smoothstep(.86,1.0,t))

static func frames(parts: Array, stride: float, activity: String, bite: float, fruit_bite:Dictionary={}) -> Dictionary:
	var transforms:={}
	for part in parts:
		var swing:=0.0
		var wave:=sin(stride*float(part.get("rate",1.0))+TAU*float(part.phase))
		if activity in ["walk","search","flee","chase"]:
			match part.motion:
				"stride":swing=float(part.get("amplitude",.39))*wave
				"sway":swing=float(part.get("amplitude",.16))*wave
		elif activity in ["takeoff","fly","land"] and part.motion=="flap":swing=float(part.get("amplitude",.65))*wave
		elif activity in ["eat","hunt"] and part.motion=="jaw":swing=float(part.get("amplitude",.19))*sin(bite*TAU)
		elif activity=="pickup" and part.id==fruit_bite.get("pivot_id"):
			swing=fruit_head_angle(float(fruit_bite.dip),bite)
		var parent:Transform2D=transforms.get(part.parent,Transform2D.IDENTITY)
		transforms[part.id]=parent*Transform2D(swing,vec(part.joint))
	return transforms
