extends RefCounted
## A single world's inventory. Commands resolve live actors by stable identity.
const Goods := preload("res://scripts/architecture/stall_goods.gd")
const Market := preload("res://scripts/architecture/market_sites.gd")
const Contracts := preload("res://scripts/village_contracts.gd")
const Roots := preload("res://scripts/village_pasture_roots.gd")
const Pasture := preload("res://scripts/village_pasture.gd")
const Livelihood := preload("res://scripts/village_livelihood.gd")
const Guild := preload("res://scripts/village_guild.gd")
const PLAYER := "player"
const COMPANION := "companion"
const ADVENTURER := "adventurer-lizhou"
const TREE := "orchard_tree-100"
const POOL_X := 24.6
const REACH := 1.85
const MARKET_REACH := 1.25
const CUP_CAPACITY := 60
const MAX_CUPS := 8
const FRUIT := -2
const EMPTY := -1
const FRUIT_GAIN := 30
const FORAGE_AT := 20
const ACCEPT_MEAL_BELOW := 70
const FRUIT_PRICE := 1
const FRUIT_MARKS := [Vector2(-.81,1.65),Vector2(.70,1.72),Vector2(-.26,2.0),
	Vector2(.26,2.27),Vector2(-.91,2.38),Vector2(.85,2.56)]
var world
const Forage := preload("res://scripts/village_forage.gd")
var contracts
var actors := {}
var tree
var fruit_stall
var people := {}
const FRUIT_RIPEN_SECONDS := 120.0
const Orchards := preload("res://scripts/village_orchards.gd")
const FOOD_WALK_METRES := 18.0
const PICK_BELOW := 30
const GroundFruit := preload("res://scripts/village_ground_fruit.gd")
var loose_fruit := GroundFruit.new()
var orchards
var fruit_mask:int:
	get:return int(orchards.crops[TREE].mask)
	set(value):orchards.crops[TREE].mask=value
var fruit_bud:int:
	get:return int(orchards.crops[TREE].bud)
	set(value):orchards.crops[TREE].bud=value
var fruit_growth:float:
	get:return float(orchards.crops[TREE].seconds)
	set(value):orchards.crops[TREE].seconds=value
var food_walks := {}
var ore_left := Guild.INITIAL_ORE
var pastures := Pasture.initial()
var mine_flash := 0.0
var hunger_clock := 0.0
var forage_clock := 0.0
var cup_drawing := false
var speech := {}
var food_destinations := {}
var last_resident_x := {}
var last_payment := {}
var restore_armaments := []
var resident_ink := {}

func _init(owner_world) -> void:
	world = owner_world
	orchards = Orchards.new(world)
	contracts = Contracts.new(world)
	index_entities()

func index_entities() -> void:
	orchards.index(self)
	tree = world.entity_by_id(TREE)
	fruit_stall = world.entity_by_id("market-2")
	people.clear()
	for e in world.entities:
		if e.is_person():
			people[e.entity_id] = e
			if not actors.has(e.entity_id): actors[e.entity_id] = _new_inventory(e.entity_id)
			if e.kind=="villager" and not actors[e.entity_id].has("livelihood"):
				actors[e.entity_id].livelihood = Livelihood.new_record()
	if not actors.has(PLAYER): actors[PLAYER] = _new_inventory(PLAYER)

func _new_inventory(id: String) -> Dictionary:
	return {"economy":Guild.new_account(),"cups":[], "held":EMPTY, "fruit":0, "red":0, "satiety":55 if id == PLAYER else 25, "meal":0.0}

func inventory(id: String) -> Dictionary:
	var result: Dictionary = actors.get(id, _new_inventory(id)).duplicate(true)
	if not result.has("economy"): result.economy = Guild.new_account()
	result.forage=int(result.get("forage",0))
	if id == PLAYER and result.economy.shortsword:
		result.economy.sword_equipped = world.game.equipped_weapon.get("source") == "guild" and not world.game.combat.bow_equipped
	return result

