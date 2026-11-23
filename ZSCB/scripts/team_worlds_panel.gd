extends Control

const Session := preload("res://scripts/world_session.gd")
const Slots := preload("res://scripts/team_worlds.gd")
var game
var board := PanelContainer.new()
var showcases := preload("res://scripts/showcase_worlds_panel.gd").new()
var showcase_button: Button
var entries := ItemList.new()
var detail := RichTextLabel.new()
var name_input := LineEdit.new()
var notice := Label.new()
var resume_button: Button
var watch_guard_button: Button
var watch_priest_button: Button
var save_button: Button
var fork_button: Button
var create_button: Button
var rename_button: Button
var night_button: Button
var pause_night: Button
var acknowledge_button: Button
var transferring := false
var import_dialog := FileDialog.new()
var cards := []
var selected := ""

func _ready() -> void:
	name = "TeamWorlds"
	theme = PaperTheme.create_menu()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.13,0.17,0.16,0.46)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	add_child(board)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation",8)
	board.add_child(contents)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",8)
	scroll.add_child(box)
	var heading := Label.new()
	heading.text = "队伍与世界存档"
	heading.add_theme_font_size_override("font_size",26)
	PaperTheme.heading(heading)
	var heading_row := HBoxContainer.new()
	contents.add_child(heading_row)
	contents.add_child(scroll)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	_button(heading_row,"选择旧档并复制",_choose_file)
	showcase_button = _button(heading_row,"试玩世界",open_showcases)
	add_child(showcases)
	showcases.visit.connect(_visit_showcase)
	showcases.back.connect(_close_showcases)
	entries.custom_minimum_size.y = 128
	entries.add_theme_stylebox_override("panel",PaperTheme.surface(Color("f3efe1"),7))
	for key in ["selected","selected_focus"]:
		entries.add_theme_stylebox_override(key,PaperTheme.surface(PaperTheme.TEAL,5))
	entries.add_theme_color_override("font_color",PaperTheme.INK)
	entries.add_theme_color_override("font_selected_color",PaperTheme.PAPER)
	entries.add_theme_font_size_override("font_size",16)
	entries.add_theme_constant_override("v_separation",4)
	entries.item_selected.connect(_select)
	entries.item_activated.connect(_activate_slot)
	box.add_child(entries)
	detail.custom_minimum_size.y = 125
	detail.add_theme_color_override("default_color",PaperTheme.INK)
	detail.add_theme_font_size_override("normal_font_size",16)
	detail.selection_enabled = true
	box.add_child(detail)
	name_input.placeholder_text = "给新队伍、分支或已有存档起名"
	name_input.max_length = 48
	box.add_child(name_input)
	var primary := HFlowContainer.new()
	box.add_child(primary)
	watch_guard_button = _button(primary,"继续并旁观战神",_resume.bind("war_god"))
	watch_priest_button = _button(primary,"继续并看牧师本人",_resume.bind("priest"))
	create_button = _button(primary,"新建队伍",_new_team)
	fork_button = _button(primary,"另存为同队分支",_fork)
	rename_button = _button(primary,"重命名所选",_rename)
	var other := HFlowContainer.new()
	box.add_child(other)
	save_button = _button(other,"保存当前队伍",_save_current)
	night_button = _button(other,"后台运行所选世界",_run_night)
	pause_night = _button(other,"暂停后台世界",_pause_night)
	acknowledge_button = _button(other,"允许未确认回合的角色继续",_acknowledge)
	_button(other,"选择 r3 村庄个人档",_choose_village)
	_button(other,"返回",hide)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size",15)
	box.add_child(notice)
	# Keep the selected world accessible while browsing the list or details.
	resume_button = _button(contents,"继续所选世界",_resume)
	PaperTheme.primary(resume_button)
	add_child(import_dialog)
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters = PackedStringArray(["*.json ; 世界存档"])
	import_dialog.title = "选取要复制的沙盒世界"
	import_dialog.file_selected.connect(import_file)
	get_viewport().size_changed.connect(_layout)
	hide()

