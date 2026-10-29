extends Node2D
## Connections own constraints, never the bodies or their source drawings.
const MAX_LINKS := 128
const MATERIAL_MARGIN := 0.25
var game
var records:Array = []
var joints:Dictionary = {}
var bodies:Dictionary = {}

static func ensure_key(object:Dictionary)->String:
	if not object.has("structure_id"):object.structure_id="part_"+Crypto.new().generate_random_bytes(16).hex_encode()
	return str(object.structure_id)

static func _key(value:Variant)->bool:
	return value is String and value.length()>0 and value.length()<=96 and value.is_valid_identifier()

static func _number(value:Variant)->bool:
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value))<=200

static func valid_state(value:Variant,objects:Array)->bool:
	if not value is Array or value.size()>MAX_LINKS:return false
	var keys:Dictionary={}
	for object in objects:
		if not object is Dictionary:return false
		if not object.has("structure_id"):continue
		if not _key(object.structure_id) or keys.has(object.structure_id):return false
		keys[object.structure_id]=object
	var ids:Dictionary={};var pairs:Dictionary={}
	for record in value:
		if not record is Dictionary or not _key(record.get("id")) or record.get("kind") not in ["fixed","hinge"]:return false
		if not _key(record.get("a")) or not _key(record.get("b")) or record.a==record.b or not keys.has(record.a) or not keys.has(record.b):return false
		var pair:Array=[record.a,record.b];pair.sort()
		if ids.has(record.id) or pairs.has(str(pair)):return false
		ids[record.id]=true;pairs[str(pair)]=true
		for field in ["ax","ay","bx","by"]:
			if not _number(record.get(field)):return false
		var world_points:Array=[]
		# Validate against active cut geometry, including JSON files before vectors restore.
		for endpoint in ["a","b"]:
			var object:Dictionary=keys[record[endpoint]].duplicate(true)
			for path in object.get("paths",[]):
				for i in path.points.size():
					if path.points[i] is Dictionary:path.points[i]=Vector2(path.points[i].x,path.points[i].y)
			var point:=Vector2(record.ax,record.ay) if endpoint=="a" else Vector2(record.bx,record.by)
			if material_distance(PaperObjectDamage.prepare(object),point)>MATERIAL_MARGIN:return false
			world_points.append(point.rotated(float(object.get("angle",0)))+Vector2(object.x,object.y))
		if world_points[0].distance_to(world_points[1])>.5:return false
	return true

static func material_distance(prepared:Dictionary,point:Vector2)->float:
	var distance:=INF
	for shape in prepared.get("shapes",[]):
		if shape.has("polygon"):
			var polygon:PackedVector2Array=shape.polygon
			if Geometry2D.is_point_in_polygon(point,polygon):return 0.0
			for i in polygon.size():distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])))
		else:distance=minf(distance,maxf(0,point.distance_to(Geometry2D.get_closest_point_to_segment(point,shape.a,shape.b))-PaperShapePhysics.INK_RADIUS))
	return distance

func remote()->bool:return game.network_session!=null
func body(key:String):
	if bodies.has(key) and is_instance_valid(bodies[key]) and not bodies[key].is_queued_for_deletion():return bodies[key]
	for i in game.objects.size():
		if game.objects[i].get("structure_id","")==key and i<game.object_nodes.size() and is_instance_valid(game.object_nodes[i]) and not game.object_nodes[i].is_queued_for_deletion():
			bodies[key]=game.object_nodes[i];return game.object_nodes[i]
	return null
func object(key:String)->Dictionary:
	var node=body(key)
	return node.data if node!=null else {}
func linked(key:String)->bool:
	for record in records:
		if key in [record.a,record.b]:return true
	return false
func pick(point:Vector2,except:String="")->String:
	var best:=0.19;var found:=""
	for node in game.object_nodes:
		if not is_instance_valid(node) or node.is_queued_for_deletion():continue
		var key:String=node.data.get("structure_id","")
		if key==except:continue
		var distance:=material_distance(node.damage_prepared,node.to_local(point))
		if distance<best:best=distance;found=key
	return found
func _failure(text:String)->Dictionary:return {"ok":false,"error":text}
func create(a:String,b:String,point:Vector2,kind:String)->Dictionary:
	if remote():return _failure("连接由服务器确认")
	if kind not in ["fixed","hinge"] or a==b or not point.is_finite():return _failure("连接选点无效")
	if records.size()>=MAX_LINKS:return _failure("连接已达128个上限")
	var node_a=body(a);var node_b=body(b)
	if node_a==null or node_b==null:return _failure("部件已经不存在，请重新选择")
	if not node_a.data.get("dynamic",true) and not node_b.data.get("dynamic",true):return _failure("至少选择一件可活动部件")
	for record in records:
		if a in [record.a,record.b] and b in [record.a,record.b]:return _failure("这两件部件已有连接，先解除再更换")
	var pa:Vector2=node_a.to_local(point);var pb:Vector2=node_b.to_local(point)
	if material_distance(node_a.damage_prepared,pa)>MATERIAL_MARGIN or material_distance(node_b.damage_prepared,pb)>MATERIAL_MARGIN:return _failure("请在两件相邻部件的接缝处连接")
	var record:Dictionary={"id":"link_"+Crypto.new().generate_random_bytes(16).hex_encode(),"kind":kind,"a":a,"b":b,"ax":pa.x,"ay":pa.y,"bx":pb.x,"by":pb.y}
	records.append(record);_build(record)
	return {"ok":true,"error":"","link":record.duplicate(true)}
