extends RefCounted
## A study describes excerpts of the actual drawings. All coordinates are metres.
const Pen := preload("res://scripts/paper_world_pen.gd")
const Palette := preload("res://scripts/pen_palette.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const PARTS_PATH := "res://assets/medieval/ink/study_parts.json"
static var part_names: Dictionary

static func groups(entry: Dictionary, strokes: Array) -> Array:
	if part_names.is_empty():
		var resource = JSON.parse_string(FileAccess.get_file_as_string(PARTS_PATH))
		if resource is Dictionary:part_names=resource
	var sections: Dictionary=part_names.get(str(entry.work_id).trim_prefix("map-folio/"),{}).duplicate(true)
	if sections.is_empty():
		for index in strokes.size():
			var layer := str(strokes[index].get("layer","笔迹"))
			if layer.is_empty():layer="笔迹"
			if not sections.has(layer):sections[layer]=[]
			sections[layer].append(index)
	var parts: Array=[]
	for key: String in sections:
		parts.append({"id":key,"label":key,"strokes":sections[key]})
	parts.append({"id":"all","label":"整页","strokes":range(strokes.size())})
	return parts

static func read_part(sheet: Dictionary, part_id: String) -> Dictionary:
	if not sheet.get("ok",false):return sheet
	var source: Array=sheet.recipe.get("strokes",[])
	if source.is_empty():return {"ok":false,"error":"这一页没有可取用的景物笔。"}
	for part: Dictionary in groups(sheet.entry,source):
		if part.id!=part_id:continue
		var strokes: Array=[]
		var area:=Rect2()
		var first:=true
		for index in part.strokes:
			var stroke: Dictionary=source[int(index)].duplicate(true)
			stroke.stroke=int(index)
			for pair in stroke.points:
				var at:=Vector2(pair[0],pair[1])
				area=Rect2(at,Vector2.ZERO) if first else area.expand(at)
				first=false
			strokes.append(stroke)
		return {"ok":true,"ref":sheet.entry,"part_id":part.id,"strokes":strokes,"bounds":[area.position.x,area.position.y,area.size.x,area.size.y]}
	return {"ok":false,"error":"这页没有所选部件，请从该页列出的部件选取。"}

static func compose(sheet: Dictionary, spec: Dictionary) -> Dictionary:
	if not sheet.get("ok",false):return sheet
	var source: Array=sheet.recipe.get("strokes",[])
	var selected = spec.get("strokes")
	if not selected is Array or selected.is_empty() or selected.size()>128 or source.is_empty():
		return {"ok":false,"error":"请从同一页选取 1–128 笔原稿。"}
	var origin:=Pen.point(spec.get("origin"))
	var pivot:=Pen.point(spec.get("pivot",[0,0]))
	var factor:=Pen.point(spec.get("scale",[1,1]))
	if not origin.is_finite() or not pivot.is_finite() or not factor.is_finite() or minf(factor.x,factor.y)<=0:
		return {"ok":false,"error":"落点、原稿基点与正数缩放需要有效的二维坐标。"}
	if not spec.get("mirror_x",false) is bool:return {"ok":false,"error":"左右镜像需要布尔值。"}
	if spec.get("mirror_x",false):factor.x=-factor.x
	var paints=spec.get("pigments",{})
	var batch=spec.get("batch_id")
	if not paints is Dictionary or not batch is String or batch.strip_edges().is_empty() or batch.length()>128:
		return {"ok":false,"error":"请提供本批的编号，逐笔改色使用原笔号和公共颜料。"}
	var seen: Dictionary={}
	var commands: Array=[]
	for id in selected:
		if not (id is int or id is float) or int(id)!=id or id<0 or id>=source.size() or seen.has(int(id)):
			return {"ok":false,"error":"本批原笔号不存在或重复。"}
		var index:=int(id)
		seen[index]=true
		var old:Dictionary=source[index]
		var tint=paints.get(str(index),old.pigment)
		if not Palette.valid(tint):return {"ok":false,"error":"第%d笔的颜料不在公共色板内。" % index}
		var points: Array=[]
		for xy in old.points:
			var p:=origin+(Pen.point(xy)-pivot)*factor
			if not p.is_finite():return {"ok":false,"error":"变形后的笔迹超出可表示范围。"}
			points.append([p.x,p.y])
		if points.size()<2:return {"ok":false,"error":"这一笔缺少路径。"}
		var page:Dictionary=sheet.entry
		var unique:=JSON.stringify([page.team_id,page.world_id,page.work_id,batch,index]).sha256_text().left(24)
		var filled := Brush.is_wash(old.brush)
		var command:={"work_id":"study-"+unique,"source_work_id":page.work_id,"source_stroke":index,
			"name":str(spec.get("name",page.name)).left(56),"world_id":page.world_id,"team_id":page.team_id,
			"points":points,"anchor":{"kind":"free","at":points[0]},"pigment":tint,
			"mode":"backdrop" if filled else "scenery"}
		if spec.get("support_kind","free")!="free" and Pen.point(old.points[0]).is_equal_approx(pivot):
			command.anchor.kind=spec.support_kind
		if not filled:command.brush=old.brush
		if old.has("ink_treatment"):command.ink_treatment=old.ink_treatment
		commands.append(command)
	for key in paints:
		if not key is String or not key.is_valid_int() or str(int(key))!=key or not seen.has(int(key)):
			return {"ok":false,"error":"改色笔号应与本批实际选取的原笔一致。"}
	return {"ok":true,"strokes":commands}
