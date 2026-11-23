extends RefCounted
## Graph vertices are feet in metres. Only columns crossed by authored terrain
## are sampled, even when two works are separated by thousands of empty pages.
const FRONTIER_NAMES := {
	"village:west-grade": ["村西长坡","地表"],
	"village:west-gallery": ["村西石洞","洞底"],
	"village:west-perch": ["村西石洞","洞内悬台"],
	"village:west-massif": ["西洞山脊","山面"],
	"village:west-roof-step": ["西洞海口","登山石阶"],
	"village:west-roof-ledge": ["西洞海口","山腰石台"],
	"village:west-basin": ["西侧海湾","岸边"]
}
const PITCH := .8
const GRAVITY := 17.0
const LIFT := 7.45
const WALK_SPEED := 4.6
const HEIGHT := .58
const HALF_WIDTH := .17
const REACHED_X := .13
const EPS := .025
var world
var revision := 0
var _paper_epoch := -1
var _east_tip := Vector2.INF
var _fixed_signature := -1
var _checked_frame := -1
var _graph := AStar2D.new()
var _columns: Array = []
var _landings: Dictionary = {}
var _groups: PackedInt32Array
var _work_ids: Array = []
var _extra: Dictionary = {}
var _obstacles: Dictionary = {}
var _rock_edges: Dictionary = {}
var _jumps := {}
var _air_indexed := false
var _incoming:Dictionary={}
var _validated:Dictionary={}
var _site_candidates: Array = []
var _fixed_ids:Dictionary={}
var _sites_by_cell:Dictionary={}
var _reachable_groups:Dictionary={}

func _init(owner) -> void:
	world=owner

static func _pair(p:Vector2) -> Array:
	return [float(p.x),float(p.y)]

static func _pos(a:Array) -> Vector2:
	return Vector2(a[0],a[1])

func _is_fixed_entity(entity) -> bool:
	# Harnessed wagons are frozen rigid bodies, but follow their horses each tick.
	return is_instance_valid(entity) and entity.alive and entity.freeze and not entity.is_actor() and not (entity.kind=="wagon" and entity.companion_id!="")

func _sync(force:bool=false) -> void:
	var epoch:int=world.paper_space.navigation_revision
	var tip:Vector2=world.terrain.profile[-1]
	var frame:=Engine.get_physics_frames()
	if not force and tip.distance_to(_east_tip)<2.0 and not world.terrain.east_ink.pending.is_empty():tip=_east_tip
	if not force and frame==_checked_frame and epoch==_paper_epoch and tip==_east_tip:return
	var signature:=_fixed_signature
	if force or _checked_frame<0 or frame/20!=_checked_frame/20:
		var fixed: Array=[]
		for body in world.game.object_nodes:
			if is_instance_valid(body) and not body.data.get("dynamic",true) and body.collision_layer & 1:
				fixed.append([body.get_instance_id(),body.transform,body.get_child_count(),body.data.get("damage_cuts",[]).hash()])
		for entity in world.entities:
			if _is_fixed_entity(entity):
				fixed.append([entity.entity_id,entity.transform,entity.alive,entity.cuts.size()])
		signature=fixed.hash()
	_checked_frame=frame
	if epoch==_paper_epoch and tip==_east_tip and signature==_fixed_signature:return
	_paper_epoch=epoch
	_east_tip=tip
	_fixed_signature=signature
	revision+=1
	_build()

func _span(xs:Dictionary,a:float,b:float) -> void:
	var lo:=minf(a,b)
	var hi:=maxf(a,b)
	if hi-lo<.04:return
	for i in range(ceili(lo/PITCH),floori(hi/PITCH)+1):xs[snappedf(i*PITCH,.001)]=true
	# Include footing inside both lips, even if a small ledge misses the grid.
	var inset:=minf(.13,(hi-lo)*.35)
	xs[snappedf(lo+inset,.001)]=true
	xs[snappedf(hi-inset,.001)]=true

func _add_extra(xs:Dictionary,a:Vector2,b:Vector2,id:String) -> void:
	if absf(b.x-a.x)<.04 or absf((b.y-a.y)/(b.x-a.x))>1.35:return
	var edge:={"a":a,"b":b,"id":id}
	for index in range(floori(minf(a.x,b.x)/16),floori(maxf(a.x,b.x)/16)+1):
		if not _extra.has(index):_extra[index]=[]
		_extra[index].append(edge)
	_span(xs,a.x,b.x)
	if absf(b.x-a.x)<2.0*PITCH:xs[snappedf((a.x+b.x)*.5,.001)]=true