func _build(record:Dictionary)->void:
	if remote():return
	var a=body(record.a);var b=body(record.b)
	if a==null or b==null:return
	var group:=Node2D.new()
	add_child(group)
	var anchor:Vector2=(a.to_global(Vector2(record.ax,record.ay))+b.to_global(Vector2(record.bx,record.by)))*.5
	# Two separated point constraints lock relative rotation without the engine's
	# unstable angular-limit solver. Neither body is frozen or repositioned.
	for index in (2 if record.kind=="fixed" else 1):
		var joint:=PinJoint2D.new()
		joint.position=anchor+Vector2(.6*index,0).rotated(a.rotation)
		group.add_child(joint)
		joint.node_a=joint.get_path_to(a);joint.node_b=joint.get_path_to(b)
		joint.softness=0.0
	joints[record.id]=group
	a.sleeping=false;b.sleeping=false
func remove(id:String)->Dictionary:
	if remote():return _failure("连接由服务器确认")
	for i in records.size():
		if records[i].id==id:
			var before:Dictionary=records[i].duplicate(true)
			_drop_joint(id);records.remove_at(i)
			return {"ok":true,"error":"","link":before}
	return _failure("连接已经不存在")
func _drop_joint(id:String)->void:
	if joints.has(id):
		var group:Node2D=joints[id]
		for joint in group.get_children():joint.node_a=NodePath();joint.node_b=NodePath()
		group.free();joints.erase(id)
func clear()->void:
	for id in joints.keys():_drop_joint(id)
	records.clear()
func snapshot()->Array:return records.duplicate(true)
func restore(value:Variant)->bool:
	if not valid_state(value,game.objects):return false
	clear();records=value.duplicate(true)
	for record in records:_build(record)
	return true
func rebuild()->void:
	bodies.clear()
	for id in joints.keys():_drop_joint(id)
	step()
	for record in records:_build(record)
func step()->bool:
	if remote():return false
	var changed:=false
	for record in records.duplicate():
		var a=body(record.a);var b=body(record.b)
		if a==null or b==null or material_distance(a.damage_prepared,Vector2(record.ax,record.ay))>MATERIAL_MARGIN or material_distance(b.damage_prepared,Vector2(record.bx,record.by))>MATERIAL_MARGIN:
			remove(record.id);changed=true
	return changed
func marker(record:Dictionary)->Vector2:
	var a=body(record.a)
	return a.to_global(Vector2(record.ax,record.ay)) if a!=null else Vector2.INF
func at_point(point:Vector2)->Dictionary:
	for record in records:
		if marker(record).distance_to(point)<.3:return record
	return {}
func active_keys(centers:Array)->Dictionary:
	var active:Dictionary={}
	for object in game.objects:
		for center in centers:
			if absf(object.x-float(center))<70:active[object.get("structure_id","")]=true;break
	for iteration in records.size():
		var changed:=false
		for record in records:
			if active.has(record.a)!=active.has(record.b):active[record.a]=true;active[record.b]=true;changed=true
		if not changed:break
	return active
func draw_world(canvas:Node2D)->void:
	for record in records:
		var world:=marker(record)
		if not world.is_finite():continue
		var p:Vector2=game.world_to_screen(world)
		var color:=Color("376f65")
		canvas.draw_circle(p,6,Color("faf7eb"));canvas.draw_arc(p,6,0,TAU,20,color,1.8,true)
		if record.kind=="fixed":
			canvas.draw_line(p-Vector2(3,3),p+Vector2(3,3),color,1.5,true);canvas.draw_line(p+Vector2(-3,3),p+Vector2(3,-3),color,1.5,true)
		else:canvas.draw_circle(p,2,color)
	if game.draw_mode==4 and not game.connection_source.is_empty():
		var source=body(game.connection_source.key)
		if source!=null:
			var p:Vector2=game.world_to_screen(source.to_global(game.connection_source.point))
			canvas.draw_arc(p,10,0,TAU,24,Color("376f65"),2,true)
			canvas.draw_string(ThemeDB.fallback_font,p+Vector2(14,-12),"选择相邻部件 · Esc取消",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("376f65"))
