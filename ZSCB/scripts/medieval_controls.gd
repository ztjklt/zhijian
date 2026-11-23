extends Control

var game = null
var panel: PanelContainer
var navigation: HBoxContainer
var regions: OptionButton
var trial_row: HBoxContainer
var menu_button: Button
var heading: Label
var trial_entry: Button
var trial_button: Button
var trial_note: Label
var last_trial_phase := ""
const Book := preload("res://scripts/architecture/building_book.gd")
var pattern_menu: MenuButton
var patterns := []
var pending_pattern := -1
var last_pattern := {}
var pattern_origin := Vector2.ZERO
var castle_origin := Vector2.INF
var frontier_visit: Button
var frontier_draw: Button
var chat_button: Button
var npc_button: Button
var chat_line: LineEdit
var painter_folio
var chat_send: Button
var chat_paint: Button
var chat_row: HBoxContainer
var priest_button: Button
var field_book_button: Button
var locations_button: Button
var focus_locations_on_return := false
var adventurer_button: Button
var adventure_menu: MenuButton
var adventure_bag: Label
var talking_to_adventurer := false
var companion_row: HBoxContainer
var chat_open := false
var painter: Node:
	get:
		var buddy = companion()
		return buddy.worker if buddy != null else null
var awaiting_painter: bool:
	get:
		var buddy = companion()
		return buddy != null and buddy.has_active_brush()

const FRONTIER_REACH := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = PaperTheme.create()
	panel = PanelContainer.new()
	var style := PaperTheme.panel()
	style.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	heading = Label.new()
	heading.text = "墨线边境 · 黑线画出的中世纪"
	heading.add_theme_font_size_override("font_size", 12)
	column.add_child(heading)
	navigation = HBoxContainer.new()
	column.add_child(navigation)
	regions = OptionButton.new()
	regions.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	regions.custom_minimum_size.y = 44
	regions.focus_mode = Control.FOCUS_NONE
	for section in MedievalWorld.SECTIONS: regions.add_item(section.name)
	regions.item_selected.connect(visit)
	navigation.add_child(regions)
	trial_row = HBoxContainer.new()
	column.add_child(trial_row)
	menu_button = _button(navigation, "选择地图", func(): game.return_to_map_select())
	locations_button=_button(trial_row,"队友方位",open_role_locations)
	locations_button.focus_mode=Control.FOCUS_ALL
	locations_button.tooltip_text="看四位队友的位置和行动"
	field_book_button = _button(trial_row,"角色图鉴",func():
		game.open_divine_status()
		game.divine_panel.open_role("adventurer-lizhou"))
	field_book_button.focus_mode=Control.FOCUS_ALL
	game.toolbar.divine_button.tooltip_text="和角色交谈、看现场 · F6"
	trial_entry = _button(trial_row,"磨坊试桥",visit_trial)
	trial_button = _button(trial_row,"布置试桥台",func():
		if game.medieval_world != null: game.bridge_trial_action("prepare" if game.medieval_world.bridge_trial.phase == "idle" else "start"))
	trial_note = Label.new()
	trial_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trial_note.custom_minimum_size.x = 260
	trial_note.add_theme_font_size_override("font_size",13)
	trial_note.add_theme_color_override("font_color",PaperTheme.INK)
	column.add_child(trial_note)
	pattern_menu = MenuButton.new()
	pattern_menu.text = "建筑笔谱"
	pattern_menu.focus_mode = Control.FOCUS_NONE
	patterns = Book.pages()
	for index in patterns.size():
		var page: Dictionary = patterns[index]
		var label: String = ("城堡 · " if page.key == "castle" else "") + page.section
		pattern_menu.get_popup().add_item(label, index)
	pattern_menu.get_popup().add_separator()
	pattern_menu.get_popup().add_item("重选城堡基点", patterns.size())
	pattern_menu.get_popup().add_item("用地形笔补画本页承重线", patterns.size()+1)
	pattern_menu.about_to_popup.connect(func():
		var popup := pattern_menu.get_popup()
		popup.set_item_disabled(popup.get_item_index(patterns.size()+1),last_pattern.is_empty() or Book.support_at(last_pattern,pattern_origin).is_empty()))
	pattern_menu.get_popup().id_pressed.connect(choose_pattern)
	navigation.add_child(pattern_menu)
	frontier_visit = _button(navigation, "到东侧纸边", visit_frontier)
	frontier_draw = _button(column, "请阿靛续画", request_frontier)
	companion_row = HBoxContainer.new()
	column.add_child(companion_row)
	chat_button = _button(companion_row,"和阿靛说话",open_chat)
	npc_button = _button(companion_row,"问问附近的人",func(): _invite("npc","帮我问问这里的人，接下来怎么走？"))
	_button(companion_row,"邀阿靛同行 · J",func():
		var buddy = companion()
		if buddy != null: buddy.recall()
		game.toolbar.navigation_open = false)
	priest_button = _button(companion_row,"看牧师 · K",visit_priest)
	adventurer_button = _button(companion_row,"找砾舟",open_adventurer)
	chat_row = HBoxContainer.new()
	column.add_child(chat_row)
	chat_line = LineEdit.new()
	chat_line.placeholder_text = "对阿靛说…"
	chat_line.custom_minimum_size.x = 180
	chat_line.max_length = 120
	chat_row.add_child(chat_line)
	chat_line.text_submitted.connect(_send_chat)
	painter_folio = preload("res://scripts/architecture/painter_folio.gd").new()
	painter_folio.controls = self
	chat_row.add_child(painter_folio)
	chat_send = _button(chat_row,"说",func(): _send_chat(chat_line.text))
	chat_paint = _button(chat_row,"照此续画",_send_paint_brief)
	chat_paint.tooltip_text = "让阿靛把这句话画到东侧纸边"
	adventure_menu = MenuButton.new()
	adventure_menu.text = "请砾舟帮忙"
	adventure_menu.focus_mode = Control.FOCUS_NONE
	chat_row.add_child(adventure_menu)
	for label in ["问问附近的村民","一起探路","去摘果带在身上","去公会交易","去公会买图纸","邀砾舟同行片刻","到公会接一单"]:
		adventure_menu.get_popup().add_item(label)
	adventure_menu.get_popup().id_pressed.connect(_adventure_request)
	adventure_bag = Label.new()
	adventure_bag.add_theme_font_size_override("font_size",12)
	chat_row.add_child(adventure_bag)
	chat_row.hide()
	refresh()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(72, 44)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func companion():
	return game.medieval_world.get_node_or_null("SandboxCompanion") if game != null and game.medieval_world != null else null