func _button(parent: Control, title: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.add_theme_font_size_override("font_size",15)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _layout() -> void:
	size = PaperGuiScale.apply(self)
	PaperGuiScale.fit_panel(board,Vector2(780,580))
	PaperGuiScale.fit_panel(showcases,Vector2(580,325))

func open(focus_id := "") -> void:
	showcases.hide()
	board.show()
	show()
	_layout()
	var id := str(game.team_slot.get("slot_id","")) if game != null else selected
	refresh(id if focus_id.is_empty() else focus_id)
	if entries.visible:entries.grab_focus()
	else:name_input.grab_focus()
	save_button.visible = game != null
	notice.text = "切换或新建前会保存当前队伍。另存分支保留原槽上次记录。" if game != null else "选择一个世界继续，或输入名称开始新队伍。"

func refresh(focus_id: String = "") -> void:
	cards = Slots.slots()
	entries.clear()
	var index := 0
	entries.custom_minimum_size.y=clampi(cards.size()*27+12,40,128)
	for n in cards.size():
		var card: Dictionary = cards[n]
		var here: bool = game != null and game.team_slot.get("slot_id") == card.slot_id
		entries.add_item(("%s · " % "当前" if here else "") + card.name + ("　/ 分支" if card.parent_slot_id!="" else "") + "　·　第 %d 次存档" % int(card.revision))
		if card.slot_id == focus_id: index = n
	if not cards.is_empty(): entries.select(index)
	_select(index if not cards.is_empty() else -1)

func resume_from_cover(id: String) -> void:
	if game != null or transferring: return
	open(id)
	if selected == id:
		await _resume()
	else:
		notice.text = "刚才的队伍已不在列表，请重新选择。"
	if is_inside_tree() and visible:
		var scroll := notice.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible.call_deferred(notice)

func _activate_slot(index:int) -> void:
	if not board.is_visible_in_tree() or transferring or index<0 or index>=cards.size():return
	_select(index)
	_resume()

func _select(index: int) -> void:
	selected = cards[index].slot_id if index >= 0 else ""
	entries.visible = not selected.is_empty()
	detail.custom_minimum_size.y = 125 if entries.visible else 32
	var state := Session.control(selected) if not selected.is_empty() else {}
	var in_night := _can_take_background(state)
	night_button.visible = Session.available() and not selected.is_empty() and not in_night
	var own_night: bool = game != null and game.team_slot.slot_id == selected and state.get("enabled",false)
	pause_night.visible = Session.available() and (in_night or own_night)
	pause_night.text = "保存并暂停此世界" if own_night else "暂停后台世界"
	resume_button.text = "接回后台世界" if in_night else "继续所选世界"
	acknowledge_button.visible = game != null and game.team_slot.slot_id == selected and not Session.blocked.get(selected,{}).is_empty()
	resume_button.visible = not selected.is_empty()
	resume_button.disabled = selected.is_empty()
	watch_guard_button.visible = ProjectSettings.get_setting("paper/war_god_enabled",true) and index >= 0 and cards[index].get("watch_guard", false)
	watch_priest_button.visible = index >= 0 and cards[index].get("watch_priest", false)
	rename_button.visible = not selected.is_empty()
	rename_button.disabled = selected.is_empty()
	fork_button.visible = game != null or not selected.is_empty()
	fork_button.disabled = game == null and selected.is_empty()
	if selected.is_empty():
		detail.text = "还没有已保存的队伍。"
		return
	var card: Dictionary = cards[index]
	var members := PackedStringArray()
	for id in Slots.MEMBERS:
		if card.get("members", {}).has(id): members.append(Slots.MEMBERS[id])
	var lines := PackedStringArray(["队伍 %s　世界 %s" % [str(card.team_id).left(8),str(card.world_id).left(8)], "成员　" + "、".join(members)])
	for work in card.get("works",[]):
		lines.append("%s · %s　%s　#%s" % [Slots.MEMBERS.get(work.author_id,work.author_id),work.kind,work.name,str(work.work_id).right(8)])
	if lines.size()==2: lines.append("本世界尚无已记录作品")
	if in_night: lines.insert(1,"本机后台运行 · 每分钟存档，接回时保存最新现场")
	if acknowledge_button.visible:
		lines.insert(1,"上次进程退出时有未确认的模型回合，相应角色已停止发单。")
	if not str(state.get("last_error","")).is_empty(): lines.append(str(state.last_error))
	detail.text = "\n".join(lines)

func _label() -> String:
	var label := name_input.text.strip_edges()
	if label.is_empty():
		notice.text = "请先填写名称。"
		name_input.grab_focus()
	return label

func _save_current() -> bool:
	if game == null: return true
	var ok: bool = game.save_game()
	notice.text = game.toolbar.status_text
	if ok: refresh(game.team_slot.slot_id)
	return ok

func _enter(card: Dictionary, data: Dictionary = {}, follow_role := "", transfer := {}) -> void:
	var acquired := Session.claim(card.slot_id,false,transfer.get("generation",""),transfer.get("ticket",""),int(card.revision))
	if not acquired.ok:
		notice.text = acquired.get("message","队伍暂时无法打开。") + _cancel_transfer(card.slot_id,transfer)
		return
	if not data.is_empty() and transfer.is_empty():
		var latest := Slots.load_slot(card.slot_id)
		if not latest.error.is_empty():
			Session.release(card.slot_id)
			notice.text = latest.error
			return
		data = latest.data
		card = latest.card
	var tree := get_tree()
	var previous := tree.current_scene
	var next = load("res://scenes/medieval.tscn").instantiate()
	next.team_slot = card
	tree.root.add_child(next)
	if data.is_empty():
		if not next.save_game():
			notice.text = next.toolbar.status_text
			tree.root.remove_child(next)
			next.queue_free()
			return
	else:
		next.apply_team_work({"data":data,"card":card})
	next.undo_stack.clear()
	next.redo_stack.clear()
	tree.current_scene = next
	Slots.mark_played(card.slot_id)
	if not follow_role.is_empty(): _watch_order(next, follow_role)
	if previous != null:
		tree.root.remove_child(previous)
		previous.queue_free()

func _new_team() -> void:
	var label := _label()
	if label == "" or not _save_current(): return
	_enter(Slots.new_slot(label))

func open_showcases() -> void:
	if transferring: return
	if not visible: open()
	board.hide()
	showcases.open(Slots.slots())
	_layout()

func _close_showcases() -> void:
	showcases.hide()
	board.show()
	showcase_button.grab_focus()

func _visit_showcase(key: String) -> void:
	if transferring: return
	var catalog := preload("res://scripts/showcase_worlds.gd")
	var result: Dictionary = catalog.find_or_copy(key)
	if not result.ok:
		showcases.note.text = result.message
		return
	_close_showcases()
	refresh(result.card.slot_id)
	_resume("showcase/" + key)

func _watch_order(world_game, role: String) -> void:
	if role.begins_with("showcase/"):
		preload("res://scripts/showcase_worlds.gd").watch(world_game, role.trim_prefix("showcase/"))
		return
	var actors := preload("res://scripts/divine_roles.gd").NODES
	if not actors.has(role) or not world_game.medieval_world.has_node(actors[role]): return
	world_game.open_divine_status()
	world_game.divine_panel.watch(role, "", role == "priest")

func is_background_world(id: String) -> bool:
	return _can_take_background(Session.control(id))

func _can_take_background(state: Dictionary) -> bool:
	return state.get("desired") == "background" or state.get("owner",{}).get("kind") == "background" or not state.get("transfer",{}).is_empty()

func _resume(follow_role := "") -> void:
	var id := selected
	if id.is_empty() or transferring: return
	if game != null and id == game.team_slot.slot_id:
		hide()
		if not follow_role.is_empty(): _watch_order(game, follow_role)
		return
	var control := Session.control(id)
	var in_handoff := _can_take_background(control)
	if in_handoff:
		# Full read through this build's normal validator, while the producer still owns the world.
		var preliminary := Slots.load_slot(id)
		if not preliminary.error.is_empty():
			notice.text = "当前版本无法读取这份队伍存档。请从新版「打开纸间」接回。后台继续运行。\n" + str(preliminary.error)
			return
	if not _save_current(): return
	var transfer := {}
	if in_handoff:
		transferring = true
		var taken := Session.run("take",id,["--generation",str(control.get("generation",""))])
		if not taken.ok:
			transferring = false
			notice.text = taken.message
			return
		transfer = taken
		notice.text = "正在等待后台世界保存最后的现场…"
		while is_inside_tree():
			var state := Session.run("status",id)
			if not state.ok or state.get("desired") != "foreground" or state.get("transfer",{}).get("ticket") != taken.ticket or selected != id or not visible:
				transferring = false
				notice.text = "队伍选择或后台状态已改变。" + _cancel_transfer(id,transfer)
				return
			if state.get("owner",{}).get("kind") != "background": break
			await get_tree().create_timer(.3).timeout
		transferring = false
	var loaded := Slots.load_slot(id)
	if not loaded.error.is_empty():
		notice.text = ("最后保存的现场需要支持它的版本，请重新打开新版「纸间」。" + _cancel_transfer(id,transfer) + "\n" if not transfer.is_empty() else "") + str(loaded.error)
		return
	_enter(loaded.card,loaded.data,follow_role,transfer)

func _cancel_transfer(id: String, transfer: Dictionary) -> String:
	if transfer.is_empty(): return ""
	var result := Session.run("cancel-take",id,["--generation",transfer.generation,"--ticket",transfer.ticket])
	return "原后台将从最后一次保存继续运行。" if result.ok else "请在队伍列表查看当前接管或暂停状态。"

func _run_night() -> void:
	if selected.is_empty() or transferring: return
	if game != null and game.team_slot.slot_id == selected:
		game.hand_over_world()
		return
	var started := Session.start_background(selected)
	notice.text = "本机已接手，关闭窗口后世界继续运行。" if started.ok else started.get("message","无法启动。")
	refresh(selected)

func _pause_night() -> void:
	if selected.is_empty(): return
	if game != null and game.team_slot.slot_id == selected:
		if not _save_current(): return
		var own_stop := Session.run("pause",selected)
		if not own_stop.ok:
			notice.text = own_stop.get("message","无法暂停。")
			return
		get_tree().change_scene_to_file("res://scenes/title_menu.tscn")
		return
	var stopped := Session.run("pause",selected)
	notice.text = "已要求后台保存并暂停。" if stopped.ok else stopped.get("message","无法暂停。")
	refresh(selected)

func _acknowledge() -> void:
	if game != null and game.team_slot.slot_id == selected:
		Session.acknowledge(selected)
		notice.text = "已允许相关角色开始新的回合。"
		refresh(selected)

func _fork() -> void:
	var label := _label()
	if label.is_empty(): return
	var captured: Dictionary
	var parent: Dictionary
	if game != null:
		if int(game.team_slot.revision)==0 and not _save_current(): return
		parent = game.team_slot
		captured = game.capture_team_work()
	else:
		var old := Slots.load_slot(selected)
		if old.error != "": notice.text = old.error; return
		parent = old.card
		var d: Dictionary = old.data
		captured = SaveStore.encode_work(d.paper,d.objects,d.bag,d.cameraX,d.playerX,d.equipped_weapon,d.world)
	if not captured.ok: notice.text = captured.message; return
	var saved := Slots.commit(Slots.new_slot(label,parent),captured.data)
	if not saved.ok: notice.text = saved.message; return
	var loaded := Slots.load_slot(saved.card.slot_id)
	if loaded.error != "": notice.text = loaded.error; return
	_enter(loaded.card,loaded.data)

func _rename() -> void:
	var label := _label()
	if label.is_empty() or selected.is_empty(): return
	var old := Slots.load_slot(selected)
	if old.error != "": notice.text = old.error; return
	var d: Dictionary = old.data
	var same: bool = game != null and game.team_slot.slot_id == selected
	var card: Dictionary = (game.team_slot if same else old.card).duplicate()
	card.name = label
	var saved: Dictionary
	if same:
		saved = game.save_team_as(card)
	else:
		var data := SaveStore.encode_work(d.paper,d.objects,d.bag,d.cameraX,d.playerX,d.equipped_weapon,d.world)
		if not data.ok: notice.text = data.message; return
		saved = Slots.commit(card,data.data)
	if saved.ok:
		if same: game.team_slot = saved.card
		refresh(selected)
	notice.text = saved.message

func _choose_file() -> void:
	import_dialog.current_dir = OS.get_user_data_dir() if FileAccess.file_exists(SaveStore.MEDIEVAL_SAVE_PATH) else OS.get_user_data_dir().get_base_dir()
	import_dialog.current_file = "paper_castle_medieval_v1.json"
	import_dialog.popup_centered_ratio(0.8)

func _choose_village() -> void:
	var profile := OS.get_user_data_dir().get_base_dir().path_join("ZhijianGrove_guild_ac29165c1418")
	import_dialog.current_dir = profile if DirAccess.dir_exists_absolute(profile) else OS.get_user_data_dir().get_base_dir()
	import_dialog.current_file = "paper_castle_medieval_v1.json"
	notice.text = "请选择你实际游玩的 r3 资料目录里的世界 JSON；确认后复制为新队伍。"
	import_dialog.popup_centered_ratio(.8)

func import_file(path: String) -> void:
	var label := name_input.text.strip_edges()
	if label == "": label = "旧档副本 · "+path.get_base_dir().get_file().left(24)
	var result := Slots.import_copy(path,label)
	notice.text = result.message
	if result.ok:
		refresh(result.card.slot_id)
		notice.text = "已复制为「%s」，可选择继续。原文件保留在 %s" % [label,path]

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel") and not import_dialog.visible:
		get_viewport().set_input_as_handled()
		if showcases.visible: _close_showcases()
		else: hide()
