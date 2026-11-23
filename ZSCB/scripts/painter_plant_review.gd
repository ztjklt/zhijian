extends RefCounted
## Test features against the committed world-space ink and the actual floor.

const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const ROLES := ["root","trunk","branch","crown_light","crown_shadow","twig","ground"]
const MAX_BATCHES := 8
const MAX_STUDY_READS := 5

static func expected_kind(phase:Dictionary) -> String:
	if phase.get("form")=="distant":return ""
	var prose:=str(phase.get("aim",""))
	if phase.get("form") in ["tree","small_detail"]:return phase.form
	if ["垂柳","岸柳","树冠","乔木","一株树","成片林","松树","老松"].any(func(s):return prose.contains(s)):
		return "tree"
	return ""

static func point(p:Array) -> Vector2:
	return Vector2(p[0],p[1])

static func _touches_floor(world, points:Array) -> bool:
	for pair in points:
		var p:=point(pair)
		for face in world.paper_surfaces(p.x,p.y-.16,p.y+.16):
			if face.face=="floor":return true
	return false

static func _near_ink(p:Vector2, line:Array, tolerance:float) -> bool:
	for i in range(1,line.size()):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,point(line[i-1]),point(line[i])))<=tolerance:
			return true
	return false

static func _outline(line:Array) -> Dictionary:
	var points:=PackedVector2Array()
	var box:=Rect2(point(line[0]),Vector2.ZERO)
	var area:=0.0
	for i in line.size():
		var p:=point(line[i])
		points.append(p)
		box=box.expand(p)
		if i>0:area+=point(line[i-1]).cross(p)
	return {"area":absf(area)*.5,"box":box,"points":points}

static func review(world, project:Dictionary) -> Dictionary:
	var leaf:Dictionary=project.get("plant",{})
	var marks:Array=leaf.get("marks",[])
	var batches:int=int(leaf.get("batches",0))
	var kind:String=str(leaf.get("kind",""))
	var unmet:= []
	if marks.size()<(5 if kind=="tree" else 2):
		unmet.append("真实轮廓、枝干或根系笔迹不足")
	var ground_roles: Array=["root","trunk"] if kind=="tree" else ["root","trunk","ground"]
	var stems:=marks.filter(func(m):return m.part in ground_roles and _touches_floor(world,m.points))
	if stems.is_empty():unmet.append("让根或干脚真正贴到可见地表")
	if kind=="tree":
		var trunk:Dictionary={}
		for mark in marks:
			if mark.part!="trunk":continue
			var bounds:Rect2=_outline(mark.points).box
			if bounds.size.y<.75:continue
			if _touches_floor(world,mark.points) or stems.any(func(r):return _near_ink(point(mark.points.front()),r.points,.22)):
				trunk=mark
				break
		if trunk.is_empty():unmet.append("从根接出一笔可辨树干，垂直差至少0.75米")
		var forks:= []
		if not trunk.is_empty():
			for mark in marks:
				if mark.part!="branch":continue
				var a:=point(mark.points.front())
				var b:=point(mark.points.back())
				if a.distance_to(b)<.2:continue
				if _near_ink(a,trunk.points,.24):forks.append(b)
				elif _near_ink(b,trunk.points,.24):forks.append(a)
		if forks.is_empty():unmet.append("将可辨主枝真实接到树干")
		var crowns:= {}
		for mark in marks:
			if mark.part not in ["crown_light","crown_shadow"] or not Brush.is_wash(mark.brush) or mark.pigment=="inherit":continue
			var outline:=_outline(mark.points)
			var b:Rect2=outline.box
			if outline.area<.095 or b.size.x<.34 or b.size.y<.19:continue
			if not forks.any(func(p):return Geometry2D.is_point_in_polygon(p,outline.points) or p.distance_to(b.get_center())<=.36):continue
			var candidates: Array=crowns.get(mark.part,[])
			candidates.append({"box":b,"pigment":mark.pigment})
			crowns[mark.part]=candidates
		if crowns.size()!=2:
			unmet.append("用两块实际闭合色面连接枝端，分出亮部与背阴")
		else:
			if not crowns.crown_light.any(func(light):return crowns.crown_shadow.any(func(shade):return _separate_crowns(light,shade))):
				unmet.append("两团冠叶用不同色，错开位置，合计轮廓至少宽0.85米")
	elif kind.is_empty():
		unmet.append("先声明本株是树还是小型植被")
	return {"ok":unmet.is_empty(),"missing":unmet,"marks":marks.size(),"batches":batches,"kind":kind}

static func _separate_crowns(light:Dictionary,shade:Dictionary) -> bool:
	var a:Rect2=light.box
	var b:Rect2=shade.box
	return light.pigment!=shade.pigment and a.merge(b).size.x>=.85 and absf(a.get_center().y-b.get_center().y)>=.12
