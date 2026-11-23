extends RefCounted
## An accepted survey belongs to the original seam even when the painter extends it.
const Ground := preload("res://scripts/priest_ground.gd")
const JOINT := .012
const WEST := -.40
const EAST := .40
const VISIT_OFFSET := .95

static func _point(pair:Array) -> Vector2:
	return Vector2(pair[0],pair[1])

# Committed sheets form a sorted chain. A wet stroke stays outside this array.
static func _next_index(world,x:float) -> int:
	var sheets:Array=world.terrain.east_ink.segments
	var low:=0
	var high:=sheets.size()
	while low<high:
		var mid:=floori((low+high)*.5)
		if float(sheets[mid].points[0][0])<x-JOINT:low=mid+1
		else:high=mid
	return low

static func _work(sheet:Dictionary) -> String:
	return str(sheet.get("work_id","east-history-%d-%s"%[int(sheet.revision),str(sheet.name).sha256_text().left(16)]))

static func basis(world,edge:Vector2) -> String:
	var index:=_next_index(world,edge.x)-1
	if index<0:return "legacy:soil"
	var old:Dictionary=world.terrain.east_ink.segments[index]
	return _work(old) if _point(old.points.back()).distance_to(edge)<=JOINT else ""

static func adjoining(world,edge:Vector2) -> Dictionary:
	var floor_row:=Ground.trace(world,edge,edge.x+1.8)
	if floor_row.is_empty():return {}
	var id:String=floor_row.work_id
	if id=="legacy:east":
		var i:=_next_index(world,edge.x)
		var sheets:Array=world.terrain.east_ink.segments
		if i>=sheets.size() or _point(sheets[i].points[0]).distance_to(edge)>JOINT:return {}
		return {"id":_work(sheets[i]),"name":str(sheets[i].name)}
	if world.paper_space!=null and world.paper_space.entries.has(id):
		var work:Dictionary=world.paper_space.entries[id].record
		return {"id":id,"name":str(work.get("name","纸面新路")).left(64)}
	return {}

static func stand(world,c:Dictionary) -> Vector2:
	var seam:=_point(c.at)
	var x:=seam.x+(VISIT_OFFSET if c.has("trail") else -VISIT_OFFSET)
	var ground:=Ground.trace(world,seam,x)
	return Vector2(x,ground.y) if not ground.is_empty() else seam

static func crossed(service,c:Dictionary) -> bool:
	var at:Vector2=service._position(c.owner)
	if not at.is_finite():return false
	var seam:=_point(c.at)
	var dx:=at.x-seam.x
	if absf(dx)>2.1:
		c.erase("trail")
		return false
	var rig=service.world.game if c.owner==service.PLAYER else service.agent_rig(c.owner)
	var foot:Dictionary={} if rig==null or not rig.on_ground else service.world.paper_ground_contact(rig.player)
	if foot.is_empty():
		c.erase("trail")
		return false
	var mark:=Vector2(foot.x,foot.y)
	var surface:=Ground.trace(service.world,seam,mark.x)
	if surface.is_empty() or absf(float(surface.y)-mark.y)>.055 or surface.work_id!=foot.work_id:
		c.erase("trail")
		return false
	dx=mark.x-seam.x
	if c.has("trail") and mark.distance_to(_point(c.trail))>.34:c.erase("trail")
	if not c.has("trail") and dx>WEST:return false
	c.trail=[mark.x,mark.y]
	if dx<EAST:return false
	var joined:=adjoining(service.world,seam)
	if joined.get("id","")!=c.source or basis(service.world,seam)!=c.basis:return false
	var face_id:String=foot.work_id
	return face_id==c.source or (face_id=="legacy:east" and c.source==joined.id and not service.world.paper_space.entries.has(c.source))