func open_role_locations(focus_role:="companion") -> void:
	if not game.FunctionalPens.available(game):return
	game.open_divine_status()
	game.divine_panel.field_book.show_locations(focus_role)

func open_chat(for_adventurer := false) -> void:
	if companion() == null: return
	if talking_to_adventurer != for_adventurer: chat_line.clear()
	talking_to_adventurer = for_adventurer
	chat_line.placeholder_text = "对砾舟说…" if for_adventurer else "对阿靛说…"
	chat_open = true
	game.toolbar.navigation_open = true
	chat_row.show()
	chat_line.grab_focus.call_deferred()

func adventurer():
	return game.medieval_world.get_node_or_null("SandboxAdventurer") if game != null and game.medieval_world != null else null

func open_adventurer() -> void:
	var traveller = adventurer()
	if traveller == null or traveller.actor == null: return
	if game.player.position.distance_to(traveller.actor.player.position) > 5:
		_visit_position(traveller.actor.player.position.x - 1.2,false)
	open_chat(true)
	var visit: Dictionary = preload("res://scripts/adventurer_goods.gd").observe(game,traveller.actor)
	var has_guild: bool = visit.destinations.any(func(place): return place.id == "guild")
	adventure_menu.get_popup().set_item_disabled(3,not has_guild)
	adventure_menu.get_popup().set_item_disabled(4,not has_guild or visit.inventory.get("cup_pattern",false))
	var bag: Dictionary = visit.inventory
	var summary := "行囊 · 朱果 %d" % int(bag.get("fruit",0))
	if bag.has("gold"): summary += " · 金币 %d" % int(bag.gold)
	if int(bag.get("ore",0))>0: summary += " · 矿样 %d" % int(bag.ore)
	if bag.get("cup_pattern",false): summary += " · 基础杯图纸"
	adventure_bag.text = summary