func _fixed_faces(xs:Dictionary) -> void:
	for body in world.game.object_nodes:
		if not is_instance_valid(body) or body.data.get("dynamic",true) or not (body.collision_layer & 1):continue
		var id:=str(body.data.get("work_id",body.data.get("structure_id","")))
		_fixed_ids[id]=true
		for fixture in body.get_children():
			if not fixture is CollisionShape2D or fixture.disabled or not fixture.shape is RectangleShape2D:continue
			var poly:PackedVector2Array=fixture.global_transform*PackedVector2Array([
				fixture.shape.get_rect().position,Vector2(fixture.shape.get_rect().end.x,fixture.shape.get_rect().position.y),
				fixture.shape.get_rect().end,Vector2(fixture.shape.get_rect().position.x,fixture.shape.get_rect().end.y)])
			if not fixture.one_way_collision:
				var min_x:=minf(minf(poly[0].x,poly[1].x),minf(poly[2].x,poly[3].x))
				var max_x:=maxf(maxf(poly[0].x,poly[1].x),maxf(poly[2].x,poly[3].x))
				for k in range(floori(min_x/16),floori(max_x/16)+1):
					if not _obstacles.has(k):_obstacles[k]=[]
					_obstacles[k].append(poly)
			# Find the actual upper long edge after the fixture's rotation.
			var a:=poly[0];var b:=poly[1]
			if poly[2].y+poly[3].y>a.y+b.y:a=poly[3];b=poly[2]
			_add_extra(xs,a,b,id)
	for e in world.entities:
		if not _is_fixed_entity(e):continue
		for edge in e.world_walk_segments():_add_extra(xs,edge[0],edge[1],str(e.entity_id))

func _floors(x:float,low:float=-INF,high:float=INF) -> Array:
	var result: Array=[]
	for row in world.paper_surfaces(x,low,high):
		if row.face=="floor":result.append(row)
	for edge in _extra.get(floori(x/16),[]):
		var y:float=world.paper_space.crossing_y(x,edge.a,edge.b)
		if is_finite(y) and y>=low and y<=high:
			result.append({"y":y,"work_id":edge.id,"mode":"platform"})
	return result

func _solid(p:Vector2) -> bool:
	if world.paper_space.solid_xy(p.x,p.y):return true
	for poly in _obstacles.get(floori(p.x/16),[]):
		if Geometry2D.is_point_in_polygon(p,poly):return true
	return false

func _rock_edge(a:Vector2,b:Vector2) -> void:
	for i in range(floori(minf(a.x,b.x)/3),floori(maxf(a.x,b.x)/3)+1):
		if not _rock_edges.has(i):_rock_edges[i]=[]
		_rock_edges[i].append([a,b])

func _room(p:Vector2) -> bool:
	# An overhang can be thinner than the distance between two point probes.
	# Query its real edge through the middle of the standing body as well.
	for edge in _rock_edges.get(floori(p.x/3),[]):
		var y:float=world.paper_space.crossing_y(p.x,edge[0],edge[1])
		if y>p.y+.075 and y<p.y+HEIGHT:return false
	for side in [-HALF_WIDTH,HALF_WIDTH]:
		for dy in [.28,HEIGHT]:
			if _solid(p+Vector2(side,dy)):return false
	return true

func _build() -> void:
	_graph.clear()
	_landings.clear()
	_extra.clear()
	_fixed_ids.clear()
	_rock_edges.clear()
	_obstacles.clear()
	_jumps.clear()
	_work_ids.clear()
	_site_candidates.clear()
	_sites_by_cell.clear()
	_reachable_groups.clear()
	_air_indexed=false
	_incoming.clear();_validated.clear()
	var xs: Dictionary={}
	var profile:PackedVector2Array=world.terrain.profile
	_span(xs,profile[0].x,profile[-1].x)
	for p in profile:xs[snappedf(p.x,.001)]=true
	for entry in world.paper_space.entries.values():
		if entry.record.mode not in ["rock","platform","carve"]:continue
		if entry.record.mode in ["rock","carve"]:
			var origin:Vector2=world.paper_space.origin_for(entry.frame)
			for edge in entry.lines:_rock_edge(origin+edge[0],origin+edge[1])
		_span(xs,entry.box.position.x,entry.box.end.x)
		for xy in entry.record.points:
			xs[snappedf(float(xy[0]),.001)]=true
	_fixed_faces(xs)
	_columns=xs.keys()
	_columns.sort()
	for x:float in _columns:
		var ids:Array=[]
		for row in _floors(x):
			var p:=Vector2(x,row.y)
			if not _room(p) or world.terrain.in_water(p+Vector2(0,.5)):continue
			var duplicate:=false
			for id in ids:
				if absf(_graph.get_point_position(id).y-p.y)<EPS:duplicate=true;break
			if duplicate:continue
			var id:=_work_ids.size()
			_graph.add_point(id,p)
			_work_ids.append(row.work_id)
			ids.append(id)
		_landings[x]=ids
	_groups.resize(_work_ids.size())
	for id in _groups.size():_groups[id]=id
	for i in range(1,_columns.size()):
		var x:float=_columns[i]
		var prev:float=_columns[i-1]
		if x-prev>PITCH+.1:continue
		for left:int in _landings[prev]:
			for right:int in _landings[x]:
				if _walkable(_graph.get_point_position(left),_graph.get_point_position(right)):
					_graph.connect_points(left,right)
					_groups[_group(left)]=_group(right)
	for id in _groups.size():_groups[id]=_group(id)
	_index_sites()

