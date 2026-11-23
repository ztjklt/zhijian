class_name PaperGuiScale
extends RefCounted
## UI-only logical pixels. World rendering and pointer events stay in viewport pixels.
## Never change Window.content_scale_size: it would also scale the paper/world.
static func factor(viewport: Vector2) -> float:
	var density := maxf(1.0, DisplayServer.screen_get_scale()) if OS.has_feature("web") or OS.has_feature("mobile") else 1.0
	var logical := viewport / density
	return density * clampf(minf(logical.x / 1280.0, logical.y / 720.0), 1.0, 3.0)

static func apply(control: Control) -> Vector2:
	var viewport := control.get_viewport_rect().size
	var amount := factor(viewport)
	control.scale = Vector2.ONE * amount
	return viewport / amount

static func logical_size(control: Control) -> Vector2:
	var viewport := control.get_viewport_rect().size
	return viewport / factor(viewport)

# Native safe areas are in window pixels. The Web shell insets its canvas
# with CSS env(safe-area-inset-*), so its viewport is already safe.
static func safe_rect(control: Control) -> Rect2:
	var viewport := control.get_viewport_rect().size
	var rect := Rect2(Vector2.ZERO, viewport)
	if OS.get_name() in ["Android", "iOS"]:
		var window := control.get_window()
		var window_rect := Rect2(Vector2(window.position), Vector2(window.size))
		var safe := window_rect.intersection(Rect2(DisplayServer.get_display_safe_area()))
		if safe.has_area() and window_rect.has_area():
			var ratio := viewport / window_rect.size
			rect = Rect2((safe.position - window_rect.position) * ratio, safe.size * ratio)
	var amount := factor(viewport)
	return Rect2(rect.position / amount, rect.size / amount)

static func fit_panel(panel: Control, maximum: Vector2, margin: float = 12.0) -> void:
	var bounds := safe_rect(panel).grow(-margin)
	panel.size = maximum.min(bounds.size)
	panel.position = bounds.position + (bounds.size - panel.size) * 0.5

# Godot 4.6 PopupMenu computes content_scale_factor from its parent when opening.
# Keep its theme in logical pixels, or high-density screens scale text twice.
static func popup(menu: PopupMenu, amount: float) -> void:
	if is_equal_approx(float(menu.get_meta("paper_ui_scale", 0.0)), amount): return
	menu.set_meta("paper_ui_scale", amount)
	menu.add_theme_font_size_override("font_size", 16)
	menu.add_theme_constant_override("v_separation", 24 if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") else 10)
	menu.size = Vector2i.ZERO