func _adventure_request(index: int) -> void:
	if index==6:
		_invite_adventurer("goods","请到公会查看委托，自己接一单，去现场履约后领报酬。","contract")
		return
	if index==5:
		var traveller = adventurer()
		if traveller!=null: traveller.recall()
		return
	var requests := [["npc","请你问问附近的村民，这一带有什么。",""],["explore","一起探探眼前的路吧。",""],
		["goods","请到果树边摘一枚朱果，带在自己的行囊里。","fruit"],
		["goods","去冒险者公会做一笔买卖。没有可交的货和金币时，先采矿样去卖。","trade"],
		["goods","请去公会买一张你自己的基础杯图纸。金币不够就先采矿换钱。","pattern"]]
	if index >= 0 and index < requests.size(): _invite_adventurer(requests[index][0],requests[index][1],requests[index][2])

func _invite_adventurer(kind: String, words: String, goal := "") -> void:
	var traveller = adventurer()
	if traveller != null and traveller.invite(kind,words,goal):
		chat_line.release_focus()
		chat_line.clear()
		chat_open = false
		game.toolbar.navigation_open = false

func _send_chat(raw: String) -> void:
	var words := raw.strip_edges()
	if words.is_empty(): return
	if talking_to_adventurer:
		_invite_adventurer("chat",words)
		return
	chat_line.release_focus()
	chat_line.clear()
	_invite("talk",words)

func _send_paint_brief() -> void:
	var words := chat_line.text.strip_edges()
	if words.is_empty():
		chat_line.placeholder_text = "想让阿靛画怎样的山形或景物？"
		chat_line.grab_focus()
		return
	if _invite("paint",words):
		chat_line.release_focus()
		chat_line.clear()

func _invite(kind: String, words: String, slot := 0) -> bool:
	var buddy = companion()
	if buddy == null: return false
	if buddy.invite(kind, words, slot):
		chat_open = false
		game.toolbar.navigation_open = false
		return true
	return false

func refresh() -> void:
	if panel == null: return
	chat_open = false
	var medieval: bool = game.medieval_world != null
	regions.visible = medieval
	trial_row.visible = medieval
	heading.visible = medieval

