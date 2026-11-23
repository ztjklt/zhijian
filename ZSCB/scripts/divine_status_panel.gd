extends Control

const Roles := preload("res://scripts/divine_roles.gd")
const ROLES := Roles.GODS
const NAMES := Roles.NAMES
const VISIT := Roles.VISIT
const COMMISSION := {"companion":"请阿靛续画", "priest":"请牧师造生"}
const SAMPLES := {"companion":"柳湾浅渡", "priest":"坡栗"}

var game
var watching := ""
var foot_tag: Node2D
var sample_role := ""
var demo: bool = ProjectSettings.get_setting("paper/divine_demo", false)
var shade := ColorRect.new()
var board := PanelContainer.new()
var strip := PanelContainer.new()
var board_scroll := ScrollContainer.new()
var strip_box := VBoxContainer.new()
var current := {}
var connection := {}
var visit := {}
var intentions := {}
var pause_buttons := {}
var budgets := {}
var chat_panel
var priest_journal
var watched_work := ""
var watching_priest_self := false
var priest_camera_button: Button
var chat_frame:=Control.new()
var chat_buttons := {}
var chat_role := ""
var quick_picker:=OptionButton.new()
var quick_text:=LineEdit.new()
var quick_button:Button
var quick_route:Label
var watch_chat_button: Button
var ordinary: Label
var title: Label
var action: Label
var route: Label
var holding_commission := false
var commission_notice: Label
var start: Button
var refresh_in := 0.0
var field_book
var pinned_point := Vector2.INF
var pinned_title := ""
var journal_return: Button
var site_return := Callable()
var site_subject := Rect2()
var strip_back: Button

