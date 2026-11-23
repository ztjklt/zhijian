extends RefCounted
## A blueprint supplies the actual ink contours. Paired limbs share one master stroke.
const Species := preload("res://scripts/priest_species.gd")
var parts := []
var paper_shapes := {}
var grounded_wash := false
var highest_screen_y:=INF
var body_bounds:=Rect2()
var foot_offset := 0.0
const INK := Color("332d2a")
const PAPER := Color("fbecd3")
const COATS := {"chestnut":Color("c78b68"), "honey":Color("d5b16b"), "ash":Color("a8aca0")}
const PARTS := ["body","head","ear","tail","leg","mark"]
const FOOD := {"oak":"橡树","pine":"松树","orchard_tree":"果树"}
var occupancy:Array=[]
var strokes := []
var length := 0.0
var fruit_bite:Dictionary={}
var fruit_anchor:=Vector2.ZERO
const PEN_ORDER := ["body","head","tail","leg","ear","mark","detail"]

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= low and value <= high

static func valid(d: Variant) -> bool:
	if d is Dictionary and d.get("schema")==Species.SCHEMA: return Species.valid(d)
	if not d is Dictionary or not d.get("name") is String or d.name.strip_edges().is_empty() or d.name.length() > 12 or "\n" in d.name: return false
	if not COATS.has(d.get("coat")) or d.get("gait") not in ["amble","trot","bound"]: return false
	if d.get("feeding") not in ["gnaw","strip"] or not FOOD.has(d.get("favorite")) or not number(d.get("pace"),0.75,1.6): return false
	for key in ["ear_scale","tail_scale"]:
		if d.has(key) and not number(d[key],.65,1.5): return false
	for key in PARTS:
		var path = d.get(key)
		if not path is Array or path.size() < (2 if key == "mark" else 3) or path.size() > 12: return false
		var poly := PackedVector2Array()
		for pair in path:
			if not pair is Array or pair.size() != 2 or not number(pair[0],0,10) or not number(pair[1],0,10): return false
			poly.append(Vector2(pair[0],pair[1]))
		if key != "mark" and Geometry2D.triangulate_polygon(poly).is_empty(): return false
	return true

func _init(d: Dictionary) -> void:
	if d.get("schema")==Species.SCHEMA:
		parts=d.parts
		fruit_bite=d.get("fruit_bite",{})
		var rest:=Species.frames(parts,0.0,"rest",0.0)
		foot_offset=INF
		for part in parts:
			var points:=Species.contour(part)
			if part.id==fruit_bite.get("part_id"):
				fruit_anchor=Species.vec(part.outline[int(fruit_bite.vertex)])
			for p in points:
				var t:Transform2D=rest[part.id]
				foot_offset=minf(foot_offset,(t*p).y)
				body_bounds=body_bounds.expand(t*p)
			paper_shapes[part.id]=points.duplicate()
			points.append(points[0])
			_add(part.id,points,Color(part.pigment), "body")
			var stroke: Dictionary = strokes.back()
			stroke.depth = ["far","body","near"].find(part.get("depth","body"))
			if part.has("wash"):
				grounded_wash = true
				stroke.parent_id = part.parent
				stroke.colors = _wash_colors(points, stroke.fill, float(part.wash), stroke.depth)
				stroke.rim = INK.lerp(stroke.fill, .38 if stroke.depth==0 else .22)
			stroke.start=length
			length+=strokes.back().length
			for mark in preload("res://scripts/priest_part_marks.gd").strokes(part.get("marks",[]),paper_shapes[part.id],Species.mark_bounds(part)):
				_add(part.id,mark.points,mark.pigment if mark.brush=="wash" else Color.TRANSPARENT)
				var detail: Dictionary = strokes.back()
				detail.mark_brush = mark.brush
				detail.mark_color = mark.pigment
				detail.depth = stroke.depth
				detail.start = length
				length += detail.length
		strokes.sort_custom(func(a,b): return a.depth < b.depth if a.depth != b.depth else a.start < b.start)
		for part in parts:
			var shape:=PackedVector2Array()
			for point:Vector2 in paper_shapes[part.id]:shape.append(rest[part.id]*point-Vector2(0,foot_offset))
			occupancy.append(shape)
		return
	var fur: Color = COATS[d.coat]
	var far := fur.darkened(0.33)
	_part(d,"tail","tail",Rect2(-1.10,0.19,0.70,0.39),fur.darkened(0.18))
	_part(d,"leg","far_hind",Rect2(-0.37,0.04,0.25,0.44),far)
	_part(d,"leg","far_fore",Rect2(0.30,0.04,0.22,0.44),far)
	_part(d,"ear","head",Rect2(0.41,0.63,0.19,0.27),far)
	_part(d,"body","body",Rect2(-0.64,0.20,1.23,0.63),fur)
	_part(d,"leg","hind",Rect2(-0.44,0.0,0.30,0.42),fur)
	_part(d,"leg","fore",Rect2(0.20,0.0,0.22,0.40),fur)
	_part(d,"head","head",Rect2(0.25,0.33,0.65,0.44),fur.lightened(0.15))
	_part(d,"ear","head",Rect2(0.33,0.63,0.21,0.27),fur)
	_part(d,"mark","body",Rect2(-0.45,0.40,0.70,0.26),Color.TRANSPARENT)
	_add("head",PackedVector2Array([Vector2(0.69,0.46),Vector2(0.84,0.44),Vector2(0.80,0.34),Vector2(0.74,0.35),Vector2(0.69,0.46)]),PAPER)
	_add("head",PackedVector2Array([Vector2(0.64,0.62),Vector2(0.67,0.62),Vector2(0.67,0.59),Vector2(0.64,0.59),Vector2(0.64,0.62)]),INK)
	_add("head",PackedVector2Array([Vector2(0.80,0.52),Vector2(0.90,0.53),Vector2(0.89,0.48),Vector2(0.83,0.48),Vector2(0.80,0.52)]),INK)

	# Render back-to-front, but let the brush establish torso and head first.
	var ink_order := strokes.duplicate()
	ink_order.sort_custom(func(a,b): return a.order < b.order)
	for stroke in ink_order:
		stroke.start = length
		length += stroke.length

