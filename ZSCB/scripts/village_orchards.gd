extends RefCounted
## Each real trunk owns one crop. Migration preserves the original six-bit harvest.
const Paper := preload("res://scripts/paper_space.gd")
const Review := preload("res://scripts/painter_plant_review.gd")
const Ground := preload("res://scripts/priest_ground.gd")
const MAX_SITES := 128
var world
var native := {}
var crops := {}

func _init(owner_world) -> void:
	world=owner_world

static func fresh(mask:int=0) -> Dictionary:
	return {"mask":mask,"bud":0,"seconds":0.0}

func index(service) -> void:
	native.clear()
	if not crops.has(service.TREE):crops[service.TREE]=fresh(63)
	for entity in world.entities:
		if entity.kind=="orchard_tree":
			native[entity.entity_id]=entity
			if not crops.has(entity.entity_id):crops[entity.entity_id]=fresh(63 if entity.entity_id==service.TREE else 0)

static func valid(value:Variant,interval:float) -> bool:
	if not value is Dictionary or value.size()>MAX_SITES:return false
	for key in value:
		if not key is String or key.is_empty() or key.length()>128:return false
		var row=value[key]
		if not row is Dictionary:return false
		var n:=6
		if row.has("plant"):
			var plant=row.plant
			if not plant is Dictionary or plant.get("species")!="zhuguo" or not Paper.pair(plant.get("at")).is_finite():return false
			if not plant.get("sites") is Array or plant.sites.size() not in range(1,7):return false
			n=plant.sites.size()
			for mark in plant.sites:
				if not mark is Dictionary or not mark.get("work_id") is String or mark.work_id.is_empty() or mark.work_id.length()>128 or not Paper.pair(mark.get("at")).is_finite():return false
		elif not key.begins_with("orchard_tree-"):return false
		for k in ["mask","bud","seconds"]:
			if not (row.get(k) is float or row.get(k) is int) or not is_finite(row[k]) or row[k]<0:return false
		if floorf(row.mask)!=row.mask or row.mask>=(1<<n) or floorf(row.bud)!=row.bud or row.bud>=n or row.seconds>=interval:return false
	return true

func _record(id:String) -> Dictionary:
	if world.paper_space!=null and world.paper_space.entries.has(id):
		var rec:Dictionary=world.paper_space.entries[id].record
		if not rec.has("projection") and rec.author_id=="companion" and rec.mode in ["backdrop","scenery"]:return rec
	for obj in world.game.objects:
		if obj.get("author_id")=="companion" and obj.get("work_id")==id and obj.get("pen")=="draw_scenery" and not obj.get("dynamic",false) and obj.get("health",1)>0:return obj
	return {}

func _lines(rec:Dictionary) -> Array:
	if rec.has("points"):return [rec.points]
	var result:=[]
	for path in rec.get("paths",[]):
		var line:=[]
		for p in path.points:
			var pos:Vector2=world.game.object_point(rec,Vector2(p.x,p.y))
			line.append([pos.x,pos.y])
		result.append(line)
	return result

func _same_line(points:Array, expected:Array) -> bool:
	var count:=expected.size()
	if count>2 and points.size()==count-1 and Paper.pair(expected[0]).distance_to(Paper.pair(expected[-1]))<=.012:count-=1
	if points.size()!=count:return false
	for i in points.size():
		if Paper.pair(points[i]).distance_to(Paper.pair(expected[i]))>.012:return false
	return true

func _same_plant(a:Dictionary,b:Dictionary) -> bool:
	if a.get("species")!=b.species or Paper.pair(a.get("at")).distance_to(Paper.pair(b.at))>.012:return false
	if a.get("sites",[]).size()!=b.sites.size():return false
	for i in b.sites.size():
		if a.sites[i].work_id!=b.sites[i].work_id or Paper.pair(a.sites[i].at).distance_to(Paper.pair(b.sites[i].at))>.012:return false
	return true

func _near_crown(point:Vector2,poly:PackedVector2Array) -> bool:
	for i in poly.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,poly[i],poly[(i+1)%poly.size()]))<.08:return true
	return false

func _branch_carries(trunk:Array,marks:Array,poly:PackedVector2Array) -> bool:
	for mark in marks:
		if mark.part!="branch":continue
		var a:=Paper.pair(mark.points.front())
		var b:=Paper.pair(mark.points.back())
		for ends in [[a,b],[b,a]]:
			if Review._near_ink(ends[0],trunk,.24) and (Geometry2D.is_point_in_polygon(ends[1],poly) or _near_crown(ends[1],poly)):return true
	return false

