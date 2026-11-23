extends RefCounted
## Move one use position on an existing plan. Geometry, service slots, and stock stay with the building.
const Plans = preload("res://scripts/architecture/building_plans.gd")
const Market = preload("res://scripts/architecture/market_sites.gd")
const Component = preload("res://scripts/painter_scene_component.gd")
const STEP := .20
const HEAD_HEIGHT := 1.5

static func _access_index(layout:Dictionary, number:int) -> int:
	var stations:Array=layout.get("stations",[])
	if number<0 or number>=stations.size():return -1
	var station:Dictionary=stations[number]
	if not station.has("x") or station.has("service"):return -1
	var same_x=func(row):return row.has("x") and absf(row.x-station.x)<.001
	if stations.filter(same_x).size()!=1:return -1
	var matches:Array=layout.access.filter(func(p):return absf(p[0]-station.x)<.001)
	return layout.access.find(matches[0]) if matches.size()==1 else -1

# Clip the original straight stroke segments to the standing figure's entire width.
static func _span(a:Vector2,b:Vector2,left:float,right:float) -> Rect2:
	if a.x>b.x:return _span(b,a,left,right)
	var lo:=maxf(a.x,left)
	var hi:=minf(b.x,right)
	if hi<lo:return Rect2(0,0,-1,0)
	var y0:=a.y
	var y1:=b.y
	if b.x!=a.x:
		y0=lerpf(a.y,b.y,(lo-a.x)/(b.x-a.x))
		y1=lerpf(a.y,b.y,(hi-a.x)/(b.x-a.x))
	return Rect2(lo,minf(y0,y1),hi-lo,absf(y1-y0))

static func _geometry(obj:Dictionary,slot:int,access:int,local:Vector2) -> Dictionary:
	var meta:Dictionary=obj.built_plan
	var layout:Dictionary=meta.layout
	var station:Dictionary=layout.stations[slot]
	var width:=.4+(Plans.PAIRED_SHIFT if station.get("workers",1)==2 else 0.0)
	var left:=local.x-width
	var right:=local.x+width
	if not Plans.pair(layout.get("footprint")):return {"error":"旧图没有可核对的建筑范围。"}
	if local.x < layout.footprint[0]-Market.REACH or local.x > layout.footprint[1]+Market.REACH:return {"error":"新位置已经离开这件建筑的使用范围。"}
	for p:Array in layout.supports:
		if absf(p[0]-local.x)<width+.015 and absf(p[1]-local.y)<HEAD_HEIGHT:return {"error":"人物的肩宽与原柱脚重叠。"}
	for i in layout.access.size():
		if i==access:continue
		var p:Array=layout.access[i]
		var other_width:=.4+(Plans.PAIRED_SHIFT if Plans.paired_station(layout,p[0]) else 0.0)
		if absf(p[0]-local.x)<width+other_width and absf(p[1]-local.y)<HEAD_HEIGHT:return {"error":"现有使用位还需要这一段站立空间。"}
	var spans:Array[Vector2]=[]
	var roofs:Array=station.get("roof_layers",[])
	var fixtures:=[]
	for s:Dictionary in layout.stations:
		fixtures.append_array(s.get("fixture_layers",[]))
	var offset:=Plans.point(meta.offset)
	for i in obj.paths.size():
		var layer:String=layout.layers[i]
		if layer not in roofs and layer not in fixtures:continue
		var points=obj.paths[i].points
		for j in range(1,points.size()):
			var clipped:=_span(points[j-1]-offset,points[j]-offset,left,right)
			if clipped.size.x<0:continue
			if clipped.end.y>local.y+.04 and clipped.position.y<local.y+HEAD_HEIGHT-.0001:
				return {"error":"站位的净空碰到原图层「%s」。"%layer}
			if layer in roofs and clipped.position.y>=local.y+HEAD_HEIGHT-.0001:spans.append(Vector2(clipped.position.x,clipped.end.x))
	spans.sort_custom(func(a,b):return a.x<b.x)
	var covered_to:=left
	for span in spans:
		if span.x>covered_to+.0001:break
		covered_to=maxf(covered_to,span.y)
	return {"sheltered":covered_to>=right-.0001}