func _group(id:int) -> int:
	while _groups[id]!=id:
		_groups[id]=_groups[_groups[id]]
		id=_groups[id]
	return id

func _support(p:Vector2,tolerance:float,preferred_work:String="") -> Dictionary:
	var best: Dictionary={}
	var gap:=tolerance+.0001
	for r in _floors(p.x,p.y-tolerance,p.y+tolerance):
		var distance:=absf(r.y-p.y)
		if not preferred_work.is_empty() and r.work_id==preferred_work:return r
		if distance<gap:
			gap=distance
			best=r
	return best

func _walkable(a:Vector2,b:Vector2) -> bool:
	if absf(b.y-a.y)>.045+absf(b.x-a.x)*1.35:return false
	for t in [.25,.5,.75]:
		var p:=a.lerp(b,t)
		var support:=_support(p,.055)
		if support.is_empty() or not _room(Vector2(p.x,support.y)):return false
	return true

func _arc(a:Vector2,b:Vector2,launch:float) -> float:
	var d:=launch*launch-2*GRAVITY*(b.y-a.y)
	return (launch+sqrt(d))/GRAVITY if d>=0 else -1.0

static func _flight_at(a:Vector2,b:Vector2,launch:float,time:float,t:float) -> Vector2:
	return Vector2(lerpf(a.x,b.x,t/time),a.y+launch*t-GRAVITY*t*t*.5)

func _flight(a:Vector2,b:Vector2,kind:String) -> float:
	var launch:=LIFT if kind=="jump" else 0.0
	var time:=_arc(a,b,launch)
	if time<=.12 or absf(b.x-a.x)>time*(WALK_SPEED-.3) or b.y<a.y-3.4:return -1
	var previous:=a
	var n:=maxi(6,ceili(time/.065))
	for i in range(1,n+1):
		var p:=_flight_at(a,b,launch,time,time*float(i)/n)
		if not _room(p) or (i<n and _solid(p+Vector2(0,.06))):return -1
		# A rigid walker presses a full direction until it reaches the landing.
		# It can strike a projecting lip long before the interpolated arc does.
		if kind=="jump" and i<n:
			var rigid:=p
			rigid.x=move_toward(a.x,b.x,WALK_SPEED*time*i/n)
			if not _room(rigid) or _solid(rigid+Vector2(0,.06)):return -1
		if previous.y>p.y+.001:
			for r in _floors(p.x,p.y+.06,previous.y-.015):
				# A descending foot cannot pass a one-way ledge to reach one below.
				if absf(r.y-b.y)>.08 or absf(p.x-b.x)>.22:return -1
		previous=p
	return time

func _index_air() -> void:
	if _air_indexed:return
	_air_indexed=true
	for i in _columns.size():
		var x:float=_columns[i]
		for j in range(i,_columns.size()):
			var next:float=_columns[j]
			if next-x>4.0:break
			for left:int in _landings[x]:
				for right:int in _landings[next]:
					if _groups[left]==_groups[right]:continue
					_add_transfer(left,right)
					_add_transfer(right,left)

func _add_transfer(start:int,end:int) -> void:
	var a:=_graph.get_point_position(start)
	var b:=_graph.get_point_position(end)
	if b.y>a.y+1.53 or b.y<a.y-3.4 or absf(a.x-b.x)>(_arc(a,b,LIFT)*(WALK_SPEED-.3)):return
	var src:=_groups[start];var dst:=_groups[end]
	if not _incoming.has(dst):_incoming[dst]={}
	if not _incoming[dst].has(src):_incoming[dst][src]=[]
	_incoming[dst][src].append(Vector2i(start,end))

