extends Control

var content: VBoxContainer
var cards: GridContainer
var status: Label
var scroll: ScrollContainer
var continue_buttons: Dictionary = {}
var previews: Array[Control] = []
var preview_textures: Dictionary = {}
var legacy_nature_button: Button

func _ready() -> void:
	get_window().title = "纸间 · 选择一张纸上的世界"
	get_window().content_scale_size = Vector2i.ZERO
	theme = PaperTheme.create_menu()
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	_label(content, "P A P E R   C A S T L E", 13, Color("5f574d"))
	_label(content, "在纸上，选一个世界。", 32)
	_label(content, "画出造物，走进笔迹。每张地图都有独立的作品存档。", 15, Color("5f574d"))
	cards = GridContainer.new()
	cards.add_theme_constant_override("h_separation", 22)
	cards.add_theme_constant_override("v_separation", 18)
	content.add_child(cards)
	_card("medieval-v1", "01  /  INK FRONTIER", "墨线边境 · 纸上山野", "山河中世纪 · 火柴人的世界", "走过丘陵树林、山脚村庄与河边集市，跨河登上城堡山。\n六种火柴人、马车与飞龙生活在同一张纸面，宏伟城堡可以逐段砸毁。", true)
	_card("knowledge-v1", "02  /  THE NOTEBOOK", "课本漫游", "六章知识 · 保留原来的地图", "在完整诗文、公式与图形之间穿行。\n二连跳、攀墙、画建筑搭桥，沿着课本的页边探索。", false)
	if _cached_game("nature-v1") != null or _has_saved_map("nature-v1"):
		legacy_nature_button = Button.new()
		legacy_nature_button.text = "继续旧版山野作品"
		legacy_nature_button.custom_minimum_size.y = 36
		legacy_nature_button.pressed.connect(func(): start_map("nature-v1",true))
		content.add_child(legacy_nature_button)
	status = _label(content, "1–5 选择工具 · 同键确认造物 · 6 图纸 · R 使用武器 · 3 选择武器类型", 13, Color("5f574d"))
	var online := Button.new()
	online.text = "双人联机 · 创建 / 加入房间"
	online.custom_minimum_size.y = 44
	online.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/network_lobby.tscn"))
	content.add_child(online)
	var back := Button.new()
	back.text = "返回封面"
	back.custom_minimum_size.y = 44
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title_menu.tscn"))
	content.add_child(back)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/title_menu.tscn")

func _label(parent: Node, text: String, font_size: int, color: Color = Color("26231f")) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", PaperTheme.menu_font_size(font_size))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _card(id: String, eyebrow: String, title: String, subtitle: String, description: String, medieval: bool) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := PaperTheme.panel()
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	cards.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_label(column, eyebrow, 11, Color("5f574d"))
	_label(column, title, 28)
	_label(column, subtitle, 14)
	var preview := Control.new()
	preview.custom_minimum_size.y = 128
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if medieval:
		var ink_material := ShaderMaterial.new()
		ink_material.shader = preload("res://scripts/medieval_castle_ink.gdshader")
		preview.material = ink_material
	preview.draw.connect(func(): _draw_preview(preview, medieval, id == "nature-v1"))
	column.add_child(preview)
	previews.append(preview)
	_label(column, description, 14)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var new_button := Button.new()
	new_button.text = "进入新地图"
	new_button.custom_minimum_size = Vector2(110, 41)
	new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_button.pressed.connect(func(): start_map(id, false))
	actions.add_child(new_button)
	PaperTheme.primary(new_button)
	var resume := Button.new()
	resume.text = "继续游玩" if _cached_game(id) != null else "读取作品"
	resume.custom_minimum_size = Vector2(100, 41)
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.disabled = _cached_game(id) == null and not _has_saved_map(id)
	resume.pressed.connect(func(): start_map(id, true))
	actions.add_child(resume)
	continue_buttons[id] = resume

