extends Node
## Ordered world-metre strokes, spatially indexed without a global page rectangle.
const Frontier := preload("res://scripts/paper_frontier.gd")
const Damage := preload("res://scripts/object_damage.gd")
const CELL := 16.0
const EPS := .0001
const CLOSED := ["rock","carve","backdrop","water"]
var terrain
var works: Array = []
var entries := {}
var cells := {}
var columns := {}
var bounds := Rect2()
var bodies := {}
var modified_legacy := {}
var legacy_refresh_pending := false
var wet_rims_to_refresh:Dictionary={}
var last_active := {}
var epoch := 0
var navigation_revision := 0
var sheet_count:=0

static func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x/CELL),floori(p.y/CELL))

static func origin_for(cell:Vector2i) -> Vector2:
	return Vector2(cell)*CELL

static func xy(p:Variant) -> Array:
	if p is Vector2:return [float(p.x),float(p.y)]
	if not p is Array or p.size()!=2:return []
	for n in p:
		if not (n is float or n is int) or not is_finite(float(n)):return []
	return [float(p[0]),float(p[1])]

static func local_point(p:Array,cell:Vector2i) -> Vector2:
	return Vector2(p[0]-float(cell.x)*CELL,p[1]-float(cell.y)*CELL)

static func to_frame(path:PackedVector2Array,from:Vector2i,to:Vector2i) -> PackedVector2Array:
	return Transform2D(0,origin_for(from-to))*path

static func pair(p: Variant) -> Vector2:
	if p is Vector2: return p
	if not p is Array or p.size()!=2: return Vector2.INF
	for n in p:
		if not (n is float or n is int) or not is_finite(float(n)): return Vector2.INF
	return Vector2(p[0],p[1])

static func normalized(raw: Variant, issue: Dictionary = {}) -> Dictionary:
	if not raw is Dictionary or not preload("res://scripts/paper_world_pen.gd").valid_appearance(raw): return {}
	var mode = raw.get("mode",raw.get("kind",""))
	if mode=="solid": mode="rock"
	if mode=="wall": mode="backdrop"
	if mode not in CLOSED and mode not in ["platform","scenery"]: return {}
	var id = raw.get("work_id",raw.get("id",""))
	if not id is String or id.is_empty() or id.length()>128: return {}
	for key in ["author_id","world_id","team_id"]:
		if not raw.get(key) is String or raw[key].is_empty(): return {}
	var anchor = raw.get("anchor")
	if not anchor is Dictionary or anchor.get("kind") not in ["free","ground","wall","hanging"]: return {}
	var at_xy:=xy(anchor.get("at"))
	if at_xy.is_empty():return {}
	var cell:=Vector2i(floori(at_xy[0]/CELL),floori(at_xy[1]/CELL))
	var at:=local_point(at_xy,cell)
	var key := "%d,%d"%[cell.x,cell.y]
	if raw.has("chunk_id") and raw.chunk_id!=key: return {}
	var pts = raw.get("points")
	if not (pts is Array or pts is PackedVector2Array) or pts.size()>256: return {}
	var path := PackedVector2Array()
	var list := []
	for value in pts:
		var world_xy:=xy(value)
		if world_xy.is_empty():return {}
		var p:=local_point(world_xy,cell)
		if not p.is_finite():return {}
		if path.is_empty() or p.distance_squared_to(path[-1])>EPS*EPS:
			path.append(p)
			list.append(world_xy)
	var closed: bool = mode in CLOSED
	if closed and path.size()>1 and path[0].distance_squared_to(path[-1])<EPS*EPS: path.resize(path.size()-1)
	if path.size() < (3 if closed else 2):
		issue.message = "去掉重合点后只余 %d 个点，%s至少需要 %d 个不同的点。" % [path.size(),mode,3 if closed else 2]
		return {}
	var box := Rect2(path[0],Vector2.ZERO)
	for p in path: box=box.expand(p)
	if maxf(box.size.x,box.size.y)>64 or not box.grow(64).has_point(at): return {}
	if closed:
		for i in path.size():
			for j in range(i+2,path.size()):
				if i==0 and j==path.size()-1: continue
				var a:=path[i]; var b:=path[(i+1)%path.size()]
				var c:=path[j]; var d:=path[(j+1)%path.size()]
				if Geometry2D.segment_intersects_segment(a,b,c,d)!=null or c.distance_squared_to(Geometry2D.get_closest_point_to_segment(c,a,b))<EPS*EPS or a.distance_squared_to(Geometry2D.get_closest_point_to_segment(a,c,d))<EPS*EPS: return {}
		if Geometry2D.triangulate_polygon(path).is_empty(): return {}
	if mode=="water":
		var rim := false
		for i in path.size():
			if absf(path[i].y-box.end.y)<EPS and absf(path[(i+1)%path.size()].y-box.end.y)<EPS: rim=true
		if not rim:
			issue.message = "水面的最高处需要两个相邻的等高点。"
			return {}
	if mode=="platform":
		var sign_x := signf(path[-1].x-path[0].x)
		for i in range(1,path.size()):
			if (path[i].x-path[i-1].x)*sign_x<=EPS:
				issue.message = "承重台面第 %d 到 %d 点的横向走向无效（x %.3f → %.3f 米）。沿一个方向画脚面；直壁可另用实岩画。" % [i,i+1,list[i-1][0],list[i][0]]
				return {}
	if raw.has("service"):
		var service = raw.service
		if mode!="platform" or not service is Dictionary or service.get("kind")!="fruit_market": return {}
		var station_xy:=xy(service.get("at"))
		if station_xy.is_empty(): return {}
		var station:=local_point(station_xy,cell)
		var supported:=false
		for i in range(1,path.size()):
			var floor_y:=crossing_y(station.x,path[i-1],path[i])
			if absf(station.y-floor_y)<.025: supported=true
		if not supported: return {}
	list.resize(path.size())
	var local_list:=[]
	for point in path:local_list.append([float(point.x),float(point.y)])
	var result: Dictionary=raw.duplicate(true)
	result.erase("id"); result.erase("kind")
	result.merge({"work_id":id,"mode":mode,"chunk_id":key,"points":list,"page":[cell.x,cell.y],"local_points":local_list,"anchor":{"kind":anchor.kind,"at":at_xy}},true)
	return result

