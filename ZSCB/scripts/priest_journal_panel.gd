extends VBoxContainer

enum Page { BLUEPRINTS, ANIMALS, MEMORY, COMMITMENTS }

const TOOL_LABELS := {"ink_species":"绘制生物", "revise_species":"改绘生物", "file_species":"保存物种图纸"}

var host
var tabs: Array[Button] = []
var page := Page.BLUEPRINTS
var scroll := ScrollContainer.new()
var content := VBoxContainer.new()
var previous: Array = []
var sheet_id := ""
var world_id := ""
var observed_labels: Dictionary = {}

class BlueprintArt extends Node2D:
	var form
	var PIXELS_PER_UNIT := 60.0
	var centre := Vector2.ZERO
	var pose := "rest"
	var phase := 0.0
	var preview_box := Rect2()
	
	func change_pose(value: String) -> void:
		pose = value
		phase = 0.0
		# Reserve a single camera across the sampled cycle, including rotated wingtips.
		preview_box = form.body_bounds
		preview_box.position.y -= form.foot_offset
		for i in 16:
			for polygon in form.world_parts(Vector2.ZERO,0,1,i*TAU/16.0,pose,i/16.0):
				for pt in polygon: preview_box = preview_box.expand(pt)
		queue_redraw()

	func _process(delta: float) -> void:
		if pose=="rest" or not is_visible_in_tree():return
		phase=fmod(phase+delta*3.4,TAU)
		queue_redraw()

	func world_to_screen(point: Vector2) -> Vector2:
		return centre + Vector2(point.x, -point.y) * PIXELS_PER_UNIT

	func _draw() -> void:
		var area: Vector2 = get_parent().size
		var bounds: Rect2 = preview_box
		PIXELS_PER_UNIT = minf((area.x - 16) / maxf(.1, bounds.size.x), (area.y - 12) / maxf(.1, bounds.size.y))
		var rest := bounds.get_center()
		centre = area * .5 - Vector2(rest.x, -rest.y) * PIXELS_PER_UNIT
		form.paint(self, self, Vector2.ZERO, 0.0, 1, "", phase, pose, phase/TAU, INF)


func _ready() -> void:
	name = "PriestJournal"
	var nav := HFlowContainer.new()
	add_child(nav)
	var group := ButtonGroup.new()
	for title: String in ["物种图纸", "本局生物", "近期手记", "长期决定"]:
		var button: Button = host._button(nav, title, select_page.bind(tabs.size()))
		button.toggle_mode = true
		button.button_group = group
		tabs.append(button)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 7)
	scroll.add_child(content)
	var footer := HFlowContainer.new()
	add_child(footer)
	host._button(footer, "与牧师交谈", host.open_chat.bind("priest"))
	host._button(footer, "返回状态", host.open)

func open() -> void:
	var current: String = host.game.team_slot.get("world_id", "")
	if current != world_id:
		world_id = current
		sheet_id = ""
		page = Page.BLUEPRINTS
	select_page(page)

func select_page(index: int) -> void:
	page = index
	tabs[index].set_pressed_no_signal(true)
	tabs[index].grab_focus()
	scroll.scroll_vertical = 0
	previous.clear()
	refresh()

func animal_label(animal) -> String:
	var phase: String = animal.phase
	var action: String = animal.action_label()
	if phase == "drawing": action = "正在运笔"
	if phase == "dead": action = "已死亡"
	return "%s　·　%s" % [str(animal.design.name), action]

func _traits(design: Dictionary) -> String:
	var details := PackedStringArray(["%d 个部件" % design.get("parts", []).size()])
	var names := {"avoid_people":"近人退避","eat_ground_fruit":"拾食地面朱果","graze_bark":"采食树皮", "flee":"避开天敌", "hunt_livestock":"捕食牲畜", "threaten_people":"会攻击村民", "graze_grass":"吃草", "fly":"飞行", "guard_food":"护食"}
	for action in design.get("actions", []):
		if names.has(action): details.append(names[action])
	return " · ".join(details)