func _process(_delta: float) -> void:
	if game == null: return
	var size := PaperGuiScale.apply(self)
	var bounds := PaperGuiScale.safe_rect(self)
	var moba:bool=game.toolbar.mobile_landscape()
	var compact := size.x < 600 or size.y < 500 or moba
	var medieval: bool = game.medieval_world != null
	var solo: bool = medieval and game.network_session == null and not game.network_headless
	var on_paper_edge := at_frontier()
	var drawing: bool = solo and game.medieval_world.east_painting()
	var buddy = companion()
	if not game.toolbar.navigation_open: chat_open = false
	companion_row.visible = buddy != null and game.toolbar.navigation_open
	adventurer_button.visible = adventurer() != null
	locations_button.visible=solo and game.toolbar.navigation_open
	field_book_button.visible = solo and game.toolbar.navigation_open and adventurer_button.visible
	priest_button.visible = medieval and game.medieval_world.has_node("SandboxPriest")
	if priest_button.is_visible_in_tree():
		var priest = game.medieval_world.get_node("SandboxPriest")
		var state: Dictionary = priest.divine_status()
		var action := str(state.action_label)
		priest_button.text = ("去看小兽" if state.phase == "born" else action) + " · K"
		priest_button.tooltip_text = state.summary
	chat_row.visible = companion_row.visible and chat_open
	painter_folio.visible = not talking_to_adventurer
	chat_paint.visible = on_paper_edge and not talking_to_adventurer
	adventure_menu.visible = talking_to_adventurer
	adventure_bag.visible = talking_to_adventurer
	chat_paint.disabled = awaiting_painter
	pattern_menu.visible = solo
	frontier_visit.visible = solo
	if solo:
		var page:=preload("res://scripts/east_paper_pages.gd").page_of(game.medieval_world.terrain.east_ink.segments.size())+1
		frontier_visit.text="到东侧纸边" if page==1 else "到东侧纸边 · 第 %d 页" % page
	frontier_draw.visible = buddy != null and (on_paper_edge or drawing)
	frontier_draw.disabled = buddy == null or not buddy.frontier_blocker().is_empty()
	frontier_draw.text = "阿靛正在落笔…" if drawing else "阿靛在看纸边…" if awaiting_painter else "请阿靛续画"
	var near: bool = medieval and game.player.position.distance_to(Vector2(133.5,5.2)) <= 12
	var side_event: bool = compact and (size.y < 500 or moba) and not game.toolbar.navigation_open
	trial_note.custom_minimum_size.x = 190 if side_event else 260
	heading.visible = medieval and game.toolbar.navigation_open and not compact
	navigation.visible = game.toolbar.navigation_open
	trial_row.visible = medieval and (game.toolbar.navigation_open or near)
	trial_note.visible = trial_row.visible
	panel.visible = (game.toolbar.navigation_open or (near and not moba) or frontier_draw.visible) and not game.bag_open and not game.onboarding.visible and not (game.experience != null and game.experience.visible)
	if focus_locations_on_return and locations_button.is_visible_in_tree():
		locations_button.grab_focus()
		focus_locations_on_return = false
	if medieval:
		var trial = game.medieval_world.bridge_trial
		trial_button.disabled = not near or trial.phase == "running"
		trial_button.text = {"idle":"布置试桥台","ready":"投放货物","running":"正在运输…","failed":"重新投放","delivered":"换种搭法再试"}.get(trial.phase,"投放货物")
		trial_note.text = {"idle":"可选 · 磨坊试桥：布置两端，画一座能承重的桥。","ready":"桥板、斜坡或组合支撑都可以。画好后投放小货车。","running":"货物运输中 · 桥有些不稳？可以继续补画加固。","failed":"货物掉下来了 · 搭建都还在，补好再试。","delivered":"送达！你的桥承住了货物 · 也可以换种搭法再试。"}.get(trial.phase,"")
		if not near: trial_note.text = "可选 · 磨坊试桥，位于磨坊渡口。前往后可布置和投放货物。"
		if last_trial_phase != "" and last_trial_phase != trial.phase and near:
			if trial.phase == "delivered": game.message("送达！这座手绘桥真正承住了货物")
			elif trial.phase == "failed": game.message("货物掉下来了 · 搭建保留，可以补好再试")
		last_trial_phase = trial.phase
	if game.medieval_world != null:
		var top: float = (game.toolbar.header.get_global_rect().end.y / scale.y) + 10
		if compact and not side_event: top = maxf(top,game.toolbar.bottom.get_global_rect().end.y / scale.y + (8 if size.y < 500 else 40))
		panel.position = Vector2(bounds.position.x+(12 if compact else 20),top)
	else:
		panel.position = Vector2(maxf(bounds.position.x+12, bounds.end.x - panel.size.x - 16), game.toolbar.header.position.y + game.toolbar.header.size.y + 10)
	panel.reset_size()
	if moba:
		# Keep both the optional event and expanded navigation away from the
		# left context tools, upper management buttons and lower thumb controls.
		panel.position.x=bounds.get_center().x-panel.size.x*.5
		panel.position.y=bounds.get_center().y-panel.size.y*.5 if game.toolbar.navigation_open else bounds.position.y+78
		panel.position.y=clampf(panel.position.y,bounds.position.y+8,maxf(bounds.position.y+8,bounds.end.y-panel.size.y-8))
	elif compact and size.y < 500 and not side_event:
		panel.position.x = maxf(bounds.position.x+12,bounds.get_center().x-panel.size.x*.5)
		# CJK font metrics change the wrapped note's height. Fit the measured
		# panel after reset_size, rather than assuming it fits below the dock.
		panel.position.y = minf(panel.position.y, bounds.end.y-panel.size.y-8)
	PaperGuiScale.popup(regions.get_popup(), scale.x)