# Bind the wash to the original vertices so the colour moves with the joint.
static func _wash_colors(points: PackedVector2Array, pigment: Color, density: float, depth: int) -> PackedColorArray:
	var colors := PackedColorArray()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	for i in points.size()-1:
		var uv := (points[i]-bounds.position) / Vector2(maxf(.001,bounds.size.x), maxf(.001,bounds.size.y))
		var deposit := clampf(.34+.49*density+.15*(1.0-uv.y)-.10*uv.x, .12, .98)
		if depth==0: deposit *= .78
		colors.append(PAPER.lerp(pigment, deposit))
	return colors

func _part(d: Dictionary, key: String, joint: String, box: Rect2, fill: Color) -> void:
	if key == "ear": box.size.y *= float(d.get("ear_scale",1.0))
	if key == "tail":
		var attachment := box.end.x
		box.size.x *= float(d.get("tail_scale",1.0))
		box.position.x = attachment - box.size.x
	var raw := PackedVector2Array()
	for pair in d[key]: raw.append(Vector2(pair[0],pair[1]))
	var bounds := Rect2(raw[0],Vector2.ZERO)
	for p in raw: bounds = bounds.expand(p)
	var points := PackedVector2Array()
	for p in raw:
		var uv := (p - bounds.position) / Vector2(maxf(.01,bounds.size.x),maxf(.01,bounds.size.y))
		if key == "mark": uv = p / 10.0
		points.append(box.position + uv * box.size)
	var smooth := PackedVector2Array()
	var closed := fill.a > 0
	if not closed: smooth.append(points[0])
	for i in (points.size() if closed else points.size()-1):
		var a := points[i]
		var b := points[(i+1)%points.size()]
		smooth.append(a.lerp(b,.17))
		smooth.append(a.lerp(b,.83))
	smooth.append(smooth[0] if closed else points[-1])
	_add(joint,smooth,fill,key)

func _add(joint: String, points: PackedVector2Array, fill: Color, kind := "detail") -> void:
	var distance := 0.0
	for i in range(1,points.size()): distance += points[i-1].distance_to(points[i])
	var order := PEN_ORDER.find(kind)*32+strokes.size()
	strokes.append({"order":order,"joint":joint,"points":points,"fill":fill,"length":distance})

