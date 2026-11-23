extends RefCounted
## A cut portion belongs to the carrier until the specified living grazer accepts it.
const Ground := preload("res://scripts/priest_ground.gd")
const Obstacles := preload("res://scripts/priest_obstacles.gd")
const PATCH_NAMES := {"west_meadow":"村西草丛","orchard_bank":"果园坡草丛","mill_meadow":"河岸草丛","east_meadow":"东野草丛"}
const LIMIT := 999

static func patch_name(id:String) -> String:
	return PATCH_NAMES.get(id,"移栽草簇")

static func feet(service,id:String) -> Vector2:
	var rig=service.world.game if id==service.PLAYER else service.agent_rig(id) if id==service.ADVENTURER else null
	if rig==null or not rig.on_ground:return Vector2.INF
	var body:Vector2=rig.player.position
	var floor_row:=Ground.nearby(service.world,body.x,body.y-.44,.45)
	if floor_row.is_empty():return Vector2.INF
	return Vector2(body.x,floor_row.y)

static func options(service,id:String) -> Array:
	var at:=feet(service,id)
	if not at.is_finite():return []
	var bag:Dictionary=service.inventory(id)
	var rows:=[]
	if bag.forage<LIMIT:
		for patch in service.pasture_near(at,service.Pasture.REACH):
			if patch.portions<=0 or not service.Pasture.can_graze(service,patch.id,at):continue
			if not Obstacles.contact(service.world,at+Vector2(0,.31),Vector2(patch.x,patch.y+.25)):continue
			rows.append({"id":"forage.cut."+patch.id,"target":patch.id,"label":"割一份牧草 · "+patch_name(patch.id),"item":"牧草","quantity":1})
	var priest=service.world.get_node_or_null("SandboxPriest")
	if bag.forage>0 and priest!=null and priest.has_method("hungry_livestock_near"):
		for beast in priest.hungry_livestock_near(at,1.35):
			var key:String=beast.work_id
			if not priest.can_contact_person(key,at):continue
			var ground:=Ground.trace(service.world,Vector2(beast.x,beast.y),at.x)
			if ground.is_empty() or absf(at.y-float(ground.y))>.65:continue
			rows.append({"id":"forage.feed."+key,"target":key,"label":"喂"+str(beast.name)+" · "+key.right(6)+" · 饱食 %d"%roundi(beast.satiety),"item":"牧草","quantity":1})
	return rows

static func execute(service,id:String,choice:String) -> Dictionary:
	var match_offer:Dictionary={}
	for row in options(service,id):
		if row.id==choice:match_offer=row;break
	if match_offer.is_empty():return {"error":"草量、接近位置或这只牲畜的状态已改变"}
	var at:=feet(service,id)
	var bag:Dictionary=service.inventory(id)
	var target:String=match_offer.target
	if choice.begins_with("forage.cut."):
		if not service.graze_pasture(target,at):return {"error":"这里已经割不到草"}
		bag.forage+=1
		service.actors[id]=bag
		return {"ok":true,"message":"从%s割一份牧草，随身 %d 份"%[patch_name(target),bag.forage],"target":target}
	var priest=service.world.get_node_or_null("SandboxPriest")
	if priest==null or not priest.has_method("feed_livestock"):return {"error":"牲畜已经离开"}
	bag.forage-=1
	service.actors[id]=bag
	var fed:Dictionary=priest.feed_livestock(target,at,id)
	if not fed.get("ok",false):
		bag.forage+=1
		service.actors[id]=bag
		return {"error":fed.get("error","这只牲畜未接到草")}
	return {"ok":true,"target":target,"before":fed.before,"after":fed.after,
		"message":"已喂%s · 饱食 %d→%d，牧草余 %d 份"%[target.right(6),roundi(fed.before),roundi(fed.after),bag.forage]}