func _ready() -> void:
	name = "DivineStatusPanel"
	theme = PaperTheme.create_menu()
	foot_tag = preload("res://scripts/watch_foot_tag.gd").new()
	foot_tag.panel = self
	game.add_child(foot_tag)
	# Keyboard focus uses a separate font color in Godot, including focus entered by code.
	for control_type in ["Button", "OptionButton"]:
		theme.set_color("font_focus_color", control_type, PaperTheme.INK)
		theme.set_color("font_pressed_color", control_type, PaperTheme.INK)
		theme.set_color("font_hover_pressed_color", control_type, PaperTheme.INK)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.color = Color(0.13,0.17,0.16,0.38)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	board.add_theme_stylebox_override("panel", PaperTheme.panel())
	board.add_child(board_scroll)
	board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	board_scroll.add_child(content)
	_label(content, "至高神状态", 30)
	if not demo:
		var composer:=HFlowContainer.new()
		content.add_child(composer)
		for id:String in Roles.enabled():
			quick_picker.add_item(NAMES[id])
			quick_picker.set_item_metadata(quick_picker.item_count-1,id)
		composer.add_child(quick_picker)
		quick_picker.item_selected.connect(func(_index):_sync_composer())
		quick_text.placeholder_text="说句话或描述你的想法…"
		quick_text.max_length=600
		quick_text.custom_minimum_size.x=208
		composer.add_child(quick_text)
		quick_text.text_changed.connect(func(words):
			chat_panel.set_draft(_quick_role(),words)
			_refresh_composer())
		quick_button=_button(composer,"发送（调用模型）",_from_composer,true)
		quick_route=_label(content,"",14,PaperTheme.MENU_MUTED,true)
	if demo:
		_label(content, "独立演示存档 · 恢复真实 Harness 已生成笔稿", 16, PaperTheme.TEAL)
	for role: String in (SAMPLES.keys() if demo else Roles.enabled()):
		content.add_child(HSeparator.new())
		_label(content, NAMES[role], 22)
		current[role] = _label(content, "", 17, PaperTheme.INK, true)
		connection[role] = _label(content, "", 15, PaperTheme.MENU_MUTED, true)
		var row := HFlowContainer.new()
		content.add_child(row)
		visit[role] = _button(row, VISIT[role], watch.bind(role), true)
		if demo:
			_button(row, "恢复已生成笔稿 · " + SAMPLES[role], resume_sample.bind(role))
		else:
			chat_buttons[role] = _button(row,Roles.CHAT[role],open_chat.bind(role))
			if role == "priest":
				_button(row, "看牧师本人", watch.bind("priest", "", true))
				_button(row, "图纸与手记", open_priest_journal)
			_autonomy_controls(content,row,role)
	content.add_child(HSeparator.new())
	ordinary = _label(content, "", 15, PaperTheme.MENU_MUTED, true)
	if not demo:
		var travel_row := HFlowContainer.new()
		content.add_child(travel_row)
		_autonomy_controls(content,travel_row,"adventurer-lizhou")
	var footer := HFlowContainer.new()
	content.add_child(footer)
	if not demo:
		_button(footer, "设置 · 添加自己的连接", _settings)
		if _demo_launcher() != "":
			_button(footer, "另开已生成笔稿演示", _open_demo)
	_button(footer, "返回玩家视角", close)
	if not demo:
		chat_panel=preload("res://scripts/divine_chat_panel.gd").new()
		chat_panel.host=self
		board.add_child(chat_frame)
		chat_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		chat_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
		chat_frame.add_child(chat_panel)
		chat_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		chat_frame.hide()
		priest_journal = preload("res://scripts/priest_journal_panel.gd").new()
		priest_journal.host = self
		chat_frame.add_child(priest_journal)
		priest_journal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		priest_journal.hide()
		field_book=preload("res://scripts/role_field_book.gd").new()
		field_book.host=self
		board.add_child(field_book)
		var paper:=PaperTheme.panel(Color("fbf6e9"))
		paper.set_content_margin_all(14)
		board.add_theme_stylebox_override("panel",paper)
	add_child(strip)
	strip.add_theme_stylebox_override("panel", PaperTheme.scrap())
	strip.add_child(strip_box)
	strip_box.add_theme_constant_override("separation", 3)
	title = _label(strip_box, "", 16, PaperTheme.TEAL)
	action = _label(strip_box, "", 19, PaperTheme.INK, true)
	route = _label(strip_box, "", 14, PaperTheme.MENU_MUTED, true)
	var controls := HFlowContainer.new()
	strip_box.add_child(controls)
	start = _button(controls, "", _commission, true)
	start.button_down.connect(func(): holding_commission = true)
	start.button_up.connect(func(): _release_hold.call_deferred())
	if not demo:
		priest_camera_button = _button(controls, "看牧师本人", func(): watch("priest", "", not watching_priest_self))
		watch_chat_button=_button(controls,"与这位神交谈",func():open_chat(watching))
	_button(controls, "至高神状态", open)
	journal_return=_button(controls,"回到这条手记",_return_from_site)
	journal_return.hide()
	strip_back = _button(controls, "回到我", close)
	commission_notice = _label(strip_box, "", 15, PaperTheme.TEAL, true)
	commission_notice.hide()
	strip.minimum_size_changed.connect(_resize_strip, CONNECT_DEFERRED)
	get_viewport().size_changed.connect(_layout)
	hide()
	set_process(false)

func _autonomy_controls(content: Control, row: Control, role: String) -> void:
	intentions[role] = _label(content,"",14,PaperTheme.MENU_MUTED,true)
	pause_buttons[role] = _button(row,"暂停自主",_toggle_autonomy.bind(role))
	var picker := OptionButton.new()
	picker.tooltip_text = "自主行动的模型回合额度，调用计入此角色绑定的服务商账户"
	for limit in [0,1,3,8,16,32]:
		picker.add_item("持续自主" if limit==0 else "最多 %d 回合" % limit,limit)
	picker.item_selected.connect(func(index):
		var actor := _actor(role)
		if actor!=null and actor.has_method("set_action_budget"):
			actor.set_action_budget(picker.get_item_id(index))
			_refresh())
	row.add_child(picker)
	budgets[role] = picker

func _autonomy_state(actor: Node) -> Dictionary:
	if actor==null: return {}
	if actor.has_method("divine_status"): return actor.divine_status()
	if actor.has_method("autonomy_status"): return actor.autonomy_status()
	return {}

func _toggle_autonomy(role: String) -> void:
	var actor := _actor(role)
	if actor==null or not actor.has_method("set_autonomy_paused"): return
	var state := _autonomy_state(actor)
	actor.set_autonomy_paused(not bool(state.get("autonomy_paused",false)))
	_refresh()