func _rows(priest: Node) -> Array:
	var rows := []
	if priest == null: return [{"text":"牧师尚未入场。"}]
	match page:
		Page.BLUEPRINTS:
			for plan in priest.blueprints:
				var chosen: bool = plan.blueprint_id == sheet_id or (sheet_id.is_empty() and rows.is_empty())
				rows.append({"text":str(plan.name)+(" · 另存改稿" if plan.get("archived_revision",false) else ""), "traits":_traits(plan.design), "id":str(plan.blueprint_id), "sheet":plan.design if chosen else {}, "reason":str(plan.get("reason","")) if chosen else ""})
			if rows.is_empty(): rows.append({"text":"牧师还没有保存物种图纸。"})
		Page.ANIMALS:
			for animal in priest.works:
				rows.append({"text":str(animal.design.name), "id":str(animal.work_id), "blueprint_id":str(animal.blueprint_id), "editable":animal.phase not in ["drawing","dead"]})
			if rows.is_empty(): rows.append({"text":"本世界尚无牧师画出的生物。"})
		Page.MEMORY:
			for i in range(priest.memory.size() - 1, -1, -1):
				var entry: Dictionary = priest.memory[i]
				var activity := str(entry.get("action",""))
				var lines := PackedStringArray([str(TOOL_LABELS.get(activity, activity))])
				for key: String in ["reason", "result"]:
					var words := str(entry.get(key, "")).strip_edges()
					if not words.is_empty():
						lines.append(("缘由　" if key == "reason" else "结果　") + words)
				var row := {"text":"\n".join(lines)}
				var work_id := str(entry.get("work_id",""))
				if priest.work_by_id(work_id) != null: row.id = work_id
				rows.append(row)
			if rows.is_empty(): rows.append({"text":"牧师在这支队伍还没有留下手记。"})
		Page.COMMITMENTS:
			for i in range(priest.commitments.size() - 1, -1, -1):
				var note: Dictionary = priest.commitments[i]
				var words := PackedStringArray([str(note.topic), "打算　" + str(note.intent), "复查条件　" + str(note.review_when)])
				words.append("复查结果　"+str(note.outcome) if not str(note.outcome).is_empty() else "待复查")
				var row := {"text":"\n".join(words), "blueprint_id":note.get("blueprint_id","")}
				if priest.work_by_id(str(note.work_id)) != null: row.id = note.work_id
				rows.append(row)
			if rows.is_empty(): rows.append({"text":"牧师尚未记下需要长期复查的决定。"})
	return rows

