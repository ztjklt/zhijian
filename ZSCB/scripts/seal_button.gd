class_name PaperSealButton
extends Button
## Hand-cut silhouettes; motion changes drawing only, keeping hit targets stationary.
var accent := Color("376f65")
var filled := false
var emphasized := false
var paper_opacity := 1.0
var silhouette := "pebble"
var hover_mix := 0.0:
	set(value): hover_mix = value; queue_redraw()
var press_mix := 0.0:
	set(value): press_mix = value; queue_redraw()
var hover_tween: Tween
var press_tween: Tween

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size.y = maxf(custom_minimum_size.y, 44)
	refresh_appearance()
	mouse_entered.connect(func(): _hover(1))
	mouse_exited.connect(func(): _hover(0))
	focus_entered.connect(func(): _hover(1))
	focus_exited.connect(func(): _hover(0))
	button_down.connect(func(): _press(1))
	button_up.connect(func(): _press(0))

func refresh_appearance() -> void:
	for state in ["normal","hover","pressed","disabled","focus"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 12
		empty.content_margin_right = 12
		empty.content_margin_top = 4
		empty.content_margin_bottom = 4
		add_theme_stylebox_override(state,empty)
	for state in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color"]: add_theme_color_override(state,Color.TRANSPARENT)
	queue_redraw()

func _hover(value: float) -> void:
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self,"hover_mix",value,.16)

func _press(value: float) -> void:
	if press_tween: press_tween.kill()
	press_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	press_tween.tween_property(self,"press_mix",value,.16 if value == 0 else .07)

static func outline(dimensions: Vector2, kind: String = "pebble") -> PackedVector2Array:
	var points := PackedVector2Array()
	if kind == "portal":
		# Arched paper door, ending in a softly pointed folded foot.
		for i in range(25):
			var angle := PI + PI * i / 24.0
			points.append(Vector2(dimensions.x*.5,dimensions.x*.48) + Vector2(cos(angle)*dimensions.x*.49,sin(angle)*dimensions.x*.47))
		points.append(Vector2(dimensions.x*.97,dimensions.y*.86))
		points.append(Vector2(dimensions.x*.73,dimensions.y*.97))
		points.append(Vector2(dimensions.x*.24,dimensions.y*.985))
		points.append(Vector2(dimensions.x*.025,dimensions.y*.90))
	else:
		for i in range(64):
			var a := TAU*i/64.0
			var variation := 1.0 + .025*sin(a*3+.6) + .012*cos(a*5)
			points.append(dimensions*.5 + Vector2(cos(a),sin(a))*(dimensions*.48)*variation)
	return points

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point,outline(size,silhouette))

func _get_minimum_size() -> Vector2:
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	return Vector2(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+24,54 if icon != null else 44)

func label_ink() -> Color:
	return Color("fffdf5") if filled and not disabled else Color("8b9289") if disabled else accent

func _draw() -> void:
	var points := outline(size,silhouette)
	var center := size*.5
	for i in points.size(): points[i] = center + (points[i]-center)*(1.0+.018*hover_mix-.045*press_mix) + Vector2(0,-2*hover_mix+2*press_mix)
	var shadow := points.duplicate()
	for i in shadow.size(): shadow[i] += Vector2(0,3)
	draw_colored_polygon(shadow,Color(.19,.23,.20,.09))
	var paper := accent if filled else Color("fcf9ef").lerp(Color("e3ece4"),hover_mix*.5)
	if emphasized and not filled: paper = Color("dfe9df")
	if disabled: paper = Color("e5e5dc")
	paper.a=minf(1.0,.62 if disabled and paper_opacity<1.0 else paper_opacity+hover_mix*.12)
	draw_colored_polygon(points,paper)
	var edge := points.duplicate(); edge.append(points[0])
	draw_polyline(edge,Color(accent,.7 if has_focus() or emphasized else .22),1.8 if emphasized else 1.2,true)
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var label_width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var color := label_ink()
	var baseline := (size.y+font.get_ascent(font_size)-font.get_descent(font_size))*.5+press_mix*2
	if icon != null:
		var icon_size := Vector2.ONE * minf(22,size.y*.38)
		draw_texture_rect(icon,Rect2(Vector2((size.x-icon_size.x)*.5,size.y*.14+press_mix*2),icon_size),false,Color(color,.4 if disabled else 1))
		baseline = size.y*.84+press_mix*2
	draw_string(font,Vector2((size.x-label_width)*.5,baseline),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
