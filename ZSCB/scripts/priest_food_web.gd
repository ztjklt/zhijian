extends RefCounted
const GRASS_GAIN:=23.0
const SATIETY_LOSS:=.55
const FLEE_LOSS:=.4
const GroundFruit:=preload("res://scripts/priest_ground_fruit.gd")
const Obstacles:=preload("res://scripts/priest_obstacles.gd")
const Ground := preload("res://scripts/priest_ground.gd")

static func alive(a) -> bool:
	return a.phase not in ["drawing","dead"]

static func near(a, b, distance: float) -> bool:
	if absf(a.beast_x-b.beast_x)>distance or absf(a.beast_y-b.beast_y)>distance:return false
	var foot:=Ground.trace(a.world,Vector2(a.beast_x,a.beast_y),b.beast_x)
	return not foot.is_empty() and absf(float(foot.y)-b.beast_y)<.6 and (distance>2 or Obstacles.contact(a.world,Vector2(a.beast_x,a.beast_y+.4),Vector2(b.beast_x,b.beast_y+.4)))

static func closest(a, predators: bool):
	var chosen=null
	var best:float=a.design.sight
	for b in a.keeper.works:
		if a==b or not alive(b):continue
		if predators and not b.has_action("hunt_livestock"):continue
		if not predators and not b.design.get("edible",false):continue
		var dist:float=Vector2(a.beast_x,a.beast_y).distance_to(Vector2(b.beast_x,b.beast_y))
		if dist<best and near(a,b,best):
			best=dist
			chosen=b
	return chosen

# Use the physical person's foot and the animal's walk layer. A camera has no body.
static func nearby_person(a) -> String:
	var from:=Vector2(a.beast_x,a.beast_y)
	var nearest:float=minf(2.35,a.design.sight)
	var found:=""
	for body in [a.game.player]+a.world.survival.people.values():
		if not is_instance_valid(body):continue
		var player:bool=body==a.game.player
		if not player and (body.kind!="villager" or not body.alive):continue
		var x:float=body.position.x
		if absf(from.x-x)>=nearest:continue
		var floor_row:=Ground.trace(a.world,from,x)
		if floor_row.is_empty() or absf(float(floor_row.y)-float(body.position.y)+(.44 if player else 0.0))>.38:continue
		var foot:=Vector2(x,floor_row.y)
		var distance:=from.distance_to(foot)
		if distance>=nearest or not Obstacles.contact(a.world,from+Vector2(0,.25),foot+Vector2(0,.25)):continue
		found="player" if player else str(body.entity_id)
		nearest=distance
	return found

static func viable(site:Dictionary,design:Dictionary) -> bool:
	return habitat_problem(site,design).is_empty()

static func habitat_problem(site:Dictionary,design:Dictionary) -> String:
	var actions:Array=design.actions
	if design.edible and site.livestock>=3:return "附近已有三只可食牲畜"
	if "hunt_livestock" in actions and site.predators>=1:return "附近已有捕食兽"
	var missing:=PackedStringArray()
	if "hunt_livestock" in actions:
		if site.livestock>0:return ""
		missing.append("可捕食的牲畜")
	if "graze_grass" in actions:
		if site.grass_units>0:return ""
		missing.append("可取食的牧草")
	if "eat_ground_fruit" in actions:
		if site.get("fruit_units",0)>0:return ""
		missing.append("落在同层地面的果实")
	if "graze_bark" in actions:
		if site.healthy_food_trees>0:return ""
		missing.append("健康的食物树")
	return "这块地缺少"+"或".join(missing) if not missing.is_empty() else ""

# Test the same body on the same walking surface as its next actual steps.
static func pasture_barrier(a, patch:Dictionary) -> String:
	var foot:=Vector2(a.beast_x,a.beast_y)
	var destination:=Vector2(patch.x,patch.y)
	if can_reach_portion(a,foot,destination):return ""
	if not a.has_action("ground_walk"):return "ground"
	var facing:=1 if destination.x>foot.x else -1
	var steps:=ceili(absf(destination.x-foot.x)/.18)
	for n in steps:
		var x:=move_toward(foot.x,destination.x,.18)
		var floor_row:=Ground.trace(a.world,foot,x)
		if floor_row.is_empty():return "ground"
		var next:=Vector2(x,floor_row.y)
		var slope:=atan2(next.y-foot.y,absf(next.x-foot.x))*facing
		var block:=Obstacles.movement_blocker(a,foot,next,slope,facing)
		if block!="":return block
		foot=next
		if can_reach_portion(a,foot,destination):return ""
	return "ground"

static func can_reach_portion(a,foot:Vector2,patch:Vector2) -> bool:
	if foot.distance_to(patch)>1.15:return false
	var floor_row:=Ground.trace(a.world,patch,foot.x)
	return not floor_row.is_empty() and absf(float(floor_row.y)-foot.y)<=.35 and Obstacles.contact(a.world,foot+Vector2(0,.25),patch+Vector2(0,.15))