func agent_rig(id: String):
	var path := "SandboxAdventurer" if id == ADVENTURER else "SandboxCompanion" if id == COMPANION else ""
	if path.is_empty(): return null
	var owner = world.get_node_or_null(path)
	return owner.actor if owner != null else null

func _body(id: String):
	if id == PLAYER: return world.game.player
	if id == COMPANION or id == ADVENTURER:
		var rig = agent_rig(id)
		return rig.player if rig != null else null
	var resident = people.get(id)
	return resident if is_instance_valid(resident) and resident.alive else null

func _position(id: String) -> Vector2:
	var body = _body(id)
	if body == null: return Vector2.INF
	return body.position + (Vector2(0,.45) if people.has(id) else Vector2.ZERO)

func counter_hit(id:String) -> Dictionary:
	return Market.counter_at(world.game,_position(id))

func at_market(id: String) -> bool:
	return not counter_hit(id).is_empty()

func nearby_reed(id:String):
	var body:=_position(id)
	var nearest=null
	var reach:=1.6
	for plant in world.entities:
		if plant.kind!="reeds" or not plant.alive:continue
		var d:=body.distance_to(plant.position+Vector2(0,.35))
		if d<reach:
			nearest=plant
			reach=d
	return nearest

func pool_position() -> Vector2:
	return Vector2(POOL_X, world.travel_height(POOL_X) + .18)

func fruit_visible(i:int) -> bool:
	return orchards.visible_fruit(self,TREE,i)

func fruit_branch_present(i:int) -> bool:
	return orchards.branch(self,TREE,i)

func fruit_count() -> int:
	return orchard_facts().ripe

func _next_bud() -> int:
	return orchards.next(self,TREE)

func _grow_fruit(delta:float) -> void:
	orchards.grow(self,delta)

func orchard_facts(id:String=TREE) -> Dictionary:
	return orchards.facts(self,id)

func orchard_sites() -> Array:
	var sites:=[]
	for id in orchards.crops:
		var row:=orchard_facts(id)
		if row.alive:sites.append(row)
	return sites

func register_fruit_tree(project:Dictionary) -> Dictionary:
	return orchards.register_tree(project)

func ground_fruit_near(at:Vector2,radius:float) -> Array:
	return loose_fruit.near(at,radius)

func take_ground_fruit(id:String,mouth:Vector2,collector_id:String) -> Dictionary:
	return loose_fruit.take(self,id,mouth,collector_id)

func nearby_tree(at:Vector2, required_id:String="") -> String:
	var nearest := ""
	var distance := REACH
	for id in orchards.crops:
		if (not required_id.is_empty() and id!=required_id) or not orchards.alive(id):continue
		var d:=at.distance_to(orchards.at(id)+Vector2(0,.7))
		if d<=distance:
			distance=d
			nearest=id
	return nearest

func observe(id: String) -> Dictionary:
	var at := _position(id)
	if not at.is_finite(): return {"error":"找不到这位角色"}
	var nearest := ""
	var distance := REACH
	for key in people:
		if key == id or people[key].kind != "villager": continue
		var d := at.distance_to(_position(key))
		if d < distance:
			nearest = key
			distance = d
	var at_tree:=nearby_tree(at)
	var quote:=Goods.public_quote(counter_hit(id))
	return {"inventory":inventory(id),"market":not quote.is_empty(),"counter_offer":quote, "guild":Guild.near(self,id,Guild.COUNTER_X), "vein":Guild.near(self,id,Guild.VEIN_X), "ore_left":ore_left, "pool":at.distance_to(pool_position()) <= REACH,
		"tree":not at_tree.is_empty(), "tree_id":at_tree, "fruit_left":orchard_facts(at_tree).ripe if not at_tree.is_empty() else 0, "person":nearest,
		"person_satiety":int(actors.get(nearest,{}).get("satiety",25)) if nearest != "" else -1}