static func _floor_ok(game,at:Vector2,workers:int) -> bool:
	for dx in ([-Plans.PAIRED_SHIFT,0.0,Plans.PAIRED_SHIFT] if workers==2 else [0.0]):
		var p:=at+Vector2(dx,0)
		if game.medieval_world.terrain.in_water(p+Vector2(0,.015)):return false
		if not Plans._can_stand(game,p) or not Market._at_counter(game.medieval_world,p+Vector2(0,.4),p):return false
	return true

static func describe(game,obj:Dictionary) -> Array:
	var meta:Dictionary=obj.built_plan
	var layout:Dictionary=meta.layout
	var origin:Vector2=game.object_point(obj,Plans.point(meta.offset))
	var result:=[]
	if not Plans.pair(layout.get("footprint")):return result
	var built:=Plans._built(game)
	for slot in layout.get("stations",[]).size():
		var access:=_access_index(layout,slot)
		if access<0:continue
		var station:Dictionary=layout.stations[slot]
		var old:=Plans.point(layout.access[access])
		var choices:={}
		for n in range(ceili((layout.footprint[0]-Market.REACH)/STEP),floori((layout.footprint[1]+Market.REACH)/STEP)+1):
			var x:=n*STEP
			if absf(x-old.x)<STEP:continue
			var probe:=origin+Vector2(x,old.y)
			var floors:Array=game.medieval_world.paper_surfaces(probe.x,probe.y-1.5,probe.y+1.5).filter(func(f):return f.face=="floor")
			floors.sort_custom(func(a,b):return absf(a.y-probe.y)<absf(b.y-probe.y))
			for f:Dictionary in floors:
				var at:=Vector2(probe.x,f.y)
				var shape:=_geometry(obj,slot,access,at-origin)
				if shape.has("error") or not _floor_ok(game,at,station.get("workers",1)):continue
				var width:=.8+(2*Plans.PAIRED_SHIFT if station.get("workers",1)==2 else 0.0)
				var interval:={"x":at.x,"y":at.y,"width":width,"reason":"access"}
				if not Plans.interval_occupants(game.medieval_world,interval,built,obj.structure_id,true).is_empty():continue
				var cover:String="sheltered" if shape.sheltered else "open"
				var key:="%s/%s" % ["west" if x<old.x else "east",cover]
				if not choices.has(key) or absf(x-old.x)>absf(float(choices[key].local_x)-old.x):
					choices[key]={"id":"%s/%d/%s"%[obj.work_id,slot,key],"feet":Plans.coords(at),"local_x":x,"cover":cover,"surface":f.work_id}
				break
		result.append({"slot":slot,"use":station.get("use",""),"feet":Plans.coords(origin+old),"cover":station.get("cover","open"),"options":choices.values()})
	return result

static func selected(work:Dictionary,args:Dictionary) -> Dictionary:
	for row:Dictionary in work.get("use_positions",[]):
		for node:Dictionary in row.options:
			if node.id==args.get("site"):
				return {"work_id":work.work_id,"expected_origin":work.origin_world,"expected_plan_id":work.plan_id,"slot":row.slot,"feet":node.feet,"cover":node.cover,"use":args.get("use",row.use)}
	return {"error":"这处脚点不是本次勘察的候位。"}

