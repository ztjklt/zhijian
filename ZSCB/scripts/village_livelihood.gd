extends RefCounted
## Resident side of the food chain. Animal portions belong to the priest's work.
const Ground := preload("res://scripts/priest_ground.gd")
const MEAT_GAIN := 35
const SIGHT := 6.0
const TAKE_REACH := .95
const BITE_REACH := .95
const BITE_DAMAGE := 6.0
const ESCAPE_TIME := 4.0
const BITE_WAIT := 2.0
const WORK := ["patrol", "gather"]

static func new_record() -> Dictionary:
	return {"meat":0, "collected":0, "eaten":0, "meat_meal":false, "fatigue":0.0,
		"work_s":0.0, "interrupted_s":0.0, "resting":false, "activity":"idle",
		"source_id":"", "escape_costs_work":false, "escape_s":0.0, "danger_x":0.0, "bite_wait":0.0}

static func valid(life: Variant, meal: float) -> bool:
	if not life is Dictionary: return false
	for key in ["meat","collected","eaten"]:
		if not _number(life.get(key),0,1e12) or floorf(life[key]) != life[key]: return false
	if life.meat > 999 or life.collected != life.meat + life.eaten: return false
	if not life.get("source_id","") is String or life.get("source_id","").length()>128: return false
	if not life.get("escape_costs_work",false) is bool: return false
	if not life.get("resting") is bool or not life.get("meat_meal") is bool: return false
	if life.meat_meal and (life.meat < 1 or meal <= 0): return false
	return life.get("activity") in ["patrol","gather","meal","escape","rest","hurt","idle","escort"] and _number(life.get("fatigue"),0,100) and _number(life.get("work_s"),0,1e12) and _number(life.get("interrupted_s"),0,1e12) and _number(life.get("escape_s"),0,ESCAPE_TIME) and _number(life.get("bite_wait"),0,BITE_WAIT) and _number(life.get("danger_x"),-1e7,1e7)

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func _meal(service, id: String, bag: Dictionary) -> void:
	service.Guild.stow(service,id,bag)
	bag.held = service.EMPTY
	bag.meal = 1.5
	bag.livelihood.meat_meal = true
	service._say(id,"拿到一份肉，先吃一口。")

static func eat(service, id: String, bag: Dictionary) -> Dictionary:
	var life: Dictionary = bag.get("livelihood",{})
	if life.get("meat",0)<1 or bag.satiety>=100: return {"error":"没有可吃的肉或已经饱了"}
	life.meat -= 1
	life.eaten += 1
	life.meat_meal = false
	bag.meal = 0.0
	bag.satiety = mini(100, int(bag.satiety)+MEAT_GAIN)
	service.actors[id] = bag
	service._say(id,"吃完这份肉了。")
	return {"ok":true,"satiety":bag.satiety,"meat":life.meat}

static func _open_contact(world, a: Vector2, b: Vector2) -> bool:
	var lift := Vector2(0,.3)
	var ray := PhysicsRayQueryParameters2D.create(a+lift,b+lift,9)
	return world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

static func seek_food(service, resident, bag: Dictionary, priest) -> void:
	var id: String = resident.entity_id
	var life: Dictionary = bag.livelihood
	if life.meat>0:
		_meal(service,id,bag)
		return
	if priest == null or not priest.has_method("livestock_near"): return
	var at: Vector2 = resident.position
	var support := Ground.nearby(service.world,at.x,at.y,.65)
	if support.is_empty(): return
	var foot := Vector2(at.x,support.y)
	var closest := INF
	var target := {}
	for entry in priest.livestock_near(at,SIGHT):
		if entry.alive and bag.satiety>service.FORAGE_AT:continue
		var pos := Vector2(entry.x,entry.y)
		var d := at.distance_to(pos)
		if entry.portions<=0 or d>SIGHT:continue
		if not target.is_empty():
			if entry.alive and not target.alive:continue
			if entry.alive==target.alive and d>=closest:continue
		if d<=TAKE_REACH and not _open_contact(service.world,at,pos): continue
		var floor_row: Dictionary = Ground.trace(service.world,foot,pos.x)
		if floor_row.is_empty() or absf(float(floor_row.y)-pos.y)>.6: continue
		closest = d
		target = entry
	if target.is_empty(): return
	if closest <= TAKE_REACH and priest.take_livestock_portion(target.work_id,at,id):
		life.meat += 1
		life.collected += 1
		service.food_destinations.erase(id)
		_meal(service,id,bag)
	else:
		service.food_destinations[id] = float(target.x)