## Read-only view for one role in this world. Callers supply their own location and sight.
func decision_facts(id: String, at: Vector2, sight: float = 8.0) -> Dictionary:
	return preload("res://scripts/village_facts.gd").observe(self, id, at, sight)

func armor(id: String = PLAYER) -> int:
	return Guild.COAT_ARMOR if actors.get(id,{}).get("coat","absent") == "worn" else 0

func cup_ink(id: String = PLAYER) -> int:
	var state: Dictionary = actors.get(id,{})
	var slot := int(state.get("held",EMPTY))
	return int(state.cups[slot].ink) if slot >= 0 else 0

func _reserve(id: String):
	if id == PLAYER: return world.game.ink
	var rig = agent_rig(id)
	if rig != null: return rig.ink
	if not resident_ink.has(id): resident_ink[id] = PaperInkReserve.new()
	return resident_ink[id]

func pay_creation(price: int,id: String = PLAYER) -> void:
	var paid := mini(cup_ink(id),price)
	if paid > 0:
		var state: Dictionary = actors[id]
		state.cups[int(state.held)].ink -= paid
	_reserve(id).spend(price-paid)
	last_payment = {"cup":paid,"reserve":price-paid}

static func _whole(n, low: int, high: int) -> bool:
	return typeof(n) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(n)) and n == floorf(n) and n >= low and n <= high

static func _valid_shape(shape) -> bool:
	if not shape is Array or shape.is_empty() or shape.size() > 16: return false
	var points := 0
	for line in shape:
		if not line is Array or line.size() < 2: return false
		points += line.size()
		if points > 1024: return false
		for pair in line:
			if not pair is Array or pair.size() != 2: return false
			for n in pair:
				if typeof(n) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(n)) or absf(n) > 1.01: return false
	return true

static func valid_state(value) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not _whole(value.get("fruit_mask"),0,63): return false
	if not _whole(value.get("ore_left",Guild.INITIAL_ORE),0,Guild.INITIAL_ORE): return false
	if value.has("contracts") and not Contracts.valid(value.contracts): return false
	if value.has("fruit_bud")!=value.has("fruit_progress"):return false
	if value.has("fruit_bud"):
		var growth=value.fruit_progress
		if not _whole(value.fruit_bud,0,FRUIT_MARKS.size()-1) or not (growth is int or growth is float) or not is_finite(growth) or growth<0 or growth>=1.0:return false
	if value.has("ground_fruit") and not GroundFruit.valid(value.ground_fruit):return false
	if value.has("orchards") and (not Orchards.valid(value.orchards,FRUIT_RIPEN_SECONDS) or value.orchards.has(TREE)):return false
	if value.has("pastures") and not Pasture.valid(value.pastures): return false
	var clock = value.get("hunger_clock")
	if typeof(clock) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(clock)) or clock < 0 or clock >= 60: return false
	var records = value.get("actors")
	if not records is Dictionary or records.size() > 384: return false
	for id in records:
		if not id is String or id.is_empty() or id.length() > 80: return false
		var s = records[id]
		if not s is Dictionary or not s.get("cups") is Array or s.cups.size() > MAX_CUPS: return false
		if s.get("coat","absent") not in ["absent","packed","worn"]: return false
		if not _whole(s.get("forage",0),0,Forage.LIMIT):return false
		if s.has("economy") and not Guild.valid_account(s.economy,_whole): return false
		if not _whole(s.get("fruit"),0,999) or not _whole(s.get("red"),0,999) or not _whole(s.get("satiety"),0,100): return false
		if not _whole(s.get("paper_lantern",0),0,Goods.LIMIT) or not _whole(s.get("reed_leaf",0),0,Goods.LIMIT) or not s.get("lamp_lit",false) is bool:return false
		if s.get("held")==Goods.LAMP_SLOT and s.get("paper_lantern",0)<=0:return false
		if not _whole(s.get("held"),Goods.LAMP_SLOT,s.cups.size()-1) or (s.held == FRUIT and s.fruit == 0): return false
		var meal = s.get("meal")
		if typeof(meal) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(meal)) or meal < 0 or meal > 1.5: return false
		if s.has("livelihood") and not Livelihood.valid(s.livelihood,float(meal)): return false
		for cup in s.cups:
			if not cup is Dictionary or not _whole(cup.get("ink"),0,CUP_CAPACITY) or not _valid_shape(cup.get("shape")): return false
	for contract in value.get("contracts", {}).get("cards", []):
		if contract.has("fruit_ahead") and contract.fruit_ahead >= records.get(contract.target, {}).get("fruit", 0):
			return false
	return Pasture.valid_ownership(value.get("pastures",Pasture.initial()),records)

