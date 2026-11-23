extends Control
## The existing manuscript runs in its own physics world. Only the saved painter
## receives a turn. The foreground team and its in-flight state stay on their scene.
signal closed
signal play_street

const Worlds := preload("res://scripts/showcase_worlds.gd")
const Lantern := preload("res://scripts/showcase_lantern_replay.gd")
var street: Lantern
var play_button: Button

var world_view := SubViewport.new()
var status := Label.new()
var exit_button := Button.new()
var layer := CanvasLayer.new()
var previous: Node
var previous_mode: ProcessMode
var previous_title := ""
const Session := preload("res://scripts/world_session.gd")
var preview_id := ""
var game
var painter

func open(host: Node, return_to_game: bool, lantern := false) -> void:
	previous = host
	previous_title = host.get_window().title
	previous_mode = host.process_mode
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	layer.add_child(self)
	host.process_mode = Node.PROCESS_MODE_DISABLED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = PaperTheme.create_menu()
	mouse_filter = Control.MOUSE_FILTER_STOP
	world_view.world_2d = World2D.new()
	world_view.gui_disable_input = true
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_view.size = Vector2i(size).max(Vector2i(2,2))
	add_child(world_view)
	var picture := TextureRect.new()
	picture.texture = world_view.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	add_child(card)
	var row := HBoxContainer.new()
	card.add_child(row)
	if lantern: card.add_theme_stylebox_override("panel",PaperTheme.surface(PaperTheme.PAPER,8))
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(caption)
	var title := Label.new()
	title.text = "阿靛建灯铺 · 官方母图重演" if lantern else "阿靛续岸 · 柳湾浅渡"
	PaperTheme.heading(title)
	title.add_theme_font_size_override("font_size",21)
	caption.add_child(title)
	status.text = "正在展开已生成笔稿"
	status.add_theme_font_size_override("font_size",15)
	caption.add_child(status)
	exit_button.add_theme_color_override("font_focus_color",PaperTheme.INK)
	exit_button.text = "回到原现场" if return_to_game else "回到试玩册"
	exit_button.pressed.connect(close)
	if lantern:
		play_button = Button.new()
		var prior := Worlds.lookup(Worlds.LANTERN, Worlds.Slots.slots())
		play_button.text = "到灯柜试玩" if prior.is_empty() else "继续灯铺试玩"
		play_button.add_theme_color_override("font_focus_color",PaperTheme.INK)
		play_button.pressed.connect(_play_lantern)
		row.add_child(play_button)
		play_button.hide()
	row.add_child(exit_button)
	resized.connect(func():
		world_view.size = Vector2i(size).max(Vector2i(2,2))
		_layout(card))
	_layout(card)
	exit_button.grab_focus()
	var path := "res://assets/showcase_worlds/lantern_manuscript.json" if lantern else "res://assets/manuscripts/companion.json"
	var seed := SaveStore.read_work(path,"medieval-v1")
	if seed.error!="":
		status.text = "原笔稿未能打开"
		return
	game = load("res://scenes/medieval.tscn").instantiate()
	game.manuscript_preview = true
	# A scoped identity permits original world tools while keeping this replay off the roster.
	game.team_slot = preload("res://scripts/team_worlds.gd").new_slot("纸灯小铺原稿" if lantern else "柳湾浅渡原稿")
	preview_id = game.team_slot.slot_id
	Session.draining[preview_id] = true
	world_view.add_child(game)
	if not game.apply_team_work(seed):
		status.text = "原笔稿未能恢复"
		return
	game.open_divine_status()
	game.divine_panel.close()
	for canvas in game.find_children("*","CanvasLayer",true,false):canvas.hide()
	# Some old saves lack the newer residents. Pause their normal schedulers too.
	for actor_name in ["SandboxCompanion","SandboxPriest","SandboxWarGod","SandboxAdventurer"]:
		var actor = game.medieval_world.get_node_or_null(actor_name)
		if actor != null:actor.set_autonomy_paused(true)
	painter = game.medieval_world.get_node("SandboxCompanion")
	if lantern:
		street = Lantern.new()
		game.character_visual.hide()
		street.start(game,painter)

func _play_lantern() -> void:
	if street == null or street.stage != "done": return
	var result := Worlds.keep_lantern(game)
	if not result.ok:
		street.message = result.message
		return
	close()
	play_street.emit()

func _layout(card: PanelContainer) -> void:
	var width := minf(size.x - 16, 560 if play_button != null else 490)
	card.size = Vector2(width,0)
	card.position = Vector2((size.x - width)/2,8)

func _process(_delta: float) -> void:
	if not is_instance_valid(painter) or not is_instance_valid(painter.actor):return
	var feet: Vector2 = painter.observation_target()
	if not feet.is_finite():return
	if street != null:
		status.text = street.message
		play_button.visible = street.stage == "done"
		game.divine_panel._camera_at(feet.lerp(Lantern.ORIGIN,.18) + Vector2(0,.68))
		return
	var target: Dictionary = game.medieval_world.east_work_target(0)
	var at := feet
	if not target.is_empty():
		if target.get("from") is Vector2:at=feet.lerp(target.from,.35)
		if target.get("phase")=="ground":
			status.text="已生成笔稿 · 观看免费　正在沿地面接坡"
		else:
			status.text="已生成笔稿 · 观看免费　河柳第 %d 笔" % (int(target.get("stroke",0))+1)
	else:
		status.text="已收笔 · 阿靛正在试走新岸" if painter.phase=="walk" else "已收笔 · 新岸留在这份原稿里"
	game.divine_panel._camera_at(at)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if is_queued_for_deletion() or layer.is_queued_for_deletion():return
	previous.process_mode = previous_mode
	get_window().title = previous_title
	layer.hide()
	layer.process_mode = Node.PROCESS_MODE_DISABLED
	layer.queue_free()
	closed.emit()

func _exit_tree() -> void:
	if not preview_id.is_empty():Session.draining.erase(preview_id)
