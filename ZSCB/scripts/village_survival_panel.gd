extends Control
## Local controls translate into the same actor commands available to residents.
var game
var opened := false
var dock := HBoxContainer.new()
var shortcut := Button.new()
var bag_button := Button.new()
var shade := ColorRect.new()
var panel := PanelContainer.new()
var scroll := ScrollContainer.new()
var title := Label.new()
var inventory_label := Label.new()
var notice := Label.new()
var cup_list := OptionButton.new()
var buttons := {}
var guild_actions := GridContainer.new()
var ledger := Label.new()
var context := ""
const Witness := preload("res://scripts/village_witness.gd")
var witness_row := HBoxContainer.new()
var witness_person := OptionButton.new()
var people_here: Array = []
var pressed_witness := ""
var preferred_witness := ""
var nearest_witness := ""
var witness_bubble := PanelContainer.new()
var witness_words := Label.new()
var witness_time := 0.0
var speaking_world := 0
var speaker_id := ""
var quote:Dictionary={}
var interval := 0.0
const Coat := preload("res://scripts/village_coat.gd")
var supplies := VBoxContainer.new()
var fitting := VBoxContainer.new()
var comparison := Label.new()
var coat_status := Label.new()
var world_coat: Node2D
var preview_coat: Node2D
var contract_page:=preload("res://scripts/village_contract_page.gd").new()
var contracts_open:=false
var fitting_open := false
var preview_selected := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = PaperTheme.create_menu()
	add_child(dock)
	dock.add_child(shortcut)
	shortcut.button_down.connect(func():
		pressed_witness = nearest_witness if context == "witness" else "")
	shortcut.pressed.connect(func():
		if pressed_witness.is_empty():
			_interact()
		else:
			_ask_witness(pressed_witness)
			pressed_witness = "")
	dock.add_child(bag_button)
	bag_button.text = "实物背包 I"
	bag_button.pressed.connect(open)
	add_child(shade)
	shade.color = Color(.12,.16,.17,.25)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.hide()
	add_child(panel)
	panel.hide()
	var style := PaperTheme.panel()
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	title.text = "实物背包"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",22)
	row.add_child(title)
	_button(row,"contracts","委托簿",_toggle_contracts)
	_button(row,"fitting","试穿护衣",_toggle_fitting)
	_button(row,"close","收起",close)
	column.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	pages.add_child(supplies)
	supplies.add_theme_constant_override("separation",8)
	supplies.add_child(witness_row)
	witness_person.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	witness_person.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	witness_row.add_child(witness_person)
	_button(witness_row,"ask_witness","问近况",func():
		_ask_witness(pressed_witness)
		pressed_witness = "")
	buttons.ask_witness.button_down.connect(func():
		pressed_witness = str(witness_person.get_selected_metadata()) if witness_person.selected >= 0 else "")
	supplies.add_child(inventory_label)
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cup_list.fit_to_longest_item = false
	cup_list.clip_text = true
	supplies.add_child(cup_list)
	cup_list.item_selected.connect(func(i):
		var pick=cup_list.get_item_metadata(i)
		if pick is Dictionary:_act(pick.verb,pick.get("args",{})))
	var actions := GridContainer.new()
	actions.columns = 3
	supplies.add_child(actions)
	_button(actions,"draw","手绘墨杯",_start_cup)
	_button(actions,"fill","汲满杯子",func(): _act("fill"))
	_button(actions,"stow","收起手中物",func(): _act("hold",{"slot":-1}))
	_button(actions,"pick","摘一枚朱果",func(): _act("pick"))
	_button(actions,"eat","吃一枚",func(): _act("eat"))
	_button(actions,"give","递给村民",_give)
	supplies.add_child(ledger)
	ledger.add_theme_font_size_override("font_size",15)
	guild_actions.columns = 3
	supplies.add_child(guild_actions)
	for key in ["ore","hide","bounty"]:
		var item: String = key
		_button(guild_actions,"sell_"+item,"",func(): _act("sell",{"item":item}))
	_button(guild_actions,"buy_pattern","杯图纸 · 3 金",func(): _act("buy_pattern"))
	_button(guild_actions,"buy_sword","成品短剑 · 6 金",func(): _act("buy_sword"))
	_button(guild_actions,"equip_sword","装备公会短剑",func(): _act("equip_sword"))
	_button(guild_actions,"mine","采一份矿样",func(): _act("mine"))
	world_coat = Coat.mount(game.character_visual)
	pages.add_child(contract_page)
	contract_page.configure(self)
	pages.add_child(fitting)
	_build_fitting()
	pages.add_child(notice)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size",14)
	notice.custom_minimum_size.y = 42
	witness_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	witness_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	witness_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	witness_words.add_theme_font_size_override("font_size", 15)
	witness_words.add_theme_color_override("font_color", PaperTheme.INK)
	witness_bubble.add_child(witness_words)
	add_child(witness_bubble)
	witness_bubble.hide()