func snapshot() -> Dictionary:
	var extra:Dictionary=orchards.crops.duplicate(true)
	extra.erase(TREE)
	return {"version":1, "orchards":extra,"ground_fruit":loose_fruit.state.duplicate(true), "contracts":contracts.state.duplicate(true), "pastures":pastures.duplicate(true), "ore_left":ore_left, "fruit_mask":fruit_mask, "fruit_bud":fruit_bud,"fruit_progress":fruit_growth/FRUIT_RIPEN_SECONDS, "actors":actors.duplicate(true), "hunger_clock":hunger_clock}

func restore(value: Dictionary) -> void:
	contracts.restore(value.get("contracts",{}))
	actors = value.get("actors",{}).duplicate(true)
	pastures = value.get("pastures",Pasture.initial()).duplicate(true)
	loose_fruit=GroundFruit.new()
	if value.has("ground_fruit"):loose_fruit.state=value.ground_fruit.duplicate(true)
	orchards.crops=value.get("orchards",{}).duplicate(true)
	orchards.crops[TREE]=Orchards.fresh()
	food_walks.clear()
	fruit_mask = int(value.get("fruit_mask",63))
	fruit_bud=int(value.get("fruit_bud",0))
	fruit_growth=float(value.get("fruit_progress",0.0))*FRUIT_RIPEN_SECONDS
	ore_left = int(value.get("ore_left",Guild.INITIAL_ORE))
	hunger_clock = value.get("hunger_clock",0.0)
	cup_drawing = false
	speech.clear()
	food_destinations.clear()
	last_resident_x.clear()
	last_payment.clear()
	index_entities()
	resident_ink.clear()
	restore_armaments.clear()
	for id in [ADVENTURER,COMPANION]:
		if actors.get(id,{}).get("economy",{}).get("sword_equipped",false): restore_armaments.append(id)

func make_cup(paths: Array, new_pattern: bool,id: String = PLAYER) -> Dictionary:
	if _body(id) == null or (new_pattern and id != PLAYER): return {"error":"这位制作者没有可用杯稿"}
	var state := inventory(id)
	if state.cups.size() >= MAX_CUPS: return {"error":"实物背包里已有八只杯子"}
	if paths.is_empty() or paths.size() > 16: return {"error":"请用 1 至 16 笔画杯身"}
	var bounds := ShapeMatcher.bounds(paths)
	if bounds.width < .12 or bounds.height < .12: return {"error":"杯身需要有宽度和深度，请再补几笔"}
	var center := Vector2(bounds.min_x + bounds.width*.5,bounds.min_y + bounds.height*.5)
	var shape := []
	for path in paths:
		var line := []
		for p: Vector2 in path.points:
			if new_pattern and p.distance_to(_position(PLAYER)) > DrawingRules.BUILD_RANGE: return {"error":"请走近杯稿再成形"}
			var q := (p-center)/maxf(bounds.width,bounds.height)
			line.append([q.x,q.y])
		shape.append(line)
	if not _valid_shape(shape): return {"error":"杯身最多 1024 个点，每笔至少两点"}
	var pattern := {"source":"own","kind":"ink_cup","paths":[]}
	for line in shape:
		var points := []
		for xy in line: points.append(Vector2(xy[0],xy[1]))
		pattern.paths.append({"points":points,"collision":false})
	var cost := 0 if new_pattern and state.cups.is_empty() else int(PaperInkReserve.cost(pattern))
	if cup_ink(id)+_reserve(id).amount < cost: return {"error":"再制一只杯需要 %d 墨" % cost}
	if new_pattern:
		var added := BlueprintBag.add_entry(world.game.bag,pattern)
		if added.entry.is_empty(): return {"error":added.error}
		added.entry.category = "器具"
		world.game.selected_blueprint_id = added.entry.id
	if cost > 0: pay_creation(cost,id)
	# The payment may have drawn from an older cup, so use its committed state.
	state = inventory(id)
	Guild.stow(self,id,state)
	state.held = state.cups.size()
	state.cups.append({"shape":shape,"ink":0})
	actors[id] = state
	if id == PLAYER: cup_drawing = false
	return {"ok":true,"message":"已拿起手绘空杯 · 到台地村庄的圣墨池按 E 汲墨","cost":cost}