static func _pose(p: Vector2, joint: String, gait: String, stride: float, activity: String, bite_phase: float) -> Vector2:
	if activity in ["walk","search"]:
		var cycle := sin(stride)
		var lift := absf(cycle)*(.080 if gait == "bound" else .025)
		if joint in ["fore","hind","far_fore","far_hind"]:
			var offset := {"fore":0.0,"hind":PI,"far_fore":PI,"far_hind":0.0}
			if gait == "bound": offset = {"fore":0.0,"hind":PI,"far_fore":.40,"far_hind":PI+.40}
			elif gait == "amble": offset = {"fore":0.0,"hind":.85,"far_fore":PI,"far_hind":PI+.85}
			var step := stride+float(offset[joint])
			var heel := clampf(1.0-p.y/.42,0,1)
			return p + Vector2(sin(step)*heel*.16,maxf(0,cos(step))*heel*.12+lift*(1.0-heel))
		if joint == "tail": p.y += sin(stride-.8)*maxf(0,-p.x-.42)*.16
		p.y += lift
	elif activity == "eat" and joint == "head":
		var hinge := Vector2(.32,.49)
		p = hinge + (p-hinge).rotated(-.18+.16*cos(bite_phase*TAU))
		p.x += sin(bite_phase*PI)*.08
	elif activity == "rest":
		p.y -= .075*clampf(p.y/.34,0,1)
		if joint == "body": p.y += sin(stride)*.016*clampf((p.y-.2)/.6,0,1)
	return p

## Same sample and cursor drive both the brush tip and the contour it leaves.
func _posed_floor(poses:Dictionary,activity:String) -> float:
	if not grounded_wash or activity not in ["walk","search","chase","flee"]:return foot_offset
	var low:=INF
	for id in paper_shapes:
		var pose:Transform2D=poses[id]
		for point:Vector2 in paper_shapes[id]:
			low=minf(low,(pose*point).y)
	return low

func _wash_edge(canvas:Node2D,stroke:Dictionary,points:PackedVector2Array,poses:Dictionary,width:float) -> void:
	var seams:=PackedVector2Array()
	var lit:=PackedVector2Array()
	var ink:=PackedVector2Array()
	var parent_shape:PackedVector2Array=paper_shapes.get(stroke.parent_id,PackedVector2Array())
	var relative:=Transform2D.IDENTITY
	if not parent_shape.is_empty():relative=poses[stroke.parent_id].affine_inverse()*poses[stroke.joint]
	for i in points.size()-1:
		var a:Vector2=stroke.points[i]
		var b:Vector2=stroke.points[i+1]
		for half in 2:
			var t:=.5*half
			var local:=a.lerp(b,t+.25)
			var from:=points[i].lerp(points[i+1],t)
			var to:=points[i].lerp(points[i+1],t+.5)
			if not parent_shape.is_empty() and Geometry2D.is_point_in_polygon(relative*local,parent_shape):
				seams.append(from)
				seams.append(to)
			elif to.y<from.y or stroke.depth==0:
				lit.append(from)
				lit.append(to)
			else:
				ink.append(from)
				ink.append(to)
	var rim:Color=stroke.rim
	if not seams.is_empty():canvas.draw_multiline(seams,rim.lerp(stroke.fill,.75),maxf(.6,width*.36),true)
	if not lit.is_empty():canvas.draw_multiline(lit,rim.lerp(stroke.fill,.42),maxf(.75,width*.58),true)
	if not ink.is_empty():canvas.draw_multiline(ink,rim,width*.83,true)

## This is the selected vertex of the ink polygon in exactly the displayed pose.
func fruit_mouth(base:Vector2,slope:float,facing:int,fraction:float) -> Vector2:
	if fruit_bite.is_empty():return Vector2.INF
	var poses:=Species.frames(parts,0.0,"pickup",fraction,fruit_bite)
	var joint:Transform2D=poses[fruit_bite.part_id]
	var local:=joint*fruit_anchor-Vector2(0,foot_offset)
	return base+Vector2(local.x*facing,local.y).rotated(slope)

func world_parts(base:Vector2,slope:float,facing:int,stride:float,activity:String,bite:float) -> Array[PackedVector2Array]:
	var result:Array[PackedVector2Array]=[]
	var poses:=Species.frames(parts,stride,activity,bite,fruit_bite)
	var floor_y:=_posed_floor(poses,activity)
	var place:=Transform2D(slope,base).scaled_local(Vector2(facing,1))
	for part in parts:
		var shape:=PackedVector2Array()
		var transform:Transform2D=poses[part.id]
		for point:Vector2 in paper_shapes[part.id]:
			shape.append(place*(transform*point-Vector2(0,floor_y)))
		result.append(shape)
	return result