func _intent_text(value: Variant) -> String:
	if value == null: return ""
	if value is Array or value is PackedStringArray:
		var labels := PackedStringArray()
		for item in value:
			var label := _intent_text(item)
			if not label.is_empty(): labels.append(label)
		return "、".join(labels)
	return str(value).strip_edges()

func _show_intent(role: String, actor: Node) -> void:
	if not intentions.has(role): return
	var state := _autonomy_state(actor)
	var details := PackedStringArray()
	for pair in [["capabilities","能力"],["goal","目标"],["reason","依据"],["progress","进度"],["pause_reason","暂停原因"]]:
		var value = state.get(pair[0], "")
		var words := _intent_text(value)
		if not state.is_empty() and words.is_empty():
			match pair[0]:
				"goal": words = "等待本轮自主决定"
				"reason": words = _intent_text(state.get("pause_reason"))
				"progress": words = _intent_text(state.get("summary", "等待这一轮开始"))
			if pair[0] == "reason" and words.is_empty(): words = "本轮决定尚未返回"
		if words!="": details.append("%s　%s" % [pair[1],words])
	if role == "war_god" and not str(state.get("target_work_id","")).is_empty():
		details.append("目标生物　#"+str(state.target_work_id).right(8))
	if state.has("work_count"): details.append("已存作品　%d" % int(state.work_count))
	if state.has("used"): details.append("自主回合　%d / %s" % [int(state.used),"持续" if int(state.get("budget",0))==0 else str(state.budget)])
	intentions[role].text = "\n".join(details)
	intentions[role].visible = not details.is_empty()
	pause_buttons[role].visible = actor!=null and actor.has_method("set_autonomy_paused")
	pause_buttons[role].text = "恢复自主（可能调用模型）" if state.get("autonomy_paused",false) else "暂停自主"
	var picker: OptionButton = budgets[role]
	picker.visible = actor!=null and actor.has_method("set_action_budget")
	var limit := int(state.get("budget",0))
	if picker.get_item_index(limit)<0: picker.add_item("最多 %d 回合" % limit,limit)
	picker.select(picker.get_item_index(limit))

func _label(parent: Node, words: String, px: int, ink := PaperTheme.INK, wrap := false) -> Label:
	var line := Label.new()
	line.text = words
	line.add_theme_font_size_override("font_size", px)
	line.add_theme_color_override("font_color", ink)
	if px >= 22: PaperTheme.heading(line)
	if wrap: line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(line)
	return line

