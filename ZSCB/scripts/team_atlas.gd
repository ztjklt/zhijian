extends RefCounted
## A read-through index of the loaded world's drawings. The original owners
## keep the geometry, inventories and live state. Only ref carries authority to select a page.
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Book := preload("res://scripts/architecture/building_book.gd")
const Pen := preload("res://scripts/paper_world_pen.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const Group := preload("res://scripts/architecture/building_study_revision.gd")
const Study := preload("res://scripts/atlas_study.gd")
const REFERENCES := ["market","house","windmill","pine_tips"]
const AUTHORS := {"companion":"画家阿靛","priest":"牧师","war_god":"战神","adventurer-lizhou":"冒险者砾舟","player":"玩家","reference":"地图参考","map-curator":"地图师"}

static func _add(rows: Array, game, data: Dictionary, id: String, author: String, title: String, kind: String, format: String, origin := "") -> void:
	if id.is_empty(): return
	var entry := {"team_id":game.team_slot.team_id,"world_id":game.team_slot.world_id,"work_id":id,
		"author_id":author,"name":title,"kind":kind,"format":format,"source_work_id":origin}
	rows.append({"entry":entry,"data":data})

static func _plan_id(game, owner: String, plan: Dictionary) -> String:
	return str(plan.get("work_id","plan-%s-%s%d" % [game.team_slot.team_id,"player-" if owner=="player" else "",int(plan.id)]))

static func _records(game) -> Array:
	var rows := []
	if not is_instance_valid(game) or game.medieval_world==null or str(game.team_slot.get("world_id","")).is_empty(): return rows
	var world = game.medieval_world
	for owner in ["player","companion"]:
		var bag := Plans.bag_for(game,owner)
		for plan: Dictionary in bag.get("entries",[]):
			if plan.get("source")=="library": continue
			var origin := str(plan.get("source_work_id",""))
			if origin.is_empty() and plan.has("parent_id"):
				var parent := BlueprintBag.find_entry(bag,int(plan.parent_id))
				if not parent.is_empty(): origin = _plan_id(game,owner,parent)
			_add(rows,game,plan,_plan_id(game,owner,plan),owner,str(plan.name),"建筑图纸" if plan.has("layout") else str(plan.get("category","图纸")),"plan" if plan.has("layout") else "drawing",origin)
	for obj: Dictionary in game.objects:
		var id := str(obj.get("work_id","ink-"+str(obj.structure_id) if obj.has("structure_id") else ""))
		var author := str(obj.get("author_id",obj.get("artist","player")))
		if author=="painter": author="companion"
		var title := str(obj.get("name",BlueprintBag.NAMES.get(obj.get("kind",""),"手绘造物")))
		var origin := ""
		var built: Dictionary = obj.get("built_plan",{})
		if not built.is_empty():
			var owner := str(built.get("owner",""))
			var bag := Plans.bag_for(game,owner)
			if bag.has("entries"):
				var plan := BlueprintBag.find_entry(bag,int(built.get("id",-1)))
				if not plan.is_empty():
					origin = _plan_id(game,owner,plan)
					title = str(plan.name)
		_add(rows,game,obj,id,author,title,"建筑实物" if not origin.is_empty() else "实物","object",origin)
	if world.paper_space != null:
		var scenic_sheets: Dictionary={}
		for work: Dictionary in world.paper_space.works:
			if work.get("author_id","map")=="map": continue
			_add(rows,game,work,work.work_id,work.author_id,str(work.get("name",Pen.MODES.get(work.mode,"地貌"))),"地貌","paper",str(work.get("source_work_id","")))
			if work.has("projection"):
				var id:String=work.projection.id
				if not scenic_sheets.has(id):scenic_sheets[id]=[]
				scenic_sheets[id].append(work)
		for id:String in scenic_sheets:
			var marks:Array=scenic_sheets[id]
			marks.sort_custom(func(a,b):return a.projection.index<b.projection.index)
			var first:Dictionary=marks.front()
			_add(rows,game,{"marks":marks,"work_ids":marks.map(func(mark):return mark.work_id)},id,first.author_id,first.name,"远景纸","distant")

	for segment: Dictionary in world.east_segments_snapshot():
		var legacy := "legacy-east-"+JSON.stringify([segment.get("revision",0),segment.get("name",""),segment.get("points",[])]).sha256_text().left(24)
		_add(rows,game,segment,str(segment.get("work_id",legacy)),"companion",str(segment.get("name","续画")),"东侧地形","east")
	var priest = world.get_node_or_null("SandboxPriest")
	var blueprints: Array = priest.blueprints if priest!=null else world.priest_work.get("blueprints",[])
	for bio: Dictionary in blueprints:
		_add(rows,game,bio,str(bio.get("blueprint_id","")),"priest",str(bio.get("name","物种图纸")),"物种图纸","species")
	if priest!=null:
		for beast in priest.works:
			var bio := {"design":beast.design,"phase":beast.phase,"blueprint_id":beast.blueprint_id,"at":[beast.beast_x,beast.beast_y],"health":beast.health}
			_add(rows,game,bio,beast.work_id,"priest",str(beast.design.get("name","生物")),"生物","individual",beast.blueprint_id)
	else:
		for beast: Dictionary in world.priest_work.get("works",[]):
			_add(rows,game,beast,str(beast.get("work_id","")),"priest",str(beast.get("design",{}).get("name","生物")),"生物","individual",str(beast.get("blueprint_id","")))
	var painter = world.get_node_or_null("SandboxCompanion")
	if painter!=null and painter.has_method("atlas_projects"):
		for project: Dictionary in painter.atlas_projects():
			var site_id := str(project.get("site",{}).get("id",""))
			var origin := site_id.trim_prefix("work:") if site_id.begins_with("work:") else ""
			_add(rows,game,project,str(project.get("project_id","")),"companion",str(project.get("title","创作委托")),"创作工程","project",origin)
	for page: Dictionary in Book.pages():
		if page.key in REFERENCES or page.has("reference_id"):
			_add(rows,game,page,str(page.get("reference_id","reference:%s:%s" % [page.key,page.section])),str(page.get("author_id","reference")),page.section,"参考笔谱","reference")
	return rows

static func query(game, filters := {}) -> Array:
	var result := []
	var search := str(filters.get("text","")).strip_edges().to_lower()
	for row: Dictionary in _records(game):
		var entry: Dictionary = row.entry
		if entry.format=="paper" and row.data.has("projection") and not filters.get("include_marks",false) and search!=entry.work_id:continue
		if entry.format=="reference" and filters.get("author_id","") not in ["reference","map-curator"] and not filters.get("include_references",false):continue
		if not str(filters.get("author_id","")).is_empty() and filters.author_id!=entry.author_id and not (filters.author_id=="reference" and entry.format=="reference"): continue
		if not str(filters.get("kind","")).is_empty() and filters.kind!=entry.kind: continue
		if not search.is_empty() and not (str(entry.name)+" "+entry.work_id+" "+entry.kind+" "+str(AUTHORS.get(entry.author_id,entry.author_id))).to_lower().contains(search): continue
		result.append(entry)
	return result

static func _stroke(points, brush: String, pigment: String, layer: String) -> Dictionary:
	var coords := []
	for v in points:
		var point:Vector2 = v if v is Vector2 else Vector2(v[0],v[1])
		coords.append([point.x,point.y])
	return {"points":coords,"brush":brush,"pigment":pigment,"layer":layer}

static func _recipe(game, entry: Dictionary, data: Dictionary) -> Dictionary:
	var strokes := []
	match entry.format:
		"reference":
			var layout := Book.building_layout(data,Vector2.ZERO,null)
			if layout.has("footprint"):
				var extent:=Vector2(layout.footprint[0],layout.footprint[1])
				layout.footprint=[extent.x,extent.y]
			for i in data.strokes.size():
				var path: Dictionary=data.strokes[i]
				strokes.append(_stroke(path.points,path.brush,path.get("pigment","inherit"),layout.layers[i] if layout.has("layers") else path.get("layer",path.get("section",""))))
				if path.has("ink_treatment"):strokes[-1].ink_treatment=path.ink_treatment
			return {"strokes":strokes,"layout":layout,"style":"ink"}
		"plan","drawing","object":
			var built: Dictionary = data.get("built_plan",{})
			var layout: Dictionary = data.get("layout",built.get("layout",{})).duplicate(true)
			if not built.is_empty() and not layout.is_empty():
				# Object paths are centred on the rendered body, while its plan is not.
				var offset := Plans.point(built.offset)
				for field in ["supports","access"]:
					layout[field] = layout[field].map(func(p): return Plans.coords(Plans.point(p)+offset))
				for station: Dictionary in layout.get("stations",[]):
					if station.has("x"): station.x += offset.x
				if layout.has("footprint"):
					layout.footprint = [layout.footprint[0]+offset.x,layout.footprint[1]+offset.x]
			var sources: Array = layout.get("stroke_sources",[])
			for i in data.paths.size():
				var path: Dictionary = data.paths[i]
				var line := _stroke(path.points,path.get("brush","fine"),path.get("pigment","inherit"),str(layout.layers[i]) if layout.has("layers") and i<layout.layers.size() else str(path.get("layer","笔迹")))
				if path.has("ink_treatment"): line.ink_treatment = path.ink_treatment
				if i<sources.size() and sources[i] is Dictionary:
					line.source_work_id = sources[i].source_work_id
					line.source_stroke = int(sources[i].source_stroke)
				strokes.append(line)
			return {"strokes":strokes,"layout":layout,"style":data.get("ink_style","ink"),"pen":data.get("pen",""),"bag_id":int(data.get("id",-1)) if entry.format!="object" else -1}
		"species","individual":
			return {"design":data.get("design",{}).duplicate(true),"phase":str(data.get("phase","")),"at":data.get("at",[data.get("x",0),data.get("y",0)]).duplicate(),"health":data.get("health",0),"call_id":str(data.get("call_id",""))}
		"distant":
			var page: Dictionary=data.marks[0].projection
			for mark:Dictionary in data.marks:
				strokes.append({"points":mark.projection.uv.duplicate(true),"brush":mark.projection.get("wash_effect",mark.get("brush","wash")),"pigment":mark.get("pigment","inherit"),"source_work_id":mark.get("source_work_id",""),"source_stroke":mark.get("source_stroke",-1)})
			var moves: Array = data.marks[0].get("sheet_moves", [])
			var original := strokes.duplicate(true)
			for j in range(moves.size()-1, -1, -1):
				for change in moves[j].get("changes", []):
					original[int(change.index)].brush = change.from
			return {"original_strokes":original,"strokes":strokes,"revision":moves.size(),"moves":moves.duplicate(true),"size":page.size.duplicate(),"origin":page.origin.duplicate(),"work_ids":data.work_ids.duplicate()}
		"paper":
			return {"record":data.duplicate(true)}
		"east":
			return {"segment":data.duplicate(true)}
		"project":
			var result := {}
			for field in ["project_id","title","brief","stage","outcomes","work_ids","scope","phases","cursor"]:
				if data.has(field): result[field]=data[field]
			return result.duplicate(true)
	return {}

static func read_sheet(game, ref: Dictionary) -> Dictionary:
	if not is_instance_valid(game) or game.team_slot.get("team_id")!=ref.get("team_id") or game.team_slot.get("world_id")!=ref.get("world_id"):
		return {"ok":false,"error":"所选图页属于另一份世界。"}
	var rows := _records(game)
	var matches := rows.filter(func(row):return row.entry.work_id==ref.get("work_id",""))
	if matches.size()!=1:return {"ok":false,"error":"此世界找不到唯一对应的原稿。"}
	var source: Dictionary = matches[0]
	var related := []
	var origin: String = source.entry.source_work_id
	var targets: Array = source.data.get("work_ids",[]) if source.entry.format in ["project","distant"] else []
	var recipe := _recipe(game,source.entry,source.data)
	var source_pages := {}
	for mark in recipe.get("layout",{}).get("stroke_sources",[]):
		if mark is Dictionary:
			source_pages[mark.source_work_id] = true
	for row: Dictionary in rows:
		if (not origin.is_empty() and row.entry.work_id==origin) or row.entry.source_work_id==source.entry.work_id or row.entry.work_id in targets or source_pages.has(row.entry.work_id):
			related.append(row.entry)
	if source.entry.format=="project":
		recipe.records=[]
		recipe.segments=[]
		recipe.strokes=[]
		for row: Dictionary in rows:
			if row.entry.work_id not in targets:continue
			match row.entry.format:
				"paper":recipe.records.append(row.data.duplicate(true))
				"east":recipe.segments.append(row.data.duplicate(true))
				"object":
					var object: Dictionary=row.data
					var object_at:=Vector2(object.get("x",0),object.get("y",0))
					var pose:=Transform2D(float(object.get("angle",0)),object_at)
					for line: Dictionary in _recipe(game,row.entry,object).strokes:
						for i in line.points.size():
							var point: Vector2=pose*Pen.point(line.points[i])
							line.points[i]=[point.x,point.y]
						recipe.strokes.append(line)
	var focus:=Vector2.INF
	match source.entry.format:
		"paper":focus=Pen.point(source.data.anchor.at)
		"distant":focus=Pen.point(recipe.origin)+Pen.point(recipe.size)*.5
		"object":focus=Vector2(source.data.x,source.data.y)
		"east":
			var path: Array=source.data.get("points",[])
			if not path.is_empty():focus=Pen.point(path[path.size() >> 1])
		"project":focus=Pen.point(source.data.get("site",{}).get("stand"))
	var sheet:={"ok":true,"entry":source.entry,"recipe":recipe,"related":related}
	if focus.is_finite():sheet.focus=[focus.x,focus.y]
	return sheet

static func copy_plan(game, ref: Dictionary, owner: String, title: String, patches: Array, counter := {}, groups: Array = []) -> Dictionary:
	var sheet := read_sheet(game,ref)
	if not sheet.ok: return sheet
	var bag := Plans.bag_for(game,owner)
	if bag.is_empty() or (sheet.entry.format not in ["plan","reference"] and not (sheet.entry.format=="drawing" and sheet.recipe.get("pen")=="draw_scenery")):
		return {"ok":false,"error":"请选择可复用的景物或建筑笔谱。"}
	if not counter.is_empty():
		var stations:Array=sheet.recipe.get("layout",{}).get("stations",[])
		var i=counter.get("slot")
		if not preload("res://scripts/architecture/stall_goods.gd").whole(i,0,stations.size()-1) or not preload("res://scripts/architecture/stall_goods.gd").valid(counter.get("offer")):
			return {"ok":false,"error":"请选图纸已有的使用位和有效货价。"}
		stations[int(i)].service="market_counter"
		stations[int(i)].offer=counter.offer.duplicate(true)
	var strokes: Array = sheet.recipe.strokes
	if sheet.entry.format == "reference":
		for stroke: Dictionary in strokes:
			stroke.points = Brush.reference_points(stroke.points,stroke.brush)
	if patches.size()>strokes.size(): return {"ok":false,"error":"局部改绘的笔数超出原图。"}
	var touched := {}
	for patch in patches:
		if not patch is Dictionary or not (patch.get("stroke") is int or patch.get("stroke") is float): return {"ok":false,"error":"请选择要改的原笔编号。"}
		var i := int(patch.stroke)
		if i!=patch.stroke or i<0 or i>=strokes.size() or touched.has(i) or patch.size()<2: return {"ok":false,"error":"改绘笔号无效或重复。"}
		for key in patch:
			if key not in ["stroke","brush","pigment","points"]:return {"ok":false,"error":"此修改不属于一笔的线、色或形。"}
			if key!="stroke": strokes[i][key]=patch[key]
		if strokes[i].get("ink_treatment") == "reserve" and not Brush.is_wash(strokes[i].brush):
			strokes[i].erase("ink_treatment")
		touched[i]=true
	if not groups.is_empty():
		if not patches.is_empty():return {"ok":false,"error":"请先保存这一组，再另存单笔的形或色。"}
		var edits:=study_variant(game,sheet,groups)
		if not edits.ok:return edits
		strokes=edits.strokes
		sheet.recipe.layout=edits.layout
		for i in edits.indices:touched[i]=true
	var command := {"tool":"draw_scenery","style":sheet.recipe.style,"strokes":[],"brushes":[],"pigments":[]}
	for stroke: Dictionary in strokes:
		command.strokes.append(stroke.points)
		command.brushes.append(stroke.brush)
		command.pigments.append(stroke.pigment)
	Brush.add_treatments(command,strokes)
	var result: Dictionary
	if sheet.recipe.layout.is_empty():
		var design := Plans.prepare_scenery(title,command,Vector2.ZERO)
		if design.has("error"):return {"ok":false,"error":design.error}
		var added := BlueprintBag.add_entry(bag,design)
		if added.entry.is_empty():return {"ok":false,"error":added.error}
		added.entry.name=design.name
		for i in strokes.size():added.entry.paths[i].layer=strokes[i].layer
		result={"ok":true,"id":int(added.entry.id)}
	else:
		result = Plans.store(game,owner,title,command,Vector2.ZERO,sheet.recipe.layout,sheet.recipe.get("bag_id",-1) if owner==sheet.entry.author_id else -1)
	if not result.ok: return result
	var page := BlueprintBag.find_entry(bag,int(result.id))
	page.work_id = "plan-"+Crypto.new().generate_random_bytes(12).hex_encode()
	page.author_id = owner
	page.source_work_id = sheet.entry.work_id
	page.source_author_id = sheet.entry.author_id
	page.changed_strokes = touched.keys()
	result.work_id = page.work_id
	return result

static func study_variant(game,sheet:Dictionary,groups:Array) -> Dictionary:
	var layout:Dictionary=sheet.recipe.layout.duplicate(true)
	if layout.is_empty():return {"ok":false,"error":"请选择有支点和使用位的旧建筑图纸。"}
	var edit:=Group.expand(game,groups,layout.layers,read_sheet)
	if edit.has("error"):return {"ok":false,"error":edit.error}
	var strokes:Array=sheet.recipe.strokes
	for i:int in edit.slots:
		if Group.protected(layout,i,strokes[i].points):return {"ok":false,"error":"第%d笔承担原建筑支点或设施，请选装饰笔。"%i}
		for line:Dictionary in edit.slots[i]:
			if line.points.size()>32 or Group.cuts_access(layout,line.points):return {"ok":false,"error":"取件超过32点或侵入原使用位净空。"}
	var sources:Array=layout.get("stroke_sources",[])
	if sources.is_empty():sources.resize(strokes.size())
	layout.stroke_sources=Group.replace_slots(sources,edit.slots,"source")
	layout.layers=Group.replace_slots(layout.layers,edit.slots,"layer")
	return {"ok":true,"strokes":Group.replace_slots(strokes,edit.slots),"layout":layout,"indices":edit.slots.keys()}

## Make a fresh public command at the requested anchor. Submission owns the
## real contact check, reach, actor charge and creation of the new world object.
static func rebase_paper(game, ref: Dictionary, at: Vector2, appearance := {}) -> Dictionary:
	var page := read_sheet(game,ref)
	if not page.ok: return page
	if page.entry.format!="paper" or not at.is_finite():return {"ok":false,"error":"请选择本世界的一笔地貌和有效的支点。"}
	var old: Dictionary=page.recipe.record
	var shift:=at-Pen.point(old.anchor.at)
	var command := {"work_id":"stroke-"+Crypto.new().generate_random_bytes(12).hex_encode(),"name":(str(page.entry.name)+" · 临本").left(56),"source_work_id":page.entry.work_id,"mode":old.mode,"points":[],"anchor":{"kind":old.anchor.kind,"at":[at.x,at.y]}}
	for pair in old.points:command.points.append([float(pair[0])+shift.x,float(pair[1])+shift.y])
	for field in ["brush","pigment","ink_treatment"]:
		if old.has(field):command[field]=old[field]
	for field in appearance:
		if field not in ["brush","pigment"]: return {"ok":false,"error":"该位置只接受笔型或颜料修改。"}
		command[field]=appearance[field]
	if not Pen.valid_appearance(command): return {"ok":false,"error":"此类地貌不接受所选笔型或颜料。"}
	if old.has("service"):
		command.service=old.service.duplicate(true)
		command.service.at=[float(old.service.at[0])+shift.x,float(old.service.at[1])+shift.y]
	return {"ok":true,"command":command}

static func stage_player_paper(game, ref: Dictionary, at: Vector2) -> Dictionary:
	var result := rebase_paper(game,ref,at)
	if not result.ok:return result
	var existing: Array=game.draft if game.draw_mode==8 else game.mode_drafts.get(8,[])
	if not existing.is_empty() or game.active_stroke!=null:
		return {"ok":false,"error":"地形笔已有草稿，请先完成或收起再临摹。"}
	var cmd: Dictionary=result.command
	game.set_draw_mode(8)
	if game.draw_mode!=8:return {"ok":false,"error":"当前不能切到地形笔。"}
	game.paper_pen_mode=cmd.mode
	game.pen_anchor_kind=cmd.anchor.kind
	var draft:={"points":[],"paper_work_id":cmd.work_id,"source_work_id":cmd.source_work_id,"paper_anchor_at":cmd.anchor.at,"paper_name":cmd.name}
	for p in cmd.points:draft.points.append(Vector2(p[0],p[1]))
	for field in ["brush","pigment","service","ink_treatment"]:
		if cmd.has(field):draft[field]=cmd[field]
	game.draft=[draft]
	game.toolbar.update_buttons()
	return {"ok":true,"work_id":cmd.work_id}

static func study_catalog(game) -> Array:
	var pages: Array=[]
	for row: Dictionary in _records(game):
		if row.entry.format not in ["reference","plan","drawing"]:continue
		if row.entry.format=="drawing" and row.data.get("pen")!="draw_scenery":continue
		var recipe:=_recipe(game,row.entry,row.data)
		if not recipe.get("strokes",[]).is_empty():
			pages.append({"ref":row.entry,"work_id":row.entry.work_id,"name":row.entry.name,"parts":Study.groups(row.entry,recipe.strokes)})
	return pages

static func study_part(game, work_id: String, part_id: String) -> Dictionary:
	return Study.read_part(read_sheet(game,{"team_id":game.team_slot.get("team_id"),"world_id":game.team_slot.get("world_id"),"work_id":work_id}),part_id)

static func compose_study(game, ref: Dictionary, spec: Dictionary) -> Dictionary:
	var sheet:=read_sheet(game,ref)
	if not sheet.ok:return sheet
	var support=spec.get("support_kind","free")
	if support not in ["ground","hanging","wall","free"]:return {"ok":false,"error":"未识别该支点类型。"}
	if support!="free":
		var at:=Pen.resolve_anchor(game,{"kind":support,"at":spec.get("origin")})
		if not at.is_finite():return {"ok":false,"error":"所选位置没有可贴合的地表、岩壁或吊点。"}
		var pivot:=Pen.point(spec.get("pivot",[0,0]))
		var actual: Array=sheet.recipe.get("strokes",[])
		if not actual.any(func(s):return not s.points.is_empty() and Pen.point(s.points[0]).is_equal_approx(pivot)):
			return {"ok":false,"error":"请选原稿中一笔实际起笔处作为接触支点。"}
		spec=spec.duplicate(true)
		spec.origin=[at.x,at.y]
	return Study.compose(sheet,spec)