func _cached_game(id: String):
	var holder := get_tree().root.get_node_or_null("MapSessions")
	if holder != null:
		for child in holder.get_children():
			if child is PaperCastleMain and not child.is_queued_for_deletion() and child.world_kind == id: return child
		for child in holder.get_children():
			if child is PaperCastleMain and not child.is_queued_for_deletion() and child.map_workspaces.has(id): return child
		if id == "knowledge-v1":
			for child in holder.get_children():
				if child is PaperCastleMain and not child.is_queued_for_deletion() and child.world_kind == "paper": return child
	return null


func _reset_cached_map(id: String) -> void:
	var holder := get_tree().root.get_node_or_null("MapSessions")
	if holder == null: return
	for cached in holder.get_children():
		if not cached is PaperCastleMain or cached.is_queued_for_deletion(): continue
		if cached.world_kind == id:
			var other_maps: Array = cached.map_workspaces.keys().filter(func(key): return key != id)
			if other_maps.is_empty():
				cached.queue_free()
				continue
			var other_id: String = other_maps.front()
			if other_id == "paper":
				# Legacy flat works are also real workspaces; restore them in place.
				var saved: Dictionary = cached.map_workspaces[other_id]
				var snapshot: Dictionary = cached.snapshot()
				snapshot.objects = cached._clone(saved.objects)
				snapshot.world = cached._clone(saved.world)
				# Restoring the legacy world must also retain every other workspace.
				snapshot.world.maps = cached._clone(cached.map_workspaces)
				snapshot.world.maps.erase(other_id)
				snapshot.world.maps.erase(id)
				snapshot.player_position = Vector2(saved.player_x, saved.world.player_y)
				snapshot.camera_position = Vector2(saved.camera_x, saved.world.camera_y)
				cached.restore(snapshot)
			else:
				cached.change_map(other_id)
			# Switching creates a new map UI even while the scene is dormant.
			for layer in cached.find_children("*", "CanvasLayer", true, false): layer.hide()
		# An explicit new map resets only that map, never the other world or draft.
		cached.map_workspaces.erase(id)

func _has_saved_map(id: String) -> bool:
	var result := SaveStore.load_game("medieval-v1" if id == "medieval-v1" else "")
	if not result.error.is_empty(): return false
	var world: Dictionary = result.data.get("world", {"id": "paper"})
	return world.id == id or world.get("maps", {}).has(id) or (id == "knowledge-v1" and world.id == "paper")

func start_map(id: String, resume: bool = false) -> void:
	if id not in ["knowledge-v1", "medieval-v1", "nature-v1"]: return
	var tree := get_tree()
	var cached = _cached_game(id)
	if resume and cached != null:
		tree.current_scene = null
		cached.reparent(tree.root)
		cached.process_mode = Node.PROCESS_MODE_INHERIT
		cached.show()
		for node in cached.find_children("*", "CanvasLayer", true, false): node.show()
		var preferences := preload("res://scripts/preferences.gd")
		preferences.apply(get_viewport(), preferences.read())
		if cached.world_kind != id and not (id == "knowledge-v1" and cached.world_kind == "paper" and not cached.map_workspaces.has(id)): cached.change_map(id)
		tree.current_scene = cached
		queue_free()
		return
	if resume:
		var result := SaveStore.load_game("medieval-v1" if id == "medieval-v1" else "")
		if not result.error.is_empty():
			if status != null: status.text = result.error
			return
	if not resume: _reset_cached_map(id)
	var scene: PackedScene = load("res://scenes/medieval.tscn" if id == "medieval-v1" else "res://scenes/sandbox.tscn")
	var game = scene.instantiate()
	if id == "nature-v1": game.world_kind = id
	tree.current_scene = null
	tree.root.add_child(game)
	tree.current_scene = game
	if resume:
		game.load_game()
		if game.world_kind != id and not (id == "knowledge-v1" and game.world_kind == "paper"): game.change_map(id)
	queue_free()

