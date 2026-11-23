extends Control
## Original cover-v10 artwork and image buttons; preserve its approved design.
const Preferences := preload("res://scripts/preferences.gd")
var buttons: Dictionary = {}
var layers: Dictionary = {}
var team_panel: Control
var teams_button: Button
var trial_button := Button.new()
var continue_button := Button.new()
var continue_caption := Label.new()
var continue_name := Label.new()
var recent_id := ""
var settings_panel: Control
var layout: Dictionary
var stage: Control
var landscape_guard: PaperLandscapeGuard
func _ready() -> void:
	get_window().title = "纸间 · 在同一张纸上"
	get_window().content_scale_size = Vector2i.ZERO
	Preferences.apply(get_viewport(), Preferences.read())
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cover/layout.json"))
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	for item: Dictionary in layout.layers:
		var texture: Texture2D = load("res://assets/cover/" + item.file)
		if item.has("crop"):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			var crop: Array = item.crop
			atlas.region = Rect2(crop[0],crop[1],crop[2],crop[3])
			texture = atlas
		var node: Control
		if item.id in ["practice","multiplayer","settings"]:
			var action := TextureButton.new()
			action.texture_normal = texture
			action.ignore_texture_size = true
			action.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			action.tooltip_text = {"practice":"选择沙盒或双人对战，继续作品","multiplayer":"课本世界：创建或加入双人房间","settings":"设置：声音、画面与 AI 角色" if OS.get_name() in ["macOS","Windows","Linux"] else "设置：声音与画面"}[item.id]
			action.mouse_entered.connect(func(): action.modulate = Color(1.08,1.08,1.08))
			action.mouse_exited.connect(func(): action.modulate = Color.WHITE)
			action.focus_entered.connect(func(): action.modulate = Color(1.08,1.08,1.08))
			action.focus_exited.connect(func(): action.modulate = Color.WHITE)
			buttons[item.id] = action
			node = action
		else:
			var art := TextureRect.new()
			art.texture = texture
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node = art
		node.name = item.id
		node.modulate.a = item.get("opacity",1.0)
		stage.add_child(node)
		layers[item.id] = node
	trial_button.text = "试玩世界"
	trial_button.tooltip_text = "翻开试玩册，看原作、亲手试玩"
	trial_button.theme = PaperTheme.create_menu()
	PaperTheme.primary(trial_button)
	trial_button.add_theme_color_override("font_focus_color", PaperTheme.PAPER)
	trial_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	trial_button.add_theme_font_size_override("font_size", 24)
	add_child(trial_button)
	teams_button = PaperSealButton.new()
	teams_button.text = "队伍与世界存档"
	teams_button.theme = PaperTheme.create_menu()
	add_child(teams_button)
	team_panel = preload("res://scripts/team_worlds_panel.gd").new()
	add_child(team_panel)
	continue_button.theme = trial_button.theme
	PaperTheme.primary(continue_button)
	continue_button.pressed.connect(func():
		if not team_panel.visible and not settings_panel.visible: team_panel.resume_from_cover(recent_id))
	add_child(continue_button)
	move_child(continue_button, team_panel.get_index())
	var words := VBoxContainer.new()
	continue_button.add_child(words)
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	words.offset_left = 12
	words.offset_right = -12
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", -2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line:Label in [continue_caption,continue_name]:
		words.add_child(line)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_theme_color_override("font_color", PaperTheme.PAPER)
	continue_caption.add_theme_font_size_override("font_size", 13)
	continue_name.add_theme_font_size_override("font_size", 20)
	team_panel.visibility_changed.connect(func():
		if not team_panel.visible and is_inside_tree(): _refresh_continue())
	teams_button.pressed.connect(team_panel.open)
	trial_button.pressed.connect(team_panel.open_showcases)
	settings_panel = preload("res://scripts/settings_panel.gd").new()
	add_child(settings_panel)
	buttons.practice.pressed.connect(func(): get_tree().change_scene_to_file.call_deferred("res://scenes/map_select.tscn"))
	buttons.multiplayer.pressed.connect(func(): get_tree().change_scene_to_file.call_deferred("res://scenes/network_lobby.tscn"))
	buttons.settings.pressed.connect(func(): settings_panel.show())
	get_viewport().size_changed.connect(_layout)
	_refresh_continue()
	if continue_button.visible: continue_button.grab_focus()
	landscape_guard = PaperLandscapeGuard.install(self)