func _build_fitting() -> void:
	fitting.hide()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	fitting.add_child(row)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(106,150)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var rig: Node2D = preload("res://scenes/character.tscn").instantiate()
	portrait.add_child(rig)
	rig.position = Vector2(52,91)
	rig.scale = Vector2.ONE*1.85
	rig.pencil.hide()
	rig.animator.play("idle")
	preview_coat = Coat.mount(rig)
	var details := VBoxContainer.new()
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(details)
	var name_label := Label.new()
	name_label.text = "青布护衣"
	name_label.add_theme_font_size_override("font_size",21)
	details.add_child(name_label)
	details.add_child(coat_status)
	details.add_child(comparison)
	comparison.add_theme_font_size_override("font_size",16)
	var actions := HBoxContainer.new()
	fitting.add_child(actions)
	_button(actions,"buy_coat","购入护衣",func(): _act("buy_coat"))
	_button(actions,"wear_coat","确认穿戴",func():
		if preview_selected: _act("wear_coat")
		else:
			preview_selected = true
			refresh())
	_button(actions,"remove_coat","卸下护衣",func(): _act("remove_coat"))

func _toggle_contracts() -> void:
	scroll.scroll_vertical = 0
	contracts_open=not contracts_open
	fitting_open=false
	preview_selected=false
	notice.text=""
	refresh()

func _toggle_fitting() -> void:
	contracts_open=false
	scroll.scroll_vertical = 0
	fitting_open = not fitting_open
	preview_selected = fitting_open
	notice.text = ""
	refresh()

func _button(parent: Control, key: String, words: String, action: Callable) -> void:
	var b := Button.new()
	b.text = words
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 36
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	b.pressed.connect(action)
	buttons[key] = b

func service():
	return game.medieval_world.survival if game != null and game.medieval_world != null and game.network_session == null else null

func _process(delta: float) -> void:
	if witness_time > 0.0:
		_place_witness_text(delta)
	interval -= delta
	if interval <= 0:
		interval = .15
		refresh()