func guild_events(after_seq:int=0,limit:int=20) -> Dictionary:
	return contracts.events(after_seq,limit)

func guild_contracts(actor_id:String) -> Dictionary:
	return contracts.board(actor_id)

func guild_guard_result(work_id:String,source_id:String) -> void:
	contracts.protected(work_id,source_id)

func guild_pasture_attack(attacker:String,prey:String,at:Vector2) -> void:
	contracts.pasture_attack(attacker,prey,at)

func guild_offers(id: String) -> Array:
	return Guild.offers(self,id)

func act(id: String, verb: String, args: Dictionary = {}) -> Dictionary:
	var before: Dictionary = actors.get(id, {})
	var fruit_before := int(before.get("fruit", 0))
	var satiety_before := int(before.get("satiety", 0))
	var result := _act(id, verb, args)
	# Contract delivery enters act("give") itself. Observe only the physical item operation.
	if not result.get("ok", false) or verb == "contract":
		return result
	var after: Dictionary = actors.get(id, {})
	if int(after.get("fruit", 0)) >= fruit_before:
		return result
	contracts.fruit_spent(id, verb == "eat", satiety_before, int(after.satiety))
	if verb == "give":
		var target := str(args.to)
		var receipt: String = contracts.fruit_given(id, target, int(actors[target].fruit) - 1)
		if not receipt.is_empty():
			result.message = receipt
	return result