func register_tree(project:Dictionary) -> Dictionary:
	var plant:Dictionary=project.get("plant",{})
	var sites=plant.get("fruit_sites")
	if not plant.get("marks") is Array or plant.marks.size()>256:return {"error":"缺少完整树稿"}
	if plant.get("species")!="zhuguo" or plant.get("kind")!="tree" or not sites is Array or sites.size() not in range(1,7):
		return {"error":"请为一株朱果树选一至六处冠上果位"}
	var crowns:={}
	var trunk_id:=""
	var trunk:Array=[]
	var foot:=Vector2.INF
	for m in plant.get("marks",[]):
		if not m is Dictionary or not m.get("points") is Array or m.points.size()<2 or m.points.size()>256 or not m.get("work_id") is String:return {"error":"缺少原笔"}
		if m.get("part") not in Review.ROLES or not m.get("brush") is String or not m.get("pigment") is String:return {"error":"原笔部位或笔法不全"}
		for xy in m.points:
			if not xy is Array or not Paper.pair(xy).is_finite():return {"error":"原笔位置无效"}
		var rec:=_record(m.work_id)
		if rec.is_empty() or not _lines(rec).any(func(line):return _same_line(line,m.points)):return {"error":"原树笔迹已改变"}
		if m.get("part") in ["crown_light","crown_shadow"]:
			if not crowns.has(m.work_id):crowns[m.work_id]=[]
			crowns[m.work_id].append(Review._outline(m.points).points)
		if m.get("part")=="trunk" and trunk_id.is_empty() and Review._outline(m.points).box.size.y>=.75:
			trunk_id=m.work_id
			trunk=m.points
		if m.get("part") in ["root","trunk"] and not foot.is_finite():
			for p in m.points:
				var pt:=Paper.pair(p)
				var floor_row:=Ground.nearby(world,pt.x,pt.y,.16)
				if not floor_row.is_empty():
					foot=Vector2(pt.x,floor_row.y)
					break
	if trunk_id.is_empty() or not foot.is_finite() or not Review.review(world,project).ok:return {"error":"树形与根脚尚未验过"}
	var accepted:=[]
	for mark in sites:
		if not mark is Dictionary or not crowns.has(mark.get("work_id")):return {"error":"果位缺少本株树冠"}
		var p:=Paper.pair(mark.get("at"))
		if not p.is_finite() or not crowns[mark.work_id].any(func(poly):return Geometry2D.is_point_in_polygon(p,poly) and _branch_carries(trunk,plant.marks,poly)):return {"error":"果位在树冠外"}
		for other in accepted:
			if p.distance_to(Paper.pair(other.at))<.15:return {"error":"两个果位太近"}
		accepted.append({"work_id":mark.work_id,"at":[p.x,p.y]})
	var identity:={"species":"zhuguo","at":[foot.x,foot.y],"sites":accepted}
	if crops.has(trunk_id):
		if not _same_plant(crops[trunk_id].get("plant",{}),identity):return {"error":"这株树已登记另一组果位"}
	elif crops.size()<MAX_SITES:
		crops[trunk_id]=fresh()
		crops[trunk_id].plant=identity
	else:return {"error":"本世界果树登记已满"}
	return {"ok":true,"tree_id":trunk_id,"slots":accepted.size()}

func alive(id:String) -> bool:
	if native.has(id):return is_instance_valid(native[id]) and native[id].alive
	return crops.has(id) and crops[id].has("plant") and not _record(id).is_empty()

func at(id:String) -> Vector2:
	if native.has(id):return native[id].position
	if crops.has(id) and crops[id].has("plant"):return Paper.pair(crops[id].plant.at)
	return Vector2.INF

func count_slots(id:String) -> int:
	return crops[id].plant.sites.size() if crops[id].has("plant") else 6

func marker(service,id:String,i:int) -> Vector2:
	if crops[id].has("plant"):return Paper.pair(crops[id].plant.sites[i].at)
	var tree=native[id]
	return tree.to_global(tree.art_to_local(service.FRUIT_MARKS[i]))

func branch(service,id:String,i:int) -> bool:
	if not alive(id):return false
	if crops[id].has("plant"):return not _record(crops[id].plant.sites[i].work_id).is_empty()
	var tree=native[id]
	if tree.cuts.is_empty():return true
	for poly in tree.render_polygons:
		if Geometry2D.is_point_in_polygon(service.FRUIT_MARKS[i],poly):return true
	return false

func visible_fruit(service,id:String,i:int) -> bool:
	return bool(int(crops[id].mask)&(1<<i)) and branch(service,id,i)

func next(service,id:String) -> int:
	var row:Dictionary=crops[id]
	var n:=count_slots(id)
	if row.mask==(1<<n)-1 or not alive(id):return -1
	for off in n:
		var i:=(int(row.bud)+off)%n
		if not int(row.mask)&(1<<i) and branch(service,id,i):return i
	return -1

func grow(service,elapsed:float) -> void:
	for id in crops:
		var row:Dictionary=crops[id]
		var delta:=elapsed
		while delta>0:
			var slot:=next(service,id)
			if slot<0:
				row.seconds=0.0
				break
			if slot!=row.bud:
				row.bud=slot
				row.seconds=0.0
			var left:float=service.FRUIT_RIPEN_SECONDS-row.seconds
			if delta+.000001<left:
				row.seconds+=delta
				break
			row.mask=int(row.mask)|(1<<slot)
			row.bud=(slot+1)%count_slots(id)
			row.seconds=0.0
			delta-=left

func facts(service,id:String) -> Dictionary:
	if not crops.has(id):return {"id":id,"at":[],"alive":false,"ripe":0,"growing_slot":-1,"next_in_s":-1}
	var pos:=at(id)
	var ripe:=0
	for i in count_slots(id):
		if visible_fruit(service,id,i):ripe+=1
	var bud:=next(service,id)
	var row:Dictionary=crops[id]
	return {"id":id,"at":[pos.x,pos.y] if pos.is_finite() else [],"alive":alive(id),"ripe":ripe,"growing_slot":bud,
		"next_in_s":-1 if bud<0 else ceili(service.FRUIT_RIPEN_SECONDS-(row.seconds if bud==row.bud else 0.0))}

