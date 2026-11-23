extends RefCounted
## A section reserves no terrain. Only indexed works and measured openings advance it.
const Pen := preload("res://scripts/paper_world_pen.gd")
const Passage := preload("res://scripts/paper_waterway.gd")

static func section(project:Dictionary, id:String) -> Dictionary:
	for row:Dictionary in project.get("channel_plan",{}).get("sections",[]):
		if row.id==id:return row
	return {}

static func draft(project:Dictionary, proposed:Array) -> bool:
	var sections:Array=project.get("channel_plan",{}).get("sections",[]).duplicate(true)
	if proposed.is_empty() or proposed.size()>8:return false
	var revised:={}
	for raw:Dictionary in proposed:
		var id:String=str(raw.get("id",""))
		if revised.has(id) and not id.is_empty():return false
		var before:=section(project,id)
		if not id.is_empty() and (before.is_empty() or before.get("verified",false)):return false
		var a:=Pen.point(raw.get("from"))
		var b:=Pen.point(raw.get("to"))
		if not a.is_finite() or not b.is_finite() or a.distance_to(b)>9.0 or absf(a.x-b.x)<.28:return false
		var bed:Array=raw.get("bed",[])
		if bed.size()<2 or bed.size()>8:return false
		for p in bed:
			var sample:=Pen.point(p)
			if not sample.is_finite() or sample.x<minf(a.x,b.x)-.25 or sample.x>maxf(a.x,b.x)+.25:return false
			if absf(sample.y-(a.y+b.y)*.5)>4.0:return false
		if raw.get("kind") not in ["excavate","water"]:return false
		if raw.kind=="water":
			if not (raw.get("level") is float or raw.get("level") is int) or not is_finite(float(raw.level)):return false
			if bed.any(func(point):return float(point[1])>float(raw.level)-.055):return false
		var row:=raw.duplicate(true)
		if row.has("grade_for_water"):
			var water:=section(project,str(row.grade_for_water))
			if row.kind!="excavate" or water.get("kind")!="water" or not row.get("level") is float and not row.get("level") is int:return false
			var level:=float(row.level)
			if not is_equal_approx(level,float(water.level)) or bed.any(func(p):return float(p[1])>level-Passage.DRAFT+.000001):return false
			if sections.any(func(other):return other.id!=id and other.get("grade_for_water")==row.grade_for_water and other.bed==bed):return false
		if before.is_empty():
			row.id="channel-"+Crypto.new().generate_random_bytes(5).hex_encode()
			row.work_ids=[]
			sections.append(row)
		else:
			row.work_ids=before.work_ids.filter(func(work):return work not in before.get("linked_water_work_ids",[]))
			sections[sections.find(before)]=row
		if not id.is_empty():revised[id]=true
	if sections.is_empty():return false
	project.channel_plan={"v":1,"sections":sections}
	return true

static func restore_plan(raw:Variant) -> Dictionary:
	if not raw is Dictionary or not raw.get("sections") is Array:return {}
	var sections:Array=[]
	var ids:={}
	for row in raw.sections:
		if not row is Dictionary or not row.get("id") is String or not row.id.begins_with("channel-") or ids.has(row.id):continue
		if not row.get("name") is String or row.get("kind") not in ["excavate","water"] or not row.get("bed") is Array or row.bed.size()<2 or row.bed.size()>8:continue
		if not Pen.point(row.get("from")).is_finite() or not Pen.point(row.get("to")).is_finite() or not row.bed.all(func(point):return Pen.point(point).is_finite()):continue
		if row.kind=="water" and not (row.get("level") is float or row.get("level") is int):continue
		var copy:Dictionary=row.duplicate(true)
		if copy.kind=="water" and copy.bed.any(func(point):return float(point[1])>float(copy.level)-.055):
			copy.depth_revision="现稿床线有高于预计水面的地段。请就真实槽底修订床线或水位，再落水笔。"
		copy.work_ids=copy.work_ids.filter(func(work):return work is String) if copy.get("work_ids") is Array else []
		var inferred=copy.get("linked_water_work_ids",[])
		if not inferred is Array:copy.erase("linked_water_work_ids")
		var measurement=copy.get("measurement",{})
		if not measurement is Dictionary or not measurement.get("clear_span_m") is float and not measurement.get("clear_span_m") is int or \
			not measurement.get("planned_span_m") is float and not measurement.get("planned_span_m") is int:
			copy.erase("measurement")
		var history=copy.get("measurement_history",[])
		copy.measurement_history=history.filter(func(item):return item is Dictionary) if history is Array else []
		if copy.get("verified",false) and (not copy.get("measurement",{}).get("ok",false) or copy.work_ids.is_empty()):
			copy.verified=false
		ids[copy.id]=true
		sections.append(copy)
	var source:Dictionary={}
	if raw.get("last_edit") is Dictionary:
		for key in ["provider","model","call_id","request_id"]:
			var value=raw.last_edit.get(key)
			if value is String:source[key]=value.left(120)
	return {"v":1,"sections":sections,"last_edit":source} if not sections.is_empty() else {}