func choose_pattern(index: int) -> void:
	if not game.FunctionalPens.available(game): return
	if index == patterns.size()+1:
		load_support()
		return
	if index == patterns.size():
		castle_origin = Vector2.INF
		game.message("下次打开城堡笔谱时，点击纸面选择新的底部中心")
		return
	if index < 0 or index >= patterns.size(): return
	game.set_draw_mode(7)
	if not game.draft.is_empty():
		game.message("请先完成或清空当前的景物草稿")
		return
	game.toolbar.navigation_open = false
	pending_pattern = index
	game.plan_site_preview.clear()
	var page: Dictionary = patterns[index]
	if page.key == "castle" and castle_origin.is_finite() and absf(game.player.position.x-castle_origin.x) < 15:
		place_pattern(castle_origin)
	else:
		game.message("点击纸面确定「%s」的底部中心 · Esc 取消" % page.section)

func preview_pattern_site(origin: Vector2) -> void:
	if pending_pattern<0 or not game.point_preview_changed(origin): return
	var layout := Book.building_layout(patterns[pending_pattern],origin,game.medieval_world.terrain)
	game.plan_site_preview=game.BuildingPlans.preview_layout(game,layout,origin) if not layout.is_empty() else {}

func place_pattern(origin: Vector2) -> bool:
	if painter_folio != null and painter_folio.place(origin): return true
	if pending_pattern < 0: return false
	var page: Dictionary = patterns[pending_pattern]
	if game.draw_mode != 7 or not game.draft.is_empty(): return false
	var layout := Book.building_layout(page,origin,game.medieval_world.terrain)
	if not layout.is_empty():
		var site: Dictionary = game.BuildingPlans.preview_layout(game,layout,origin)
		if not site.ok:
			game.plan_site_preview=site
			game.message(site.error)
			return true
	pending_pattern=-1
	game.plan_site_preview.clear()
	if page.key == "castle": castle_origin = origin
	else: castle_origin = Vector2.INF
	game.record()
	game.creation_context += 1
	last_pattern = page
	pattern_origin = origin
	game.draft = Book.placed_draft(page, origin, game.medieval_world.terrain)
	if not layout.is_empty():
		game.draft[0].sheet={"name":page.section,"origin":[origin.x,origin.y],"layout":layout}
	game.mode_drafts[7] = game._clone(game.draft)
	game.message("「%s」%d 笔 · 可补画，按 7 落墨，或请画家誊绘" % [page.section,game.draft.size()])
	game.refresh_buttons()
	return true

func load_support() -> void:
	if last_pattern.is_empty(): return
	var paths := Book.support_at(last_pattern,pattern_origin,game.medieval_world.terrain)
	if paths.is_empty(): return
	game.set_draw_mode(8)
	if not game.draft.is_empty():
		game.message("请先确认或清空已有地形草稿")
		return
	game.record()
	game.creation_context += 1
	if Book.catalog()[last_pattern.key].has("bearing_edges"):
		game.paper_pen_mode="platform"
		game.pen_anchor_kind="free"
	game.draft = paths
	game.mode_drafts[8] = game._clone(paths)
	game.toolbar.navigation_open = false
	game.message("承重线已对齐「%s」，离开线条后按 8 确认" % last_pattern.section)
	game.refresh_buttons()

func visit_trial() -> void:
	if game.network_session != null:
		game.message("磨坊试桥在磨坊渡口，沿路走到约129米处；联机不会直接传送")
		return
	visit(6)
	game.toolbar.navigation_open = false
	game.message("来到磨坊试桥 · 先布置试桥台，再画桥、投放货物")