func paint(canvas: Node2D, game, base: Vector2, slope: float, face: int, gait: String, stride: float, activity: String, bite_phase: float, budget: float) -> Vector2:
	var tip := base
	highest_screen_y=INF
	var frames:=Species.frames(parts,stride,activity,bite_phase,fruit_bite) if not parts.is_empty() else {}
	var floor_y:=_posed_floor(frames,activity)
	for stroke in strokes:
		var drawn: float = budget-stroke.start
		if drawn <= 0: continue
		var points := PackedVector2Array()
		var previous: Vector2 = stroke.points[0]
		var remaining := drawn
		for p: Vector2 in stroke.points:
			var span := previous.distance_to(p)
			if span > remaining: p = previous.lerp(p,remaining/span)
			var posed:Vector2
			if frames.is_empty(): posed=_pose(p,stroke.joint,gait,stride,activity,bite_phase)
			else:
				var transform:Transform2D=frames[stroke.joint]
				posed=transform*p-Vector2(0,floor_y)
				if activity=="dead":posed=Vector2(posed.x,posed.y*.32)
			var world_point := base + Vector2(posed.x*face,posed.y).rotated(slope)
			if drawn <= stroke.length: tip = world_point
			var screen_point:Vector2=game.world_to_screen(world_point)
			highest_screen_y=minf(highest_screen_y,screen_point.y)
			points.append(screen_point)
			remaining -= span
			if remaining <= 0: break
			previous = p
		if drawn >= stroke.length and stroke.fill.a > 0 and points.size() >= 4:
			if stroke.has("colors") and points.size()==stroke.points.size():
				canvas.draw_polygon(points.slice(0,-1),stroke.colors)
			else:
				canvas.draw_colored_polygon(points.slice(0,-1),stroke.fill)
		if points.size() > 1:
			var width := clampf(game.PIXELS_PER_UNIT * (.020 if stroke.fill.a == 0 else .031),1.1,3.2)
			if stroke.has("mark_brush"):
				if stroke.mark_brush=="thin" or drawn<stroke.length:
					canvas.draw_polyline(points,stroke.mark_color,clampf(game.PIXELS_PER_UNIT*.019,1.0,2.8),true)
			elif stroke.has("rim") and drawn>=stroke.length:_wash_edge(canvas,stroke,points,frames,width)
			else:canvas.draw_polyline(points,stroke.get("rim",INK),width,true)
	return tip

static func valid_work(data: Variant, east: float, west := -5.0) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true
	if data.get("version") == 2:
		return _valid_collection(data,east,west)
	return valid_creature(data,east,west)

static func _short(row:Dictionary,key:String,max_length:int,allow_empty:=false) -> bool:
	var val=row.get(key)
	return val is String and val.length()<=max_length and (allow_empty or not val.is_empty())

static func _plan_index(books:Array) -> Dictionary:
	var ids:={}
	for b in books:
		if not b is Dictionary or not Species.valid(b.get("design")) or b.get("name")!=b.design.name or b.get("author_id")!="priest":return {}
		for field in ["blueprint_id","team_id","world_id","call_id","served_model"]:
			if not _short(b,field,128):return {}
		for optional in ["goal","reason","origin_work_id"]:
			if b.has(optional) and not _short(b,optional,220,true):return {}
		if ids.has(b.blueprint_id):return {}
		ids[b.blueprint_id]=b
	return ids

