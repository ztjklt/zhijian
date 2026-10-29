extends Control
## Approved cover-v10, built from its original independent art layers.
const Preferences := preload("res://scripts/preferences.gd")
var buttons: Dictionary = {}
var layers: Dictionary = {}
var settings_panel: Control
var layout: Dictionary
var stage: Control
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
			action.tooltip_text = {"practice":"单人练习：选择地图或继续作品","multiplayer":"多人对战：创建或加入双人房间","settings":"设置：音量与画质"}[item.id]
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
	settings_panel = preload("res://scripts/settings_panel.gd").new()
	add_child(settings_panel)
	buttons.practice.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/map_select.tscn"))
	buttons.multiplayer.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/network_lobby.tscn"))
	buttons.settings.pressed.connect(func(): settings_panel.show())
	get_viewport().size_changed.connect(_layout)
	_layout()
func _layout() -> void:
	var viewport := get_viewport_rect().size
	var factor := minf(viewport.x / 1672.0, viewport.y / 941.0)
	stage.position = (viewport - Vector2(1672,941)*factor)*0.5
	for item: Dictionary in layout.layers:
		var node: Control = layers[item.id]
		var rect: Array = item.rect
		node.position = Vector2(rect[0],rect[1])*factor
		node.size = Vector2(rect[2],rect[3])*factor
		node.pivot_offset = node.size * 0.5
		node.rotation_degrees = item.get("rotation",0.0)
	if viewport.x < 600:
		stage.position = Vector2.ZERO
		var background: TextureRect = layers.background
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.position = Vector2.ZERO
		background.size = viewport
		for key in ["school-left","school-right"]: layers[key].visible = false
		layers["title-paper"].position = Vector2(22,28)
		layers["title-between"].position = Vector2(132,28)
		layers["title-paper"].size = Vector2(100,95)
		layers["title-between"].size = Vector2(90,95)
		for i in range(3):
			var action: Control = buttons[["practice","multiplayer","settings"][i]]
			action.size = Vector2(minf(280, viewport.x-48),76)
			action.position = Vector2((viewport.x-action.size.x)*0.5, viewport.y-264+i*82)
			action.rotation_degrees = 0
	else:
		layers.background.stretch_mode = TextureRect.STRETCH_SCALE
		for key in ["school-left","school-right"]: layers[key].visible = true
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),Color("f3f0e8"))
