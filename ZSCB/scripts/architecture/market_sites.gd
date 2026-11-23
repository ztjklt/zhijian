extends RefCounted
## Resolve one real counter from an actor's world-space body centre.
const Goods=preload("res://scripts/architecture/stall_goods.gd")
const REACH := 1.25

static func _at_counter(world, body: Vector2, feet: Vector2) -> bool:
	if absf(body.x-feet.x)>REACH or absf(body.y-(feet.y+.4))>.42: return false
	for dx: float in [-.27,0.0,.27]:
		var x:=feet.x+dx
		if world.paper_space.solid_at(Vector2(x,feet.y+.34)) or world.terrain.in_water(Vector2(x,feet.y+.12)): return false
		for hit in world.paper_surfaces(x,feet.y+.13,feet.y+.79):
			if hit.face=="ceiling": return false
	return true

static func _built_spots(game,obj:Dictionary) -> Array:
	var spots:=[]
	if not obj.has("built_plan") or obj.get("hp",1)<=0:return spots
	var meta:Dictionary=obj.built_plan
	var origin:Vector2=game.object_point(obj,Vector2(meta.offset[0],meta.offset[1]))
	for i in meta.layout.get("stations",[]).size():
		var station:Dictionary=meta.layout.stations[i]
		if not Goods.is_counter(station):continue
		for p in meta.layout.access:
			if absf(p[0]-station.x)<=.001:spots.append({"at":origin+Vector2(p[0],p[1]),"slot":i,"terms":station})
	return spots

# Expose only this world's actual, usable counters. Overlapping claims follow normal E priority.
static func known_stalls(game,observer:Vector2) -> Array:
	var world=game.medieval_world
	var result:=[]
	var candidates:=[]
	var old=world.entity_by_id("market-2")
	if is_instance_valid(old) and old.alive:candidates.append({"id":"market-2","feet":old.position})
	if world.paper_space!=null:
		for entry in world.paper_space.entries.values():
			var record:Dictionary=entry.record
			if record.get("service",{}).get("kind")=="fruit_market":
				var p:Array=record.service.at
				candidates.append({"id":record.work_id,"feet":Vector2(p[0],p[1])})
		for obj in game.objects:
			for p:Dictionary in _built_spots(game,obj):
				candidates.append({"id":obj.structure_id,"feet":p.at,"slot":p.slot if p.terms.service=="market_counter" else -1})
	var seen:={}
	candidates.sort_custom(func(a,b):return observer.distance_squared_to(a.feet)<observer.distance_squared_to(b.feet))
	for row in candidates:
		var at:Vector2=row.feet
		var key:String=row.id
		var hit:=counter_at(game,at+Vector2(0,.4))
		if hit.get("station")!=key or hit.get("slot",-1)!=row.get("slot",-1):continue
		var site:="fruit-stall."+key
		if hit.has("slot"):site="market-counter.%s.%d"%[key,hit.slot]
		if seen.has(site):continue
		var offer:=Goods.public_quote(hit)
		seen[site]=true
		result.append({"station":key,"site":site,"name":world.survival.contracts.market_title(key),"at":[at.x,at.y],"price":offer.unit_price,"offer":offer})
	return result

static func station_id(game, body: Vector2) -> String:
	return str(counter_at(game,body).get("station",""))

static func counter_at(game, body: Vector2) -> Dictionary:
	if not body.is_finite() or game==null or game.medieval_world==null: return {}
	var world = game.medieval_world
	var stall = world.entity_by_id("market-2")
	if is_instance_valid(stall) and stall.alive and body.distance_to(stall.position+Vector2(0,.45))<=REACH: return {"station":"market-2","offer":Goods.LEGACY}
	if world.paper_space==null: return {}
	var box:=Rect2(body-Vector2(REACH,1.1),Vector2(REACH*2,2.2))
	for entry in world.paper_space.nearby(box):
		var rec: Dictionary=entry.record
		if rec.get("service",{}).get("kind")!="fruit_market": continue
		var at:=Vector2(rec.service.at[0],rec.service.at[1])
		if _at_counter(world,body,at): return {"station":rec.work_id,"offer":Goods.LEGACY}
	var nearest:={}
	var distance:=INF
	for obj in game.objects:
		for spot in _built_spots(game,obj):
			var at:Vector2=spot.at
			var d:=body.distance_squared_to(at+Vector2(0,.4))
			if d>=distance or not _at_counter(world,body,at) or not preload("res://scripts/architecture/building_plans.gd")._load_bearing(game,at,.16):continue
			distance=d
			if spot.terms.service=="fruit_market":
				nearest={"station":obj.structure_id,"offer":Goods.LEGACY}
			else:
				nearest={"station":obj.structure_id,"slot":spot.slot,"offer":spot.terms.offer,"object":obj}
	return nearest