static func overlaps_original_cut(repair: Dictionary, source: Dictionary) -> bool:
	if source.get("mode") != "carve": return false
	var offset := pair(repair.points[0])
	var fill := PackedVector2Array()
	var hole := PackedVector2Array()
	for p in repair.points: fill.append(pair(p)-offset)
	for p in source.points: hole.append(pair(p)-offset)
	return not Geometry2D.intersect_polygons(fill, hole).is_empty()

static func valid_state(state: Variant) -> bool:
	if not state is Dictionary or state.get("version")!=1 or not state.get("works") is Array: return false
	var seen := {}
	for raw in state.works:
		var record:=normalized(raw)
		if record.is_empty() or seen.has(record.work_id): return false
		if record.get("ink_treatment") == "soil_repair" and not overlaps_original_cut(record, seen.get(record.source_work_id, {})):
			return false
		seen[record.work_id]=record if record.mode=="carve" else {}
	return true

static func saved_bounds(state: Dictionary,east: float) -> Rect2:
	var box:=Rect2(Vector2(-5,-14),Vector2(east+5,27))
	for work in state.get("works",Frontier.first_works()):
		if work.has("projection"):continue
		for p in work.points: box=box.expand(pair(p))
	return box

static func cells_for(box: Rect2) -> Array:
	var result := []
	var start:=cell_at(box.position)
	var end:=cell_at(box.end)
	for x in range(start.x,end.x+1):
		for y in range(start.y,end.y+1): result.append(Vector2i(x,y))
	return result

func submit(records: Array,commit: bool) -> Dictionary:
	var pending := {}
	var results := []
	for raw in records:
		var issue := {}
		var rec:=normalized(raw,issue)
		if rec.is_empty(): return {"ok":false,"error":"第 %d 笔：%s" % [results.size()+1,issue.get("message","无效的笔划、支点或轮廓。")]}
		var id: String=rec.work_id
		if rec.get("ink_treatment") == "soil_repair":
			var source: Dictionary = entries.get(rec.source_work_id, {}).get("record", pending.get(rec.source_work_id, {}))
			if not overlaps_original_cut(rec, source):
				return {"ok":false,"error":"补坡笔须与指定的原挖空相接。"}
		var old: Dictionary=entries[id].record if entries.has(id) else pending.get(id,{})
		if not old.is_empty() and old!=rec: return {"ok":false,"error":"作品编号已经对应另一笔。"}
		results.append({"ok":true,"work_id":id,"chunk_id":rec.chunk_id,"changed":old.is_empty()})
		if old.is_empty(): pending[id]=rec
	if commit and not pending.is_empty():
		var dirty := {}
		var changed_cut := false
		var changed_travel := false
		for rec in pending.values():
			var entry:=_index(rec)
			if rec.mode in ["rock","carve","platform","water"]:changed_travel=true
			dirty[rec.work_id]=true
			if rec.mode=="carve":
				changed_cut=true
			for near in neighbors_of(entry):
				dirty[near.record.work_id]=true
		for id in dirty: _compile(entries[id])
		if changed_travel:navigation_revision+=1
		if changed_cut:refresh_legacy()
		for id in dirty:
			if entries[id].record.mode=="water":_compile_water(entries[id])
		epoch+=1
	return {"ok":true,"changed":not pending.is_empty(),"results":results}

## Called only after every transformed mark in one sheet has been validated.
func replace_projection(records: Array) -> void:
	for record: Dictionary in records:
		var old: Dictionary = entries[record.work_id]
		for cell in cells_for(old.local_box):
			var address: Vector2i = old.frame + cell
			cells[address].erase(old)
			if cells[address].is_empty(): cells.erase(address)
		var box: Rect2 = old.local_box
		for x in range(old.frame.x + cell_at(box.position).x, old.frame.x + cell_at(box.end).x + 1):
			columns[x].erase(old)
			if columns[x].is_empty(): columns.erase(x)
		_index(record, old.order)
	epoch += 1

