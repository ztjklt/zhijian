extends RefCounted
## New sandbox composition. Stable IDs still identify each piece on save/load.
## Doorways, wells and the bridge approach share the actor's ground lane.
const NEW_X := {
	"house-0":21.05,"house-1":27.81,"house-2":34.5,
	"market-0":41.1,"market-1":45.6,"market-2":50.1,
	"well-100":37.9,"signpost-102":53.15,"crate-0":18.30,
	"cart_goods-100":14.95,"barrel-0":7.55,
	"crate-1":97.1,"barrel-1":101.5,"crate-2":144.3,
	"barrel-2":146.3,"crate-3":93.2,"barrel-3":95.0,
	"forge-100":104.35,"windmill-100":116.94,"tavern-100":121.6,"watermill-100":127.04,
	"ruin_arch-100":148.0,"ruin_arch-101":144.8,"ruin_arch-102":162.25,"ruin_arch-103":159.0,"orchard_tree-103":99.95,
	"crate-106":92.2,
	"well-101":142.35,"tent-101":174.4,"tent-102":178.1}
# Repeated small dressings previously occupied the very same station. Keep
# the district's services, three houses, three stalls and reachable cargo.
const OMIT := ["bench-100","bench-101","bench-102","lantern-100","lantern-101","lantern-102","lantern-103",
	"crate-101","crate-102","crate-103","barrel-101","barrel-102","barrel-103",
	"cart_goods-101","signpost-101","fence-101","fence-102","haystack-100",
	"bench-104","haystack-103","haystack-105","cart_goods-102","fence-107","fence-108","barrel-107",
	"cart_goods-104","bench-107","haystack-107","fence-105","lantern-106","haystack-104",
	"barrel-106","crate-107","fence-106","crate-110","bench-105","bench-106","lantern-109",
	"cart_goods-103","haystack-106","signpost-106","barrel-109","fence-109","signpost-107"]
const STATIONS := {"village-pool":Vector2(24.6,.84),"village-guild":Vector2(31.0,1.04),"village-vein":Vector2(17.0,.67),
	"west-bridge-entry":Vector2(54.15,0),"west-bridge-exit":Vector2(67.8,0),
	"mill-bridge-entry":Vector2(128.0,0),"mill-bridge-exit":Vector2(140.0,0)}
const DOORS := ["house","market","well","forge","tavern","windmill","watermill","tent","crate","barrel","cart_goods"]

static func inspect_site(world, x: float, width: float, clearance := .8, base_y := INF) -> Dictionary:
	var conflicts := []
	if not is_finite(x) or not is_finite(width) or width <= 0 or not is_finite(clearance) or clearance < 0 or (base_y != INF and not is_finite(base_y)):
		return {"ok":false,"conflicts":[]}
	var road: float = world.travel_height(x)
	var level: float = road if base_y == INF else base_y
	var interval := Vector2(x-width*.5-clearance,x+width*.5+clearance)
	for entity in world.entities:
		if not entity.alive or entity.is_actor() or entity.is_foliage() or entity.kind=="wagon": continue
		var cx: float = entity.position.x
		var half: float = entity.size.x*.5
		# A canopy is overhead. Only the trunk occupies the walking lane.
		if entity.kind in ["oak","pine","orchard_tree"]: half = minf(half,.32)
		var tree_station: bool = entity.entity_id == "orchard_tree-100"
		var reach := 1.35 if tree_station else .65
		if cx+half+reach<interval.x or cx-half-reach>interval.y: continue
		if entity.kind == "castle_piece" and entity.position.y-world.travel_height(entity.position.x)>1.5: continue
		var sample := clampf(x,cx-half,cx+half)
		var surface: float = world.surface_height(sample) if entity.kind=="bridge_stone" else world.travel_height(sample)
		var offset: float = entity.position.y-(world.surface_height(cx) if entity.kind=="bridge_stone" else world.travel_height(cx))
		var contact := surface+offset
		if absf((level-road)-(contact-world.travel_height(sample)))>1.0: continue
		_append(conflicts,interval,entity.entity_id,entity.kind,"footprint",cx,half,contact)
		if tree_station: _append(conflicts,interval,entity.entity_id,entity.kind,"access",cx,1.35,contact)
		if entity.kind in DOORS:
			var station := cx if entity.kind not in ["crate","barrel","cart_goods"] else cx+half+.28
			_append(conflicts,interval,entity.entity_id,entity.kind,"access",station,.40,contact)
	if absf(level-road)<=.6:
		for deck in world.terrain.ROAD_DECKS:
			var a: Vector2=deck[0];var b: Vector2=deck[1]
			if b.x<=interval.x or a.x>=interval.y:continue
			_append(conflicts,interval,"road-deck-"+str(int(a.x)),"crossing","access",(a.x+b.x)*.5,(b.x-a.x)*.5,world.travel_height(clampf(x,a.x,b.x)))
	for id in STATIONS:
		var station: Vector2 = STATIONS[id]
		if absf(level-road)>1.0: continue
		var half:=maxf(.45,station.y)
		if station.x+half<=interval.x or station.x-half>=interval.y:continue
		var floor_y: float = world.travel_height(station.x)
		if station.y>0: _append(conflicts,interval,id,"station","footprint",station.x,station.y,floor_y)
		_append(conflicts,interval,id,"station","access",station.x,.45,floor_y)
	return {"ok":conflicts.is_empty(),"conflicts":conflicts}

static func _append(items: Array, interval: Vector2, id: String, kind: String, reason: String, x: float, half: float, y: float) -> void:
	if x+half > interval.x and x-half < interval.y:
		items.append({"id":id,"kind":kind,"reason":reason,"x":x,"left":x-half,"right":x+half,"y":y})