static func _valid_collection(data: Dictionary, east: float, west: float) -> bool:
	if not data.get("works") is Array or data.works.size()>Species.MAX_WORKS or not data.get("autonomy_paused") is bool: return false
	if not number(data.get("x"),west,east) or not number(data.get("destination"),west,east): return false
	if data.has("y") and not number(data.y,-1000000,1000000): return false
	for key in ["budget","used"]:
		var count = data.get(key,0)
		if not number(count,0,1000000000) or floorf(count)!=count: return false
	if not number(data.get("next_turn"),0,180) or not number(data.get("protect_left"),0,90): return false
	if data.get("activity") not in ["idle","wait","draw","survey","tend","travel","feed","plant"]: return false
	var alternatives=data.get("travel_alternatives",[])
	if not alternatives is Array or alternatives.size()>3:return false
	for site in alternatives:
		if not site is Dictionary or not _short(site,"id",192) or not _short(site,"label",80):return false
		var coords=site.get("at")
		if not coords is Array or coords.size()!=2 or not number(coords[0],west,east) or not number(coords[1],-1000000,1000000):return false
	var travel=data.get("travel_target",{})
	if not travel is Dictionary:return false
	if travel.has("place_id") and not _short(travel,"place_id",192,true):return false
	if travel.has("chat") and not travel.chat is bool:return false
	if data.activity=="travel":
		var xy=travel.get("at")
		if not _short(travel,"label",80) or not xy is Array or xy.size()!=2 or not number(xy[0],west,east) or not number(xy[1],-1000000,1000000):return false
	var messages = data.get("chat",[])
	if not data.get("chat_draft","") is String or data.get("chat_draft","").length()>600: return false
	if not messages is Array or messages.size()>20: return false
	for line in messages:
		if not line is Dictionary or line.get("speaker") not in ["player","god","status"] or not line.get("text") is String or line.text.length()>600: return false
		for field in ["model","call_id","work_id"]:
			if line.has(field) and (not line[field] is String or line[field].length()>256): return false
	for key in ["goal","reason","model_reason","progress","habitat_id","tending_tree","protected_tree","eco_call","focus_id"]:
		if not data.get(key) is String or data[key].length()>256: return false
	var books=data.get("blueprints",[])
	if not books is Array or books.size()>Species.MAX_PLANS:return false
	var plans:=_plan_index(books)
	if plans.size()!=books.size():return false
	var notes=data.get("memory",[])
	if not notes is Array or notes.size()>32:return false
	for note in notes:
		if not note is Dictionary or note.get("role")!="priest":return false
		for field in ["team_id","world_id","action"]:
			if not _short(note,field,128):return false
		for field in ["reason","result","work_id","call_id"]:
			if not _short(note,field,240,true):return false
	var intentions=data.get("commitments",[])
	if not intentions is Array or intentions.size()>128:return false
	var note_ids:={}
	for n in intentions:
		if not n is Dictionary or n.get("role")!="priest" or n.get("status") not in ["open","resolved"]:return false
		for key in ["note_id","team_id","world_id","topic","intent","review_when","call_id"]:
			if not _short(n,key,220):return false
		if not _short(n,"outcome",1000,true):return false
		for key in ["work_id","blueprint_id"]:
			if not _short(n,key,220,true):return false
		for key in ["review_call_id","review_team_id","review_world_id"]:
			if n.has(key) and not _short(n,key,128):return false
		if note_ids.has(n.note_id):return false
		note_ids[n.note_id]=true
	var living:=0
	var ids := {}
	var drawings := 0
	for item in data.works:
		if not item is Dictionary or not valid_creature(item,east,west) or item.get("author_id")!="priest": return false
		for key in ["work_id","team_id","world_id","habitat_id"]:
			if not item.get(key) is String or item[key].is_empty() or item[key].length()>128: return false
		if item.phase!="dead":living+=1
		if item.design.has("schema"):
			var book:Dictionary=plans.get(item.get("blueprint_id",""),{})
			if book.is_empty() or book.design!=item.design: return false
			var eco=item.get("eco")
			if not eco is Dictionary or not number(eco.get("health"),0,36) or not number(eco.get("stamina"),0,1) or not number(eco.get("cooldown"),0,4):return false
			for extra in ["flight_energy","hostile_left","perch_y"]:
				if eco.has(extra) and not number(eco[extra],-1000000 if extra=="perch_y" else 0,1 if extra=="flight_energy" else 12 if extra=="hostile_left" else 1000000):return false
			if eco.has("avoided_person") and not _short(eco,"avoided_person",128,true):return false
			if eco.has("fruit_bite_id") and not _short(eco,"fruit_bite_id",128,true):return false
			if item.phase=="pickup" and (not "eat_ground_fruit" in item.design.actions or str(eco.get("fruit_bite_id","")).is_empty()):return false
			if eco.has("hostile_reason") and not _short(eco,"hostile_reason",128,true):return false
			if not number(eco.get("hunger_seconds",0),0,100000):return false
			if not preload("res://scripts/priest_grazing_memory.gd").valid(eco.get("grazed_places",[])):return false
			for count in ["portions","hits","kills","fruit_meals","grass_meals","takeoffs","landings","delivered_meals"]:
				if not eco.has(count) and count not in ["portions","hits","kills"]:continue
				var amount=eco.get(count)
				if not number(amount,0,3 if count=="portions" else 1000000000) or floorf(amount)!=amount:return false
			if (eco.health==0)!=(item.phase=="dead") or not item.design.edible and eco.portions!=0:return false
			for key in ["last_target","other_id"]:
				if not _short(eco,key,128,true):return false
		elif item.phase not in ["drawing","walk","rest","eat","search"]:return false
		if ids.has(item.work_id): return false
		ids[item.work_id]=item
		if item.phase=="drawing":
			drawings+=1
			if data.focus_id!=item.work_id: return false
	if not data.works.is_empty() and not ids.has(data.focus_id): return false
	var offers=data.get("revision_offers",[])
	if not offers is Array or offers.size()>data.works.size():return false
	var seen:={}
	for offer in offers:
		if not offer is Dictionary:return false
		for field in ["call_id","work_id","source_blueprint_id","served_model","goal","reason"]:
			if not _short(offer,field,128 if field not in ["goal","reason"] else 220):return false
		var source:Dictionary=plans.get(offer.source_blueprint_id,{})
		var body:Dictionary=ids.get(offer.work_id,{})
		if not offer.get("waiting",false) is bool:return false
		if offer.has("reply") and not _short(offer,"reply",220,true):return false
		if offer.get("waiting",false) and not offer.has("reply"):return false
		if seen.has(offer.work_id) or (not offer.get("waiting",false) and body.get("phase")!="dead") or body.get("blueprint_id")!=offer.source_blueprint_id or source.is_empty():return false
		if not Species.valid(offer.get("design")):return false
		if offer.has("edit_part_id") and (not _short(offer,"edit_part_id",128) or not Species.only_part_changed(source.design,offer.design,offer.edit_part_id)):return false
		seen[offer.work_id]=true
	for n in intentions:
		if n.work_id!="" and not ids.has(n.work_id) or n.blueprint_id!="" and not plans.has(n.blueprint_id):return false
	for b in books:
		if b.has("archived_revision") and (b.archived_revision!=true or not _short(b,"parent_blueprint_id",128) or not plans.has(b.parent_blueprint_id) or b.parent_blueprint_id==b.blueprint_id):return false
		if not str(b.get("origin_work_id","")).is_empty() and not ids.has(b.origin_work_id):return false
	if not preload("res://scripts/priest_pasture_care.gd").valid(data.get("pasture_job",{}),ids,data.activity=="plant"):return false
	if not preload("res://scripts/priest_feed_run.gd").valid(data.get("feed_run",{}),ids,data.activity=="feed"):return false
	if not data.get("historical_reviews_read",false) is bool:return false
	if not preload("res://scripts/priest_ecology_log.gd").valid(data.get("ecology_records",[]),ids,plans):return false
	return living<=Species.MAX_LIVE and drawings==(1 if data.activity=="draw" else 0)

