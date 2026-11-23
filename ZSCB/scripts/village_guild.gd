extends RefCounted
## Prices and goods are shared by player, residents and the visible adventurer.
const COUNTER_X := 31.0
const VEIN_X := 17.0
const INITIAL_ORE := 12
const PRICES := {"ore":3,"hide":4,"bounty":10}
const NAMES := {"ore":"矿样","hide":"狩猎凭证","bounty":"讨伐凭证"}
const VERBS := ["mine","sell","buy_pattern","buy_sword","equip_sword","use_cup_pattern","buy_coat","wear_coat","remove_coat"]
const PATTERN_COST := 3
const BLADE_COST := 6
const COAT_COST := 3
const COAT_ARMOR := 4

static func new_account() -> Dictionary:
	return {"coins":0,"ore":0,"hide":0,"bounty":0,"cup_pattern":false,"shortsword":false,"sword_equipped":false}

static func valid_account(value, whole: Callable) -> bool:
	if not value is Dictionary: return false
	for key in ["coins","ore","hide","bounty"]:
		if not whole.call(value.get(key),0,9999): return false
	for key in ["cup_pattern","shortsword","sword_equipped"]:
		if not value.get(key) is bool: return false
	return not value.sword_equipped or value.shortsword

static func near(service,id: String,x: float) -> bool:
	return service._position(id).distance_to(Vector2(x,service.world.travel_height(x)+.4)) <= service.REACH

static func cup_design() -> Dictionary:
	return {"kind":"ink_cup","source":"guild","paths":[
		{"points":[Vector2(-.45,.35),Vector2(-.31,-.32),Vector2(-.20,-.39),Vector2(.18,-.39),Vector2(.28,-.32),Vector2(.39,.35),Vector2(-.45,.35)],"collision":false},
		{"points":[Vector2(.37,.23),Vector2(.57,.23),Vector2(.61,.12),Vector2(.55,-.06),Vector2(.31,-.13)],"collision":false}]}

static func sword() -> Dictionary:
	var strokes := [{"points":[Vector2(-.18,0),Vector2(.06,0),Vector2(.15,.08),Vector2(.96,.065),Vector2(1.16,0),Vector2(.96,-.065),Vector2(.15,-.08),Vector2(.06,0)]},
		{"points":[Vector2(.08,-.17),Vector2(.08,.17)]}]
	var item := PaperWeaponGrip.make_weapon(strokes,Vector2.ZERO)
	item.weapon_type = "sword"
	item.model_fill = true
	item.source = "guild"
	return item

static func equip(service,id: String) -> void:
	var controller = service.world.game if id == service.PLAYER else service.agent_rig(id)
	if controller != null:
		controller.equipped_weapon = sword()
		controller.combat.bow_equipped = false
		controller.combat.cancel_draw()

static func stow(service,id: String,state: Dictionary) -> void:
	var e: Dictionary = state.get("economy",{})
	if not e.get("sword_equipped",false): return
	e.sword_equipped = false
	var controller = service.world.game if id == service.PLAYER else service.agent_rig(id)
	if controller != null and controller.equipped_weapon.get("source") == "guild":
		controller.equipped_weapon = {}
		controller.combat.cancel_draw()

static func missing_pattern(service,id: String) -> bool:
	return id == service.PLAYER and not service.world.game.bag.entries.any(func(entry):
		return entry.get("source") == "guild" and entry.get("kind") == "ink_cup")

static func offers(service,id: String) -> Array:
	var s: Dictionary = service.inventory(id)
	var e: Dictionary = s.economy
	var result := []
	if near(service,id,VEIN_X) and service.ore_left > 0 and e.ore < 9999:
		result.append({"verb":"mine","args":{},"label":"采一份矿样"})
	if near(service,id,COUNTER_X):
		for item in PRICES:
			if e[item] > 0 and e.coins+PRICES[item] <= 9999:
				result.append({"verb":"sell","args":{"item":item},"label":"交%s · %d 金" % [NAMES[item],PRICES[item]]})
		if e.coins >= PATTERN_COST and not e.cup_pattern:
			result.append({"verb":"buy_pattern","args":{},"label":"买基础杯图纸 · 3 金"})
		if e.coins >= BLADE_COST and not e.shortsword:
			result.append({"verb":"buy_sword","args":{},"label":"买公会短剑 · 6 金"})
	if e.cup_pattern and id != service.PLAYER and s.cups.size() < service.MAX_CUPS:
		result.append({"verb":"use_cup_pattern","args":{},"label":"照个人图纸耗墨做一只空杯"})
	if e.shortsword: result.append({"verb":"equip_sword","args":{},"label":"装备公会短剑"})
	return result