func _index(rec: Dictionary, order: int = -1) -> Dictionary:
	if order < 0 and rec.has("projection"):sheet_count+=1
	var path:=PackedVector2Array()
	var frame:=Vector2i(rec.page[0],rec.page[1])
	for p in rec.local_points:path.append(Vector2(p[0],p[1]))
	var box:=Rect2(path[0],Vector2.ZERO)
	for p in path: box=box.expand(p)
	var entry:={"record":rec,"order":works.size() if order < 0 else order,"path":path,"frame":frame,"local_box":box,"box":Rect2(box.position+origin_for(frame),box.size),"convex":[],"parts":[],"lines":[]}
	if rec.mode in ["rock","carve","water"]:
		entry.convex=convex(path)
	if order < 0: works.append(rec)
	else: works[order] = rec
	entries[rec.work_id]=entry
	if not rec.has("projection"):
		bounds=entry.box if entries.size()-sheet_count==1 else bounds.merge(entry.box)
	for local_cell:Vector2i in cells_for(box):
		var address:=frame+local_cell
		if not cells.has(address): cells[address]=[]
		cells[address].append(entry)
	for cx in range(frame.x+cell_at(box.position).x,frame.x+cell_at(box.end).x+1):
		if not columns.has(cx): columns[cx]=[]
		columns[cx].append(entry)
	return entry

static func convex(poly: PackedVector2Array) -> Array:
	var input:=poly.duplicate()
	if Geometry2D.is_polygon_clockwise(input): input.reverse()
	var result:= []
	for part: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(input):
		if Geometry2D.is_polygon_clockwise(part): part.reverse()
		result.append(part)
	return result

func nearby(box: Rect2) -> Array:
	var hits := {}
	for cell in cells_for(box):
		for entry in cells.get(cell,[]):
			if entry.box.intersects(box,true): hits[entry.record.work_id]=entry
	var result:=hits.values()
	result.sort_custom(func(a,b):return a.order<b.order)
	return result

func neighbors_of(entry:Dictionary) -> Array:
	var hits:={}
	var box:Rect2=entry.local_box.grow(.002)
	for local_cell:Vector2i in cells_for(box):
		for other in cells.get(entry.frame+local_cell,[]):
			var offset:=origin_for(other.frame-entry.frame)
			if box.intersects(Rect2(other.local_box.position+offset,other.local_box.size),true):hits[other.record.work_id]=other
	var found:=hits.values()
	found.sort_custom(func(a,b):return a.order<b.order)
	return found

static func cutters_in(entry:Dictionary,frame:Vector2i) -> Array:
	var parts: Array=[]
	for part in entry.convex:parts.append(to_frame(part,entry.frame,frame))
	return parts

static func clean_part(input:PackedVector2Array) -> PackedVector2Array:
	# Subtracting convex half planes can leave the intersection twice or add a
	# collinear vertex. Canonicalize once for both the renderer and the fixture.
	if input.size()<3:return PackedVector2Array()
	var origin:=input[0]
	var local:=PackedVector2Array()
	for p in input:local.append(p-origin)
	var hull:=Geometry2D.convex_hull(local)
	if hull.size()<4:return PackedVector2Array()
	hull.resize(hull.size()-1)
	var area:=0.0
	for i in hull.size():area+=hull[i].cross(hull[(i+1)%hull.size()])
	if absf(area)<.00001:return PackedVector2Array()
	for i in hull.size():hull[i]+=origin
	return hull

static func subtract(parts: Array,cut: Array) -> Array:
	for cutter in cut:
		var next := []
		for part in parts:
			for piece in Damage._subtract(part,cutter):
				var clean:=clean_part(piece)
				if not clean.is_empty():next.append(clean)
		parts=next
	return parts

func _village_seam_wash(entry: Dictionary) -> ArrayMesh:
	# Match either exposed end of the hand-inked profile. The incoming rock
	# carries the same paper tone at its join, on the visible mesh only.
	var bank: Vector2 = terrain.profile[0]
	var direction := -1.0
	if not is_equal_approx(entry.box.end.x,bank.x):
		bank=terrain.profile[-1]
		direction=1.0
		if not is_equal_approx(entry.box.position.x,bank.x):return null
	var origin := origin_for(entry.frame)
	var seam := bank-origin
	if not Array(entry.path).any(func(vertex:Vector2):return vertex.distance_squared_to(seam)<EPS*EPS):return null

	# Clip the visible convex fragments at wash stops so a long rock doesn't
	# stretch the fade over its whole span. Keep pigment on the exposed wall
	# underneath the bottom of the old slab. The mesh uses page-local metres.
	var pieces: Array = entry.parts.duplicate()
	for distance:float in [3.3,2.5,1.3,.42]:
		pieces=_split_wash_parts(pieces,Vector2(seam.x+direction*distance,0),Vector2.DOWN)
	var bottom: float = terrain.BOTTOM-origin.y
	for level in [bottom,bottom+1.1]:
		pieces=_split_wash_parts(pieces,Vector2(0,level),Vector2.RIGHT)
	var vertices:=PackedVector2Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	for piece:PackedVector2Array in pieces:
		var start:=vertices.size()
		for p in piece:
			var strength:=smoothstep(.06,3.3,(p.x-seam.x)*direction)
			var exposed:=1.0-smoothstep(bottom,bottom+1.1,p.y)
			vertices.append(p)
			colors.append(Color(Color("ddd1b8"),maxf(strength,exposed)))
		for i in range(2,piece.size()):
			indices.append_array(PackedInt32Array([start,start+i-1,start+i]))
	if indices.is_empty():return null
	var surface: Array=[]
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX]=vertices
	surface[Mesh.ARRAY_COLOR]=colors
	surface[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface)
	return mesh