func _button(parent: Node, words: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	parent.add_child(button)
	if primary:
		PaperTheme.primary(button)
		var hover_style:=button.get_theme_stylebox("hover") as PaperCutStyle
		hover_style.bg_color=Color("3e7374")
		button.add_theme_color_override("font_focus_color", PaperTheme.PAPER)
		button.add_theme_color_override("font_hover_pressed_color", PaperTheme.PAPER)
	return button

func _demo_launcher() -> String:
	var path := OS.get_environment("ZHIJIAN_DIVINE_DEMO_LAUNCHER")
	return path if path.is_absolute_path() and path.get_file() == "打开已生成笔稿演示.command" and FileAccess.file_exists(path) else ""

func _open_demo() -> void:
	var path := _demo_launcher()
	if path != "" and OS.create_process("/usr/bin/python3", [path]) != -1: return
	game.message("演示启动失败，请从试玩目录打开「已生成笔稿演示」。")

func _settings() -> void:
	var return_role:String=chat_panel.role if chat_role!="" and chat_panel!=null else ""
	close()
	game.open_sandbox_settings(return_role)
	if return_role!="" and game.sandbox_settings!=null and game.sandbox_settings.visible:
		game.sandbox_settings.visibility_changed.connect(func():
			if is_inside_tree() and not game.sandbox_settings.visible: open_chat.call_deferred(return_role),CONNECT_ONE_SHOT)

func _actor(role: String) -> Node:
	if game.medieval_world == null: return null
	return game.medieval_world.get_node_or_null(Roles.NODES[role])

func _route_state(role: String) -> Dictionary:
	var actor := _actor(role)
	if actor != null and actor.has_method("divine_connection_status"):
		return actor.divine_connection_status()
	return ModelConnections.role_status(role)

func _connection_text(role: String, state := {}) -> String:
	if demo: return "来源 · 历史实机存档「%s」" % SAMPLES[role]
	if state.is_empty(): state = _route_state(role)
	if state.id == "": return "模型未配置 · 可在设置中添加自己的连接"
	for record in ModelConnections.list_connections():
		if record.id == state.id:
			return "%s · %s · %s\n%s" % [record.label, record.model, state.message, record.base_url]
	return state.message

func _quick_role() -> String:
	return quick_picker.get_item_metadata(quick_picker.selected)

func _sync_composer() -> void:
	if demo or chat_panel==null:return
	if chat_panel.world_id!=str(game.team_slot.get("world_id","")):chat_panel.open_for(_quick_role())
	quick_text.text=chat_panel.draft_for(_quick_role())
	_refresh_composer()

func _refresh_composer() -> void:
	if demo or quick_button==null:return
	var id:=_quick_role()
	var route:Dictionary=_route_state(id)
	quick_route.text=_connection_text(id,route)+(" · 按此账户计费" if route.ready else "")
	if route.has("retry_after_ms"):
		quick_button.text="等待下一回合"
		quick_button.disabled=true
		return
	if not route.ready:
		quick_button.text="补本次 Key" if route.code=="needs_key" else "设置 AI 角色"
		quick_button.disabled=false
		return
	var actor:=_actor(id)
	var state:Dictionary=actor.divine_chat_status() if actor!=null and actor.has_method("divine_chat_status") else {"can_send":false}
	quick_button.text="发送（调用模型）"
	quick_button.disabled=quick_text.text.strip_edges().is_empty() or state.get("pending",false) or not state.get("can_send",true)

func _from_composer() -> void:
	var id:=_quick_role()
	open_chat(id)
	if _route_state(id).ready:chat_panel._send()
	else:_settings()

func open_priest_journal() -> void:
	if demo or priest_journal == null: return
	open_chat("priest")
	chat_panel.hide()
	priest_journal.show()
	priest_journal.open()

func open_chat(role: String) -> void:
	pinned_point=Vector2.INF
	if field_book!=null:field_book.hide()
	if demo or not Roles.enabled().has(role):return
	chat_role=role
	watching=""
	game.observed_camera=Vector2.INF
	game.get_node("UILayer").show()
	board_scroll.hide()
	strip.hide()
	shade.show()
	board.show()
	chat_frame.show()
	priest_journal.hide()
	chat_panel.show()
	chat_panel.open_for(role)
	chat_panel.editor.grab_focus()
	_layout()
	show()
	set_process(true)

func open() -> void:
	if field_book!=null:
		open_role(field_book.role)
		return
	open_all_controls()

func open_role(id: String) -> void:
	journal_return.hide()
	if field_book==null:return
	watching=""
	pinned_point=Vector2.INF
	chat_role=""
	game.observed_camera=Vector2.INF
	game.get_node("UILayer").show()
	shade.show()
	board.show()
	board_scroll.hide()
	chat_frame.hide()
	strip.hide()
	field_book.show()
	show()
	field_book.select_role(id)
	field_book.role_buttons[id].grab_focus()
	_layout()
	_layout.call_deferred()
	set_process(true)

func open_role_controls(id: String) -> void:
	field_book.show_controls(id)

func open_team_atlas(id: String) -> bool:
	var path:="res://scripts/team_atlas_panel.gd"
	if not ResourceLoader.exists(path):return false
	var atlas=load(path)
	if atlas==null:return false
	var owner_world:=str(game.team_slot.get("world_id",""))
	var on_return:=func():
		if is_inside_tree() and owner_world==str(game.team_slot.get("world_id","")):open_role(id)
	return atlas.open_for(game,{"author_id":id},on_return)!=null

func open_role_settings(id: String) -> void:
	close()
	game.open_sandbox_settings(id)
	if game.sandbox_settings!=null:
		game.sandbox_settings.visibility_changed.connect(func():
			if is_inside_tree() and not game.sandbox_settings.visible:open_role.call_deferred(id),CONNECT_ONE_SHOT)

func open_all_controls() -> void:
	if field_book!=null:field_book.hide()
	chat_role=""
	if chat_panel!=null:chat_frame.hide()
	board_scroll.show()
	if not demo and chat_panel!=null:
		quick_picker.select(maxi(0,ROLES.find(chat_panel.role)))
		_sync_composer()
	watching = ""
	game.observed_camera = Vector2.INF
	game.get_node("UILayer").show()
	shade.show()
	board.show()
	strip.hide()
	show()
	_refresh()
	_layout()
	set_process(true)

func close() -> void:
	var returning_from_site := not watching.is_empty() or pinned_point.is_finite()
	var person := watching if watching != "priest" or watching_priest_self else ""
	pinned_point=Vector2.INF
	holding_commission = false
	watching = ""
	game.observed_camera = Vector2.INF
	game.get_node("UILayer").show()
	hide()
	set_process(false)
	if returning_from_site:foot_tag.point_to("player", person)

func person_point(role: String) -> Vector2:
	var actor:=_actor(role)
	if actor==null:return Vector2.INF
	if role=="priest":return Vector2(actor.priest_x,actor.priest_y)
	if role=="adventurer-lizhou":return actor.actor.player.position if is_instance_valid(actor.actor) else Vector2.INF
	return actor.observation_target()

func observed_animal(priest: Node):
	if watching != "priest" or watching_priest_self or not is_visible_in_tree(): return null
	if not watched_work.is_empty(): return priest.work_by_id(watched_work)
	var animal = priest.focus_animal
	if animal != null and animal.phase != "drawing" and not priest.pending and priest.activity in ["idle","draw"]:
		return animal
	return null

func _return_from_site() -> void:
	if site_return.is_valid(): site_return.call()
	else: field_book.journal_view.restore_card()

func watch_point(at:Vector2,label:String,recorded_place: String = "",on_return := Callable(),subject := Rect2(),return_caption := "回到这项工程") -> void:
	journal_return.hide()
	journal_return.text = return_caption if on_return.is_valid() else "回到这条手记"
	site_return = on_return
	site_subject = subject
	if not at.is_finite():return
	pinned_point=at
	pinned_title=label
	watching=""
	chat_role=""
	game.get_node("UILayer").hide()
	board.hide()
	shade.hide()
	strip.show()
	start.hide()
	commission_notice.hide()
	if priest_camera_button!=null:priest_camera_button.hide()
	if watch_chat_button!=null:watch_chat_button.hide()
	title.text="工程现场" if on_return.is_valid() else ("当时的地点 · 当前实景" if not recorded_place.is_empty() else "事件地点")
	action.text=label
	route.text=("%s（%.1f，%.1f 米）"%[recorded_place,at.x,at.y]) if not recorded_place.is_empty() else game.medieval_world.paper_nav_label("",at)
	_camera_at(at)
	_layout()
	show()
	set_process(true)
	if site_return.is_valid():
		journal_return.show()
		journal_return.grab_focus()
	else:
		strip_back.grab_focus()

func watch(role: String, work_id := "", follow_priest := false) -> void:
	journal_return.hide()
	journal_return.text = "回到这条手记"
	site_return = Callable()
	pinned_point=Vector2.INF
	var actor := _actor(role)
	if actor == null: return
	watching = role
	watched_work = work_id if role == "priest" else ""
	watching_priest_self = role == "priest" and follow_priest
	if priest_camera_button != null:
		priest_camera_button.visible = role == "priest"
		priest_camera_button.text = "看造生现场" if watching_priest_self else "看牧师本人"
	chat_role=""
	if watch_chat_button!=null:
		watch_chat_button.visible=Roles.CHAT.has(role)
		watch_chat_button.text=Roles.CHAT.get(role,"交谈")
	commission_notice.hide()
	game.get_node("UILayer").hide()
	board.hide()
	shade.hide()
	strip.show()
	_track()
	_refresh()
	_layout()
	strip_back.grab_focus()
	if watching != "priest" or watching_priest_self:
		foot_tag.point_to(watching)
	else:
		foot_tag.stop()

func resume_sample(role: String) -> void:
	if not demo or not SAMPLES.has(role): return
	if not game.load_game(role): return
	sample_role = role
	open()
	watch(role)
	game.get_window().title = "纸间 · 已生成笔稿 · " + SAMPLES[role]

func _release_hold() -> void:
	holding_commission = false
	if visible and not watching.is_empty(): _refresh()

func _commission() -> void:
	if demo or not COMMISSION.has(watching): return
	var actor := _actor(watching)
	var started: bool = actor != null and actor.divine_status().can_start and actor.start_creation()
	if started:
		commission_notice.hide()
	else:
		var state: Dictionary = actor.divine_status() if actor != null else {}
		var reason: String = state.get("start_hint", state.get("summary", "角色尚未入场"))
		commission_notice.text = "本次未发起新作 · " + reason
		commission_notice.show()
	_refresh(false)

func _track() -> void:
	var actor := _actor(watching)
	if actor == null:
		open()
		return
	var point: Vector2
	if watching_priest_self:
		point = Vector2(actor.priest_x, actor.priest_y)
	elif not watched_work.is_empty():
		var animal = actor.work_by_id(watched_work)
		if animal == null:
			open_priest_journal()
			return
		point = Vector2(animal.beast_x, animal.beast_y)
	elif watching == "priest":
		point = actor.observation_target()
	else:
		point = person_point(watching)
	_camera_at(point)

func _camera_at(point:Vector2) -> void:
	if not point.is_finite(): return
	var height: float = get_viewport_rect().size.y
	game.observed_camera = Vector2(point.x, point.y - game.GROUND_Y + (game._ground_margin() - height * 0.34) / game.PIXELS_PER_UNIT)

func _priest_person_summary(actor: Node, state: Dictionary) -> String:
	if not str(state.get("person_summary","")).is_empty(): return str(state.person_summary)
	if actor.activity == "travel": return actor.progress
	var at := "脚点（%.1f，%.1f 米）" % [actor.priest_x, actor.priest_y]
	if actor.activity == "idle" and not actor.pending:
		if actor.progress.begins_with("已到"): return "站定 · " + actor.progress
		return "站定 · " + at
	return "%s · %s" % [state.get("summary", actor.progress), at]

func action_summary(state: Dictionary, activity: String) -> String:
	var source := str(state.get("decision_source","")).strip_edges()
	if state.get("autonomy_paused",false) and not source.contains("暂停"):
		source = "自主已暂停" if source.is_empty() else "自主已暂停 · " + source
	if source.is_empty() or activity.begins_with(source) or (source == "本地行动" and activity.begins_with("本地")): return activity
	return source + "　" + activity

func _refresh(keep_held_button := true) -> void:
	# Changing wrapped connection text can move the button out from under the mouse.
	if pinned_point.is_finite():return
	if keep_held_button and holding_commission: return
	if field_book!=null and field_book.is_visible_in_tree():
		field_book.refresh()
		return
	if watching=="" and chat_role!="" and chat_panel!=null:
		if priest_journal.visible: priest_journal.refresh()
		else: chat_panel.refresh()
		return
	if watching == "":
		_refresh_composer()
		for role: String in (SAMPLES.keys() if demo else Roles.enabled()):
			var actor := _actor(role)
			var state: Dictionary = actor.divine_status() if actor != null else {}
			_show_intent(role,actor)
			var activity: String = _priest_person_summary(actor, state) if role == "priest" and actor != null else state.get("summary", "角色尚未入场")
			current[role].text = action_summary(state, activity) if not demo else activity
			connection[role].text = _connection_text(role)
			visit[role].disabled = actor == null or not actor.observation_target().is_finite()
		_show_intent("adventurer-lizhou",_actor("adventurer-lizhou"))
		ordinary.text = "普通冒险者 · 砾舟　　随行探索与公会交易" if game.medieval_world.has_node("SandboxAdventurer") else ""
		return
	var actor := _actor(watching)
	if actor == null: return
	var state: Dictionary = _autonomy_state(actor)
	var prefix := "本局现场"
	if demo:
		prefix = "独立演示档" if sample_role == "" else "已生成笔稿「%s」" % SAMPLES[sample_role]
	title.text = "%s   /   %s" % [prefix, "牧师本人" if watching_priest_self else str(NAMES.get(watching,"冒险者砾舟"))]
	action.text = action_summary(state, _priest_person_summary(actor, state) if watching_priest_self else state.summary) if not demo else state.summary
	var watched_at := person_point(watching)
	if watching == "priest" and not watching_priest_self:
		watched_at = actor.observation_target()
		var animal = observed_animal(actor)
		if animal != null:
			watched_at = Vector2(animal.beast_x, animal.beast_y)
			title.text = "%s   /   %s" % [prefix, animal.design.name]
			if animal.phase == "drawing":
				action.text = "正在运笔　%d%%" % clampi(floori(100.0 * animal.cursor / animal.form.length), 0, 99)
			elif animal.phase == "dead":
				action.text = "遗骸　余肉 %d 份" % animal.portions
			else:
				var warning: String = animal.field_warning()
				var activity: String = animal.action_label()
				if warning in ["敌意","缺食"]: activity += " · " + warning
				action.text = "%s　饱食 %d" % [activity, roundi(animal.satiety)]
	route.text = game.medieval_world.paper_nav_label("",watched_at) if not demo else "历史 Harness 存档 · 沙盒实时演算"
	var hint: String = state.get("start_hint", "")
	if watching == "companion":
		# A blocker for starting a new edge is unrelated to a visit to the artist.
		var east_job:bool = actor.phase == "work" or (actor.phase == "walk" and actor.destination in ["edge","cross"]) or actor.divine_job.get("selected_site",{}).get("after_arrival","") == "expand"
		if east_job and not str(state.get("progress","")).is_empty():
			route.text += "\n东侧续画 · " + str(state.progress)
	elif not demo and not hint.is_empty() and _route_state(watching).ready:
		route.text += "\n" + hint
	start.visible = not demo and not watching_priest_self and watched_work.is_empty() and COMMISSION.has(watching) and state.get("can_start",false)
	if start.visible: start.text = COMMISSION[watching] + "（调用模型，按账户计费）"

func _layout() -> void:
	var bounds := PaperGuiScale.apply(self)
	size = bounds
	shade.size = bounds
	var safe := PaperGuiScale.safe_rect(self).grow(-10)
	if chat_panel!=null:chat_panel.fit_view(safe.size)
	if field_book!=null:field_book.fit(safe.size)
	var reading:bool=field_book!=null and field_book.visible and field_book.page=="events"
	board.size = Vector2(minf(780 if reading else 720 if field_book!=null and field_book.visible else 660,safe.size.x), minf(590 if reading else 452 if field_book!=null and field_book.visible else 580,safe.size.y))
	if field_book != null and field_book.visible and field_book.page == "locations":
		board.size = Vector2(minf(655,safe.size.x),minf(292,safe.size.y))
	board.position = safe.get_center() - board.size * 0.5
	_resize_strip()

func _resize_strip() -> void:
	if not strip.is_visible_in_tree(): return
	var safe := PaperGuiScale.safe_rect(self).grow(-10)
	var width := minf(478, safe.size.x)
	strip_box.custom_minimum_size.x = width - 18
	strip.size = Vector2(width, 0)
	strip.position = Vector2(safe.get_center().x - width * 0.5, safe.position.y)
	if pinned_point.is_finite() and site_return.is_valid() and site_subject.has_area():
		_camera_at(pinned_point)
		var roof: Vector2 = game.world_to_screen(site_subject.end)
		var foot: Vector2 = game.world_to_screen(site_subject.position)
		var room := get_viewport_rect().size.y - foot.y - 10.0
		var shift := clampf(strip.get_global_rect().end.y + 8.0 - roof.y, 0.0, maxf(0.0,room))
		game.observed_camera.y += shift / game.PIXELS_PER_UNIT

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode!=KEY_ESCAPE:return
	get_viewport().set_input_as_handled()
	if journal_return.is_visible_in_tree():_return_from_site()
	elif watching!="" or pinned_point.is_finite():close()
	elif not demo and chat_frame.visible and priest_journal.visible:open_chat("priest")
	elif not demo and chat_frame.visible:open_role(chat_panel.role)
	elif field_book!=null and field_book.visible and field_book.page=="locations":field_book.return_to_map()
	elif field_book!=null and field_book.visible and field_book.page!="person":open_role(field_book.role)
	else:close()

func _process(delta: float) -> void:
	if watching != "": _track()
	refresh_in -= delta
	if refresh_in <= 0:
		refresh_in = 0.2
		_refresh()