static func valid_creature(data: Dictionary, east: float, west: float) -> bool:
	var revision = data.get("revision",{})
	if not revision is Dictionary: return false
	if not revision.is_empty():
		if not valid(revision.get("original_design")) or not number(revision.get("count"),1,10000000): return false
		for key in ["original_model","original_call_id"]:
			if not revision.get(key) is String or revision[key].length()>256: return false
	if data.has("y") and not number(data.y,-1000000,1000000): return false
	if data.get("version") != 1 or not valid(data.get("design")): return false
	if data.get("phase") not in ["drawing","search","walk","eat","rest","dead","hunt","flee","chase","takeoff","fly","land","pickup"]: return false
	if not number(data.get("face"),-1,1) or absf(data.face) != 1.0 or not number(data.get("x"),west,east): return false
	if not number(data.get("cursor"),0,1000) or not number(data.get("satiety"),0,100): return false
	if not number(data.get("stride"),0,TAU+.01) or not number(data.get("bite"),0,1): return false
	for key in ["call_id","target","last_tree"]:
		if not data.get(key) is String or data[key].length() > 128: return false
	if not data.get("eaten") is Dictionary or data.eaten.size() > 384: return false
	for id in data.eaten:
		if not id is String or id.is_empty() or id.length() > 64 or not number(data.eaten[id],1,3) or data.eaten[id] != floorf(data.eaten[id]): return false
	return true
