extends RefCounted
## Loose fruit changes owner only after support, contact and available space are checked.
const Ground := preload("res://scripts/priest_ground.gd")
const Obstacles := preload("res://scripts/priest_obstacles.gd")
const RADIUS := .085
const TAKE_REACH := .95
const FULL_BRANCH_SECONDS := 120.0
const LIMIT := 256
var state := {"serial":0,"items":{},"full_seconds":{}}

static func valid(value:Variant) -> bool:
	if not value is Dictionary or not _whole(value.get("serial"),0,1e12):return false
	var items=value.get("items")
	var timers=value.get("full_seconds")
	if not items is Dictionary or items.size()>LIMIT or not timers is Dictionary or timers.size()>128:return false
	for id in items:
		var item=items[id]
		if not item is Dictionary or not id is String or not id.begins_with("ground-fruit-"):return false
		var num:String=id.trim_prefix("ground-fruit-")
		if not num.is_valid_int() or int(num)<1 or int(num)>value.serial or str(int(num))!=num:return false
		if not item.get("source_id") is String or item.source_id.is_empty() or item.source_id.length()>128:return false
		for axis in ["x","y"]:
			if not (item.get(axis) is int or item.get(axis) is float) or not is_finite(item[axis]) or absf(item[axis])>1e7:return false
	for id in timers:
		var time=timers[id]
		if not id is String or id.length()>128 or not (time is int or time is float) or not is_finite(time) or time<0 or time>FULL_BRANCH_SECONDS:return false
	return true

static func _whole(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(value) and floorf(value)==value and value>=minimum and value<=maximum

func _open_segment(world,start:Vector2,end:Vector2) -> bool:
	if not Obstacles.contact(world,start,end):return false
	var count:=maxi(1,ceili(start.distance_to(end)/.05))
	for i in count+1:
		if world.paper_space.solid_at(start.lerp(end,float(i)/count)):return false
	return true

func add(service,source:String,foot:Vector2,offset:float) -> Dictionary:
	if not foot.is_finite() or state.items.size()>=LIMIT or state.serial>=1e12:return {"ok":false,"error":"此处放不了果子"}
	var x:=foot.x+offset
	var ground:=Ground.trace(service.world,foot,x)
	if ground.is_empty():return {"ok":false,"error":"脚前没有相连的地面"}
	var center:=Vector2(x,float(ground.y)+RADIUS)
	if not _open_segment(service.world,foot+Vector2(0,.25),center):
		return {"ok":false,"error":"脚前被实物挡住了"}
	state.serial+=1
	var id:="ground-fruit-"+str(int(state.serial))
	state.items[id]={"source_id":source,"x":center.x,"y":center.y}
	return {"ok":true,"id":id,"at":[center.x,center.y],"source_id":source}

func near(at:Vector2,radius:float) -> Array:
	var result:=[]
	if not at.is_finite() or not is_finite(radius) or radius<0:return result
	for id in state.items:
		var item:Dictionary=state.items[id]
		var d:=at.distance_to(Vector2(item.x,item.y))
		if d<=radius:result.append({"id":id,"x":item.x,"y":item.y,"item":"fruit","quantity":1,"portions":1,"source_id":item.source_id,"distance":d})
	result.sort_custom(func(a,b):return a.distance<b.distance)
	return result

func take(service,id:String,mouth:Vector2,collector:String) -> Dictionary:
	var item:Dictionary=state.items.get(id,{})
	if item.is_empty() or collector.is_empty() or not mouth.is_finite():return {"ok":false,"error":"地上已没有这枚果"}
	var pos:=Vector2(item.x,item.y)
	if mouth.distance_to(pos)>TAKE_REACH or not _open_segment(service.world,mouth,pos):return {"ok":false,"error":"够不到这枚果"}
	var floor_row:=Ground.nearby(service.world,pos.x,pos.y-RADIUS,.06)
	if floor_row.is_empty():return {"ok":false,"error":"果子脚下的支撑已变"}
	var support:=Ground.trace(service.world,Vector2(pos.x,floor_row.y),mouth.x)
	if support.is_empty() or mouth.y<support.y-.05 or mouth.y>support.y+TAKE_REACH:return {"ok":false,"error":"与果子不在同层"}
	for face in service.world.paper_surfaces(mouth.x,support.y+.07,mouth.y-.01):
		if face.face in ["floor","ceiling"]:return {"ok":false,"error":"与果子有层板相隔"}
	state.items.erase(id)
	return {"ok":true,"before":1,"after":0,"id":id,"source_id":item.source_id,"at":[pos.x,pos.y],"collector_id":collector}

func fall(service,delta:float) -> void:
	for id in service.orchards.crops:
		var crop:Dictionary=service.orchards.crops[id]
		var size:int=service.orchards.count_slots(id)
		if crop.mask!=(1<<size)-1 or not service.orchards.alive(id):
			state.full_seconds.erase(id)
			continue
		var time:float=minf(FULL_BRANCH_SECONDS,float(state.full_seconds.get(id,0.0))+delta)
		if time<FULL_BRANCH_SECONDS:
			state.full_seconds[id]=time
			continue
		state.full_seconds[id]=FULL_BRANCH_SECONDS-5.0
		for i in size:
			if not service.orchards.visible_fruit(service,id,i):continue
			var foot:Vector2=service.orchards.at(id)
			var marker:Vector2=service.orchards.marker(service,id,i)
			var result:=add(service,id,foot,clampf(marker.x-foot.x,-1.4,1.4))
			if result.ok:
				crop.mask=int(crop.mask)&~(1<<i)
				state.full_seconds.erase(id)
				break