static func permits(project:Dictionary,id:String,records:Array) -> bool:
	var row:=section(project,id)
	if row.is_empty() or row.get("verified",false):return false
	var a:=Pen.point(row.from)
	var b:=Pen.point(row.to)
	var bounds:=Rect2(a,Vector2.ZERO).expand(b).grow(.45)
	for point in row.bed:bounds=bounds.expand(Pen.point(point))
	return not records.is_empty() and records.all(func(record):
		return record.mode in ["carve","rock","platform","water"] and record.points.any(func(p):return bounds.has_point(Pen.point(p))))

static func record(project:Dictionary,id:String,ids:Array) -> void:
	var row:=section(project,id)
	if row.is_empty():return
	for work in ids:
		if work not in row.work_ids:row.work_ids.append(work)

## Attribute a fill recorded by the project to its water section. A linked bed
## may be outside the planned run. Its water still cannot verify the run itself.
static func link_water_works(world, project:Dictionary) -> void:
	var sections:Array=project.get("channel_plan",{}).get("sections",[])
	if sections.is_empty() or world==null or world.paper_space==null:return
	var spans_by_water:={}
	var linked:={}
	for row:Dictionary in sections:
		if row.kind=="water":
			spans_by_water[row.id]=[]
			linked[row.id]=[]
	if spans_by_water.is_empty():return
	for row:Dictionary in sections:
		var owner:String=row.id if row.kind=="water" else str(row.get("grade_for_water",""))
		if not spans_by_water.has(owner):continue
		var a:=Pen.point(row.from)
		var b:=Pen.point(row.to)
		spans_by_water[owner].append(Vector2(minf(a.x,b.x),maxf(a.x,b.x)))
	var scopes:Array=[project.get("scope",{})]+project.get("trade_origin_scopes",[])
	for id in project.get("work_ids",[]):
		var entry:Dictionary=world.paper_space.entries.get(id,{})
		var ink:Dictionary=entry.get("record",{})
		if ink.get("mode")!="water" or ink.get("author_id")!="companion":continue
		if str(ink.get("world_id","")).is_empty() or str(ink.get("team_id","")).is_empty():continue
		if not scopes.any(func(scope):return scope.get("world_id")==ink.get("world_id") and scope.get("team_id")==ink.get("team_id")):continue
		var surface:float=entry.box.end.y
		var levels:=preload("res://scripts/paper_water_sections.gd").measure(entry.convex,
			preload("res://scripts/paper_space.gd").origin_for(entry.frame),[surface])
		var owners:Array=[]
		for water_id:String in spans_by_water:
			var water:=section(project,water_id)
			if absf(float(water.level)-surface)>.002:continue
			for band:Dictionary in levels[0].spans:
				if spans_by_water[water_id].any(func(span:Vector2):
					return minf(span.y,band.right)-maxf(span.x,band.left)>.0001):
					owners.append(water_id)
					break
		if owners.size()==1:linked[owners[0]].append(id)
	for water_id:String in linked:
		var row:=section(project,water_id)
		var previous:Array=row.get("linked_water_work_ids",[])
		var explicit_ids:Array=row.work_ids.filter(func(work):return work not in previous)
		var inferred:Array=linked[water_id].filter(func(work):return work not in explicit_ids)
		row.work_ids=explicit_ids+inferred
		if inferred.is_empty():row.erase("linked_water_work_ids")
		else:row.linked_water_work_ids=inferred

