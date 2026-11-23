extends RefCounted
## Verify the model's chosen scenic water on the same real terrain and level.

const Waterway := preload("res://scripts/paper_waterway.gd")
const Sections := preload("res://scripts/paper_water_sections.gd")
const HorizontalTolerance := 0.025
const WaterLevelTolerance := 0.002

static func valid(body:Dictionary) -> bool:
	return body.get("kind") in ["pond","stream"] and not str(body.get("purpose","")).strip_edges().is_empty() and 		_finite(body.get("left")) and _finite(body.get("right")) and _finite(body.get("level")) and 		float(body.right)-float(body.left)>=2.4 and float(body.right)-float(body.left)<=20.0

static func _finite(value:Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _merge_spans(spans:Array[Vector2]) -> Array[Vector2]:
	spans.sort_custom(func(a,b):return a.x<b.x)
	var joined:Array[Vector2]=[]
	for span in spans:
		if joined.is_empty() or span.x>joined.back().y+.001:joined.append(span)
		else:joined[-1]=Vector2(joined.back().x,maxf(joined.back().y,span.y))
	return joined

static func observe(world,project:Dictionary) -> Dictionary:
	var body:Dictionary=project.get("water_body",{})
	if not valid(body):return {}
	var level:float=body.level
	var spans:Array[Vector2]=[]
	var bed_spans:Array[Vector2]=[]
	var water_pieces:Array=[]
	for id in project.get("work_ids",[]):
		var entry:Dictionary=world.paper_space.entries.get(id,{})
		var mode:String=str(entry.get("record",{}).get("mode",""))
		if mode=="water" and absf(float(entry.box.end.y)-level)<=WaterLevelTolerance:
			water_pieces.append_array(Waterway.water_parts(entry))
		elif mode=="carve":
			_add_spans(bed_spans,world.paper_space.basin_sections(id,[level]),body)
	var higher:Array=[]
	var band:=Rect2(Vector2(body.left,level-.055),Vector2(float(body.right)-float(body.left),.060))
	for entry:Dictionary in world.paper_space.nearby(band):
		if entry.record.mode=="water" and float(entry.box.end.y)>level+WaterLevelTolerance:
			higher.append_array(Waterway.water_parts(entry))
	var visible:=Waterway.uncovered_water(water_pieces,higher)
	_add_spans(spans,Sections.measure(visible,Vector2.ZERO,[level]),body)
	bed_spans.append_array(spans)
	var joined:=_merge_spans(spans)
	var excavated:=_merge_spans(bed_spans)
	var longest:=_longest(joined)
	var target:=maxf(2.4,(float(body.right)-float(body.left))*.8)
	return {"target":body,"wet_spans":joined.map(func(span:Vector2):return [span.x,span.y]),
		"bed_spans":excavated.map(func(span:Vector2):return [span.x,span.y]),
		"excavated_width_m":snappedf(_longest(excavated),.001),"connected_width_m":snappedf(longest,.001),"target_width_m":snappedf(target,.001),"ready":longest+.005>=target}

static func _add_spans(out:Array[Vector2],sections:Array,body:Dictionary) -> void:
	for section:Dictionary in sections:
		for span:Dictionary in section.spans:
			var left:=maxf(body.left,span.left)
			var right:=minf(body.right,span.right)
			if right>left and float(span.depth)>=.05:out.append(Vector2(left,right))

static func _longest(spans:Array[Vector2]) -> float:
	var result:=0.0
	for span in spans:result=maxf(result,span.y-span.x)
	return result

static func check(records:Array, status:Dictionary) -> String:
	if status.is_empty():return ""
	var body:Dictionary=status.target
	var wet:Array=status.wet_spans.duplicate()
	var beds:Array=status.bed_spans.duplicate()
	for record:Dictionary in records:
		if record.mode not in ["carve","water"]:continue
		var left:=INF
		var right:=-INF
		var highest:=-INF
		for point:Array in record.points:
			left=minf(left,point[0])
			right=maxf(right,point[0])
			highest=maxf(highest,point[1])
		if left<float(body.left)-HorizontalTolerance or right>float(body.right)+HorizontalTolerance:
			return "这一笔出了所选同一岸的 %.2f 至 %.2f 米范围，请沿原岸分段接。"%[body.left,body.right]
		if record.mode=="water":
			if absf(highest-float(body.level))>WaterLevelTolerance:
				return "这项工程的池面是 %.3f 米，下一水段接在同一个水平面。"%body.level
			if not wet.is_empty() and not _touches(wet,left,right):
				return "新水与当前实测水面不相接，请先打开中间岸床，再接同一片水。"
			wet.append([left,right])
		elif highest>float(body.level):
			if not beds.is_empty() and not _touches(beds,left,right):
				return "这一槽离原工程的岸床还有空档。请沿上次开到的位置继续，或沿同一岸换脚。"
			beds.append([left,right])
	return ""

static func _touches(spans:Array,left:float,right:float) -> bool:
	return spans.any(func(span):return right>=float(span[0])-.001 and left<=float(span[1])+.001)