func _act(id: String, verb: String, args: Dictionary) -> Dictionary:
	var at := _position(id)
	if not at.is_finite(): return {"error":"角色已离开或倒下"}
	var s := inventory(id)
	if verb=="dig_root":return dig_pasture_root(id,str(args.get("patch_id","")))
	if verb=="plant_root":
		var spot=args.get("at")
		if not spot is Vector2:return {"error":"请选择一处真实栽植点"}
		return plant_pasture_root(id,str(args.get("root_id","")),spot)
	if verb=="counter_trade":return Goods.trade(self,id,args)
	if verb=="counter_provision":return Goods.provision(self,id,args)
	if verb=="harvest_reed":
		var reed=nearby_reed(id)
		if reed==null or reed.entity_id!=args.get("target","") or s.get("reed_leaf",0)>=Goods.LIMIT:return {"error":"请走近原处活芦苇，背包需有空位。"}
		# Harvest one whole stem from the destructible source, retaining its saved health.
		reed.damage(minf(4.0,reed.health),reed.position+Vector2(0,.24),Vector2.ZERO)
		s.reed_leaf=int(s.get("reed_leaf",0))+1
		actors[id]=s
		return {"ok":true,"message":"采入一份苇叶 · 共 %d 份"%s.reed_leaf}
	if verb=="toggle_lamp":
		if s.held!=Goods.LAMP_SLOT or s.get("paper_lantern",0)<=0:return {"error":"请先拿起背包里的纸灯。"}
		s.lamp_lit=not s.get("lamp_lit",false)
		actors[id]=s
		return {"ok":true,"message":"点亮纸灯" if s.lamp_lit else "熄灭纸灯"}
	if verb=="forage":return Forage.execute(self,id,str(args.get("option","")))
	if verb=="contract": return contracts.execute(id,str(args.get("option","")))
	if verb in Guild.VERBS: return Guild.act(self,id,verb,args,s)
	var message := ""
	var market_id := ""
	match verb:
		"pick":
			var source:=nearby_tree(at,str(args.get("tree_id","")))
			if source.is_empty():return {"error":"请走到这株活果树旁"}
			var index:=-1
			for i in orchards.count_slots(source):
				if orchards.visible_fruit(self,source,i):
					index=i
					break
			if index<0 or s.fruit>=999:return {"error":"没有可摘的熟果或背包已满"}
			orchards.crops[source].mask=int(orchards.crops[source].mask)&~(1<<index)
			s.fruit += 1
			message = "摘下一枚朱果 · 背包有 %d 枚" % int(s.fruit)
		"drop_fruit":
			if id!=PLAYER or s.fruit<1:return {"error":"行囊里没有可放的朱果"}
			var placed:=loose_fruit.add(self,id,Forage.feet(self,id),.52*world.game.facing)
			if not placed.ok:return placed
			_consume_fruit(s)
			actors[id]=s
			placed.message="在脚前放下一枚朱果，行囊余 %d 枚"%int(s.fruit)
			return placed
		"gather_ground_fruit":
			if s.fruit>=999:return {"error":"背包已满"}
			var mouth:=at
			var choices:=ground_fruit_near(mouth,GroundFruit.TAKE_REACH)
			for choice in choices:
				if not str(args.get("id","")).is_empty() and choice.id!=args.id:continue
				var receipt:=take_ground_fruit(choice.id,mouth,id)
				if not receipt.ok:continue
				s.fruit+=1
				actors[id]=s
				receipt.message="拾起一枚朱果，行囊有 %d 枚"%int(s.fruit)
				return receipt
			return {"error":"眼前没有够得到的落果"}
		"hold":
			var slot = args.get("slot",EMPTY)
			if not _whole(slot,Goods.LAMP_SLOT,s.cups.size()-1) or (slot==Goods.LAMP_SLOT and s.get("paper_lantern",0)<=0) or (slot == FRUIT and s.fruit == 0): return {"error":"背包里没有这件实物"}
			if slot != EMPTY: Guild.stow(self,id,s)
			s.held = int(slot)
			if slot!=Goods.LAMP_SLOT:s.lamp_lit=false
			message = "提起纸灯" if slot==Goods.LAMP_SLOT else "拿起朱果" if slot == FRUIT else "已收进背包" if slot == EMPTY else "拿起第 %d 只墨杯" % (int(slot)+1)
		"fill":
			if s.held < 0: return {"error":"先拿起墨杯"}
			if at.distance_to(pool_position()) > REACH: return {"error":"走到圣墨池边再汲墨"}
			var cup: Dictionary = s.cups[int(s.held)]
			if cup.ink == CUP_CAPACITY: return {"error":"这只杯已经汲满"}
			var amount := CUP_CAPACITY-int(cup.ink)
			cup.ink = CUP_CAPACITY
			message = "汲入 %d 墨 · 持杯作画会先用杯中墨" % amount
		"sell_fruit":
			var market:=counter_hit(id)
			if market.has("object"):return {"error":"请按这处柜台的当前货物和报价交易。"}
			market_id=market.get("station","")
			if market_id.is_empty(): return {"error":"请走到可以交果的摊位"}
			if s.fruit<1: return {"error":"这摊每枚朱果收 1 金。去村西果树摘一枚再来。"}
			if s.economy.coins>=9999: return {"error":"钱袋已满"}
			_consume_fruit(s)
			s.economy.coins += FRUIT_PRICE
			message = "%s 收下一枚朱果 · 实收 1 金"%contracts.market_title(market_id)
		"give":
			var target: String = str(args.get("to",""))
			if target == id or at.distance_to(_position(target)) > REACH: return {"error":"请走到接果的人身旁"}
			if s.fruit < 1: return {"error":"背包里没有朱果"}
			var other := inventory(target)
			if other.fruit >= 999: return {"error":"对方的背包已满"}
			_consume_fruit(s)
			other.fruit += 1
			Guild.stow(self,target,other)
			var eating_meat: bool = other.get("livelihood",{}).get("meat_meal",false)
			if not eating_meat: other.held = FRUIT
			if not eating_meat and people.has(target) and other.satiety < ACCEPT_MEAL_BELOW:
				other.meal = 1.5
				_say(target,"正饿着，谢谢你！")
			else: _say(target,"我先收下了。")
			speech[target].from = id
			actors[target] = other
			message = "递出一枚朱果 · 对方已接过"
		"eat":
			if s.get("livelihood",{}).get("meat_meal",false): return {"error":"正在吃肉"}
			if s.fruit < 1: return {"error":"背包里没有朱果"}
			if s.satiety >= 100: return {"error":"已经吃饱了"}
			_consume_fruit(s)
			s.satiety = mini(100,int(s.satiety)+FRUIT_GAIN)
			s.meal = 0.0
			message = "吃下一枚朱果 · 饱食 %d / 100" % int(s.satiety)
			if id != PLAYER: _say(id,"甜的！饱食 %d" % int(s.satiety))
		"make_pigment":
			if s.fruit < 1 or s.red >= 999: return {"error":"缺少朱果或颜料已满"}
			_consume_fruit(s)
			s.red += 1
			message = "一枚朱果制成一份朱红颜料"
		_: return {"error":"没有这个生存动作"}
	actors[id] = s
	if verb=="sell_fruit": contracts.market_trade(id,market_id,at,s.economy.coins,s.fruit,contracts.market_title(market_id))
	return {"ok":true,"message":message}