# The outside tip of a one-way prop can be crossed before its contact
# fixture accepts a descending body. Aim inside the actual support segment.
func _landing_inside(id:int,at:Vector2) -> bool:
	var work_id:String=_work_ids[id]
	var on_prop:=false
	for surface in _extra.get(floori(at.x/16),[]):
		if surface.id!=work_id:continue
		if absf(world.paper_space.crossing_y(at.x,surface.a,surface.b)-at.y)>=EPS:continue
		on_prop=true
		var lo:=minf(surface.a.x,surface.b.x)
		var hi:=maxf(surface.a.x,surface.b.x)
		var inset:=minf(StickmanPlayer.BODY_RADIUS,(hi-lo)*.25)
		if at.x<lo+inset or at.x>hi-inset:continue
		return true
	return not on_prop

func _link(src:int,dst:int) -> bool:
	var key:=Vector2i(src,dst)
	if _validated.has(key):return _validated[key]
	var options:Array=_incoming[dst][src]
	options.sort_custom(func(u,v):
		return _graph.get_point_position(u.x).distance_squared_to(_graph.get_point_position(u.y))<_graph.get_point_position(v.x).distance_squared_to(_graph.get_point_position(v.y)))
	for edge:Vector2i in options:
		var a:=_graph.get_point_position(edge.x);var b:=_graph.get_point_position(edge.y)
		if not _landing_inside(edge.y,b):continue
		# A descending circle can stop short of its goal and stay caught on
		# the takeoff ledge. A solid step needs room to clear that edge.
		if b.y < a.y-.35 and absf(b.x-a.x) < StickmanPlayer.BODY_RADIUS+REACHED_X:
			var source := _support(a,.05,_work_ids[edge.x])
			if source.get("mode") in ["rock","carve"]:
				continue
		var kind:="jump"
		var duration:=-1.0
		var upper:Dictionary=world.paper_space.entries.get(_work_ids[edge.x],{})
		if absf(b.x-a.x)<.01 and b.y<a.y-.28 and upper.get("record",{}).get("mode")=="platform":
			duration=_flight(a,b,"drop")
			if duration>0:kind="drop_through"
		if duration<=0 and b.y<a.y-.35 and absf(b.x-a.x)>.18 and _support(Vector2(b.x,a.y),.14).is_empty():
			duration=_flight(a,b,"drop")
			if duration>0:kind="drop"
		if duration<=0:duration=_flight(a,b,"jump")
		if duration<=0:continue
		_graph.connect_points(edge.x,edge.y,false)
		_jumps[edge]={"kind":kind,"duration":duration}
		_validated[key]=true
		return true
	_validated[key]=false
	return false

func _can_reach(source:int,destination:int) -> bool:
	if source==destination:return true
	var pair:=Vector2i(source,destination)
	if not _reachable_groups.has(pair):
		_reachable_groups[pair]=_connect_route(source,destination)
	return _reachable_groups[pair]

func _connect_route(source:int,destination:int) -> bool:
	_index_air()
	var queue:Array[int]=[destination]
	var seen:Dictionary={destination:true}
	var cursor:=0
	while cursor<queue.size():
		var group:=queue[cursor];cursor+=1
		var incoming:Dictionary=_incoming.get(group,{})
		if incoming.has(source) and _link(source,group):return true
		for previous:int in incoming:
			if previous==source or seen.has(previous) or not _link(previous,group):continue
			seen[previous]=true
			queue.append(previous)
	return false

func _site_text(work:String,at:Vector2,record:Dictionary) -> Dictionary:
	var place: String
	var layer: String
	if FRONTIER_NAMES.has(work):
		place=FRONTIER_NAMES[work][0]
		layer=FRONTIER_NAMES[work][1]
	elif work in ["road","legacy:soil","legacy:road","legacy:east"]:
		if at.x>world.terrain.EastInk.ORIGINAL_EDGE.x:
			place="村东续画路"
			for drawing in world.terrain.east_ink.drawings:
				var contour:PackedVector2Array=drawing.contour
				if not contour.is_empty() and at.x>=contour[0].x and at.x<=contour[-1].x:
					place=str(drawing.get("name",place))
					break
		else:
			var nearest_distance:=INF
			for section in world.SECTIONS:
				var distance:=absf(section.x-at.x)
				if distance<nearest_distance:
					nearest_distance=distance
					place=section.name
		layer="桥面" if work=="legacy:road" else "地表"
	else:
		var author:=str(record.get("author_id",""))
		var who:=str({"player":"玩家","companion":"阿靛","priest":"牧师","war_god":"战神"}.get(author,""))
		place=str(record.get("name","")).strip_edges()
		if place.is_empty():place=who+"的作品" if not who.is_empty() else "纸上落脚点"
		var mode:=str(record.get("mode","platform"))
		layer=str({"platform":"承重台面","rock":"岩面","carve":"洞底"}.get(mode,"落脚面"))
	return {"name":place,"layer":layer,"label":"%s · %s（%.1f，%.1f 米）"%[place,layer,at.x,at.y]}