static func threaten(service, at: Vector2, reach: float, source_id: String) -> Dictionary:
	if not at.is_finite() or not is_finite(reach) or reach<=0 or source_id.length()>128: return {}
	var closest := INF
	var target
	var priest = service.world.get_node_or_null("SandboxPriest") if not source_id.is_empty() else null
	var check_creature: bool = priest != null and priest.has_method("can_contact_person") and priest.work_by_id(source_id) != null
	for id in service.people:
		var person = service.people[id]
		if person.kind!="villager" or not person.alive: continue
		var distance := at.distance_to(person.position)
		if distance>reach or distance>=closest: continue
		if not _open_contact(service.world,at,person.position): continue
		if check_creature and not priest.can_contact_person(source_id,person.position): continue
		closest = distance
		target = person
	if target == null: return {}
	var id: String = target.entity_id
	var life: Dictionary = service.actors[id].livelihood
	var before: float = target.health
	var interrupted: bool = life.escape_s<=0 and life.activity in WORK
	if life.escape_s<=0:
		life.escape_costs_work = interrupted
		service._say(id,"野兽来了，先躲开！")
	life.source_id = source_id
	life.danger_x = at.x
	life.escape_s = ESCAPE_TIME
	life.activity = "escape"
	service.food_destinations.erase(id)
	if closest <= BITE_REACH and life.bite_wait <= 0 and target.hurt_timer <= 0:
		var direction := 1.0 if target.position.x>=at.x else -1.0
		service.world.damage_entity(target,BITE_DAMAGE,target.position+Vector2(0,.35),Vector2(direction*1.1,.18))
		life.bite_wait = BITE_WAIT
	return {"ok":true,"id":id,"source_id":source_id,"at":[target.position.x,target.position.y],"health_before":before,
		"health_after":target.health,"damage":before-target.health,"alive":target.alive,
		"message":"%s 生命 %d→%d，%s" % [id,int(before),int(target.health),"倒下" if not target.alive else "停工避险" if interrupted else "避险"],
		"evading":target.alive,"work_interrupted":interrupted,"interrupted_s":life.interrupted_s}

static func after_patrol(service, resident, delta: float) -> void:
	if not resident.alive: return
	var id: String = resident.entity_id
	var bag: Dictionary = service.actors[id]
	var life: Dictionary = bag.livelihood
	var x: float = resident.position.x
	var travelled := absf(x-float(service.last_resident_x.get(id,x)))
	service.last_resident_x[id] = x
	life.bite_wait = maxf(0,life.bite_wait-delta)
	if life.escape_s > 0:
		life.activity = "escape"
		if life.get("escape_costs_work",false): life.interrupted_s += minf(delta,life.escape_s)
		life.escape_s = maxf(0,life.escape_s-delta)
		if resident.hurt_timer<=0:
			resident.facing = 1 if x>=life.danger_x else -1
			resident.linear_velocity.x = resident.facing*1.6
		return
	if resident.hurt_timer>0:
		life.activity = "hurt"
		return
	if bag.meal>0:
		life.activity = "meal"
		resident.state = "idle"
		resident.linear_velocity.x = 0
		return
	if life.fatigue>=65: life.resting = true
	if life.resting:
		life.activity = "rest"
		resident.state = "idle"
		resident.linear_velocity.x = 0
		life.fatigue = maxf(0,life.fatigue-2.0*delta)
		if life.fatigue<=35: life.resting = false
		return
	if service.contracts.escort_motion(resident,delta):
		life.activity="escort"
		return
	var gathering: bool = service.food_destinations.has(id)
	if gathering:
		var dx := float(service.food_destinations[id])-x
		resident.facing = 1 if dx>=0 else -1
		resident.linear_velocity.x = resident.facing*.70 if absf(dx)>.10 else 0.0
	# Wounds and a low food reserve reduce actual walking and collection speed.
	var strength := clampf(float(resident.health)/resident.max_health,.4,1.0)
	if bag.satiety<=service.FORAGE_AT: strength *= .65
	resident.linear_velocity.x *= strength
	life.activity = "gather" if gathering else "patrol"
	if travelled <= .035*delta or travelled > .18: return
	life.work_s += delta
	life.fatigue = minf(100,life.fatigue+delta*(1.2 if bag.satiety<35 else .45))