func refresh() -> void:
	var s = service()
	visible = s != null
	if s == null:
		world_coat.hide()
		if opened: close()
		return
	var screen_size := PaperGuiScale.apply(self)
	var safe := PaperGuiScale.safe_rect(self)
	var obs: Dictionary = s.observe(s.PLAYER)
	if obs.has("error"): return
	var bag: Dictionary = obs.inventory
	people_here = Witness.nearby(game.medieval_world, game.player.position)
	var person: Dictionary = people_here.front() if not people_here.is_empty() else {}
	if not preferred_witness.is_empty():
		var found := people_here.find_custom(func(npc):return npc.id == preferred_witness)
		if found >= 0: person = people_here[found]
		else: preferred_witness = ""
	nearest_witness = person.get("id","")
	context = ""
	quote=obs.counter_offer
	if obs.market: context = "counter_trade" if quote.has("stock") else "sell_fruit"
	elif obs.guild: context = "guild"
	elif obs.vein and obs.ore_left > 0: context = "mine"
	elif obs.pool: context = "fill" if bag.held >= 0 else "hold" if not bag.cups.is_empty() else "draw"
	elif obs.tree and obs.fruit_left > 0: context = "pick"
	elif obs.person != "" and bag.fruit > 0: context = "give"
	var forage:Array=s.Forage.options(s,s.PLAYER) if context=="" or opened else []
	if context=="" and not forage.is_empty():context="forage"
	shortcut.visible = context != "" and not s.cup_drawing
	shortcut.text = {"sell_fruit":"朱果摊 · 1 枚换 1 金 E" if bag.fruit>0 else "问朱果收价 E","forage":"牧草与牲畜 E","guild":"公会交易 E","mine":"采矿 E","fill":"汲墨 E","hold":"拿杯 E","draw":"画只杯 E","pick":"摘朱果 E","give":"递朱果 E"}.get(context,"")
	if context=="counter_trade":shortcut.text="%s · %s E"%[quote.label,("余 %d"%quote.stock if quote.direction==s.Goods.SELL else "柜款 %d"%quote.coins)]
	if context=="" and obs.tree:
		var orchard:Dictionary=s.orchard_facts(obs.tree_id)
		if orchard.next_in_s>=0:
			shortcut.visible=true
			shortcut.text="果树 · 下一枚朱果约 %d 秒"%orchard.next_in_s
	if context.is_empty() and not s.cup_drawing and not shortcut.visible and not nearest_witness.is_empty():
		context = "witness"
		shortcut.text = "%s · 问近况 E" % person.label
		shortcut.show()
	bag_button.text = "实物背包 I" if bag.held < 0 else "杯墨 %d/%d · I" % [s.cup_ink(),s.CUP_CAPACITY]
	dock.visible = not opened and not game.bag_open and not game.personal_overlay_open() and not game.toolbar.navigation_open and not game.selecting_weapon_type
	dock.reset_size()
	var dock_top: float = game.toolbar.header.get_global_rect().end.y / scale.y + 8
	var map: BaseButton = game.toolbar.nearby_minimap
	if map != null and map.is_visible_in_tree():
		dock_top = maxf(dock_top,map.get_global_rect().end.y / scale.y + 4)
		if game.toolbar.session_key_button.is_visible_in_tree():
			dock_top = maxf(dock_top,game.toolbar.session_key_button.get_global_rect().end.y / scale.y + 4)
	if game.toolbar.walking_hud():
		dock_top = safe.end.y - dock.size.y - 8
	game.toolbar.reserve_interaction_width(dock.size.x if dock.visible else 0.0)
	dock.position = Vector2(safe.end.x-dock.size.x-16,dock_top)
	var coat: String = bag.get("coat","absent")
	var trying: bool = opened and fitting_open and preview_selected and (coat != "absent" or obs.guild)
	world_coat.visible = coat == "worn" or trying
	if not opened: return
	supplies.visible = not fitting_open and not contracts_open
	if supplies.visible: _refresh_witness_choices()
	contract_page.visible=contracts_open
	buttons.contracts.text="物品" if contracts_open else "委托簿"
	fitting.visible = fitting_open
	buttons.fitting.text = "回到物品" if fitting_open else "试穿护衣"
	shade.size = screen_size
	var panel_width := minf(430,safe.size.x-20)
	panel.size = Vector2(panel_width,minf(safe.size.y - 16, 480))
	panel.position = safe.get_center()-panel.size*.5
	if contracts_open:
		title.text="公会委托"
		contract_page.refresh(s)
		return
	if fitting_open:
		# Keep the map actor beside the bag on a desktop. Small windows have the same rig in the panel.
		if safe.size.x >= 1024: panel.position.x = safe.end.x-panel.size.x-18
		title.text = "试穿"
		preview_coat.visible = coat == "worn" or trying
		coat_status.text = {"absent":"公会出售 · %d 金" % s.Guild.COAT_COST,"packed":"背包中 · 试穿预览" if trying else "背包中 · 已卸下","worn":"已穿戴"}.get(coat,"")
		comparison.text = "当前护甲  %d\n穿后护甲  %d" % [s.armor(),s.Guild.COAT_ARMOR]
		buttons.buy_coat.visible = coat == "absent"
		buttons.buy_coat.disabled = not obs.guild or bag.economy.coins < s.Guild.COAT_COST
		buttons.buy_coat.text = "购入 · %d 金（持有 %d）" % [s.Guild.COAT_COST,bag.economy.coins] if obs.guild else "台地村庄 · 公会有售"
		buttons.wear_coat.visible = coat == "packed"
		buttons.wear_coat.text = "确认穿戴" if trying else "试穿护衣"
		buttons.remove_coat.visible = coat == "worn"
		return
	title.text = "冒险者公会" if obs.guild else "实物背包"
	var hand := "空手" if bag.held == s.EMPTY else "朱果" if bag.held == s.FRUIT else ("亮纸灯" if bag.get("lamp_lit",false) else "纸灯") if bag.held==s.Goods.LAMP_SLOT else "第 %d 只杯" % (int(bag.held)+1)
	inventory_label.text = "手中 · %s     饱食 %d / 100\n墨杯 %d 只     朱果 %d 枚     朱红颜料 %d 份" % [hand,bag.satiety,bag.cups.size(),bag.fruit,bag.red]
	if bag.get("paper_lantern",0)>0:inventory_label.text+="　纸灯 %d"%int(bag.paper_lantern)
	if bag.get("reed_leaf",0)>0:inventory_label.text+="　苇叶 %d"%int(bag.reed_leaf)
	if not bag.get("grass_roots",[]).is_empty():inventory_label.text+="　带土活根 %d 簇"%bag.grass_roots.size()
	if bag.forage>0:inventory_label.text+="　牧草 %d 份"%bag.forage
	var account: Dictionary = bag.economy
	ledger.text = "金币 %d　矿样 %d　狩猎凭证 %d　讨伐凭证 %d" % [account.coins,account.ore,account.hide,account.bounty]
	for item in s.Guild.PRICES:
		var b: Button = buttons["sell_"+item]
		b.visible = obs.guild
		b.text = "交%s · %d 金" % [s.Guild.NAMES[item].trim_suffix("凭证"),s.Guild.PRICES[item]]
		b.disabled = account[item] == 0
	buttons.buy_pattern.visible = obs.guild
	var recover: bool = account.cup_pattern and s.Guild.missing_pattern(s,s.PLAYER)
	buttons.buy_pattern.text = "补领杯图纸" if recover else "杯图纸 · 3 金"
	buttons.buy_pattern.disabled = not recover and (account.coins < s.Guild.PATTERN_COST or account.cup_pattern)
	buttons.buy_sword.visible = obs.guild
	buttons.buy_sword.disabled = account.coins < s.Guild.BLADE_COST or account.shortsword
	buttons.equip_sword.visible = account.shortsword
	buttons.mine.visible = obs.vein
	buttons.mine.disabled = obs.ore_left <= 0
	guild_actions.visible = obs.guild or obs.vein or account.shortsword
	if not cup_list.get_popup().visible: _refresh_items(bag,s,forage)
	buttons.fill.disabled = not obs.pool or bag.held < 0 or s.cup_ink() == s.CUP_CAPACITY
	buttons.pick.disabled = not obs.tree or obs.fruit_left == 0
	buttons.give.disabled = obs.person == "" or bag.fruit == 0
	buttons.eat.disabled = bag.fruit == 0 or bag.satiety >= 100
	buttons.stow.disabled = bag.held == s.EMPTY