static func _split_wash_parts(parts:Array,at:Vector2,along:Vector2) -> Array:
	var result: Array=[]
	for part in parts:
		for inside in [true,false]:
			var piece:=clean_part(Damage._half(part,at,at+along,inside))
			if not piece.is_empty():result.append(piece)
	return result

func _compile(entry: Dictionary) -> void:
	entry.erase("distant_visible")
	var mode:String=entry.record.mode
	if mode=="rock":
		var parts: Array=entry.convex.duplicate()
		for other in neighbors_of(entry):
			if other.order>entry.order and other.record.mode=="carve":parts=subtract(parts,cutters_in(other,entry.frame))
		entry.parts=parts
		if entry.record.get("ink_treatment") == "soil_repair":
			entry.exposed_repair = _above_original_soil(entry)
			terrain.east_ground_wash.clear()
		else:
			entry.seam_wash=_village_seam_wash(entry)
	if mode in ["rock","carve"]: entry.lines=_exposed_edges(entry)
	var id:String=entry.record.work_id
	if bodies.has(id):
		_remove_body(id)
		_add_body(entry)

# Original soil pigment covers the buried part. Keep the ordinary rock face
# where a repaired shoulder protrudes into air or extends outside the old map.
func _above_original_soil(entry: Dictionary) -> Array:
	var visible: Array = entry.parts.duplicate()
	var origin := origin_for(entry.frame)
	var profile: PackedVector2Array = terrain.profile
	for i in range(terrain.profile_span(profile,entry.box.position.x), terrain.profile_span(profile,entry.box.end.x)+1):
		var a := profile[i-1] - origin
		var b := profile[i] - origin
		var floor_y: float = terrain.BOTTOM - origin.y
		var soil := clean_part(PackedVector2Array([a,b,Vector2(b.x,floor_y),Vector2(a.x,floor_y)]))
		if not soil.is_empty(): visible = subtract(visible,[soil])
	return visible

func solid_at(p: Vector2) -> bool:
	return solid_xy(p.x,p.y)

func solid_xy(x:float,y:float) -> bool:
	var solid:bool=x>=terrain.profile[0].x and x<=terrain.profile[-1].x and y>=terrain.BOTTOM and y<=terrain.surface_height(x)
	for entry in cells.get(Vector2i(floori(x/CELL),floori(y/CELL)),[]):
		var p:=Vector2(x-entry.frame.x*CELL,y-entry.frame.y*CELL)
		if entry.record.mode in ["rock","carve"] and entry.local_box.has_point(p) and Geometry2D.is_point_in_polygon(p,entry.path):
			solid=entry.record.mode=="rock"
	return solid

func _exposed_edges(entry: Dictionary) -> Array:
	var result := []
	var neighbors:=neighbors_of(entry)
	var origin:=origin_for(entry.frame)
	var path:PackedVector2Array=entry.path
	for i in path.size():
		var a:=path[i]; var b:=path[(i+1)%path.size()]; var delta:=b-a
		var cuts: Array[float]=[0.0,1.0]
		for other in neighbors:
			if other.order==entry.order or other.record.mode not in ["rock","carve"]: continue
			var near_path:=to_frame(other.path,other.frame,entry.frame)
			for j in near_path.size():_split_edge(cuts,a,b,near_path[j],near_path[(j+1)%near_path.size()])
		if entry.box.end.x>=terrain.profile[0].x and entry.box.position.x<=terrain.profile[-1].x:
			for j in range(1,terrain.profile.size()): _split_edge(cuts,a,b,terrain.profile[j-1]-origin,terrain.profile[j]-origin)
		cuts.sort()
		for j in range(1,cuts.size()):
			if (cuts[j]-cuts[j-1])*delta.length()<.001:continue
			var mid:=a+delta*((cuts[j]+cuts[j-1])*.5)
			var normal:=delta.orthogonal().normalized()*.0008
			if solid_xy(entry.frame.x*CELL+mid.x+normal.x,entry.frame.y*CELL+mid.y+normal.y)!=solid_xy(entry.frame.x*CELL+mid.x-normal.x,entry.frame.y*CELL+mid.y-normal.y): result.append([a+delta*cuts[j-1],a+delta*cuts[j]])
	return result

static func _split_edge(ts:Array[float],a:Vector2,b:Vector2,c:Vector2,d:Vector2) -> void:
	var cross_point=Geometry2D.segment_intersects_segment(a,b,c,d)
	if cross_point!=null: ts.append(clampf((cross_point-a).dot(b-a)/a.distance_squared_to(b),0,1))
	else:
		for p:Vector2 in [c,d]:
			if Geometry2D.get_closest_point_to_segment(p,a,b).distance_squared_to(p)<.00000001:
				ts.append(clampf((p-a).dot(b-a)/a.distance_squared_to(b),0,1))

