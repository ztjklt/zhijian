extends Control

signal closed(placed:bool)
const Sheet:=preload("res://scripts/distant_sheet.gd")
const Pen:=preload("res://scripts/paper_world_pen.gd")
const Palette:=preload("res://scripts/pen_palette.gd")
var game
var sheet:Dictionary
var strokes:Array=[]
var all_strokes:Array=[]
var selector:=HBoxContainer.new()
var numbers:=LineEdit.new()
var start:=Vector2.INF
var end:=Vector2.INF
var dragging:=false
var status:=Label.new()
var confirm:=Button.new()
var identity:=""
var page_id:=""
var reframe := false
var lock_size := false
var frame_size: Array = []
var drag_from := Vector2.ZERO
var original_box := Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	theme=PaperTheme.create()
	identity=game.team_slot.world_id
	page_id=Crypto.new().generate_random_bytes(12).hex_encode()
	var bar:=PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_stylebox_override("panel",PaperTheme.panel())
	add_child(bar)
	var column:=VBoxContainer.new()
	bar.add_child(column)
	var row:=HBoxContainer.new()
	column.add_child(row)
	status.text="在现场拖出画幅，预览后落笔。远景不承重。"
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(status)
	var choose:=Button.new()
	choose.text="锁定尺寸" if reframe else "取笔"
	choose.toggle_mode = reframe
	row.add_child(choose)
	if reframe:
		choose.toggled.connect(func(locked): lock_size = locked)
	else:
		choose.pressed.connect(func():selector.visible=not selector.visible)
	confirm.text="落笔"
	confirm.disabled=true
	row.add_child(confirm)
	confirm.pressed.connect(_commit)
	var cancel:=Button.new()
	cancel.text="返回图页"
	row.add_child(cancel)
	cancel.pressed.connect(_dismiss.bind(false))
	column.add_child(selector)
	selector.hide()
	numbers.placeholder_text="原笔号，如 1,3,7-9；留空取整页"
	numbers.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	selector.add_child(numbers)
	var apply:=Button.new()
	apply.text="应用笔号"
	selector.add_child(apply)
	apply.pressed.connect(_select_strokes)
	numbers.text_submitted.connect(func(_text):_select_strokes())
	var paths:Array=sheet.recipe.strokes
	var bounds:=Rect2()
	var first:=true
	for stroke:Dictionary in paths:
		for point in stroke.points:
			var p:=Pen.point(point)
			bounds=Rect2(p,Vector2.ZERO) if first else bounds.expand(p)
			first=false
	for i in paths.size():
		var line:Dictionary=paths[i]
		var mark:={"points":[],"brush":line.get("brush","fine"),"pigment":line.get("pigment","inherit"),"source_work_id":sheet.entry.work_id,"source_stroke":i}
		for point in line.points:
			var p:=Pen.point(point)-bounds.position
			if sheet.entry.format=="distant":
				mark.points.append(point.duplicate())
			else:
				mark.points.append([clampf(p.x/bounds.size.x,0,1) if bounds.size.x>0 else .5,clampf(p.y/bounds.size.y,0,1) if bounds.size.y>0 else .5])
		all_strokes.append(mark)
	strokes=all_strokes.duplicate()
	if reframe:
		start = Pen.point(sheet.recipe.origin)
		frame_size = sheet.recipe.size.duplicate()
		end = start + Pen.point(frame_size)
		confirm.text = "确认改位"
		status.text = "拖出新的画幅，保留原笔和署名。"