func _refresh_items(bag: Dictionary,s,forage:Array) -> void:
	cup_list.clear()
	cup_list.add_item("选择物品或照料牲畜" if not forage.is_empty() else "选择一只墨杯或拿起朱果")
	for i in bag.cups.size():
		cup_list.add_item("拿起第 %d 只墨杯 · %d / %d 墨" % [i+1,bag.cups[i].ink,s.CUP_CAPACITY])
		cup_list.set_item_metadata(cup_list.item_count-1,{"verb":"hold","args":{"slot":i}})
	for ground in s.ground_fruit_near(s._position(s.PLAYER),s.GroundFruit.TAKE_REACH).slice(0,1):
		cup_list.add_item("拾起脚边朱果")
		cup_list.set_item_metadata(cup_list.item_count-1,{"verb":"gather_ground_fruit","args":{"id":ground.id}})
	if bag.fruit>0:
		cup_list.add_item("脚前放一枚朱果")
		cup_list.set_item_metadata(cup_list.item_count-1,{"verb":"drop_fruit"})
		cup_list.add_item("拿起一枚朱果")
		cup_list.set_item_metadata(cup_list.item_count-1,{"verb":"hold","args":{"slot":s.FRUIT}})
	if opened:
		var feet:Vector2=s.Roots.feet(s,s.PLAYER)
		for patch in s.pasture_near(feet,s.Pasture.REACH):
			if patch.can_divide and s.Roots.reachable(s,feet,Vector2(patch.x,patch.y)):
				_add_bag_action("分一簇带土活根 · "+s.Forage.patch_name(patch.id),"dig_root",{"patch_id":patch.id})
		if not bag.get("grass_roots",[]).is_empty():
			var site:Dictionary=s.pasture_root_site(feet)
			if site.ok:
				for root_id in bag.grass_roots:
					_add_bag_action("在脚边栽下活根 · "+s.Forage.patch_name(root_id.get_slice("-",1))+" "+root_id.get_slice("-",2),"plant_root",{"root_id":root_id,"at":Vector2(site.x,site.y)})
			else:
				cup_list.add_item("栽根 · "+str(site.error))
				cup_list.set_item_disabled(cup_list.item_count-1,true)
	for offer in forage:
		cup_list.add_item(offer.label)
		cup_list.set_item_metadata(cup_list.item_count-1,{"verb":"forage","args":{"option":offer.id}})
	if bag.get("paper_lantern",0)>0:
		_add_bag_action("拿起纸灯","hold",{"slot":s.Goods.LAMP_SLOT})
		if bag.held==s.Goods.LAMP_SLOT:_add_bag_action("熄灭纸灯" if bag.get("lamp_lit",false) else "点亮纸灯","toggle_lamp",{})
	var reed=s.nearby_reed(s.PLAYER)
	if reed!=null:_add_bag_action("采一份此处苇叶","harvest_reed",{"target":reed.entity_id})
	if quote.has("stock"):
		var hit:Dictionary=s.counter_hit(s.PLAYER)
		var opts:Dictionary={}
		if quote.direction==s.Goods.SELL:
			if bag.get(quote.item,0)>0:opts.stock="从自己背包补入一份"+quote.name
			if quote.item=="paper_lantern":opts.make_lamp="用自己 %d 墨制灯补柜"%s.Goods.LAMP_INK
		else:opts.fund="从自己钱袋存 %d 金到本柜"%int(quote.unit_price)
		if hit.has("object") and hit.object.built_plan.owner==s.PLAYER:
			if quote.coins>0:opts.collect="结取自己的柜款 · %d 金"%quote.coins
			if quote.stock>0:opts.retrieve="从自己的柜台取回一份"+quote.name
		for action in opts:
			var choice:=quote.duplicate()
			choice.action=action
			_add_bag_action(opts[action],"counter_provision",choice)
	cup_list.disabled=cup_list.item_count<=1