static func prepare(game,args:Dictionary) -> Dictionary:
	var key=args.get("work_id","")
	var index:int=game.objects.find_custom(func(o):return o.get("work_id")==key and Component._eligible(o))
	if index<0:return {"error":"本队没有该建筑实物。"}
	var obj:Dictionary=game.objects[index]
	var issue:=Component._editability(obj)
	if not issue.is_empty():return {"error":issue}
	var meta:Dictionary=obj.built_plan
	var origin:Vector2=game.object_point(obj,Plans.point(meta.offset))
	if int(args.get("expected_plan_id",-1))!=int(meta.id) or not Plans.pair(args.get("expected_origin")) or origin.distance_to(Plans.point(args.expected_origin))>.005:return {"error":"实物或母图已经变化，请重新勘察。"}
	var slot:=int(args.get("slot",-1))
	var access:=_access_index(meta.layout,slot)
	if access<0:return {"error":"请选择一个独立的非买卖使用位。"}
	if not Plans.pair(args.get("feet")):return {"error":"新位置需要实测世界脚点。"}
	var at:=Plans.point(args.feet)
	var local:=at-origin
	var layout:Dictionary=meta.layout.duplicate(true)
	var station:Dictionary=layout.stations[slot]
	var old:=Plans.point(layout.access[access])
	if local.distance_to(old)<.05:return {"error":"所选位置仍是原使用位。"}
	var shape:=_geometry(obj,slot,access,local)
	if shape.has("error"):return shape
	var cover=args.get("cover")
	if cover not in ["sheltered","open"] or (cover=="sheltered" and not shape.sheltered):return {"error":"棚面未能遮住这一位置的双肩。"}
	if not _floor_ok(game,at,int(station.get("workers",1))):return {"error":"新站位需要有承重、干燥且容得下身体的真实脚面。"}
	layout.access[access]=Plans.coords(local)
	station.x=local.x
	station.use=str(args.get("use",station.get("use",""))).strip_edges().left(48)
	if station.use.is_empty():return {"error":"请保留这处使用位的用途。"}
	station.cover=cover
	# Shelter is a property of this standing place. Keep the original roof layer names
	# so later surveys can return under the eaves and protect their brushwork.
	var site:=Plans.preview_layout(game,layout,origin,obj.structure_id)
	if not site.ok:return {"error":site.error}
	return {"ok":true,"object":obj,"layout":layout,"old_feet":Plans.coords(origin+old),"feet":args.feet,"slot":slot}

## The foot sensor can report grounded during a short drop. Match a resting body's
## physical contact to the same continuous paper face that was surveyed for this position.
static func standing_contact(game,actor,at:Vector2) -> Dictionary:
	var player=actor.player
	if not actor.on_ground or absf(player.position.x-at.x)>.28 or player.linear_velocity.length()>.35:
		return {}
	var world=game.medieval_world
	var contact:Dictionary=world.paper_ground_contact(player)
	if contact.is_empty():
		return {}
	var floor_point:=Vector2(contact.x,contact.y)
	for i in range(1,5):
		var sample:=floor_point.lerp(at,i/4.0)
		var faces:Array=world.paper_surfaces(sample.x,sample.y-.015,sample.y+.015)
		if not faces.any(func(face):return face.face=="floor" and face.work_id==contact.work_id):
			return {}
	return contact

static func install(game,actor,args:Dictionary,authorship:Dictionary) -> Dictionary:
	var edit:=prepare(game,args)
	if edit.has("error"):return edit
	var foot:Vector2=actor.player.position-Vector2(0,.29)
	var at:=Plans.point(edit.feet)
	if game.medieval_world.terrain.in_water(foot+Vector2(0,.015)):return {"error":"阿靛落脚处仍有水，请再找一处干脚面。"}
	var contact:=standing_contact(game,actor,at)
	if contact.is_empty():return {"error":"阿靛尚未在新使用位的同层脚面站稳。"}
	var obj:Dictionary=edit.object
	var meta:Dictionary=obj.built_plan
	var parent:=int(meta.id)
	var bag:=Plans.bag_for(game,"companion")
	var original:=Plans._source(game,"companion",parent)
	if original.is_empty() or bag.entries.size()>=BlueprintBag.MAX_ENTRIES:return {"error":"请先确认原母图或整理图纸包。"}
	game.record()
	var copied:=BlueprintBag.duplicate_entry(bag,parent)
	if copied.entry.is_empty():return {"error":copied.error}
	var entry:Dictionary=copied.entry
	entry.parent_id=parent
	entry.name=obj.name.left(49)+"·使用位改稿"
	entry.author_id="companion"
	if not entry.has("work_id"):entry.work_id="companion-"+Crypto.new().generate_random_bytes(12).hex_encode()
	edit.layout.access_revision=authorship.merged({"slot":edit.slot,"from":edit.old_feet,"to":edit.feet})
	entry.layout=edit.layout.duplicate(true)
	meta.id=entry.id
	meta.layout=edit.layout
	return {"ok":true,"work_id":obj.work_id,"structure_id":obj.structure_id,"original_plan_id":parent,"plan_id":entry.id,"station_index":edit.slot,"from":edit.old_feet,"to":edit.feet,"actual_feet":Plans.coords(foot),"support":contact,"use":edit.layout.stations[edit.slot].use}
