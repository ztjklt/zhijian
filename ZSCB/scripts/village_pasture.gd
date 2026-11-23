extends RefCounted
## Each of the original sixteen living crowns supplies a quarter of a meadow's growth.
const Ground := preload("res://scripts/priest_ground.gd")
const Obstacles := preload("res://scripts/priest_obstacles.gd")
const SITES := {"west_meadow":3.4,"orchard_bank":14.2,"mill_meadow":57.0,"east_meadow":109.2}
const CAPACITY := 4
const REGROW_SECONDS := 24.0
const REACH := 1.15

static func initial() -> Dictionary:
	var records := {}
	for id in SITES: records[id] = {"portions":CAPACITY,"regrow_s":0.0}
	return records

static func token(source:String, seat:int) -> String:
	return "root-%s-%d"%[source,seat]

static func interval(capacity:int) -> float:
	return REGROW_SECONDS*CAPACITY/capacity if capacity>0 else 0.0

static func whole(n:Variant,cap:int) -> bool:
	return (n is int or n is float) and is_finite(n) and n==floorf(n) and n>=0 and n<=cap

static func valid(records:Variant) -> bool:
	if not records is Dictionary or records.size()>SITES.size()*(CAPACITY+1):return false
	for id in SITES:
		if not records.has(id):return false
	var movable:={}
	for id in SITES:
		for seat in range(1,CAPACITY+1):movable[token(id,seat)]=true
	for id in records:
		var row=records[id]
		if not row is Dictionary:return false
		var cap=row.get("capacity",CAPACITY)
		if not whole(cap,CAPACITY) or not whole(row.get("portions"),int(cap)):return false
		var t=row.get("regrow_s")
		if not (t is int or t is float) or not is_finite(t) or t<0 or t>interval(int(cap))+.000001:return false
		if (row.portions==cap)!=(t==0):return false
		if SITES.has(id):continue
		if not movable.has(id) or cap!=1 or row.get("owner") not in ["player","priest","adventurer-lizhou"]:return false
		if not row.get("work_id") is String or row.work_id.is_empty() or row.work_id.length()>160:return false
		for axis in ["x","y"]:
			var n=row.get(axis)
			if not (n is int or n is float) or not is_finite(n) or absf(n)>1e7:return false
	return true

static func valid_ownership(records:Dictionary, actors:Dictionary) -> bool:
	var issued:={}
	for id in SITES:
		for seat in range(int(records[id].get("capacity",CAPACITY))+1,CAPACITY+1):
			issued[token(id,seat)]=true
	for id in records:
		if not SITES.has(id) and not issued.erase(id):return false
	for actor in actors:
		var held=actors[actor].get("grass_roots",[])
		if not held is Array or held.size()>SITES.size()*CAPACITY:return false
		if not held.is_empty() and actor not in ["player","priest","adventurer-lizhou"]:return false
		for root in held:
			if not root is String or not issued.erase(root):return false
	return issued.is_empty()

static func info(service,id:String) -> Dictionary:
	if not service.pastures.has(id):return {}
	var row:Dictionary=service.pastures[id]
	var cap:=int(row.get("capacity",CAPACITY))
	if cap==0:return {}
	var x:=float(SITES[id] if SITES.has(id) else row.x)
	var y:=float(service.world.travel_height(x) if SITES.has(id) else row.y)
	var surface:=Ground.nearby(service.world,x,y,.045)
	if surface.is_empty() or (row.has("work_id") and surface.work_id!=row.work_id):return {}
	if not SITES.has(id) and service.world.terrain.in_water(Vector2(x,y+.025)):return {}
	return {"id":id,"x":x,"y":float(surface.y),"work_id":surface.work_id,"owner":row.get("owner",""),
		"portions":row.portions,"capacity":cap,"regrow_s":row.regrow_s,"interval_s":interval(cap),"can_divide":row.portions>0}

static func near(service,at:Vector2,radius:float) -> Array:
	var found:=[]
	if not at.is_finite() or not is_finite(radius) or radius<0:return found
	for id in service.pastures:
		var x:=float(SITES[id] if SITES.has(id) else service.pastures[id].x)
		if absf(at.x-x)>radius:continue
		var site:=info(service,id)
		if not site.is_empty() and at.distance_to(Vector2(x,site.y))<=radius:found.append(site)
	return found

static func can_graze(service,id:String,at:Vector2) -> bool:
	if not at.is_finite():return false
	var site:=info(service,id)
	if site.is_empty() or site.portions<=0:return false
	var root:=Vector2(site.x,site.y)
	if root.distance_to(at)>REACH:return false
	var layer:=Ground.trace(service.world,root,at.x)
	var standing:=Ground.nearby(service.world,at.x,at.y,.35)
	if layer.is_empty() or standing.is_empty() or layer.work_id!=standing.work_id or absf(layer.y-standing.y)>.012:return false
	return Obstacles.contact(service.world,at+Vector2(0,.27),root+Vector2(0,.25))

static func graze(service,id:String,at:Vector2) -> bool:
	if not can_graze(service,id,at):return false
	var row:Dictionary=service.pastures[id]
	row.portions-=1
	if row.regrow_s<=0:row.regrow_s=interval(int(row.get("capacity",CAPACITY)))
	return true

static func step(records:Dictionary,delta:float) -> void:
	for row in records.values():
		var cap:=int(row.get("capacity",CAPACITY))
		if row.portions==cap:continue
		row.regrow_s-=delta
		while row.regrow_s<=0 and row.portions<cap:
			row.portions+=1
			row.regrow_s+=interval(cap)
		if row.portions==cap:row.regrow_s=0.0

static func draw(canvas:Node2D,service,game) -> void:
	for id in service.pastures:
		var x:=float(SITES[id] if SITES.has(id) else service.pastures[id].x)
		if absf(game.view_camera().x-x)>13:continue
		var site:=info(service,id)
		if site.is_empty():continue
		for i in int(site.capacity):
			var foot_x:=x+(i-(float(site.capacity)-1)*.5)*.27
			var soil:=Ground.trace(service.world,Vector2(x,site.y),foot_x)
			if soil.is_empty():continue
			var at:Vector2=game.world_to_screen(Vector2(foot_x,soil.y))
			var length:float=game.PIXELS_PER_UNIT*(.31 if i<site.portions else .075)
			for side in [-1.0,.15,.85]:
				var tip:=at+Vector2(side*.49,-1.0+absf(side)*.25)*length
				canvas.draw_polyline(PackedVector2Array([at,at.lerp(tip,.55)+Vector2(-side*length*.12,0),tip]),Color("68744b"),1.8,true)