func _add_bag_action(label:String,verb:String,args:Dictionary) -> void:
	cup_list.add_item(label)
	cup_list.set_item_metadata(cup_list.item_count-1,{"verb":verb,"args":args})

func open() -> void:
	if service() == null or game.bag_open or game.personal_overlay_open(): return
	game.retain_active_stroke()
	game.cancel_pointer()
	game.combat.cancel_draw()
	game.touch_controls.reset()
	game.toolbar.navigation_open = false
	opened = true
	scroll.scroll_vertical = 0
	shade.show()
	panel.show()
	notice.text = "公会柜台收矿样、狩猎和讨伐凭证。\n图纸可反复制杯；成品短剑买后即可装备。" if service().observe("player").guild else "首只墨杯可用纸面底墨手绘。\n台地村庄井旁可汲墨，村西林间可摘朱果。"
	refresh()

func close() -> void:
	opened = false
	contracts_open = false
	fitting_open = false
	preview_selected = false
	if world_coat != null:
		var s = service()
		world_coat.visible = s != null and s.armor() > 0
	shade.hide()
	panel.hide()
	interval = 0.0

func _refresh_witness_choices() -> void:
	# Leave an open list stable. The speaker is checked again when the player asks.
	if witness_person.get_popup().visible: return
	witness_row.visible = not people_here.is_empty()
	var ids := people_here.map(func(person):return person.id)
	var previous_ids: Array = []
	for i in witness_person.item_count:
		previous_ids.append(witness_person.get_item_metadata(i))
	if ids == previous_ids: return
	var selected = witness_person.get_selected_metadata() if witness_person.selected >= 0 else ""
	witness_person.clear()
	for person in people_here:
		witness_person.add_item(person.label)
		var index := witness_person.item_count - 1
		witness_person.set_item_metadata(index, person.id)
		if selected == person.id: witness_person.select(index)

