extends RefCounted
## The public landscape and the observer's own portable assets, read at decision time.

const TREE_KINDS := preload("res://scripts/ink_life_form.gd").FOOD

static func observe(service, id: String, at: Vector2, sight: float) -> Dictionary:
	var facts := {"trees": [], "villagers": [], "pastures": [], "sites": {}}
	if not at.is_finite() or not is_finite(sight) or sight < 0:
		return facts
	for entity in service.world.entities:
		if not is_instance_valid(entity) or at.distance_to(entity.position) > sight:
			continue
		if TREE_KINDS.has(entity.kind):
			var tree := {"id": entity.entity_id, "kind": entity.kind, "at": _pair(entity.position),
				"alive": entity.alive, "health": entity.health, "max_health": entity.max_health}
			if service.orchards.native.has(entity.entity_id):
				var orchard:Dictionary=service.orchard_facts(entity.entity_id)
				tree.ripe_fruit=orchard.ripe
				tree.next_in_s=orchard.next_in_s
				tree.growing_slot=orchard.growing_slot
			facts.trees.append(tree)
		elif entity.kind == "villager" and entity.alive:
			var state: Dictionary = service.actors.get(entity.entity_id, {})
			if state.is_empty(): continue
			facts.villagers.append({"id": entity.entity_id, "at": _pair(entity.position),
				"needs_fruit": state.satiety <= service.FORAGE_AT,
				"would_eat_gift": state.satiety < service.ACCEPT_MEAL_BELOW,
				"holding_fruit": state.held == service.FRUIT, "meal_pending": state.meal > 0,
				"satiety":state.satiety, "health":entity.health, "max_health":entity.max_health,
				"activity":state.livelihood.activity, "fatigue":snappedf(state.livelihood.fatigue,.1),
				"eating_meat":state.livelihood.meat_meal, "evading":state.livelihood.escape_s>0,
				"threat_source":state.livelihood.get("source_id","") if state.livelihood.escape_s>0 else "",
				"work_seconds":snappedf(state.livelihood.work_s,.1),
				"interrupted_seconds":snappedf(state.livelihood.interrupted_s,.1)})
	for site in service.orchard_sites():
		if not service.orchards.native.has(site.id) and at.distance_to(Vector2(site.at[0],site.at[1]))<=sight:
			facts.trees.append({"id":site.id,"at":site.at,"kind":"orchard_tree","species":"zhuguo","alive":true,"ripe_fruit":site.ripe,"next_in_s":site.next_in_s,"growing_slot":site.growing_slot})
	if id == "priest": facts.village = _village(service)
	facts.ground_fruit=service.ground_fruit_near(at,sight)
	facts.pastures = service.pasture_near(at,sight)
	var guild_at := Vector2(service.Guild.COUNTER_X, service.world.travel_height(service.Guild.COUNTER_X) + .4)
	if at.distance_to(guild_at) <= sight:
		facts.sites.guild = {"at": _pair(guild_at), "within_reach": at.distance_to(guild_at) <= service.REACH,
			"orchard":service.orchard_facts(),"orchards":service.orchard_sites(), "service": "standing_trade", "pays": service.Guild.PRICES.duplicate(),
			"prices": {"cup_pattern": service.Guild.PATTERN_COST, "shortsword": service.Guild.BLADE_COST, "coat": service.Guild.COAT_COST}}
	var mine_at := Vector2(service.Guild.VEIN_X, service.world.travel_height(service.Guild.VEIN_X) + .4)
	if at.distance_to(mine_at) <= sight:
		facts.sites.mine = {"at": _pair(mine_at), "within_reach": at.distance_to(mine_at) <= service.REACH, "ore_left": service.ore_left}
	var pool_at: Vector2 = service.pool_position()
	if at.distance_to(pool_at) <= sight:
		facts.sites.ink_pool = {"at": _pair(pool_at), "within_reach": at.distance_to(pool_at) <= service.REACH, "cup_capacity": service.CUP_CAPACITY}
	if is_instance_valid(service.fruit_stall):
		var market_at: Vector2 = service.fruit_stall.position + Vector2(0, .45)
		if at.distance_to(market_at) <= sight:
			facts.sites.fruit_market = {"at": _pair(market_at), "open": service.fruit_stall.alive,
				"within_reach": at.distance_to(market_at) <= service.MARKET_REACH, "fruit_price": service.FRUIT_PRICE}
	if service._body(id) != null:
		facts["self"] = _own_goods(service, id)
	if id == service.COMPANION and facts.has("self"):
		# FunctionalPens.submit(game, ..., "painter") checks the sandbox drawing reserve.
		# Report action affordability; personal cups and the player's wallet stay separate.
		var minimum := PaperInkReserve.cost({})
		facts["self"].functional_pen = {"ink_source": "sandbox_drawing_reserve",
			"minimum_cost": minimum, "can_pay_minimum": service.world.game.ink.can_spend(minimum)}
	return facts

static func _village(service) -> Dictionary:
	var totals := {"living":0,"dead":0,"injured":0,"hungry":0,"resting":0,"evading":0,
		"ripe_fruit":0,"stored_fruit":0,"meat_in_bags":0,"portions_collected":0,
		"meat_meals_eaten":0,"work_seconds":0.0,"interrupted_seconds":0.0,"mean_fatigue":0.0}
	for site in service.orchard_sites():totals.ripe_fruit+=site.ripe
	for person in service.people.values():
		if person.kind != "villager": continue
		var bag: Dictionary = service.actors[person.entity_id]
		var life: Dictionary = bag.livelihood
		totals.portions_collected += life.collected
		totals.meat_meals_eaten += life.eaten
		totals.work_seconds += life.work_s
		totals.interrupted_seconds += life.interrupted_s
		if not person.alive:
			totals.dead += 1
			continue
		totals.living += 1
		totals.stored_fruit += bag.fruit
		totals.meat_in_bags += life.meat
		if person.health<person.max_health: totals.injured += 1
		if bag.satiety<=service.FORAGE_AT: totals.hungry += 1
		if life.activity=="rest": totals.resting += 1
		if life.escape_s>0: totals.evading += 1
		totals.mean_fatigue += life.fatigue
	totals.mean_fatigue = snappedf(totals.mean_fatigue/maxi(1,totals.living),.1)
	for key in ["work_seconds","interrupted_seconds"]: totals[key] = snappedf(totals[key],.1)
	return totals

static func _own_goods(service, id: String) -> Dictionary:
	var bag: Dictionary = service.inventory(id)
	var reserve = service.resident_ink.get(id)
	if id == service.PLAYER:
		reserve = service.world.game.ink
	elif id in [service.COMPANION, service.ADVENTURER]:
		reserve = service.agent_rig(id).ink
	var cup_amounts := []
	for cup in bag.cups: cup_amounts.append(int(cup.ink))
	return {"id": id, "fruit": bag.fruit, "forage": bag.forage, "red_pigment": bag.red, "satiety": bag.satiety,
		"cup_amounts": cup_amounts, "held": bag.held, "coat": bag.get("coat", "absent"),
		"reserve_ink": floori(reserve.amount) if reserve != null else int(PaperInkReserve.MAXIMUM),
		"held_cup_ink": service.cup_ink(id), "economy": bag.economy}

static func _pair(at: Vector2) -> Array:
	return [snappedf(at.x, .01), snappedf(at.y, .01)]
