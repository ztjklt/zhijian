extends Control

var team_panel: Control
var content: VBoxContainer
var cards: GridContainer
var status: Label
var scroll: ScrollContainer
var continue_buttons: Dictionary = {}
var previews: Array[Control] = []
var preview_textures: Dictionary = {}
var legacy_nature_button: Button

var mode_buttons: Dictionary = {}
var brand: Label
var heading: Label
var tagline: Label
var back_button: Button
var landscape_guard: PaperLandscapeGuard

func _ready() -> void:
	get_window().title = "纸间 · 选择模式"
	get_window().content_scale_size = Vector2i.ZERO
	theme = PaperTheme.create_menu()
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",12)
	scroll.add_child(content)
	brand = _label(content,"纸 间   /   PLAY",13,Color("708174"))
	heading = _label(content,"选一种，开始。",34)
	tagline = _label(content,"把想象画成世界，或与朋友一决高下。",15,Color("65746a"))
	cards = GridContainer.new()
	cards.columns = 2
	cards.add_theme_constant_override("h_separation",16)
	content.add_child(cards)
	_portal("sandbox","沙盒模式","纸上山野 · 自由创造","进入沙盒","01",Color("376f65"),"res://assets/ui/modes/sandbox.png",func(): start_map("medieval-v1"))
	_portal("duel","双人对战","课本世界 · 好友同场","邀请朋友","02",Color("9b6151"),"res://assets/ui/modes/duel.png",open_duel)
	team_panel = preload("res://scripts/team_worlds_panel.gd").new()
	add_child(team_panel)
	var continuations := HFlowContainer.new()
	continuations.alignment = FlowContainer.ALIGNMENT_CENTER
	content.add_child(continuations)
	var teams := PaperSealButton.new()
	teams.text = "队伍与世界存档"
	teams.pressed.connect(team_panel.open)
	continuations.add_child(teams)
	for id in ["medieval-v1","knowledge-v1"]:
		var resume := PaperSealButton.new()
		resume.text = "继续沙盒作品" if id == "medieval-v1" else "继续旧课本作品"
		resume.custom_minimum_size = Vector2(150,44)
		resume.disabled = _cached_game(id) == null and not _has_saved_map(id)
		resume.visible = not resume.disabled
		resume.pressed.connect(func(): start_map(id,true))
		continuations.add_child(resume)
		continue_buttons[id] = resume
	if _cached_game("nature-v1") != null or _has_saved_map("nature-v1"):
		legacy_nature_button = PaperSealButton.new()
		legacy_nature_button.text = "继续旧版山野作品"
		legacy_nature_button.custom_minimum_size = Vector2(170,44)
		legacy_nature_button.pressed.connect(func(): start_map("nature-v1",true))
		continuations.add_child(legacy_nature_button)
	continuations.visible = continuations.get_children().any(func(node): return node.visible)
	status = _label(content,"沙盒随心画 · 对战与朋友共用一张纸",13,Color("708174"))
	back_button = PaperSealButton.new()
	back_button.text = "返回封面"
	back_button.custom_minimum_size = Vector2(136,44)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func(): get_tree().change_scene_to_file.call_deferred("res://scenes/title_menu.tscn"))
	content.add_child(back_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	mode_buttons.sandbox.grab_focus()
	landscape_guard = PaperLandscapeGuard.install(self)

func open_duel() -> void:
	get_tree().set_meta("paper_entry_map","knowledge-v1")
	get_tree().change_scene_to_file.call_deferred("res://scenes/network_lobby.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if team_panel != null and team_panel.visible: return
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file.call_deferred("res://scenes/title_menu.tscn")

func _label(parent: Node,value: String,font_size: int,ink: Color = Color("283d35")) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",ink)
	parent.add_child(label)
	return label

func _portal(id: String,title: String,detail: String,action: String,number: String,accent: Color,art: String,callback: Callable) -> void:
	var portal := PaperModePortal.new()
	portal.heading = title; portal.detail = detail; portal.action_label = action
	portal.number = number; portal.accent = accent
	portal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ResourceLoader.exists(art): portal.artwork = load(art)
	portal.pressed.connect(callback)
	portal.tooltip_text = title + " · " + detail
	cards.add_child(portal)
	mode_buttons[id] = portal

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
	if id == "medieval-v1" and not preload("res://scripts/team_worlds.gd").slots().is_empty(): return true
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
	if resume and id == "medieval-v1" and not ProjectSettings.get_setting("paper/divine_demo",false):
		team_panel.open()
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
	var viewport := PaperGuiScale.apply(self)
	var bounds := PaperGuiScale.safe_rect(self)
	var short := bounds.size.y < 500
	var width := minf(960,bounds.size.x-24)
	brand.visible = not short
	tagline.visible = not short
	status.visible = not short
	heading.add_theme_font_size_override("font_size",24 if short else 30 if bounds.size.x < 600 else 38)
	cards.add_theme_constant_override("h_separation",12 if bounds.size.x < 600 else 28)
	for portal in mode_buttons.values():
		portal.custom_minimum_size = Vector2(0, maxf(170,bounds.size.y-120) if short else minf(420 if bounds.size.x > 760 else 340,maxf(250,bounds.size.y-260)))
		portal.queue_redraw()
	content.custom_minimum_size.x = width-12
	scroll.reset_size()
	scroll.position = bounds.position+Vector2((bounds.size.x-width)*.5,8 if short else 24)
	scroll.size = Vector2(width,bounds.size.y-(16 if short else 48))
	queue_redraw()

func _draw() -> void:
	var viewport := PaperGuiScale.logical_size(self)
	PaperUIArt.background(self,viewport,true)
	# Wide quiet margins, a few dotted registration marks instead of a grid.
	for x in [24.0,viewport.x-24]:
		for y in range(28,int(viewport.y),28): draw_circle(Vector2(x,y),.65,Color(.26,.37,.30,.12))
