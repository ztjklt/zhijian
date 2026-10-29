class_name PaperGuiScale
extends RefCounted
## UI-only logical pixels. World rendering and pointer events stay in viewport pixels.
## Never change Window.content_scale_size: it would also scale the paper/world.
static func factor(viewport: Vector2) -> float:
	return clampf(minf(viewport.x / 1280.0, viewport.y / 720.0), 1.0, 3.0)

static func apply(control: Control) -> Vector2:
	var viewport := control.get_viewport_rect().size
	var amount := factor(viewport)
	control.scale = Vector2.ONE * amount
	return viewport / amount

static func logical_size(control: Control) -> Vector2:
	var viewport := control.get_viewport_rect().size
	return viewport / factor(viewport)

# PopupMenu is a Window and does not inherit a Control's transform.
static func popup(menu: PopupMenu, amount: float) -> void:
	if is_equal_approx(float(menu.get_meta("paper_ui_scale", 0.0)), amount): return
	menu.set_meta("paper_ui_scale", amount)
	menu.add_theme_font_size_override("font_size", roundi(16 * amount))
	menu.add_theme_constant_override("v_separation", roundi(10 * amount))
	menu.size = Vector2i.ZERO