func label_for(site_id:String,at:Vector2) -> String:
	if not at.is_finite():return "未知地点"
	_sync()
	# Old role saves stored the full site key directly in the HUD label.
	var work:=site_id.get_slice("@",0) if site_id.contains("@") else site_id
	if work.is_empty() or (not FRONTIER_NAMES.has(work) and not world.paper_space.entries.has(work) and work not in ["road","legacy:soil","legacy:east","legacy:road"] and not _fixed_ids.has(work)):
		var support:=_support(at,.42)
		work=str(support.get("work_id",""))
	var entry:Dictionary=world.paper_space.entries.get(work,{})
	return _site_text(work,at,entry.get("record",{})).label

func _index_sites() -> void:
	var by_site: Dictionary={}
	for id in _work_ids.size():
		var work:String=_work_ids[id]
		if work.begins_with("legacy:") and work!="legacy:road":
			work="road"
		elif work!="legacy:road" and not world.paper_space.entries.has(work) and not _fixed_ids.has(work):continue
		var p:=_graph.get_point_position(id)
		var cell:Vector2i=world.paper_cell_at(p)
		var key:="%s@%d,%d"%[work,cell.x,cell.y]
		var center:float=(cell.x+.5)*16
		if by_site.has(key) and absf(by_site[key].at[0]-center)<absf(p.x-center):continue
		var entry:Dictionary=world.paper_space.entries.get(work,{})
		by_site[key]={"id":key,"at":_pair(p),"work_id":_work_ids[id],"cell":[cell.x,cell.y],"author_id":entry.get("record",{}).get("author_id","map"),"node":id}
	for site in by_site.values():
		var record:Dictionary=world.paper_space.entries.get(site.work_id,{}).get("record",{})
		site.merge(_site_text(site.work_id,_pos(site.at),record))
		var cell:=Vector2i(site.cell[0],site.cell[1])
		if not _sites_by_cell.has(cell):_sites_by_cell[cell]=[]
		_sites_by_cell[cell].append(site)
	_site_candidates=by_site.values()

func _nearby_sites(from:Vector2,limit:int,radius:float) -> Array:
	if not from.is_finite() or not radius>0 or limit<=0:return []
	var source:=_start_anchor(from)
	if source.is_empty():return []
	var group:=_groups[source.id]
	var lo:Vector2i=world.paper_cell_at(from-Vector2.ONE*radius)
	var hi:Vector2i=world.paper_cell_at(from+Vector2.ONE*radius)
	var cells:Array=[]
	if (1.0+float(hi.x)-lo.x)*(1.0+float(hi.y)-lo.y)>_sites_by_cell.size():
		for cell:Vector2i in _sites_by_cell:
			if cell.x>=lo.x and cell.x<=hi.x and cell.y>=lo.y and cell.y<=hi.y:cells.append(cell)
	else:
		for x in range(lo.x,hi.x+1):
			for y in range(lo.y,hi.y+1):cells.append(Vector2i(x,y))
	var nearby:Array=[]
	for cell:Vector2i in cells:
		for site:Dictionary in _sites_by_cell.get(cell,[]):
			var distance:=from.distance_squared_to(_pos(site.at))
			if distance>radius*radius or (distance<.16 and _groups[site.node]==group):continue
			nearby.append(site)
	nearby.sort_custom(func(a,b):
		var da:=from.distance_squared_to(_pos(a.at))
		var db:=from.distance_squared_to(_pos(b.at))
		return da<db if da!=db else a.id<b.id)
	var result:Array=[]
	for site:Dictionary in nearby:
		if not _can_reach(group,_groups[site.node]):continue
		var row:=site.duplicate(true)
		row.erase("node")
		result.append(row)
		if result.size()==limit:break
	return result