func _refresh_continue() -> void:
	var recent := preload("res://scripts/team_worlds.gd").cover_slot()
	recent_id = str(recent.get("card", {}).get("slot_id",""))
	continue_button.visible = not recent_id.is_empty()
	if continue_button.visible:
		var card:Dictionary = recent.card
		var background:bool = team_panel.is_background_world(recent_id)
		continue_caption.text = "接回后台世界" if background else "继续上次的队伍" if recent.played else "继续最近保存"
		continue_name.text = str(card.name)
		continue_button.tooltip_text = "%s · %s" % [continue_caption.text, card.name]
		continue_button.accessibility_name = continue_button.tooltip_text
		for style in ["normal","hover","pressed","focus"]: trial_button.remove_theme_stylebox_override(style)
		for color in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: trial_button.remove_theme_color_override(color)
		trial_button.add_theme_font_size_override("font_size", 16)
	else:
		PaperTheme.primary(trial_button)
		trial_button.add_theme_color_override("font_focus_color", PaperTheme.PAPER)
		trial_button.add_theme_font_size_override("font_size", 24)
	_layout()

func _layout() -> void:
	var viewport := get_viewport_rect().size
	var logical_safe := PaperGuiScale.safe_rect(self)
	var amount := PaperGuiScale.factor(viewport)
	var safe := Rect2(logical_safe.position*amount, logical_safe.size*amount)
	var factor := minf(safe.size.x / 1672.0, safe.size.y / 941.0)
	teams_button.scale = Vector2.ONE * amount
	teams_button.reset_size()
	teams_button.position = safe.position+Vector2(safe.size.x-(teams_button.size.x+18)*amount,16*amount)
	stage.position = safe.position + (safe.size - Vector2(1672,941)*factor)*0.5
	for item: Dictionary in layout.layers:
		var node: Control = layers[item.id]
		var rect: Array = item.rect
		node.position = Vector2(rect[0],rect[1])*factor
		node.scale = Vector2.ONE
		node.size = Vector2(rect[2],rect[3])*factor
		node.pivot_offset = node.size * 0.5
		node.rotation_degrees = item.get("rotation",0.0)
	trial_button.scale = Vector2.ONE * amount
	trial_button.size = Vector2(258, 60)
	trial_button.position = stage.position + Vector2(75, 296)*factor
	if logical_safe.size.x < 600 or logical_safe.size.y < 500:
		stage.position = Vector2.ZERO
		var background: TextureRect = layers.background
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.position = Vector2.ZERO
		background.size = viewport
		for key in ["school-left","school-right"]: layers[key].visible = false
		layers["title-paper"].position = safe.position + Vector2(22,28)*amount
		layers["title-between"].position = safe.position + Vector2(132,28)*amount
		layers["title-paper"].size = Vector2(100,95)*amount
		layers["title-between"].size = Vector2(90,95)*amount
		var landscape := safe.size.x > safe.size.y
		var item_w := minf(222,logical_safe.size.x-48)
		var left := safe.end.x - (item_w+52)*amount if landscape else safe.get_center().x - item_w*amount*.5
		var top := safe.position.y + 63*amount if landscape else safe.end.y - 318*amount
		var step := minf(68, (safe.end.y-top-8*amount)/(amount*4))
		trial_button.size = Vector2(item_w, minf(step-6,52))
		trial_button.position = Vector2(left,top)
		for i in range(3):
			var action: Control = buttons[["practice","multiplayer","settings"][i]]
			action.size = Vector2(item_w,step-3)*amount
			action.position = Vector2(left,top+(i+1)*step*amount)
			action.pivot_offset = action.size*.5
			action.rotation_degrees = 0
	else:
		layers.background.stretch_mode = TextureRect.STRETCH_SCALE
		for key in ["school-left","school-right"]: layers[key].visible = true
	if continue_button.visible:
		continue_button.scale = trial_button.scale
		continue_button.size = trial_button.size
		continue_button.position = trial_button.position
		trial_button.size = Vector2(96,44)
		trial_button.position = teams_button.position - Vector2(104*amount,0)
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),Color("f3f0e8"))
