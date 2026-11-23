class_name PaperLandscapeGuard
extends CanvasLayer
## Touch devices play in landscape. Portrait is a rotation prompt, never a second HUD.
var force_mobile := false
var mobile_override: Callable
var surface: Control
var was_active := false

static func install(host: Node) -> PaperLandscapeGuard:
	var guard := PaperLandscapeGuard.new()
	guard.name = "LandscapeGuard"
	host.add_child(guard)
	return guard

func is_active() -> bool:
	var mobile := force_mobile or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	if mobile_override.is_valid(): mobile = mobile or bool(mobile_override.call())
	var viewport := get_viewport().get_visible_rect().size
	return mobile and viewport.y > viewport.x

func _ready() -> void:
	layer = 1000
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(surface)
	surface.draw.connect(_paint)
	if OS.get_name() in ["Android","iOS"]: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	visible = is_active()

func _input(event: InputEvent) -> void:
	if is_active() and (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse or event is InputEventKey):
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	visible = is_active()
	if visible and not was_active:
		for popup in get_parent().find_children("*","PopupMenu",true,false): popup.hide()
	was_active = visible
	if visible: surface.queue_redraw()

func _paint() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var unit := PaperGuiScale.factor(viewport)
	var center := viewport*.5
	surface.draw_rect(Rect2(Vector2.ZERO,viewport),Color("f3f0e6"))
	var phone := Rect2(center+Vector2(-54,-98)*unit,Vector2(108,58)*unit)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("faf9f2"); frame.border_color = Color("376f65")
	frame.set_border_width_all(roundi(2*unit)); frame.set_corner_radius_all(roundi(10*unit))
	surface.draw_style_box(frame,phone)
	surface.draw_line(phone.position+Vector2(12,12)*unit,phone.position+Vector2(12,46)*unit,Color("b4c5b7"),2*unit,true)
	_centered("横过来，让笔迹展开。",center.y+10*unit,roundi(24*unit),Color("2c493d"))
	_centered("请旋转手机，横屏游玩",center.y+48*unit,roundi(16*unit),Color("708174"))
	_centered("左手移动  ·  右手绘画与出招",center.y+86*unit,roundi(13*unit),Color("708174"))

func _centered(text: String, baseline: float, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	surface.draw_string(font,Vector2((get_viewport().get_visible_rect().size.x-width)*.5,baseline),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