func legacy_line(a:Vector2,b:Vector2) -> Array:
	var lines: Array=[[a,b]]
	for entry in nearby(Rect2(a,Vector2.ZERO).expand(b)):
		if entry.record.mode!="carve":continue
		for cutter in cutters_in(entry,Vector2i.ZERO):
			var next: Array=[]
			for line in lines: next.append_array(Damage._outside(line[0],line[1],cutter))
			lines=next
	return lines

func legacy_changed(box:Rect2) -> void:
	var queue_water:bool=wet_rims_to_refresh.is_empty()
	for entry in nearby(box):
		entry.erase("distant_visible")
		if entry.record.get("ink_treatment") == "soil_repair":
			entry.exposed_repair = _above_original_soil(entry)
			terrain.east_ground_wash.clear()
		if entry.record.mode=="carve" and not legacy_refresh_pending:
			legacy_refresh_pending=true
			refresh_legacy.call_deferred()
		elif entry.record.mode=="water":
			wet_rims_to_refresh[entry.record.work_id]=true
	if queue_water and not wet_rims_to_refresh.is_empty():_refresh_wet_rims.call_deferred()

func _refresh_wet_rims() -> void:
	# Carving can replace soil fixtures later in the same physics tick.
	if legacy_refresh_pending:return
	for id in wet_rims_to_refresh:
		if entries.has(id):_compile_water(entries[id])
	wet_rims_to_refresh.clear()

func refresh_legacy() -> void:
	if sheet_count>0:
		for entry in entries.values():entry.erase("distant_visible")
	terrain.east_ground_wash.clear()
	legacy_refresh_pending=false
	for id in modified_legacy:
		var pair_data: Dictionary=modified_legacy[id]
		if is_instance_valid(pair_data.fixture): pair_data.fixture.disabled=false
		if is_instance_valid(pair_data.replacement):
			pair_data.replacement.get_parent().remove_child(pair_data.replacement)
			pair_data.replacement.queue_free()
	modified_legacy.clear()
	for group in ["MountainRiverSoil","EastInkSoil"]:
		var soil:=get_parent().get_node_or_null(group)
		if soil==null:continue
		for fixture in soil.get_children():
			if not fixture is CollisionPolygon2D:continue
			var polygon:PackedVector2Array=fixture.polygon
			var box:=Rect2(polygon[0],Vector2.ZERO)
			for p in polygon:box=box.expand(p)
			var cuts: Array=[]
			for entry in nearby(box):
				if entry.record.mode=="carve":cuts.append_array(cutters_in(entry,Vector2i.ZERO))
			if cuts.is_empty():continue
			var pieces:=subtract(convex(polygon),cuts)
			var body:=_solid_body(pieces)
			add_child(body)
			fixture.disabled=true
			modified_legacy[fixture.get_instance_id()]={"fixture":fixture,"replacement":body,"source":polygon,"parts":pieces}
	_refresh_wet_rims()

func _solid_body(parts: Array) -> StaticBody2D:
	var body:=StaticBody2D.new()
	body.collision_layer=1;body.collision_mask=3
	body.set_meta("map_drop_allowed",false)
	for part in parts:
		var shape:=ConvexPolygonShape2D.new()
		shape.points=part
		var fixture:=CollisionShape2D.new()
		fixture.shape=shape
		body.add_child(fixture)
	return body

func _solid_occluders(entry:Dictionary) -> Array:
	var blockers: Array=[]
	for neighbor in neighbors_of(entry):
		if neighbor.record.mode=="rock":
			for part in neighbor.parts:blockers.append(to_frame(part,neighbor.frame,entry.frame))
	if entry.box.end.x>=terrain.profile[0].x and entry.box.position.x<=terrain.profile[-1].x:
		for group in ["MountainRiverSoil","EastInkSoil"]:
			var soil:=get_parent().get_node_or_null(group)
			if soil==null:continue
			for fixture in soil.get_children():
				if not fixture is CollisionPolygon2D:continue
				var source:PackedVector2Array=fixture.polygon
				if source[0].x>entry.box.end.x or source[1].x<entry.box.position.x:continue
				var surviving:Array=modified_legacy.get(fixture.get_instance_id(),{}).get("parts",[])
				if not fixture.disabled:surviving=convex(source)
				for part in surviving:blockers.append(to_frame(part,Vector2i.ZERO,entry.frame))
	return blockers

func _compile_water(entry:Dictionary) -> void:
	var blockers:=_solid_occluders(entry)
	entry.parts=subtract(entry.convex,blockers)
	var rims: Array=[]
	for i in entry.path.size():
		var a:Vector2=entry.path[i];var b:Vector2=entry.path[(i+1)%entry.path.size()]
		if absf(a.y-entry.local_box.end.y)<EPS and absf(b.y-entry.local_box.end.y)<EPS:rims.append([a,b])
	for blocker in blockers:
		var next:Array=[]
		for line in rims:next.append_array(Damage._outside(line[0],line[1],blocker))
		rims=next
	entry.lines=rims
	terrain.east_ground_wash.clear()

