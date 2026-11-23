extends RefCounted

const Slots := preload("res://scripts/team_worlds.gd")
const WORLDS := {
	"mountain_market": {
		"title": "山口果铺", "byline": "画家阿靛 · 原创集市",
		"description": "阿靛画了棚、柜和果篮。你在柜前，手里有一枚从村西摘来的朱果。点「回到我」，按 E 卖出，得 1 金。",
		"seed": "mountain_market_ready",
	},
	"mosswing_deer": {
		"title": "苔翼巡鹿", "byline": "牧师原稿 · 磨坊牧草场观察副本",
		"description": "同一只巡鹿从磨坊草甸旁起飞，会落地吃草。附近饥饿的村民也会来取肉。进入后镜头跟着鹿。",
	},
	"guild_shores": {
		"title": "三道新岸", "byline": "砾舟与阿靛 · 公会探路",
		"seed": "guild_shores_restored",
		"description": "从砾舟第三次越过旧岸的地点看起。三张探路单各结了 5 金。回到我，去世界手记的公会账本查看三次来回。",
	},
	"paper_mill": {
		"title": "水磨纸坊", "byline": "美术参考 · 开发者用公共笔谱搭建",
		"description": "回到我，向左沿石阶下水，再向右回到晾纸廊和工作案。水轮和纸张是静态陈设。",
	},
}
const DEER_ID := "life-566a41f99a0f2f7b97914813"
const LANTERN := "lantern_replay"
const MARKET_ID := "companion-77c65365874d2423ef977046"

# A fixed slot within this local profile lets simultaneous first visits compete for
# the same revision. The team and world IDs are new for each created copy.
static func slot_id(key: String) -> String:
	return ("paper-showcase-v1/" + key).sha256_text().left(32)

static func lookup(key: String, cards: Array) -> Dictionary:
	for card: Dictionary in cards:
		if card.get("slot_id") == slot_id(key) and card.get("showcase_id") == key:
			return card
	return {}

static func find_or_copy(key: String) -> Dictionary:
	if not WORLDS.has(key) and key != LANTERN:
		return {"ok":false, "message":"这份试玩世界不在册中。"}
	var prior := lookup(key, Slots.slots())
	if not prior.is_empty():
		return {"ok":true, "card":prior}
	if key == LANTERN: return {"ok":false,"message":"请先看阿靛画完灯铺。"}
	var sample := SaveStore.read_work("res://assets/showcase_worlds/%s.json" % WORLDS[key].get("seed",key), "medieval-v1")
	if sample.error != "":
		return {"ok":false, "message":"未能读取原世界。" + str(sample.error)}
	var data: Dictionary = sample.data
	for actor in ["companion", "adventurer", "war_god"]:
		data.world[actor].autonomy.paused = true
	data.world.priest_work.autonomy_paused = true
	var order: Dictionary = data.world.war_god.action
	if not order.is_empty():
		order.finish_before_pause = true
	var encoded := SaveStore.encode_work(data.paper, data.objects, data.bag, data.cameraX, data.playerX, data.equipped_weapon, data.world)
	if not encoded.ok:
		return encoded
	var card := Slots.new_slot("试玩 · " + str(WORLDS[key].title))
	card.slot_id = slot_id(key)
	card.showcase_id = key
	var saved := Slots.commit(card, encoded.data)
	if not saved.ok:
		prior = lookup(key, Slots.slots())
		if not prior.is_empty():
			return {"ok":true, "card":prior}
	return saved

# Only an explicit handover writes a trial slot. Further visits resume its existing history.
static func keep_lantern(game) -> Dictionary:
	var prior := lookup(LANTERN,Slots.slots())
	if not prior.is_empty():return {"ok":true,"card":prior}
	var card: Dictionary = game.team_slot.duplicate()
	card.name = "试玩 · 纸灯小铺"
	card.slot_id = slot_id(LANTERN)
	card.showcase_id = LANTERN
	var result: Dictionary = game.save_team_as(card)
	if not result.ok:
		prior = lookup(LANTERN,Slots.slots())
		if not prior.is_empty():return {"ok":true,"card":prior}
	return result

static func saved_market_step(slot: String) -> String:
	var loaded := Slots.load_slot(slot)
	if loaded.get("error","")!="":return "继续此队，查看山口果铺与上次保存的行囊。"
	var data: Dictionary = loaded.data
	var exists: bool = data.objects.any(func(o):return o.get("work_id")==MARKET_ID and o.get("hp",1)>0)
	if not exists:return "此队保留了果铺的建造记录。可以回到原址看看现在的样子。"
	var count := int(data.world.survival.actors.get("player",{}).get("fruit",0))
	if count>0:return "上次保存时带着 %d 枚朱果。回到我，在山口果铺柜前按 E，每枚换 1 金。" % count
	return "上次保存时行囊里没有朱果。地图选「台地村庄」，往西摘果；再选「古修道院」，往东到山口果铺交果。"

static func watch(game, key: String) -> void:
	game.open_divine_status()
	var panel = game.divine_panel
	match key:
		LANTERN:
			panel.close()
			var hit: Dictionary = game.medieval_world.survival.counter_hit("player")
			var quote: Dictionary = preload("res://scripts/architecture/stall_goods.gd").public_quote(hit)
			if quote.get("item") == "paper_lantern" and quote.get("stock",0) > 0:
				game.message("在灯柜旁按 E 买灯，一盏 2 金。")
		"mountain_market":
			for obj in game.objects:
				if obj.get("work_id") == MARKET_ID and obj.get("hp",1)>0:
					var fruit := int(game.medieval_world.survival.inventory("player").fruit)
					var nearby: bool = preload("res://scripts/architecture/market_sites.gd").station_id(game,game.player.position)==obj.structure_id
					var hint := "回到我，去柜前按 E 交朱果" if fruit>0 else "去台地村庄西侧摘朱果"
					if nearby and fruit>0:hint="回到我，按 E 卖朱果得 1 金"
					panel.watch_point(Vector2(obj.x, obj.y), "山口果铺 · "+hint)
					panel.title.text="画家阿靛 · 已完成的原作"
					return
			panel.watch_point(Vector2(154.61, 6.375), "山口果铺原址")
		"paper_mill":
			var mill_focus := Vector2(218.4,12.55) if game.get_viewport_rect().size.x<800 else Vector2(220.4,12.1)
			panel.watch_point(mill_focus,"水磨纸坊 · 回到我，向左沿石阶涉水")
			panel.title.text="美术参考 · 公共笔谱习作"
		"mosswing_deer":
			var priest = panel._actor("priest")
			if priest != null and priest.work_by_id(DEER_ID) != null:
				panel.watch("priest", DEER_ID)
			else:
				panel.watch_point(Vector2(3.52, 7.996), "苔翼巡鹿最初落脚的坡地")
		"guild_shores":
			panel.watch_point(Vector2(658.623718261719, -0.224359780550003), "第三道新岸 · 砾舟在这里越过旧界")
