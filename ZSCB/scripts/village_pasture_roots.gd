extends RefCounted
const Pasture:=preload("res://scripts/village_pasture.gd")
const Ground:=preload("res://scripts/priest_ground.gd")
const Obstacles:=preload("res://scripts/priest_obstacles.gd")
const SPACING:=.85
const HALF_WIDTH:=.19

static func held(service,actor:String) -> Array[String]:
	var result:Array[String]=[]
	result.assign(service.actors.get(actor,{}).get("grass_roots",[]))
	return result

static func feet(service,actor:String) -> Vector2:
	if actor=="priest":
		var priest=service.world.get_node_or_null("SandboxPriest")
		if priest!=null:
			var at:=Vector2(priest.priest_x,priest.priest_y)
			var floor_row:=Ground.nearby(service.world,at.x,at.y,.065)
			if not floor_row.is_empty():return Vector2(at.x,floor_row.y)
	elif actor in [service.PLAYER,service.ADVENTURER]:
		var rig=service.world.game if actor==service.PLAYER else service.agent_rig(actor)
		if rig!=null:
			var contact:Dictionary=service.world.paper_ground_contact(rig.player)
			if not contact.is_empty():return Vector2(contact.x,contact.y)
			# At the edge of a cut the centre ray may have no remaining soil face,
			# while the outside toe still bears weight on the untouched legacy slope.
			if rig.on_ground:
				for hit in rig.player.support_hits():
					if hit.collider not in rig.player.foot_bodies or hit.collider.get_parent()!=service.world:continue
					if hit.collider.name not in [&"MountainRiverSoil",&"EastInkSoil"]:continue
					if hit.normal.dot(rig.player.position-hit.position)>StickmanPlayer.BODY_RADIUS+.035:continue
					var soil:=Ground.nearby(service.world,hit.position.x,hit.position.y,.004)
					if soil.get("work_id") in ["legacy:soil","legacy:east"] and soil.mode=="rock":return hit.position
	return Vector2.INF

static func refuse(reason:String) -> Dictionary:
	return {"ok":false,"error":reason}

static func site(service,at:Vector2) -> Dictionary:
	if not at.is_finite():return refuse("请站在能扎根的干地上")
	var w=service.world
	var support:=Ground.nearby(w,at.x,at.y,.07)
	if support.is_empty() or support.mode not in ["rock","carve"]:return refuse("这里没有同层的实土或岩面")
	var root:=Vector2(at.x,support.y)
	var left:=Ground.trace(w,root,at.x-HALF_WIDTH)
	var right:=Ground.trace(w,root,at.x+HALF_WIDTH)
	if left.is_empty() or right.is_empty() or left.work_id!=support.work_id or right.work_id!=support.work_id or absf(left.y-right.y)>.30:return refuse("两侧没有足够连续的缓坡扎根")
	for tip in [Vector2(root.x-HALF_WIDTH,left.y),root,Vector2(root.x+HALF_WIDTH,right.y)]:
		if w.terrain.in_water(tip+Vector2(0,.025)):return refuse("草根不能栽进水里")
	for id in service.pastures:
		var row:Dictionary=service.pastures[id]
		if row.get("capacity",Pasture.CAPACITY)==0:continue
		var x:=float(Pasture.SITES[id] if Pasture.SITES.has(id) else row.x)
		if absf(x-at.x)>=SPACING:continue
		var y:=float(w.travel_height(x) if Pasture.SITES.has(id) else row.y)
		if root.distance_to(Vector2(x,y))<SPACING:return refuse("离已有草根太近")
	var a:=Vector2(at.x-HALF_WIDTH,left.y+.025)
	var b:=Vector2(at.x+HALF_WIDTH,right.y+.025)
	var shape:=PackedVector2Array([a,b,b+Vector2(0,.35),a+Vector2(0,.35)])
	var box:=Rect2(a,Vector2.ZERO).expand(b).expand(shape[2]).expand(shape[3])
	for item in Obstacles.nearby(w,box):
		if not Geometry2D.intersect_polygons(shape,item.points).is_empty():return refuse("实物占着这块地")
	for tree in w.entities:
		if tree.alive and tree.kind in ["oak","pine","orchard_tree"] and absf(tree.position.x-root.x)<.4 and absf(tree.position.y-root.y)<.7:return refuse("树干占着这块地")
	var footprint:=ConvexPolygonShape2D.new()
	footprint.points=shape
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=footprint
	query.collision_mask=1|8
	for hit in w.get_world_2d().direct_space_state.intersect_shape(query):
		if hit.collider is BuildObject:return refuse("造物占着这块地")
	for obj in w.game.objects:
		if obj.has("built_plan") and box.intersects(w.game.object_bounds(obj)):return refuse("建筑占着这块地")
	if not w.spawn_shape_blocker(shape).is_empty():return refuse("根上方没有生长空间")
	return {"ok":true,"x":root.x,"y":root.y,"work_id":support.work_id}

static func reachable(service,start:Vector2,finish:Vector2) -> bool:
	if not start.is_finite() or not finish.is_finite() or start.distance_to(finish)>Pasture.REACH:return false
	var surface:=Ground.trace(service.world,start,finish.x)
	var target:=Ground.nearby(service.world,finish.x,finish.y,.055)
	if surface.is_empty() or target.is_empty() or surface.work_id!=target.work_id or absf(surface.y-target.y)>.012:return false
	return Obstacles.contact(service.world,start+Vector2(0,.30),finish+Vector2(0,.20))

static func dig(service,actor:String,id:String) -> Dictionary:
	var at:=feet(service,actor)
	var patch:=Pasture.info(service,id)
	if patch.is_empty() or not patch.can_divide or not reachable(service,at,Vector2(patch.x,patch.y)):return refuse("请在同层成熟草簇旁分根")
	var row:Dictionary=service.pastures[id]
	var cap:=int(patch.capacity)
	var root:=id
	if Pasture.SITES.has(id):
		root=Pasture.token(id,cap)
		var progress:=float(row.regrow_s)/Pasture.interval(cap)
		row.capacity=cap-1
		row.portions-=1
		row.regrow_s=progress*Pasture.interval(cap-1) if row.portions<row.capacity else 0.0
	else:
		service.pastures.erase(id)
	var bag:Dictionary=service.inventory(actor)
	var carried:=held(service,actor)
	carried.append(root)
	bag.grass_roots=carried
	service.actors[actor]=bag
	return {"ok":true,"root_id":root,"source_id":id,"owner":actor,"message":"带土分下一簇活草根，已收进自己的行囊"}

static func plant(service,actor:String,root:String,at:Vector2) -> Dictionary:
	var carried:=held(service,actor)
	if not carried.has(root) or service.pastures.has(root):return refuse("行囊里没有这簇活根")
	var stood:=feet(service,actor)
	if not reachable(service,stood,at):return refuse("请走近同层的栽植点，途中不能隔着实物")
	var place:=site(service,at)
	if not place.ok:return place
	var bag:Dictionary=service.inventory(actor)
	carried.erase(root)
	bag.grass_roots=carried
	service.actors[actor]=bag
	service.pastures[root]={"capacity":1,"portions":0,"regrow_s":Pasture.interval(1),
		"x":place.x,"y":place.y,"work_id":place.work_id,"owner":actor}
	return {"ok":true,"root_id":root,"pasture_id":root,"owner":actor,"at":[place.x,place.y],"message":"活根已栽下，首份牧草还需 96 游戏秒"}
