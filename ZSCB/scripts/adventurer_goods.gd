extends RefCounted
## The ordinary adventurer sees offers from the same village inventory used by people.
const Guild := preload("res://scripts/village_guild.gd")
const ID := "adventurer-lizhou"

static func _entry(id: String, label: String, item: String, verb: String, args := {}) -> Dictionary:
	return {"offer":{"id":id, "label":label, "item":item}, "verb":verb, "args":args}

static func _view(game, actor) -> Dictionary:
	var result := {"inventory":{}, "destinations":[], "entries":[]}
	var world = game.medieval_world
	if actor == null or world == null or world.get_node_or_null("SandboxAdventurer") == null: return result
	if world.get_node("SandboxAdventurer").actor != actor or world.survival == null: return result
	var service = world.survival
	var state: Dictionary = service.observe(ID)
	if not state.has("inventory"): return result
	var bag: Dictionary = state.inventory
	var held := "空手" if bag.held == service.EMPTY else "朱果" if bag.held == service.FRUIT else "纸灯" if bag.held==service.Goods.LAMP_SLOT else "墨杯"
	result.inventory = {"paper_lantern":bag.get("paper_lantern",0),"reed_leaf":bag.get("reed_leaf",0),"forage":bag.forage,"fruit":bag.fruit, "red":bag.red, "cups":bag.cups.size(), "satiety":bag.satiety, "held":held}
	var economy: Dictionary = bag.economy
	result.inventory.merge({"gold":economy.coins, "ore":economy.ore, "hide":economy.hide, "bounty":economy.bounty,
		"cup_pattern":economy.cup_pattern,"shortsword":economy.shortsword, "sword_equipped":economy.sword_equipped})
	result.market = {"orchard":service.orchard_facts(),"ore_left":state.ore_left,"sell_prices":Guild.PRICES.duplicate(),
		"pattern_cost":Guild.PATTERN_COST,"sword_cost":Guild.BLADE_COST,"at_counter":state.guild,"at_mine":state.vein}
	var stalls:Array=preload("res://scripts/architecture/market_sites.gd").known_stalls(game,actor.player.position)
	result.market.stalls=stalls
	for stall in stalls:
		result.destinations.append({"id":stall.site,"label":stall.name+" · "+stall.offer.label,"stand":stall.at})
	var entries: Array = result.entries
	for offer in service.Forage.options(service,ID):
		entries.append({"offer":offer,"verb":"forage","args":{"option":offer.id}})
	var priest=world.get_node_or_null("SandboxPriest")
	if priest!=null and priest.has_method("hungry_livestock_near"):
		var grazers:Array=priest.hungry_livestock_near(actor.player.position,13.0)
		result.grazers=grazers
		if bag.forage>0:
			for beast in grazers:
				result.destinations.append({"id":"grazer."+beast.work_id,"label":"送牧草给"+str(beast.name),"stand":[beast.x,beast.y]})
		elif not grazers.is_empty():
			for patch in service.pasture_near(actor.player.position,13.0):
				if patch.portions>0:result.destinations.append({"id":"meadow."+patch.id,"label":service.Forage.patch_name(patch.id),"stand":[patch.x,patch.y]})
	var board:Dictionary=service.guild_contracts(ID)
	result.contracts=board.cards
	for c in board.cards:
		if c.owner==ID and c.status=="active":
			result.destinations.append({"id":"contract-site."+c.id,"label":c.title+" · "+c.target,"stand":c.at})
	for option in board.actions:
		var entry:=_entry("contract."+option.id,option.label,"contract","contract",{"option":option.id})
		entry.offer.target=option.contract_id
		entry.offer.price=option.reward
		entries.append(entry)
	if state.market and state.counter_offer.has("stock"):
		var q:Dictionary=state.counter_offer
		var can_buy:bool=q.direction==service.Goods.SELL and q.stock>0 and economy.coins>=q.unit_price
		var can_sell:bool=q.direction==service.Goods.BUY and q.coins>=q.unit_price and bag.get(q.item,0)>0
		if can_buy or can_sell:
			var action_id:="market.counter.%s.%d.%s.%s.%d"%[q.station,q.slot,q.direction,q.item,q.unit_price]
			var trade:=_entry(action_id,q.label,q.item,"counter_trade",q)
			trade.offer.merge({"target":q.station,"price":q.unit_price,"quantity":1,"direction":q.direction})
			entries.append(trade)
	elif state.market and bag.fruit>0 and economy.coins<9999:
		var station:=preload("res://scripts/architecture/market_sites.gd").station_id(game,actor.player.position)
		var title:String=service.contracts.market_title(station)
		var sale:=_entry("market.sell_fruit","向%s卖一枚朱果 · %d 金"%[title,service.FRUIT_PRICE],"朱果","sell_fruit")
		sale.offer.target=station
		sale.offer.price=service.FRUIT_PRICE
		sale.offer.quantity=1
		entries.append(sale)
	result.destinations.append({"id":"guild","label":"台地村庄的冒险者公会柜台","stand":[Guild.COUNTER_X,world.travel_height(Guild.COUNTER_X)]})
	if state.ore_left > 0:
		result.destinations.append({"id":"mine","label":"村西露头矿脉，可采矿样","stand":[Guild.VEIN_X,world.travel_height(Guild.VEIN_X)]})
	for quote in service.guild_offers(ID):
		var verb: String = quote.verb
		var id := "guild."+verb
		var item := ""
		var price := 0
		match verb:
			"mine":
				id = "mine"
				item = "ore"
			"sell":
				item = quote.args.item
				id += "."+item
				price = Guild.PRICES[item]
			"buy_pattern":
				item = "cup_pattern"
				price = Guild.PATTERN_COST
			"buy_sword":
				item = "shortsword"
				price = Guild.BLADE_COST
			"equip_sword":
				if economy.sword_equipped: continue
				item = "shortsword"
			_: continue
		var entry := _entry(id,quote.label,item,verb,quote.args)
		entry.offer.quantity = 1
		entry.offer.target = "mine" if verb == "mine" else "bag" if verb == "equip_sword" else "guild"
		if price > 0: entry.offer.price = price
		entries.append(entry)
	var orchards:Array=service.orchard_sites()
	orchards.sort_custom(func(a,b):return actor.player.position.distance_squared_to(Vector2(a.at[0],a.at[1]))<actor.player.position.distance_squared_to(Vector2(b.at[0],b.at[1])))
	for orchard in orchards:
		orchard.site="orchard" if orchard.id==service.TREE else "orchard."+orchard.id
		result.destinations.append({"id":orchard.site,"label":"%.1f 米果树 · %d 枚熟果"%[orchard.at[0],orchard.ripe],"stand":orchard.at})
	result.market.orchards=orchards
	if state.tree and state.fruit_left>0 and bag.fruit<999:
		entries.append(_entry("fruit.pick","从眼前的果树摘一枚朱果放进行囊","朱果","pick",{"tree_id":state.tree_id}))
	if bag.fruit > 0:
		if bag.held != service.FRUIT:
			entries.append(_entry("fruit.hold","从行囊拿一枚朱果到手里","朱果","hold",{"slot":service.FRUIT}))
		if bag.satiety < 100: entries.append(_entry("fruit.eat","吃掉自己的一枚朱果","朱果","eat"))
		if state.person != "":
			var give := _entry("fruit.give:"+str(state.person),"递给身边村民一枚朱果","朱果","give",{"to":state.person})
			give.offer.target = state.person
			entries.append(give)
		if actor.player.position.distance_to(game.player.position) <= service.REACH:
			var share := _entry("fruit.give:player","递给身边玩家一枚朱果","朱果","give",{"to":service.PLAYER})
			share.offer.target = service.PLAYER
			entries.append(share)
	if bag.held != service.EMPTY:
		entries.append(_entry("bag.stow","把手里的东西收进行囊",held,"hold",{"slot":service.EMPTY}))
	return result

static func observe(game,actor) -> Dictionary:
	var view := _view(game,actor)
	var offers := []
	for entry in view.entries: offers.append(entry.offer)
	return {"inventory":view.inventory,"destinations":view.destinations,"actions":offers,"contracts":view.get("contracts",[]),"grazers":view.get("grazers"),"market":view.get("market",{})}

static func execute(game,actor,id:String,args:Dictionary) -> Dictionary:
	if not args.is_empty(): return {"ok":false,"error":"该行动只接受眼前的选项"}
	var view := _view(game,actor)
	for entry in view.entries:
		if entry.offer.id != id: continue
		var acted: Dictionary = game.medieval_world.survival.act(ID,entry.verb,entry.args)
		acted.ok = acted.get("ok",false)
		acted.offer = entry.offer
		acted.inventory = _view(game,actor).inventory
		return acted
	return {"ok":false,"error":"物品、位置或报价已经变化","inventory":view.inventory}