func _layout() -> void:
	var size := PaperGuiScale.apply(self)
	var narrow := size.x < 760
	cards.columns = 1 if narrow else 2
	var width := minf(1040, size.x - (32 if narrow else 88))
	# Reduce the child minimum before sizing this uncontained scroll viewport.
	# Otherwise a desktop minimum clamps size during a narrow-window resize.
	content.custom_minimum_size.x = maxf(260, width - 14)
	scroll.reset_size()
	scroll.position = Vector2((size.x - width) * 0.5, 28 if narrow else 42)
	scroll.size = Vector2(width, size.y - scroll.position.y - 20)
	for preview in previews: preview.queue_redraw()
	queue_redraw()

func _draw() -> void:
	var size := PaperGuiScale.apply(self)
	draw_rect(Rect2(Vector2.ZERO, size), Color("f7f2e3"))
	for y in range(0, int(size.y), 26): draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.43, 0.47, 0.46, 0.12), 1)
	for x in range(0, int(size.x), 26): draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.43, 0.47, 0.46, 0.09), 1)
	draw_line(Vector2(48, 0), Vector2(48, size.y), Color(0.57, 0.31, 0.27, 0.2), 1)

func _draw_preview(control: Control, medieval: bool, nature: bool = false) -> void:
	var ink := Color("373028")
	var width := control.size.x
	var base := 116.0
	if not medieval: control.draw_line(Vector2(0, base), Vector2(width, base), ink, 1.6, true)
	if nature:
		control.draw_polyline(PackedVector2Array([Vector2(0,base),Vector2(width*.26,72),Vector2(width*.42,85),Vector2(width*.68,36),Vector2(width,base)]), ink, 1.8, true)
		for i in range(3):
			var x := width * (.16 + i*.3)
			control.draw_line(Vector2(x,100), Vector2(x,58), ink, 2, true)
			control.draw_arc(Vector2(x,51), 17, 0, TAU, 24, ink, 1.5, true)
	elif medieval:
		control.draw_polyline(PackedVector2Array([Vector2(0,base),Vector2(width*.14,98),Vector2(width*.36,98),Vector2(width*.47,120),Vector2(width*.57,120),Vector2(width*.70,70),Vector2(width*.87,70),Vector2(width,94)]),ink,1.6,true)
		control.draw_line(Vector2(width*.39,100),Vector2(width*.61,100),ink,1.5,true)
		for y in [109.0,115.0]:
			control.draw_line(Vector2(width*.44,y),Vector2(width*.56,y),Color(0.18,0.2,0.2,.5),1,true)
		_draw_medieval_asset(control, "house", Rect2(4, 14, width * 0.37, 84))
		_draw_medieval_asset(control, "castle_v2/castle_master", Rect2(width * 0.56, 0, width * 0.40, 70))
		_draw_medieval_asset(control, "dragon", Rect2(width * 0.80, 1, width * 0.20, 49))
	else:
		for i in range(3):
			var x := width * (0.04 + i * 0.32)
			var y := 95.0 - i * 28
			control.draw_line(Vector2(x, y), Vector2(x + width * 0.27, y), ink, 1.5, true)
			control.draw_string(ThemeDB.fallback_font, Vector2(x, y - 10), ["a² + b² = c²", "山河入纸", "f(x) = x²"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)

func _medieval_preview_texture(name: String) -> Texture2D:
	if preview_textures.has(name): return preview_textures[name]
	var texture: Texture2D = load("res://assets/medieval/" + name + ".png")
	var image := texture.get_image()
	var cell := Rect2i(Vector2i.ZERO, image.get_size())
	if name == "dragon": cell.size /= Vector2i(4, 2)
	var used := image.get_region(cell).get_used_rect()
	if not used.has_area(): used = cell
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(used)
	preview_textures[name] = atlas
	return atlas

func _draw_medieval_asset(control: Control, name: String, box: Rect2) -> void:
	var texture := _medieval_preview_texture(name)
	var size := texture.get_size()
	size *= minf(box.size.x / size.x, box.size.y / size.y)
	var at := box.position + Vector2((box.size.x - size.x) * 0.5, box.size.y - size.y)
	control.draw_texture_rect(texture, Rect2(at, size), false)