func sites(from:Vector2,limit:int,radius:float=INF) -> Array:
	_sync()
	if radius!=INF:return _nearby_sites(from,limit,radius)
	var choices:=_site_candidates.duplicate()
	choices.sort_custom(func(a,b):
		var a_new:int=int(a.author_id!="map")
		var b_new:int=int(b.author_id!="map")
		return a_new>b_new if a_new!=b_new else from.distance_squared_to(_pos(a.at))<from.distance_squared_to(_pos(b.at)))
	var result: Array=[]
	var seen: Dictionary={}
	for entry in choices:
		if result.size()>=maxi(0,limit):break
		var id:String=entry.work_id
		if seen.has(id) and id!="legacy:soil":continue
		seen[id]=true
		var site:Dictionary=entry.duplicate()
		site.erase("node")
		result.append(site)
	return result

func _anchor(p:Vector2,tolerance:float=.42) -> Dictionary:
	var support:=_support(p,tolerance)
	if support.is_empty():return {}
	var at:=Vector2(p.x,support.y)
	var best:=-1
	var distance:=INF
	var start:=_columns.bsearch(p.x-PITCH)
	for i in range(start,_columns.size()):
		var x:float=_columns[i]
		if x>p.x+PITCH:break
		for id:int in _landings[x]:
			var node:=_graph.get_point_position(id)
			var d:=node.distance_squared_to(at)
			if d<distance and absf(node.y-at.y)<.09+absf(x-p.x)*1.35 and _walkable(at,node):
				best=id
				distance=d
	return {} if best<0 else {"at":at,"id":best}

# A rigid foot can still rest on the lip when its center ray is already outside.
# Use nearby graph contacts only for departure. Destinations need actual floor.
func _start_anchor(p:Vector2) -> Dictionary:
	var exact:=_anchor(p,.16)
	if not exact.is_empty() or not _room(p):return exact
	var best:Dictionary={}
	var gap:=INF
	for i in range(_columns.bsearch(p.x-HALF_WIDTH),_columns.size()):
		var x:float=_columns[i]
		if x>p.x+HALF_WIDTH:break
		for id:int in _landings[x]:
			var at:=_graph.get_point_position(id)
			if absf(at.y-p.y)>.08:continue
			var distance:=at.distance_squared_to(p)
			if distance<gap:
				gap=distance
				best={"id":id,"at":at}
	return best

# A round body can be resting on a rock corner beyond the last vertical
# floor sample. Clear that corner horizontally before descending to the floor.
func _drop_x(feet:Vector2) -> float:
	var radius:=StickmanPlayer.BODY_RADIUS
	var center:=feet+Vector2(0,radius)
	var nearest:=INF
	var landing_x:=feet.x
	var edges: Array = []
	for cell in range(floori((feet.x-radius)/3),floori((feet.x+radius)/3)+1):
		edges.append_array(_rock_edges.get(cell,[]))
	# Cutting a shaft through the old slope leaves an exposed lip in the
	# original ground line as well as edges belonging to the new stroke.
	var terrain = world.terrain
	if not world.paper_space.modified_legacy.is_empty():
		var profile: PackedVector2Array = terrain.profile
		for i in range(terrain.profile_span(profile,feet.x-radius),terrain.profile_span(profile,feet.x+radius)+1):
			var a := profile[i-1]
			var b := profile[i]
			for line in world.paper_space.legacy_line(a,b):
				if not a.is_equal_approx(line[0]) or not b.is_equal_approx(line[1]):
					edges.append(line)
	for edge in edges:
		var a:Vector2=edge[0];var b:Vector2=edge[1]
		if absf(a.x-b.x)<.04 or (a.x-feet.x)*(b.x-feet.x)<=0:continue
		var lip:=a if absf(a.x-feet.x)<absf(b.x-feet.x) else b
		var offset:=center-lip
		var distance:=offset.length()
		if offset.y<radius*.35 or distance>radius+.01 or distance>=nearest:continue
		var inset:=lip.move_toward(b if lip==a else a,.025)
		if _support(inset,.012).is_empty():continue
		nearest=distance
		# Leave space for both the circle and the steering arrival tolerance.
		landing_x=lip.x+signf(offset.x)*(radius+.22)
	return landing_x

static func _step(a:Vector2,b:Vector2,kind:String,id:String,duration:float=0.0) -> Dictionary:
	return {"from":_pair(a),"to":_pair(b),"kind":kind,"work_id":id,"duration":duration}