func _select_strokes() -> void:
	var indices:Dictionary={}
	var input:=numbers.text.strip_edges().replace("，",",")
	if not input.is_empty():
		for item in input.split(","):
			var limits:=item.strip_edges().split("-")
			if limits.size()>2 or not limits[0].is_valid_int() or not limits[-1].is_valid_int():
				status.text="请输入原笔号或范围，如 1,3,7-9。";return
			var first:=int(limits[0])
			var last:=int(limits[-1])
			if first<1 or last>all_strokes.size() or first>last:
				status.text="这页的原笔号是 1 至 %d。" % all_strokes.size();return
			for i in range(first-1,last):indices[i]=true
	var selected:Array=[]
	for i in all_strokes.size():
		if input.is_empty() or indices.has(i):selected.append(all_strokes[i])
	strokes=selected
	selector.hide()
	status.text="已取 %d 笔，拖出画幅。" % strokes.size()
	if _box_ready():_review()
	queue_redraw()

func _box_ready() -> bool:
	return start.is_finite() and end.is_finite() and _box().has_area()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_dismiss(false)

func _drag_to(pos: Vector2) -> void:
	if reframe and lock_size:
		start = original_box.position + pos - drag_from
		end = start + Pen.point(frame_size)
	else:
		end = pos
		if reframe:
			var extent := _box().size
			frame_size = [extent.x, extent.y]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_from=game.screen_to_world(event.position)
			original_box=_box() if reframe else Rect2()
			if not (reframe and lock_size):
				start=drag_from
				end=start
			dragging=true
			confirm.disabled=true
		elif dragging:
			dragging=false
			_drag_to(game.screen_to_world(event.position))
			_review()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		_drag_to(game.screen_to_world(event.position))
		accept_event()
	queue_redraw()

func _process(_dt:float) -> void:
	if game.team_slot.get("world_id")!=identity:
		_dismiss(false)
	elif start.is_finite():
		queue_redraw()

func _box() -> Rect2:
	return Rect2(start,end-start).abs()

func _prepare() -> Dictionary:
	var box:=_box()
	return Sheet.prepare(game,"player",{"sheet_id":page_id,"name":str(sheet.entry.name).left(48)+" · 远景","origin":[box.position.x,box.position.y],"size":[box.size.x,box.size.y],"strokes":strokes})

func _reframe(commit: bool) -> Dictionary:
	var box := _box()
	var spec: Dictionary = sheet.entry.duplicate()
	spec.merge({"request_id":page_id, "expected_revision":sheet.recipe.revision,
		"origin":[box.position.x,box.position.y], "size":frame_size.duplicate()})
	return Sheet.reframe(game, "player", spec, commit)

func _review() -> void:
	if reframe:
		var result := _reframe(false)
		confirm.disabled = not result.ok
		status.text = "原作画幅 %.1f × %.1f 米 · 移位不耗墨" % [_box().size.x,_box().size.y] if result.ok else result.error
		return
	var compiled:=_prepare()
	if compiled.ok:
		compiled=Pen.submit(game,compiled.records,"player",false)
	confirm.disabled=not compiled.ok
	if not compiled.ok:status.text=compiled.error
	else:
		var box:=_box()
		status.text="%.1f × %.1f 米 · %d 笔 · 用墨 %d" % [box.size.x,box.size.y,strokes.size(),compiled.ink_cost]

func _commit() -> void:
	if dragging or confirm.disabled:return
	if reframe:
		var result := _reframe(true)
		if not result.ok:
			status.text = result.error
			return
		game.message("原作画幅已调整 · 第 %d 次" % result.revision)
		_dismiss(true)
		return
	var compiled:=_prepare()
	if compiled.ok:compiled=Pen.submit(game,compiled.records,"player")
	if not compiled.ok:status.text=compiled.error;return
	game.message("远景已落笔 · 用墨 %d" % compiled.ink_spent)
	_dismiss(true)

func _dismiss(placed:bool) -> void:
	if is_queued_for_deletion():return
	hide()
	closed.emit(placed)
	queue_free()

func _draw() -> void:
	if not start.is_finite():return
	var area:=_box()
	if not area.has_area():return
	var rect:=Rect2(game.world_to_screen(Vector2(area.position.x,area.end.y)),area.size*game.PIXELS_PER_UNIT)
	draw_rect(rect,Color(.2,.36,.32,.7),false,1)
	Sheet.preview(self,rect,strokes)