func _consume_fruit(s: Dictionary) -> void:
	s.fruit -= 1
	if s.fruit == 0 and s.held == FRUIT:
		s.held = EMPTY
		if not s.get("livelihood",{}).get("meat_meal",false): s.meal = 0.0

func _say(id: String, words: String) -> void:
	speech[id] = {"words":words,"left":2.7}

func pasture_roots(actor_id:String) -> Array[String]:
	return Roots.held(self,actor_id)

func pasture_root_site(at:Vector2) -> Dictionary:
	return Roots.site(self,at)

func dig_pasture_root(actor_id:String,patch_id:String) -> Dictionary:
	return Roots.dig(self,actor_id,patch_id)

func plant_pasture_root(actor_id:String,root_id:String,at:Vector2) -> Dictionary:
	return Roots.plant(self,actor_id,root_id,at)

func pasture_near(at: Vector2, radius: float) -> Array:
	return Pasture.near(self,at,radius)

func graze_pasture(id: String, at: Vector2) -> bool:
	return Pasture.graze(self,id,at)

func threaten_person(at: Vector2, reach: float, source_id: String = "") -> Dictionary:
	var result:=Livelihood.threaten(self,at,reach,source_id)
	contracts.threat(result)
	return result

func _forage() -> void:
	food_destinations.clear()
	var priest=world.get_node_or_null("SandboxPriest")
	var sites:=orchard_sites()
	for id in people:
		var resident=people[id]
		var s:Dictionary=actors[id]
		if resident.kind!="villager" or not resident.alive or resident.hurt_timer>0 or s.meal>0:continue
		if s.livelihood.escape_s>0 or s.livelihood.resting or s.satiety>=ACCEPT_MEAL_BELOW:continue
		if s.fruit>0:
			act(id,"hold",{"slot":FRUIT})
			actors[id].meal=1.5
			continue
		if s.livelihood.meat>0:
			Livelihood.seek_food(self,resident,s,priest)
			continue
		if s.satiety<PICK_BELOW and (_seek_ground_fruit(resident) or _seek_orchard(resident,sites)):continue
		Livelihood.seek_food(self,resident,s,priest)