static func current_cut_reach(proof:Dictionary,brush:Dictionary) -> Array:
	var level=proof.get("best_measured_level")
	if not (level is float or level is int) or not brush.get("grounded",false):return []
	var grip:=Pen.point(brush.get("hand"))
	if not grip.is_finite():return []
	var reach:=float(brush.get("radius",0))
	for station:Dictionary in brush.get("stations",[]):
		if station.get("measured_hand",false):reach=float(station.radius)
	var bottom:float=float(level)-float(proof.get("min_clear_depth_m",.055))-.02
	var top:float=float(level)+.03
	var dy:=maxf(absf(grip.y-bottom),absf(grip.y-top))
	if dy>=reach:return []
	var dx:=sqrt(reach*reach-dy*dy)
	var result:Array=[]
	for gap:Array in proof.get("unopened_at_best_level",[]):
		var lo:=maxf(float(gap[0]),grip.x-dx)
		var hi:=minf(float(gap[1]),grip.x+dx)
		if hi-lo<.035:continue
		result.append({"span":[lo,hi],"vertical_band":[bottom,top],"at_measured_level":level,
			"fits_whole_gap":lo<=float(gap[0])+.02 and hi>=float(gap[1])-.02})
	return result

## A water section credits its own strokes at their actual surface. Other water
## at a higher level can cover them, including water drawn by another author.
static func _section_samples(space, id:String, heights:Array, water:bool) -> Array:
	if not water:return space.basin_sections(id,heights)
	var entry:Dictionary=space.entries[id]
	var higher:Array=[]
	for other:Dictionary in space.nearby(entry.box):
		if other.record.mode=="water" and float(other.box.end.y)>float(entry.box.end.y)+Passage.EPS:
			higher.append_array(Passage.water_parts(other))
	if higher.is_empty():return space.basin_sections(id,heights)
	var visible:=Passage.uncovered_water(Passage.water_parts(entry),higher)
	return preload("res://scripts/paper_water_sections.gd").measure(visible,Vector2.ZERO,heights)

static func measure(world,project:Dictionary,id:String,commit:=true) -> Dictionary:
	var row:=section(project,id)
	if row.is_empty():return {}
	var a:=Pen.point(row.from)
	var b:=Pen.point(row.to)
	var needed:=absf(b.x-a.x)
	var water:bool=row.kind=="water"
	var linked:bool=row.has("grade_for_water") and (row.get("level") is float or row.get("level") is int)
	var minimum_depth:=Passage.DRAFT if linked else .055
	var works:Array=[]
	var heights:Array=[row.level] if water or linked else []
	for id_work in row.work_ids:
		var entry:Dictionary=world.paper_space.entries.get(id_work,{})
		if entry.get("record",{}).get("mode")!=("water" if water else "carve"):continue
		if water and absf(float(entry.box.end.y)-float(row.level))>.002:continue
		works.append(id_work)
		if not water and not linked:
			for sample:Dictionary in world.paper_space.basin_sections(id_work):
				var y:=snappedf(float(sample.level),.005)
				if not y in heights:heights.append(y)
	var by_height:={}
	for id_work:String in works:
		for sample:Dictionary in _section_samples(world.paper_space,id_work,heights,water):
			for measured:Dictionary in sample.spans:
				if measured.depth<minimum_depth:continue
				var left:=maxf(float(measured.left),minf(a.x,b.x))
				var right:=minf(float(measured.right),maxf(a.x,b.x))
				if right-left>.02:
					by_height.get_or_add(sample.level,[]).append(Vector2(left,right))
	var sections:Array=[]
	var span:=0.0
	var best_y:Variant=null
	var best:Array[Vector2]=[]
	for y in by_height:
		var at_level:Array=by_height[y]
		at_level.sort_custom(func(x,z):return x.x<z.x)
		var combined:Array[Vector2]=[]
		for band:Vector2 in at_level:
			if not combined.is_empty() and band.x<=combined.back().y+.002:
				combined[-1].y=maxf(combined.back().y,band.y)
			else:combined.append(band)
		for band:Vector2 in combined:
			sections.append({"left":band.x,"right":band.y,"level":y})
			if band.y-band.x<=span:continue
			span=band.y-band.x
			best_y=y
			best=combined
	var left:=minf(a.x,b.x)
	var gaps:Array=[]
	for band:Vector2 in best:
		if band.x-left>.02:gaps.append([left,band.x])
		left=band.y
	var right:=maxf(a.x,b.x)
	if right-left>.02:gaps.append([left,right])
	var ok:=span+.02>=needed
	var proof:={"ok":ok,"clear_span_m":snappedf(span,.01),"planned_span_m":snappedf(needed,.01),"bands":sections,
		"best_measured_level":best_y,"unopened_at_best_level":gaps,"min_clear_depth_m":minimum_depth,"work_count":row.work_ids.size()}
	if commit:
		var prior:Dictionary=row.get("measurement",{})
		if not prior.is_empty() and prior!=proof:
			var history:Array=row.get("measurement_history",[])
			history.append(prior)
			row.measurement_history=history
		row.verified=ok
		row.measurement=proof
	return proof
