extends RefCounted
## Revision of installed scenery ink. Each replacement is addressed to an original stroke.
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Group := preload("res://scripts/architecture/building_study_revision.gd")
const Atlas := preload("res://scripts/team_atlas.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const ANGLE_EPSILON := .0001
const MAX_PATCH_STROKES := 8

static func _editability(obj:Dictionary) -> String:
	var meta:Dictionary=obj.built_plan
	if obj.get("author_id",obj.get("artist","")) not in ["companion","painter"] or meta.get("owner")!="companion":
		return "可读同队实物。阿靛只直接改自己的原建筑。"
	if obj.get("pen")!="draw_scenery" or obj.get("dynamic",true) or absf(obj.get("angle",0.0))>ANGLE_EPSILON:
		return "这件实物的承重或坐标无法安全原位替换。"
	if obj.get("hp",1)<=0 or not obj.get("damage_cuts",[]).is_empty():
		return "旧稿受损，请先处理实物损伤。"
	return ""

static func _protected(obj:Dictionary, index:int) -> bool:
	var meta:Dictionary=obj.built_plan
	var path:Dictionary=obj.paths[index]
	return path.get("collision",false) or Group.protected(meta.layout,index,path.points,Plans.point(meta.offset))

static func _eligible(obj:Dictionary) -> bool:
	return obj.has("built_plan") and not str(obj.get("work_id","")).is_empty() and obj.get("hp",1)>0 \
		and obj.built_plan.get("layout",{}).get("layers",[]).size()==obj.get("paths",[]).size()

static func catalogue(game, project:Dictionary, feet:Vector2, brief:String) -> Array:
	var result := []
	var project_ids:Array=project.get("work_ids",[])
	var subject:String=project.get("subject","")
	for obj:Dictionary in game.objects:
		if not _eligible(obj):continue
		var meta:Dictionary=obj.built_plan
		var origin:Vector2=game.object_point(obj,Plans.point(meta.offset))
		var name:String=obj.get("name","")
		var named:=brief.contains(obj.work_id) or (not name.is_empty() and brief.contains(name))
		var relevant:bool=obj.work_id==subject or obj.work_id in project_ids
		var distance:=origin.distance_to(feet)
		if not named and not relevant and distance>14.0:continue
		var reason:=_editability(obj)
		if reason.is_empty() and distance>10.0:reason="请走到这件作品的真实岸脚，再原位改画。"
		var row:={"work_id":obj.work_id,"name":name,"origin_world":Plans.coords(origin),"plan_id":meta.id,"distance_m":snappedf(distance,.01),
			"editable":reason.is_empty(),"reason":reason,"rank":(0 if named else 1 if relevant else 2),"layers":[]}
		for i in meta.layout.layers.size():
			row.layers.append({"index":i,"name":meta.layout.layers[i],"protected":_protected(obj,i)})
		result.append(row)
	result.sort_custom(func(a,b):return a.distance_m<b.distance_m if a.rank==b.rank else a.rank<b.rank)
	return result.slice(0,8)

static func prepare(game, feet:Vector2, args:Dictionary) -> Dictionary:
	var slot:int=game.objects.find_custom(func(o):return o.get("work_id")==args.get("work_id") and _eligible(o))
	if slot<0:return {"error":"本队找不到这件已落实物。"}
	var obj:Dictionary=game.objects[slot]
	var issue:=_editability(obj)
	if not issue.is_empty():return {"error":issue}
	var meta:Dictionary=obj.built_plan
	var origin:Vector2=game.object_point(obj,Plans.point(meta.offset))
	if int(args.get("expected_plan_id",-1))!=int(meta.id) or not Plans.pair(args.get("expected_origin")) or origin.distance_to(Plans.point(args.expected_origin))>.005:
		return {"error":"原实物的位置或图纸已经变动，请重新察看后再落笔。"}
	if feet.distance_to(origin)>10.0:return {"error":"请先走到这件作品的实地，再原位改画。"}
	var changes=args.get("replace")
	if not changes is Array or changes.is_empty() or changes.size()>MAX_PATCH_STROKES:
		return {"error":"每次选择1至8笔已存在的原笔改画。"}
	var edit:=Group.expand(game,changes,meta.layout.layers,Atlas.read_sheet)
	if edit.has("error"):return edit
	var slots:Dictionary=edit.slots
	var order:=slots.keys()
	var cmd := {"tool":"draw_scenery","name":obj.name,"style":obj.ink_style,"strokes":[],"brushes":[],"pigments":[]}
	var fresh:=[]
	for index:int in order:
		if _protected(obj,index):return {"error":"第%d笔承担支点、遮护或实际使用设施，局部改绘须保留。"%index}
		for row:Dictionary in slots[index]:
			var points=row.get("points")
			if not points is Array or points.size()<2 or points.size()>32 or not points.all(Plans.pair):return {"error":"每笔须给2至32个有效图纸局部坐标。"}
			if Group.cuts_access(meta.layout,points):return {"error":"新笔穿过原使用位的净空。请给来客或工人留空。"}
			cmd.strokes.append(points.map(func(p):return Plans.coords(origin+Plans.point(p))))
			cmd.brushes.append(row.get("brush",""))
			cmd.pigments.append(row.get("pigment",""))
			fresh.append(row)
	Brush.add_treatments(cmd,fresh)
	var proof:=Plans.prepare_scenery(cmd.name,cmd,origin)
	if proof.has("error"):return proof
	return {"command":cmd,"changes":proof.paths,"indices":order,"slots":slots,"work_id":obj.work_id,"origin":origin,"plan_id":meta.id}

static func install(game, actor, args:Dictionary, authorship:Dictionary) -> Dictionary:
	var edit:=prepare(game,actor.player.position-Vector2(0,.29),args)
	if edit.has("error"):return edit
	var object_index:int=game.objects.find_custom(func(o):return o.get("work_id")==edit.work_id)
	var obj:Dictionary=game.objects[object_index]
	var body=game.object_nodes[object_index]
	if not is_instance_valid(body) or body.collision_layer!=0:return {"error":"现有场景物未处于可改绘状态"}
	var meta:Dictionary=obj.built_plan
	var origin:Vector2=game.object_point(obj,Plans.point(meta.offset))
	var local:Vector2=Plans.point(meta.offset)+(edit.origin-origin)
	var new_layout:Dictionary=meta.layout.duplicate(true)
	var path_slots:={}
	var cursor:=0
	for index:int in edit.indices:
		path_slots[index]=[]
		for _line in edit.slots[index]:
			var path:Dictionary=edit.changes[cursor].duplicate(true)
			for j in path.points.size():path.points[j]+=local
			path_slots[index].append(path)
			cursor+=1
	var paths:=Group.replace_slots(obj.paths,path_slots)
	new_layout.layers=Group.replace_slots(new_layout.layers,edit.slots,"layer")
	var sources:Array=new_layout.get("stroke_sources",[])
	if sources.is_empty():sources.resize(obj.paths.size())
	new_layout.stroke_sources=Group.replace_slots(sources,edit.slots,"source")
	new_layout.authorship=authorship
	var cmd:Dictionary=edit.command.duplicate(true)
	cmd.style=obj.ink_style
	cmd.strokes=[]
	cmd.brushes=[]
	cmd.pigments=[]
	for path:Dictionary in paths:
		cmd.strokes.append(path.points.map(func(p):return Plans.coords(game.object_point(obj,p))))
		cmd.brushes.append(path.get("brush","bold"))
		cmd.pigments.append(path.get("pigment","inherit"))
	cmd.erase("ink_treatments")
	Brush.add_treatments(cmd,paths)
	var draft:=Plans.prepare(obj.name,cmd,origin,new_layout)
	if draft.has("error"):return draft
	var site:=Plans.preview_layout(game,draft.layout,origin,obj.structure_id)
	if not site.ok:return {"error":site.error}
	var cost:=PaperInkReserve.cost({"paths":edit.changes})
	if not actor.ink.can_spend(cost):return {"error":"阿靛的墨量不足"}
	game.record()
	var stored:=Plans.store(game,"companion",obj.name.left(54)+"·局部改绘",cmd,origin,new_layout,edit.plan_id)
	if not stored.ok:return stored
	actor.ink.spend(cost)
	var entry:=Plans._source(game,"companion",stored.id)
	entry.work_id="companion-"+Crypto.new().generate_random_bytes(12).hex_encode()
	entry.author_id="companion"
	meta.id=stored.id
	meta.layout=draft.layout
	obj.paths=paths
	body.setup(obj)
	return {"ok":true,"work_id":obj.work_id,"structure_id":obj.structure_id,
		"original_plan_id":edit.plan_id,"plan_id":stored.id,"changed_strokes":edit.indices,"ink_spent":cost,"name":obj.name}