func _seek_ground_fruit(resident) -> bool:
	var at:Vector2=resident.position
	for item in ground_fruit_near(at,Livelihood.SIGHT):
		var floor_row:=Livelihood.Ground.trace(world,at,item.x)
		if floor_row.is_empty() or absf(float(floor_row.y)+GroundFruit.RADIUS-item.y)>.07:continue
		if not GroundFruit.Obstacles.contact(world,at+Vector2(0,.32),Vector2(item.x,item.y)):continue
		var id:String=resident.entity_id
		if act(id,"gather_ground_fruit",{"id":item.id}).get("ok",false):
			act(id,"hold",{"slot":FRUIT})
			actors[id].meal=1.5
		else:food_destinations[id]=item.x
		return true
	return false

func _seek_orchard(resident,sites:Array) -> bool:
	var id:String=resident.entity_id
	var at:Vector2=resident.position
	var closest:=FOOD_WALK_METRES
	var target:Dictionary={}
	var track:Dictionary=food_walks.get(id,{})
	if track.get("wait",0)>0:track.wait-=1
	for row in sites:
		if row.ripe<1 or (track.get("wait",0)>0 and row.id==track.get("blocked")):continue
		var foot:=Vector2(row.at[0],row.at[1])
		var d:=at.distance_to(foot)
		if d>closest:continue
		var floor_row:=Livelihood.Ground.trace(world,at,foot.x)
		if floor_row.is_empty() or absf(floor_row.y-foot.y)>.55:continue
		closest=d
		target=row
	if target.is_empty():
		track.erase("target")
		return false
	if absf(target.at[0]-at.x)<=1.15 and act(id,"pick",{"tree_id":target.id}).get("ok",false):
		target.ripe-=1
		act(id,"hold",{"slot":FRUIT})
		actors[id].meal=1.5
		_say(id,"这枚熟了。")
		food_walks.erase(id)
		return true
	var stalled:int=track.get("stalled",0)+1 if track.get("target")==target.id and closest>float(track.get("distance",INF))-.06 else 0
	if stalled>=5:
		food_walks[id]={"blocked":target.id,"wait":18}
		return false
	track.merge({"target":target.id,"distance":closest,"stalled":stalled},true)
	food_walks[id]=track
	food_destinations[id]=target.at[0]
	return true

func step(delta: float) -> void:
	if not is_finite(delta) or delta<=0: return
	loose_fruit.fall(self,delta)
	_grow_fruit(delta)
	Pasture.step(pastures,delta)
	contracts.tick(delta)
	forage_clock -= delta
	if forage_clock <= 0:
		forage_clock = 1.0
		_forage()
	for id in restore_armaments.duplicate():
		if agent_rig(id) != null:
			Guild.equip(self,id)
			restore_armaments.erase(id)
	for reserve in resident_ink.values(): reserve.step(delta)
	mine_flash = maxf(0,mine_flash-delta)
	hunger_clock += delta
	if hunger_clock >= 60.0:
		hunger_clock = fmod(hunger_clock,60.0)
		for id in actors:
			actors[id].satiety = maxi(0,int(actors[id].satiety)-1)
	for id in actors:
		var s: Dictionary = actors[id]
		if s.meal <= 0 or _body(id) == null: continue
		var life: Dictionary = s.get("livelihood",{})
		if life.get("escape_s",0)>0 or (people.has(id) and people[id].hurt_timer>0): continue
		s.meal = maxf(0,float(s.meal)-delta)
		if s.meal == 0:
			if life.get("meat_meal",false) and s.satiety>=100: life.meat_meal=false
			elif life.get("meat_meal",false): Livelihood.eat(self,id,s)
			else: act(id,"eat")
	for id in speech.keys():
		speech[id].left -= delta
		if speech[id].left <= 0: speech.erase(id)