func _other_sites(start:int,goal:Vector2) -> Array:
	var choices:Array=[]
	for site in _site_candidates:
		if _groups[site.node]!=_groups[start]:continue
		choices.append(site)
	choices.sort_custom(func(a,b):return _pos(a.at).distance_squared_to(goal)<_pos(b.at).distance_squared_to(goal))
	var result:Array=[]
	for c in choices:
		if _pos(c.at).distance_to(_graph.get_point_position(start))<.5:continue
		var s:Dictionary=c.duplicate();s.erase("node")
		result.append(s)
		if result.size()==3:break
	return result

func route(start:Vector2,goal:Vector2) -> Dictionary:
	_sync(true)
	if not start.is_finite() or not goal.is_finite():return {"ok":false,"error":"路线坐标无效"}
	var a:=_start_anchor(start)
	var steps:Array=[]
	# A saved actor can be midway through a jump. Recover along gravity to the
	# first reachable floor before planning the rest from that exact layer.
	if a.is_empty() and _room(start):
		var landing_x:=_drop_x(start)
		var levels:=_floors(landing_x,start.y-3.4,start.y)
		levels.sort_custom(func(u,v):return u.y>v.y)
		if not levels.is_empty():
			var land:=Vector2(landing_x,levels[0].y)
			var time:=_flight(start,land,"drop")
			if time>0:
				a=_anchor(land,.05)
				steps.append(_step(start,land,"drop",levels[0].work_id,time))
	if a.is_empty():return {"ok":false,"error":"当前位置没有可安全落下的脚面","goal":_pair(goal),"revision":revision}
	var b:=_anchor(goal)
	if b.is_empty():return {"ok":false,"error":"目标层没有可站的脚面","revision":revision,"goal":_pair(goal),"alternatives":_other_sites(a.id,goal)}
	if not _can_reach(_groups[a.id],_groups[b.id]):
		return {"ok":false,"error":"这两处脚面之间没有可通行的路或跳点","revision":revision,"goal":_pair(goal),"alternatives":_other_sites(a.id,goal)}
	var ids:=_graph.get_id_path(a.id,b.id)
	if ids.is_empty():return {"ok":false,"error":"这两处脚面之间没有可通行的路或跳点","revision":revision,"goal":_pair(goal)}
	var previous:Vector2=a.at
	# When replanning between two samples, start along the next walk edge
	# directly. A real jump still needs its original take-off point.
	var first:=0
	if ids.size()>1 and not _jumps.has(Vector2i(ids[0],ids[1])):
		var head:=_graph.get_point_position(ids[0])
		var next:=_graph.get_point_position(ids[1])
		if (previous-head).dot(next-previous)>=0 and _walkable(previous,next):first=1
	for i in range(first,ids.size()):
		var id:int=ids[i]
		var p:=_graph.get_point_position(id)
		if previous.distance_to(p)>.006:
			var air:Dictionary=_jumps.get(Vector2i(ids[i-1],id),{}) if i>0 else {}
			steps.append(_step(previous,p,air.get("kind","walk"),_work_ids[id],air.get("duration",0.0)))
		previous=p
	if previous.distance_to(b.at)>.006:steps.append(_step(previous,b.at,"walk",_work_ids[b.id]))
	return {"ok":true,"steps":steps,"goal":_pair(b.at),"revision":revision,"cursor":0,"flight":0.0}

func _refresh(plan:Dictionary,feet:Vector2) -> Dictionary:
	_sync()
	if plan.get("revision",-1)==revision:
		return {} if plan.get("ok",false) else plan
	var goal=plan.get("goal")
	if not goal is Array:return {"ok":false,"error":"缺少目标脚点"}
	var result:=route(feet,_pos(goal))
	if not result.ok:return result
	plan.clear();plan.merge(result)
	return {"replanned":true}

func advance(plan:Dictionary,feet:Vector2,delta:float,speed:float) -> Dictionary:
	var refreshed:=_refresh(plan,feet)
	if refreshed.has("error"):return refreshed
	var left:=maxf(0,delta)
	var kind:="walk"
	while plan.cursor<plan.steps.size() and left>.000001:
		var step:Dictionary=plan.steps[plan.cursor]
		kind=step.kind
		var a:=_pos(step.from);var b:=_pos(step.to)
		if kind=="walk":
			var duration:=feet.distance_to(b)/maxf(.1,speed)
			if duration>left:
				feet=feet.move_toward(b,left*maxf(.1,speed))
				var fraction:=clampf(inverse_lerp(a.x,b.x,feet.x),0,1) if absf(b.x-a.x)>.001 else 1.0
				var supporting:=_support(a.lerp(b,fraction),.075,step.work_id)
				if supporting.is_empty():return {"ok":false,"error":"行走途中失去所选脚面"}
				feet.y=supporting.y
				left=0
				break
			left-=duration
		else:
			var t:float=minf(step.duration,plan.flight+left)
			feet=_flight_at(a,b,LIFT if kind=="jump" else 0.0,step.duration,t)
			left-=t-plan.flight
			plan.flight=t
			if t<step.duration-.00001:break
		feet=b;plan.cursor+=1;plan.flight=0.0
	return {"ok":true,"at":feet,"arrived":plan.cursor>=plan.steps.size(),"kind":kind,"replanned":refreshed.get("replanned",false)}