func _ask_witness(id: String) -> void:
	var response: Dictionary = Witness.ask(game.medieval_world, game.player.position, id)
	if not response.ok:
		if opened: notice.text = response.message
		else: game.message(response.message)
		return
	var words := "%s：“%s”" % [response.label, response.message]
	if opened:
		preferred_witness = id
		notice.text = words
		scroll.ensure_control_visible.call_deferred(notice)
		return
	speaking_world = game.medieval_world.get_instance_id()
	speaker_id = id
	witness_words.text = words
	witness_time = clampf(2.5 + words.length() * .12, 5.0, 11.0)
	_place_witness_text(0.0)

func _place_witness_text(delta: float) -> void:
	witness_time -= delta
	var world = game.medieval_world
	if witness_time <= 0.0 or not is_instance_valid(world) or world.get_instance_id() != speaking_world or game.personal_overlay_open():
		witness_time = 0.0
		witness_bubble.hide()
		return
	var who = world.entity_by_id(speaker_id)
	if not is_instance_valid(who) or not who.alive or game.player.position.distance_to(who.position) > 4.0:
		witness_time = 0.0
		witness_bubble.hide()
		return
	var safe := PaperGuiScale.safe_rect(self)
	var anchor:Vector2 = get_global_transform_with_canvas().affine_inverse() * game.world_to_screen(who.position + Vector2(0, 1.05))
	witness_words.custom_minimum_size.x = minf(245.0, safe.size.x - 44.0)
	witness_bubble.reset_size()
	witness_bubble.position = Vector2(
		clampf(anchor.x - witness_bubble.size.x * 0.5, safe.position.x + 8, safe.end.x - witness_bubble.size.x - 8),
		clampf(anchor.y - witness_bubble.size.y, safe.position.y + 8, safe.end.y - witness_bubble.size.y - 8))
	witness_bubble.show()

func _start_cup() -> void:
	var s = service()
	close()
	game.set_draw_mode(9)
	s.cup_drawing = true
	game.message("画墨杯 · 在身旁用左键画出杯身，可补画杯把，再按 9 拿起")
	refresh()

func _give() -> void:
	var s = service()
	_act("give",{"to":s.observe(s.PLAYER).person})

func _act(verb: String, args: Dictionary = {}) -> void:
	var s = service()
	var result: Dictionary = s.act(s.PLAYER,verb,args)
	if verb == "remove_coat" and result.get("ok",false): preview_selected = false
	notice.text = result.get("message",result.get("error",""))
	game.message(notice.text)
	if result.get("ok",false) and verb=="contract" and str(args.get("option","")).begins_with("escort."):
		close()
	refresh()

func _interact() -> void:
	refresh()
	match context:
		"witness": _ask_witness(nearest_witness)
		"guild","forage": open()
		"counter_trade": _act("counter_trade",quote)
		"mine": _act("mine")
		"draw": _start_cup()
		"hold": _act("hold",{"slot":0})
		"give": _give()
		"fill","pick","sell_fruit": _act(context)

func _unhandled_key_input(event: InputEvent) -> void:
	if service() == null or not event is InputEventKey or not event.pressed or event.echo: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or game.bag_open or event.is_command_or_control_pressed() or event.alt_pressed: return
	if event.keycode == KEY_I and (opened or not game.personal_overlay_open()):
		if opened: close()
		else: open()
	elif event.keycode == KEY_E and not game.personal_overlay_open() and not game.toolbar.navigation_open:
		_interact()
	else: return
	get_viewport().set_input_as_handled()