func visit_frontier() -> void:
	if game.network_session != null or game.medieval_world == null: return
	var observation: Dictionary = game.medieval_world.observe_east_edge()
	_visit_position(float(observation.edge[0]) - 4.5,not awaiting_painter)
	game.toolbar.navigation_open = false
	game.message("来到东侧纸边 · 可观看阿靛运笔" if awaiting_painter else "来到东侧纸边 · 请画家接着画，再向右走")

func at_frontier() -> bool:
	return game.medieval_world != null and game.network_session == null and not game.network_headless \
		and absf(game.player.position.x-game.medieval_world.east_walk_limit())<=FRONTIER_REACH

func request_frontier() -> bool:
	return _invite("paint","阿靛，从眼前的纸边接一段我们能走的路吧。")

func request_pen(slot: int) -> void:
	if game.FunctionalPens.available(game) and game.FunctionalPens.TOOLS.has(slot):
		if slot == 7 and not game.draft.is_empty():
			_invite("copy","请用景物笔把这页草稿逐笔誊绘到选好的位置。",slot)
		else: _invite("pen","请拿%s在我们身边画一笔。" % game.FunctionalPens.TOOLS[slot].label,slot)

func visit(index: int) -> void:
	if game.network_session != null:
		game.message("联机请与朋友一起走过去；Home 可返回地面")
		return
	if game.medieval_world == null or index < 0 or index >= MedievalWorld.SECTIONS.size(): return
	_visit_position(float(MedievalWorld.SECTIONS[index].x))
	game.message("来到" + MedievalWorld.SECTIONS[index].name + " · 房屋、村民和城堡都可受击")

func visit_priest() -> void:
	var priest = game.medieval_world.get_node_or_null("SandboxPriest") if game.medieval_world != null else null
	if priest != null: priest.watch()

func _visit_position(world_x: float, _recall_painter := false) -> void:
	# Navigation never commits, discards or silently moves unfinished ink.
	game.retain_active_stroke()
	game.cancel_pointer()
	if game.touch_controls != null: game.touch_controls.reset()
	game.player.reset_movement()
	game.player.position = game.medieval_world.safe_spawn_position(world_x)
	game.player.linear_velocity = Vector2.ZERO
	PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, game.player.position))
	game.camera_x = game.player.position.x
	game.camera_y = game.camera_target_y()
	game.combat.cancel_draw()
	game._update_world_chunks()

# Native controls and popups receive the event first. While the map is open,
# remaining pointer events belong to navigation, including the uncovered paper.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and game != null and game.medieval_world != null and game.toolbar.navigation_open:
		get_viewport().set_input_as_handled()

func blocks_canvas(point: Vector2) -> bool:
	if game != null and game.medieval_world != null and game.toolbar.navigation_open:
		return true
	if painter_folio != null and is_instance_valid(painter_folio.page_view) and painter_folio.page_view.visible:
		return painter_folio.page_view.get_global_rect().has_point(point)
	return panel != null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(point)

func _unhandled_key_input(event: InputEvent) -> void:
	if game==null or game.medieval_world==null or not event is InputEventKey or not event.pressed or event.echo: return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or game.bag_open or game.personal_overlay_open(): return
	if event.keycode==KEY_F6 and game.FunctionalPens.available(game):
		game.open_divine_status()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and (pending_pattern >= 0 or (painter_folio != null and painter_folio.pending_id >= 0)):
		if painter_folio != null: painter_folio.pending_id = -1
		pending_pattern = -1
		game.message("已收起建筑笔谱")
		get_viewport().set_input_as_handled()
		return
	if event.keycode >= KEY_7 and event.keycode <= KEY_9 and not event.is_command_or_control_pressed() and not event.alt_pressed and not event.shift_pressed and game.FunctionalPens.available(game):
		game.activate_draw_mode(7 + event.keycode - KEY_7)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_K and not event.is_command_or_control_pressed() and not event.alt_pressed and not event.shift_pressed and game.medieval_world.has_node("SandboxPriest"):
		visit_priest()
		get_viewport().set_input_as_handled()
	elif event.keycode==KEY_HOME:
		game.respawn_medieval()
		get_viewport().set_input_as_handled()