func steer(plan:Dictionary,feet:Vector2,delta:float,grounded:Variant=null) -> Dictionary:
	var refreshed:=_refresh(plan,feet)
	if refreshed.has("error"):return refreshed
	while plan.cursor<plan.steps.size():
		var step:Dictionary=plan.steps[plan.cursor]
		var b:=_pos(step.to)
		var dx:=b.x-feet.x
		var settled:bool=step.kind=="walk" or (grounded==true if grounded is bool else (float(plan.flight)>.16 and feet.y<=float(plan.get("last_y",feet.y))+.006))
		plan.last_y=feet.y
		if absf(dx)<REACHED_X and absf(feet.y-b.y)<.24 and settled:
			plan.cursor+=1
			plan.flight=0.0
			plan.stall=0.0
			plan.takeoff_wait=0.0
			plan.takeoff_stable=0.0
			continue
		var jump:bool=step.kind=="jump" and float(plan.flight)==0.0
		if jump and grounded is bool:
			var start:=_pos(step.from)
			# A water edge or a preceding drop can carry a body through the
			# waypoint before the sole is close enough for a real takeoff.
			var near_floor:=absf(feet.y-start.y)<.24+absf(feet.x-start.x)*1.35
			plan.takeoff_stable=float(plan.get("takeoff_stable",0.0))+delta if grounded and near_floor else 0.0
			if plan.takeoff_stable<.055:
				plan.takeoff_wait=float(plan.get("takeoff_wait",0.0))+delta
				if plan.takeoff_wait>1.6:return {"ok":false,"error":"起跳处没有站稳，换一个落脚点"}
				var correction:=int(signf(start.x-feet.x)) if absf(start.x-feet.x)>.07 else 0
				return {"ok":true,"direction":correction,"jump":false,"down":false,"arrived":false,"kind":"walk"}
			plan.takeoff_wait=0.0
		var down:=false
		# A one-way ramp can catch a wide physical foot just above the planned
		# lower path. Use the ordinary double-down input while on that ramp.
		var through:bool=step.kind=="drop_through" and grounded==true and absf(dx)<.25
		if step.kind=="walk" and grounded==true and absf(dx)<.25 and feet.y-b.y>.20 and feet.y-b.y<1.0:
			var upper:=_support(feet,.15)
			through=upper.get("mode")=="platform" and upper.get("work_id")!=step.work_id
		if through:
			var phase:=fmod(float(plan.get("drop_clock",0)),.55)
			down=phase<.04 or (phase>=.12 and phase<.16)
			plan.drop_clock=phase+maxf(0,delta)
		else:plan.drop_clock=0.0
		plan.flight+=maxf(0,delta)
		if not plan.has("last_progress") or feet.distance_to(_pos(plan.last_progress))>.16:
			plan.last_progress=_pair(feet)
			plan.stall=0.0
		else:plan.stall=float(plan.get("stall",0.0))+delta
		if plan.stall>1.6:return {"ok":false,"direction":0,"jump":false,"arrived":false,"error":"角色被挡住，换一个落脚点或目标"}
		var direction:=int(signf(dx)) if absf(dx)>.07 else 0
		if step.kind=="jump" and direction!=0 and plan.flight<step.duration:
			# Normal controls are digital. Coast vertically when a full-speed
			# horizontal step would put the body ahead of its checked arc.
			var a:=_pos(step.from)
			var aim_x:=lerpf(a.x,b.x,float(plan.flight)/float(step.duration))
			if direction*(aim_x-feet.x)<WALK_SPEED*delta*.45:direction=0
		return {"ok":true,"direction":direction,"jump":jump,"down":down,"arrived":false,"kind":step.kind,"replanned":refreshed.get("replanned",false)}
	return {"ok":true,"direction":0,"jump":false,"arrived":true,"kind":"walk","replanned":refreshed.get("replanned",false)}
