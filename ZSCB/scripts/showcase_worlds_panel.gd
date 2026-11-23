extends PanelContainer

signal visit(key: String)
signal back

const Worlds := preload("res://scripts/showcase_worlds.gd")
var selected := "mountain_market"
var choices := {}
var byline := Label.new()
var description := Label.new()
var note := Label.new()
var enter := Button.new()
var replay := Button.new()
var lantern := Button.new()
var viewer: Control
var cards := []

func _ready() -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "试玩世界"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PaperTheme.heading(title)
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var back_button := Button.new()
	back_button.text = "返回队伍"
	back_button.add_theme_color_override("font_focus_color", PaperTheme.INK)
	back_button.pressed.connect(func(): back.emit())
	header.add_child(back_button)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	var group := ButtonGroup.new()
	for key: String in Worlds.WORLDS:
		var b := Button.new()
		for state in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(state, PaperTheme.INK)
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = Worlds.WORLDS[key].title
		b.pressed.connect(select.bind(key))
		tabs.add_child(b)
		choices[key] = b
	# Long saved-world instructions can scroll without moving either action.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",4)
	scroll.add_child(body)
	byline.add_theme_color_override("font_color", PaperTheme.TEAL)
	byline.add_theme_font_size_override("font_size", 18)
	body.add_child(byline)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", PaperTheme.INK)
	body.add_child(description)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", PaperTheme.MENU_MUTED)
	note.add_theme_font_size_override("font_size", 15)
	body.add_child(note)
	PaperTheme.primary(enter)
	enter.add_theme_color_override("font_focus_color", PaperTheme.PAPER)
	enter.pressed.connect(func(): visit.emit(selected))
	var actions := HBoxContainer.new()
	column.add_child(actions)
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(enter)
	replay.text = "看阿靛续岸"
	replay.add_theme_color_override("font_focus_color", PaperTheme.INK)
	replay.add_theme_color_override("font_hover_pressed_color", PaperTheme.INK)
	replay.pressed.connect(_watch_replay.bind(false))
	actions.add_child(replay)
	lantern.text = "看阿靛建灯铺"
	PaperTheme.primary(lantern)
	lantern.pressed.connect(_watch_replay.bind(true))
	actions.add_child(lantern)
	hide()

func open(slots: Array) -> void:
	cards = slots
	show()
	select(selected)
	choices[selected].grab_focus()

func select(key: String) -> void:
	selected = key
	choices[key].set_pressed_no_signal(true)
	var entry: Dictionary = Worlds.WORLDS[key]
	byline.text = entry.byline
	description.text = entry.description
	var prior := Worlds.lookup(key, cards)
	replay.visible = key=="mountain_market"
	lantern.visible = replay.visible
	var replay_note := "　两段原笔重演均可离线观看。" if replay.visible else ""
	if prior.is_empty():
		note.text = "另建试玩队，自主新回合暂停。" + replay_note
		enter.text = "新建试玩队并看现场"
	else:
		if key=="mountain_market":description.text=Worlds.saved_market_step(prior.slot_id)
		note.text = "继续你上次保存的进度。" + replay_note
		enter.text = "继续我的试玩"

func _watch_replay(watch_lantern := false) -> void:
	if is_instance_valid(viewer):return
	viewer = preload("res://scripts/showcase_ink_replay.gd").new()
	var panel = get_parent()
	var live = panel.game
	viewer.closed.connect(func():
		viewer = null
		if is_instance_valid(live):
			panel.hide()
		else:
			(lantern if watch_lantern else replay).grab_focus())
	viewer.play_street.connect(func():visit.emit(Worlds.LANTERN))
	viewer.open(get_tree().current_scene,live!=null,watch_lantern)
