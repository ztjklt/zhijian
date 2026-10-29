extends Control

var game = null
var world = null
var panel: PanelContainer
var subject: Label
var regions: OptionButton
var overview_button: Button
var maps: OptionButton
var limits: Label
var heading: HBoxContainer
var navigation: HBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = PaperTheme.create()
	panel = PanelContainer.new()
	var backing := PaperTheme.panel()
	backing.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", backing)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	heading = HBoxContainer.new()
	column.add_child(heading)
	maps = OptionButton.new()
	maps.focus_mode = Control.FOCUS_NONE
	maps.add_item("课本文字")
	maps.add_item("山野中世纪")
	maps.select(0)
	maps.item_selected.connect(func(index: int):
		game.change_map("medieval-v1" if index == 1 else "knowledge-v1"))
	heading.add_child(maps)
	subject = Label.new()
	subject.add_theme_font_size_override("font_size", 13)
	heading.add_child(subject)
	navigation = HBoxContainer.new()
	column.add_child(navigation)
	regions = OptionButton.new()
	regions.focus_mode = Control.FOCUS_NONE
	for name in world.navigation_names(): regions.add_item(name)
	regions.item_selected.connect(func(index: int): world.visit(index))
	navigation.add_child(regions)
	overview_button = Button.new()
	overview_button.focus_mode = Control.FOCUS_NONE
	overview_button.pressed.connect(func(): world.toggle_overview())
	navigation.add_child(overview_button)
	var home := Button.new()
	home.text = "回到地面"
	home.focus_mode = Control.FOCUS_NONE
	home.pressed.connect(func():
		if world.overview: world.toggle_overview()
		world.respawn())
	navigation.add_child(home)
	limits = Label.new()
	limits.text = world.extent_summary()
	limits.add_theme_font_size_override("font_size", 11)
	column.add_child(limits)
	for button in [maps, regions, overview_button, home]:
		button.custom_minimum_size = Vector2(60, 30)
		button.add_theme_font_size_override("font_size", 13)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style: StyleBox = button.get_theme_stylebox(state).duplicate()
			for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 4)
			button.add_theme_stylebox_override(state, style)

func _process(_delta: float) -> void:
	if game == null or world == null: return
	panel.visible = game.toolbar.navigation_open and not game.bag_open and not game.onboarding.visible
	var size := PaperGuiScale.apply(self)
	var compact := size.x < 600 or size.y < 500
	if compact and maps.get_parent() != navigation:
		maps.reparent(navigation)
		navigation.move_child(maps, 0)
	elif not compact and maps.get_parent() != heading:
		maps.reparent(heading)
		heading.move_child(maps, 0)
	heading.visible = not compact
	limits.text = ("有限 156m · 离地 %.1fm · " % (game.player.position.y - world.surface_height(game.player.position.x))) + ("自然实验备选" if world.map_title().contains("自然") else "页边可攀天空") if compact else world.extent_summary()
	panel.reset_size()
	PaperGuiScale.popup(regions.get_popup(), scale.x)
	PaperGuiScale.popup(maps.get_popup(), scale.x)
	panel.position = Vector2(12 if compact else 20, game.toolbar.header.position.y + game.toolbar.header.size.y + 10)
	subject.text = "%s · 离地 %.1fm" % [world.region_title(world.region), game.player.position.y - world.surface_height(game.player.position.x)]
	regions.select(world.region)
	overview_button.text = "继续 M" if world.overview else "全景 M"
	game.toolbar.bottom.visible = not game.bag_open and not world.overview

func blocks_canvas(point: Vector2) -> bool:
	return panel != null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(point)