func _remove_body(id:String) -> void:
	var body:StaticBody2D=bodies[id]
	remove_child(body)
	body.queue_free()
	bodies.erase(id)

func _add_body(entry: Dictionary) -> void:
	var mode:String=entry.record.mode
	if mode not in ["rock","platform"]:return
	var body:=_solid_body(entry.parts)
	body.position=origin_for(entry.frame)
	if mode=="platform":
		body.set_meta("map_drop_allowed",true)
		for i in range(1,entry.path.size()):
			var a:Vector2=entry.path[i-1];var b:Vector2=entry.path[i]
			if a.x>b.x:
				var temp:=a;a=b;b=temp
			var delta:=b-a
			var shape:=RectangleShape2D.new()
			shape.size=Vector2(delta.length(),.10)
			var fixture:=CollisionShape2D.new()
			fixture.position=(a+b)*.5-Vector2(-delta.y,delta.x).normalized()*.05
			fixture.rotation=delta.angle()+PI
			fixture.shape=shape
			fixture.one_way_collision=true
			fixture.one_way_collision_margin=.035
			body.add_child(fixture)
	body.set_meta("paper_work_id",entry.record.work_id)
	bodies[entry.record.work_id]=body
	add_child(body)

func activate(points:Array) -> void:
	var centers:={}
	for p:Vector2 in points:
		if p.is_finite():centers[cell_at(p)]=true
	if centers==last_active and get_meta("active_epoch",-1)==epoch:return
	last_active=centers
	var wanted:={}
	for center:Vector2i in centers:
		for dx in range(-2,3):
			for dy in range(-2,3): wanted[center+Vector2i(dx,dy)]=true
	set_meta("active_epoch",epoch)
	var ids:={}
	for cell in wanted:
		for entry in cells.get(cell,[]):
			if entry.record.mode in ["rock","platform"]:ids[entry.record.work_id]=entry
	for id in bodies.keys():
		if not ids.has(id):_remove_body(id)
	for id in ids:
		if not bodies.has(id):_add_body(ids[id])

func restore(state: Dictionary) -> bool:
	if not state.is_empty() and (state.get("version")!=1 or not state.get("works") is Array):return false
	var rows:Array=state.get("works",Frontier.first_works())
	if rows==works:return true
	if not valid_state({"version":1,"works":rows}):return false
	for id in bodies.keys(): _remove_body(id)
	navigation_revision+=1
	sheet_count=0
	bounds=Rect2()
	works=[];entries.clear();cells.clear();columns.clear();last_active.clear()
	refresh_legacy()
	epoch+=1
	return submit(rows,true).ok

static func crossing_y(x:float,a:Vector2,b:Vector2) -> float:
	if absf(a.x-b.x)<EPS or x<minf(a.x,b.x)-EPS or x>maxf(a.x,b.x)+EPS:return INF
	return lerpf(a.y,b.y,clampf((x-a.x)/(b.x-a.x),0,1))

func surfaces(x:float,low:float,high:float) -> Array:
	var marks: Array=[]
	var result: Array=[]
	if x>=terrain.profile[0].x and x<=terrain.profile[-1].x:
		var legacy_id: String="legacy:soil" if x<=terrain.EastInk.ORIGINAL_EDGE.x else "legacy:east"
		marks.append({"y":terrain.surface_height(x),"mode":"rock","work_id":legacy_id,"order":-1})
		marks.append({"y":terrain.BOTTOM,"mode":"rock","work_id":legacy_id,"order":-1})
		for deck in terrain.ROAD_DECKS:
			var h:=crossing_y(x,deck[0],deck[1])
			if is_finite(h) and h>=low and h<=high:result.append({"y":h,"face":"floor","mode":"platform","work_id":"legacy:road"})
	for entry in columns.get(floori(x/CELL),[]):
		var mode:String=entry.record.mode
		var local_x:float=x-float(entry.frame.x)*CELL
		if mode not in ["rock","carve","platform"] or local_x<entry.local_box.position.x-EPS or local_x>entry.local_box.end.x+EPS:continue
		var path:PackedVector2Array=entry.path
		for i in range(path.size()-1 if mode=="platform" else path.size()):
			var h:float=crossing_y(local_x,path[i],path[(i+1)%path.size()])+float(entry.frame.y)*CELL
			if not is_finite(h) or h<low or h>high:continue
			var mark:={"y":h,"mode":mode,"work_id":entry.record.work_id,"order":entry.order}
			if mode=="platform":
				mark.erase("order");mark.face="floor"
				if not result.has(mark):result.append(mark)
			else:marks.append(mark)
	marks.sort_custom(func(a,b):return a.order>b.order)
	for mark in marks:
		var y:float=mark.y
		if y<low or y>high:continue
		var above:=solid_xy(x,y+.0008)
		var below:=solid_xy(x,y-.0008)
		if above==below:continue
		var face: String="floor" if below else "ceiling"
		var duplicate:=false
		for other in result:
			if other.face==face and absf(other.y-y)<EPS:duplicate=true;break
		if not duplicate:result.append({"y":y,"face":face,"mode":mark.mode,"work_id":mark.work_id})
	result.sort_custom(func(a,b):return a.y<b.y)
	return result