func refresh() -> void:
	var rows := _rows(host._actor("priest"))
	if rows == previous:
		_refresh_animals(host._actor("priest"))
		return
	observed_labels.clear()
	previous = rows
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for i in rows.size():
		if i > 0: content.add_child(HSeparator.new())
		var entry: Dictionary = rows[i]
		host._label(content, entry.text, 17, PaperTheme.INK, true)
		if entry.has("traits"): host._label(content, entry.traits, 15, PaperTheme.MENU_MUTED, true)
		if not entry.has("id") and str(entry.get("blueprint_id","")).is_empty(): continue
		var line := HFlowContainer.new()
		content.add_child(line)
		if page == Page.ANIMALS:
			var animal = host._actor("priest").work_by_id(entry.id)
			observed_labels[entry.id] = host._label(content, "", 15, PaperTheme.MENU_MUTED, true)
			if animal and animal.design.has("parts") and animal.phase not in ["dead","drawing"]:
				var parts := OptionButton.new()
				for piece in animal.design.parts:parts.add_item(piece.id)
				line.add_child(parts)
				host._button(line,"起草单件改绘",_edit_part.bind(entry.id,parts))
		if page != Page.BLUEPRINTS:
			if entry.has("id"): host._button(line, "去现场", host.watch.bind("priest", entry.id))
			if not str(entry.get("blueprint_id", "")).is_empty():
				host._button(line, "看原图", show_sheet.bind(entry.blueprint_id))
		else:
			if entry.sheet.is_empty():
				host._button(line, "看原图", show_sheet.bind(entry.id))
			host._button(line, "起草复用委托", _request_blueprint.bind(entry.text, entry.id))
		var id := str(entry.get("id", entry.get("blueprint_id","")))
		var identity: Label = host._label(line, "#" + id.right(8), 14, PaperTheme.MENU_MUTED)
		identity.tooltip_text = id
		if entry.has("sheet") and not entry.sheet.is_empty():
			var shapes:=PackedStringArray()
			for piece in entry.sheet.parts:
				var shape:=str(piece.get("study",""))
				if shape!="" and shape not in shapes:shapes.append(shape)
			if not shapes.is_empty():
				var origin:Label=host._label(content,"湿岸取形 · %d 件独立轮廓"%shapes.size(),14,PaperTheme.MENU_MUTED,true)
				origin.tooltip_text="、".join(shapes)
			var frame := Control.new()
			frame.custom_minimum_size.y = 108
			frame.clip_contents = true
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(frame)
			var art := BlueprintArt.new()
			art.form = preload("res://scripts/ink_life_form.gd").new(entry.sheet)
			frame.add_child(art)
			frame.resized.connect(art.queue_redraw)
			art.change_pose("rest")
			var strip := HFlowContainer.new()
			content.add_child(strip)
			for key in ["rest","walk","fly","eat","pickup","flee"]:
				if key=="pickup" and not "eat_ground_fruit" in entry.sheet.actions:continue
				if key=="flee" and not ("avoid_people" in entry.sheet.actions or "flee" in entry.sheet.actions):continue
				if key=="fly" and "fly" not in entry.sheet.actions:continue
				if key=="walk" and "ground_walk" not in entry.sheet.actions:continue
				if key=="eat" and not entry.sheet.parts.any(func(p):return p.motion=="jaw"):continue
				host._button(strip,{"rest":"立姿","walk":"看步态","fly":"看翼相","eat":"看咬合","pickup":"看低头拾果","flee":"看逃步"}[key],art.change_pose.bind(key))
		if not str(entry.get("reason","")).is_empty():
			host._label(content, "缘由　" + str(entry.reason), 15, PaperTheme.MENU_MUTED, true)
		if page == Page.BLUEPRINTS and entry.id == sheet_id:
			scroll.ensure_control_visible.call_deferred(line)

	_refresh_animals(host._actor("priest"))

func _refresh_animals(priest) -> void:
	if not priest:return
	for id in observed_labels:
		var animal=priest.work_by_id(id)
		if animal==null:continue
		var facts:=PackedStringArray([
			animal_label(animal).get_slice("　·　",1),
			"脚点（%.1f，%.1f）米" % [animal.beast_x, animal.beast_y],
			"饱食 %d" % roundi(animal.satiety)])
		var actions:Array=animal.design.get("actions",[])
		if "graze_grass" in actions or animal.grass_meals>0:
			facts.append("自行采草 %d 次" % animal.grass_meals)
		if "eat_ground_fruit" in actions or animal.fruit_meals>0:
			facts.append("拾食落果 %d 次" % animal.fruit_meals)
		if animal.delivered_meals>0:
			facts.append("接受递草 %d 次" % animal.delivered_meals)
		if "graze_bark" in actions or not animal.eaten.is_empty():
			var bites:=0
			for count in animal.eaten.values():bites+=int(count)
			facts.append("啃树皮 %d 次" % bites)
		if "fly" in actions or animal.takeoffs>0 or animal.landings>0:
			facts.append("起飞 %d 次 · 落地 %d 次" % [animal.takeoffs, animal.landings])
		observed_labels[id].text="　".join(facts)

func _edit_part(id:String, parts:OptionButton) -> void:
	var part_id:=parts.get_item_text(parts.selected)
	var animal=host._actor("priest").work_by_id(id)
	if animal:
		_draft("请只改「%s」这只个体（%s）的 %s 部件，其余笔稿和习性照旧。我的改法是：" % [animal.design.name,id,part_id])

func show_sheet(id: String) -> void:
	sheet_id = id
	select_page(Page.BLUEPRINTS)

func _request_blueprint(title: String, id: String) -> void:
	_draft("请照「%s」这份物种图纸（%s）再画一只。" % [title, id])

func _draft(words:String) -> void:
	host.open_chat("priest")
	var editor: TextEdit = host.chat_panel.editor
	editor.set_caret_line(editor.get_line_count() - 1)
	editor.set_caret_column(editor.get_line(editor.get_caret_line()).length())
	editor.insert_text_at_caret(("" if editor.text.is_empty() else "\n") + words)
	editor.grab_focus()