static func act(service,id: String,verb: String,args: Dictionary,s: Dictionary) -> Dictionary:
	var e: Dictionary = s.economy
	var message := ""
	if verb == "use_cup_pattern":
		if not e.cup_pattern: return {"error":"尚未购买基础杯图纸"}
		if id == service.PLAYER: return {"error":"请在个人图纸里选择基础墨杯"}
		return service.make_cup(cup_design().paths,false,id)
	if verb == "mine":
		if not near(service,id,VEIN_X): return {"error":"请走到村西的露头矿脉"}
		if service.ore_left <= 0 or e.ore >= 9999: return {"error":"矿脉已空或矿袋已满"}
		service.ore_left -= 1
		e.ore += 1
		service.mine_flash = .6
		message = "采得一份矿样 · 到村中公会可换 3 金"
	elif verb in ["wear_coat","remove_coat"]:
		var expected := "packed" if verb == "wear_coat" else "worn"
		if s.get("coat","absent") != expected: return {"error":"请先选择背包里的护衣"}
		s.coat = "worn" if verb == "wear_coat" else "packed"
		message = "已穿上青布护衣" if verb == "wear_coat" else "护衣已收进背包"
	elif verb == "equip_sword":
		if not e.shortsword: return {"error":"背包中没有公会短剑"}
		equip(service,id)
		e.sword_equipped = true
		s.held = service.EMPTY
		message = "已装备公会短剑"
	else:
		if not near(service,id,COUNTER_X): return {"error":"请走到冒险者公会柜台"}
		match verb:
			"sell":
				var item = args.get("item","")
				if not item is String or not PRICES.has(item) or e[item] < 1: return {"error":"没有这份收购物品"}
				if e.coins+PRICES[item] > 9999: return {"error":"钱袋已满"}
				e[item] -= 1
				e.coins += PRICES[item]
				message = "交出一份%s · 实收 %d 金" % [NAMES[item],PRICES[item]]
			"buy_pattern":
				var recover := bool(e.cup_pattern) and missing_pattern(service,id)
				if e.cup_pattern and not recover: return {"error":"已学会公会的杯图纸"}
				if not recover and e.coins < PATTERN_COST: return {"error":"基础杯图纸需要 3 金"}
				if id == service.PLAYER:
					var added := BlueprintBag.add_entry(service.world.game.bag,cup_design())
					if added.entry.is_empty(): return {"error":added.error}
					added.entry.category = "器具"
					added.entry.name = "公会 · 基础墨杯"
					service.world.game.selected_blueprint_id = added.entry.id
				e.cup_pattern = true
				if not recover: e.coins -= PATTERN_COST
				message = "已补领原来的基础杯图纸" if recover else "付 3 金 · 基础墨杯已收入个人图纸"
			"buy_coat":
				if s.get("coat","absent") != "absent": return {"error":"已经有一件青布护衣"}
				if e.coins < COAT_COST: return {"error":"青布护衣需要 %d 金" % COAT_COST}
				e.coins -= COAT_COST
				s.coat = "packed"
				message = "已付 %d 金，护衣已放进背包" % COAT_COST
			"buy_sword":
				if e.shortsword: return {"error":"背包中已有公会短剑，可以直接装备"}
				if e.coins < BLADE_COST: return {"error":"成品公会短剑需要 6 金"}
				e.coins -= BLADE_COST
				e.shortsword = true
				e.sword_equipped = true
				s.held = service.EMPTY
				equip(service,id)
				message = "付 6 金 · 已收到并装备公会短剑"
			_: return {"error":"柜台上没有这项交易"}
	service.actors[id] = s
	return {"ok":true,"message":message,"coins":e.coins}

## Called only for the living-to-defeated edge of an attributed combat hit.
static func credit_defeat(service,id: String,kind: String) -> void:
	var item := "hide" if kind in ["deer","rabbit"] else "bounty" if kind == "dragon" else ""
	if item == "" or not service._position(id).is_finite(): return
	var s: Dictionary = service.inventory(id)
	if s.economy[item] >= 9999: return
	s.economy[item] += 1
	service.actors[id] = s
	if id == service.PLAYER: service.world.game.message("获得一份%s · 到公会交付" % NAMES[item])