func water_surface(p:Vector2) -> float:
	if solid_at(p):return -INF
	var level:float=-INF
	for entry in cells.get(cell_at(p),[]):
		if entry.record.mode=="water" and Geometry2D.is_point_in_polygon(p-origin_for(entry.frame),entry.path):
			level=maxf(level,entry.box.end.y)
	return level

## Query one authored cut or water body, after any later terrain changes.
func basin_sections(work_id: String, levels: Array = []) -> Array:
	var entry: Dictionary = entries.get(work_id, {})
	if entry.is_empty() or entry.record.mode not in ["water", "carve"]:
		return []
	var heights: Array = levels
	var pieces: Array
	var origin := origin_for(entry.frame)
	if entry.record.mode == "water":
		pieces = entry.parts
		if heights.is_empty():
			heights = [float(entry.local_box.end.y) + origin.y]
	else:
		pieces = subtract(entry.convex, _solid_occluders(entry))
		if heights.is_empty():
			heights = []
			for fraction in [0.2, 0.4, 0.6, 0.8]:
				heights.append(origin.y + entry.local_box.position.y + entry.local_box.size.y * fraction)
	return preload("res://scripts/paper_water_sections.gd").measure(pieces, origin, heights)

func geometry_in(box:Rect2) -> Array:
	var result:Array=[]
	for polygon:PackedVector2Array in terrain.collision_geometry:
		var clipped:=false
		for update in modified_legacy.values():
			if update.source==polygon:
				result.append_array(update.parts)
				clipped=true
				break
		if not clipped:result.append(polygon)
	for entry in nearby(box):
		if entry.record.mode=="rock":
			for part in entry.parts:result.append(to_frame(part,entry.frame,Vector2i.ZERO))
		if entry.record.mode=="platform":
			for i in range(1,entry.path.size()):
				var a:Vector2=entry.path[i-1];var b:Vector2=entry.path[i]
				result.append(to_frame(PackedVector2Array([a,b,b+Vector2(0,-.10),a+Vector2(0,-.10)]),entry.frame,Vector2i.ZERO))
	return result

func _draw_seam_hatching(canvas:Node2D,g) -> void:
	var join:Vector2=terrain.profile[0]
	for mark:Vector4 in [Vector4(-1.72,.20,-.12,-.09),Vector4(-.87,.13,-.09,-.10),Vector4(.44,.16,-.16,-.19)]:
		var x:=join.x+mark.x
		for face in surfaces(x,join.y-.65,join.y+.12):
			if face.face!="floor":continue
			var a:=Vector2(x,face.y-mark.y)
			var b:=a+Vector2(mark.z,mark.w)
			if solid_at(a) and solid_at(b):
				canvas.draw_line(g.world_to_screen(a),g.world_to_screen(b),Color(.24,.20,.17,.21),1,true)
			break

static func _screen_path(g,path:PackedVector2Array,frame:Vector2i) -> PackedVector2Array:
	var screen:=PackedVector2Array()
	var origin:Vector2=g.world_to_screen(origin_for(frame))
	for p in path:screen.append(origin+Vector2(p.x,-p.y)*g.PIXELS_PER_UNIT)
	return screen

func _visible_sheet_stroke(entry:Dictionary) -> Array:
	if entry.has("distant_visible"):return entry.distant_visible
	var blockers:=_solid_occluders(entry)
	var parts:Array=[]
	if entry.record.mode=="backdrop":
		parts=subtract(convex(entry.path),blockers)
	else:
		for i in range(1,entry.path.size()):parts.append(PackedVector2Array([entry.path[i-1],entry.path[i]]))
		for solid:PackedVector2Array in blockers:
			var outside:Array=[]
			for line in parts:
				for segment in Damage._outside(line[0],line[1],solid):
					outside.append(PackedVector2Array(segment))
			parts=outside
	entry.distant_visible=parts
	return parts

func draw_distant_sheets(canvas:Node2D,g) -> void:
	if sheet_count==0:return
	var area:=Rect2(g.screen_to_world(Vector2.ZERO),Vector2.ZERO).expand(g.screen_to_world(g.get_viewport_rect().size)).grow(.15)
	for entry in nearby(area):
		if not entry.record.has("projection"):continue
		var tint:Color=preload("res://scripts/pen_palette.gd").resolve(entry.record.get("pigment","inherit"),Color("544f49"))
		for part:PackedVector2Array in _visible_sheet_stroke(entry):
			var path:=_screen_path(g,part,entry.frame)
			if entry.record.mode=="backdrop":
				var colors := PackedColorArray([Color(tint,.20)])
				var mist: bool = entry.record.projection.get("wash_effect","")=="mist"
				if mist:
					colors.clear()
					var base_y: float = entry.record.projection.origin[1] - origin_for(entry.frame).y
					var height: float = entry.record.projection.size[1]
					for p in part:
						colors.append(preload("res://scripts/distant_sheet.gd").mist_color(tint,(p.y-base_y)/height))
				for i in range(2,path.size()):
					var triangle_colors := PackedColorArray([colors[0],colors[i-1],colors[i]]) if mist else colors
					canvas.draw_primitive(PackedVector2Array([path[0],path[i-1],path[i]]),triangle_colors,PackedVector2Array())
			else:
				canvas.draw_line(path[0],path[1],Color(tint,.45),1.65 if entry.record.get("brush")=="bold" else 1.0,true)