static func step(a,delta:float) -> void:
	if a.phase=="dead":return
	a.contact_timer=maxf(0.0,a.contact_timer-delta)
	if a.phase=="hunt":
		a.bite_phase=clampf(1.0-a.contact_timer/1.65,0.0,1.0)
	elif a.phase=="eat" and not a.grass_target.is_empty() and a.last_target==a.grass_target.id:
		a.bite_phase=clampf(1.0-a.contact_timer/1.4,0.0,1.0)
	a.sense_left-=delta
	if a.sense_left<=0:
		a.sense_left=.42
		if a.has_action("graze_grass"):
			var previous_plot: String = a.grass_target.get("id","")
			a.grass_target={}
			var first_barrier:=""
			if a.world.survival and a.world.survival.has_method("pasture_near"):
				var sight:float=a.design.sight if a.has_action("ground_walk") else 1.15
				var origin:=Vector2(a.beast_x,a.beast_y)
				var nearest:=sight
				var visible:Array=a.world.survival.pasture_near(origin,sight)
				for patch in visible:
					var distance:=origin.distance_to(Vector2(patch.x,patch.y))
					if patch.portions>0 and distance<=nearest:
						var ground:=Ground.trace(a.world,origin,patch.x)
						if not ground.is_empty() and absf(ground.y-patch.y)<.7:
							var barrier:="" if patch.id==previous_plot and a.blocked_by=="" else pasture_barrier(a,patch)
							if barrier!="":
								if first_barrier=="":first_barrier=barrier
								continue
							a.grass_target=patch
							nearest=distance
				a.blocked_by=first_barrier if a.grass_target.is_empty() else ""
				if a.grass_target.is_empty():a.grazing.choose(a,visible,sight)
				else:a.grazing.aim={}
				if a.blocked_by!="":a.sense_left=2
		if a.has_action("eat_ground_fruit") and a.phase!="pickup":GroundFruit.sense(a)
		if a.has_action("avoid_people"):a.avoided_person=nearby_person(a)
		a.other_id=""
		if a.has_action("flee") or a.has_action("hunt_livestock"):
			var other=closest(a,true) if a.has_action("flee") and a.stamina>.02 else null
			if not other and a.has_action("hunt_livestock"):other=closest(a,false)
			if other: a.other_id=other.work_id
	var other=a.keeper.work_by_id(a.other_id)
	if other and alive(other) and a.has_action("flee") and other.has_action("hunt_livestock") and a.stamina>0.02:
		a.avoided_person=""
		a.phase="flee"
		a.spend_satiety(delta,FLEE_LOSS)
		a.stamina=maxf(0.0,a.stamina-delta*.23)
		var away:=1 if a.beast_x>=other.beast_x else -1
		a._walk(delta*1.24,a.beast_x+away*1.8)
		return
	if a.has_action("avoid_people") and a.avoided_person!="" and a.stamina>.02:
		var person=a.game.player if a.avoided_person=="player" else a.world.entity_by_id(a.avoided_person)
		if is_instance_valid(person) and (a.avoided_person=="player" or person.alive):
			a.phase="flee"
			a.fruit_bite_id=""
			a.stamina=maxf(0.0,a.stamina-delta*.23)
			a.spend_satiety(delta,FLEE_LOSS)
			var away:=1 if a.beast_x>=person.position.x else -1
			a._walk(delta*1.24,a.beast_x+away*1.8)
			return
	a.spend_satiety(delta,SATIETY_LOSS)
	a.stamina=minf(1,a.stamina+delta*.025)
	if other and alive(other) and a.has_action("hunt_livestock") and a.satiety<80:
		if absf(a.beast_x-other.beast_x)>1.05:
			a.phase="chase"
			a._walk(delta,other.beast_x)
		elif a.contact_timer<=0 and near(a,other,1.35):
			a.phase="hunt"
			a.face=1 if other.beast_x>=a.beast_x else -1
			a.contact_timer=1.65
			a.bite_phase=0.0
			var old:float=other.health
			other.health=maxf(0,other.health-14)
			a.last_target=other.work_id
			a.hits+=1
			other.stamina=maxf(0,other.stamina-.35)
			if other.health<=0:
				other.phase="dead"
				other.portions=maxi(0,other.portions-1)
				a.satiety=minf(100,a.satiety+60)
				a.phase="rest"
				a.kills+=1
			a.keeper.ecology_log.record(a.keeper,a,"hunt",other.work_id,old,other.health,"%s 捕食 %s，生命 %d → %d。" % [a.design.name,other.design.name,old,other.health])
			if a.world.survival and a.world.survival.has_method("guild_pasture_attack"):
				a.world.survival.guild_pasture_attack(a.work_id,other.work_id,Vector2(other.beast_x,other.beast_y))
			a.keeper.record_outcome("捕食",a.design.name,"%s 生命 %d→%d" % [other.design.name,int(old),int(other.health)],a.work_id)
		return
	var guarding:=false
	if a.has_action("guard_food") and a.phase in ["eat","rest"]:
		var at:=Vector2(a.beast_x,a.beast_y)
		if not a.grass_target.is_empty() and a.grass_target.id==a.last_target:
			guarding=at.distance_to(Vector2(a.grass_target.x,a.grass_target.y))<=1.15
		var carcass=a.keeper.work_by_id(a.last_target)
		if carcass and carcass.phase=="dead" and carcass.portions>0:guarding=near(a,carcass,1.35)
	if (guarding or a.has_action("threaten_people")) and a.contact_timer<=0 and a.world.survival and a.world.survival.has_method("threaten_person"):
		var war=a.world.get_node_or_null("SandboxWarGod")
		var at:=Vector2(a.beast_x,a.beast_y)
		if a.hostile_left>0 and war and war.has_method("incoming_center") and at.distance_to(war.incoming_center())<=1.15 and Obstacles.contact(a.world,at+Vector2(0,.4),war.incoming_center()):
			var struck:Dictionary=war.receive_enemy_hit(a.work_id,6.0,at)
			if struck.get("ok",false):
				a.contact_timer=3.3
				a.hits+=1
				a.keeper.record_outcome("近身反击",a.design.name,"战神生命 %s→%s" % [struck.before,struck.after],a.work_id)
				return
		var hit:Dictionary=a.world.survival.threaten_person(Vector2(a.beast_x,a.beast_y),1.35,a.work_id)
		if hit.get("ok",false):
			a.hits+=1
			a.hostile_reason="护食驱赶" if guarding else "近身威胁居民"
			a.hostile_left=12
			a.contact_timer=3.3
			if hit.get("damage",0)>0:
				a.keeper.ecology_log.record(a.keeper,a,"injury",hit.id,hit.health_before,hit.health_after,hit.message)
			a.keeper.record_outcome("惊扰居民",a.design.name,str(hit.get("message",hit)).left(180),a.work_id)
			return
	if a.phase=="pickup" and GroundFruit.bite(a,delta):return
	if a.phase=="rest" and a.satiety>50:return
	if a.has_action("eat_ground_fruit") and GroundFruit.approach(a,delta):return
	if a.has_action("graze_grass") and a.satiety<80 and not a.grass_target.is_empty():
		var patch:Dictionary=a.grass_target
		var at:=Vector2(a.beast_x,a.beast_y)
		var within_reach:=can_reach_portion(a,at,Vector2(patch.x,patch.y))
		if not within_reach and a.has_action("ground_walk"):
			a.phase="walk"
			a._walk(delta,patch.x)
		elif within_reach and a.contact_timer<=0 and a.world.survival.graze_pasture(patch.id,at):
			a.phase="eat"
			a.contact_timer=1.4
			a.bite_phase=0.0
			a.grass_meals+=1
			a.grazing.remember(patch.id,at)
			a.last_target=patch.id
			a.satiety=minf(100,a.satiety+GRASS_GAIN)
			var left := int(a.world.survival.pastures[patch.id].portions)
			a.keeper.ecology_log.record(a.keeper,a,"grass",patch.id,left+1,left,"%s 采食一份牧草，余 %d 份。" % [a.design.name,left])
			if a.grass_meals==1:a.keeper.record_outcome("首次食草",a.design.name,patch.id+" 实际减少一份牧草",a.work_id)
			if a.satiety>=80:a.phase="rest"
		return
	if a.has_action("graze_bark") and a.has_action("ground_walk"):
		a._forage(delta)
		return
	if a.has_action("graze_grass") and a.grazing.approach(a,delta):return
	if a.blocked_by!="" and a.has_action("graze_grass") and not a.has_action("threaten_people"):
		a.phase="search"
		return
	if not a.has_action("ground_walk"):a.phase="rest";return
	a.phase="search"
	var destination:float=a.beast_x+a.face*1.5
	if a.has_action("threaten_people"):
		var nearest:float=a.design.sight
		for entity in a.world.entities:
			if entity.kind!="villager" or not entity.alive:continue
			var distance:float=entity.position.distance_to(Vector2(a.beast_x,a.beast_y))
			if distance>=nearest:continue
			var ground:=Ground.trace(a.world,Vector2(a.beast_x,a.beast_y),entity.position.x)
			if not ground.is_empty() and absf(float(ground.y)-entity.position.y)<.65:
				nearest=distance
				destination=entity.position.x
	a._walk(delta*.85,destination)