func draw_world(canvas:Node2D,g) -> void:
	var area:=Rect2(g.screen_to_world(Vector2.ZERO),Vector2.ZERO).expand(g.screen_to_world(g.get_viewport_rect().size)).grow(.15)
	var visible:=nearby(area)
	var ink:=Color("51483e")
	for e in visible:
		if e.record.has("projection"):continue
		if e.record.mode=="backdrop":
			var shade: Color = Color(.37,.34,.31,.105)
			if e.record.has("pigment"):shade=Color(preload("res://scripts/pen_palette.gd").resolve(e.record.pigment,shade),.22)
			match e.record.get("ink_treatment",""):
				"body": shade.a=.60
				"reserve": shade=Color("#f8f4e8")
			canvas.draw_colored_polygon(_screen_path(g,e.path,e.frame),shade)
		elif e.record.mode=="scenery":
			var tint := Color(.32,.29,.26,.32)
			if e.record.has("pigment"):tint=Color(preload("res://scripts/pen_palette.gd").resolve(e.record.pigment,tint),.50)
			if e.record.get("ink_treatment")=="body": tint.a=.93
			canvas.draw_polyline(_screen_path(g,e.path,e.frame),tint,1.75 if e.record.get("brush")=="bold" else 1.05,true)
	for e in visible:
		if e.get("seam_wash")!=null:
			canvas.draw_set_transform(g.world_to_screen(origin_for(e.frame)),0,Vector2(1,-1)*g.PIXELS_PER_UNIT)
			canvas.draw_mesh(e.seam_wash,null)
			canvas.draw_set_transform(Vector2.ZERO)
		elif e.record.mode in ["rock","water"]:
			var color:=Color("ddd1b8") if e.record.mode=="rock" else Color(.21,.43,.48,.34) if e.box.size.y<.28 else Color(.23,.45,.48,.22)
			for part:PackedVector2Array in e.get("exposed_repair", e.parts):
				var pts:=_screen_path(g,part,e.frame)
				for i in range(2,pts.size()):
					canvas.draw_primitive(PackedVector2Array([pts[0],pts[i-1],pts[i]]),PackedColorArray([color]),PackedVector2Array())
	for e in visible:
		var mode:String=e.record.mode
		if e.get("seam_wash")!=null and area.grow(2).has_point(terrain.profile[0]):
			_draw_seam_hatching(canvas,g)
		if mode in ["rock","carve"]:
			for line in e.lines:
				var a:Vector2=line[0]+origin_for(e.frame);var b:Vector2=line[1]+origin_for(e.frame)
				if not area.intersects(Rect2(a,Vector2.ZERO).expand(b),true):continue
				canvas.draw_line(g.world_to_screen(a),g.world_to_screen(b),ink,1.9,true)
				if minf(a.x,b.x)==maxf(a.x,b.x):continue
				for i in range(ceili(maxf(area.position.x,minf(a.x,b.x))),floori(minf(area.end.x,maxf(a.x,b.x)))+1):
					var x:=i+.23*sin(i*2.7)
					var y:=crossing_y(x,a,b)
					if not is_finite(y) or i%3==0:continue
					var dir:float=-1 if solid_at(Vector2(x,y-.06)) else 1
					var p:=Vector2(x,y+dir*.11)
					var q:=p+Vector2(-.15-.05*cos(i),dir*(.13+.06*sin(i)))
					if solid_at(q):canvas.draw_line(g.world_to_screen(p),g.world_to_screen(q),Color(.24,.20,.17,.25),1.0,true)
		elif mode=="platform":
			var path:=_screen_path(g,e.path,e.frame)
			var shadow:=path.duplicate()
			for i in shadow.size():shadow[i]+=Vector2(0,5)
			canvas.draw_polyline(shadow,Color("a79b86"),1.7,true)
			canvas.draw_polyline(path,ink,2.3,true)
			for i in range(1,path.size()):
				var a:Vector2=path[i-1];var b:Vector2=path[i]
				for j in range(0,ceili(a.distance_to(b)),14):
					var p:=a.move_toward(b,float(j))
					canvas.draw_line(p+Vector2(0,2),p+Vector2(-3,5),ink,1,true)
		elif mode=="water":
			for line in e.lines:
				var a:Vector2=line[0]+origin_for(e.frame);var b:Vector2=line[1]+origin_for(e.frame)
				canvas.draw_line(g.world_to_screen(a),g.world_to_screen(b),Color("52747c") if e.box.size.y<.28 else Color("607c7d"),1.25,true)
				for wave in range(ceili(maxf(area.position.x,minf(a.x,b.x))+.5),floori(minf(area.end.x,maxf(a.x,b.x))-.5)):
					var level:float=a.y-.12-.08*sin(wave*2.17+terrain.elapsed*.6)
					var p:=Vector2(wave,level)
					if water_surface(p)>-INF:canvas.draw_line(g.world_to_screen(p),g.world_to_screen(p+Vector2(.28+.10*sin(wave),0)),Color(.23,.38,.40,.35),1,true)
