class_name PaperTheme
extends RefCounted

const INK := Color("263638")
const MUTED := Color("687777")
const MENU_MUTED := Color("4f6060")
const TEAL := Color("386e70")
const PAPER := Color("faf7ee")
const SHEET_PATH := "res://assets/ui/paper/sheet.png"
const STRIP_PATH := "res://assets/ui/paper/strip.png"
static var _textures: Dictionary = {}

# The texture's ragged edge stays intact while its quiet paper centre stretches.
static func paper_texture(path: String, color: Color = Color.WHITE, edge: int = 32) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	if not _textures.has(path) and ResourceLoader.exists(path):
		var source: Texture2D = load(path)
		var pixels := source.get_image()
		if path == SHEET_PATH:
			pixels = pixels.get_region(Rect2i(8, 95, 1604, 780))
		elif path == STRIP_PATH:
			pixels = pixels.get_region(Rect2i(30, 145, 2120, 480))
		# Normalise the source border to UI pixels before applying nine-patch margins.
		# The original generated PNG is kept unchanged for future edits.
		var width := 320 if path == STRIP_PATH else 640
		pixels.resize(width, maxi(1, roundi(float(pixels.get_height()) * width / pixels.get_width())), Image.INTERPOLATE_LANCZOS)
		_textures[path] = ImageTexture.create_from_image(pixels)
	style.texture = _textures.get(path)
	style.modulate_color = color
	if path == SHEET_PATH: style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, edge)
		style.set_content_margin(side, 14)
	return style

static func panel(color: Color = PAPER, radius: int = 6) -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("d3cfc2")
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(18)
	style.shadow_color = Color(0.12, 0.15, 0.13, 0.09)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style

static func scrap(color: Color = Color.WHITE) -> StyleBox:
	return surface(PAPER if color == Color.WHITE else color, 9)

static func surface(color: Color = PAPER, padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("d8d4c8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(padding)
	return style

static func icon(name: String) -> Texture2D:
	return load("res://assets/ui/clean/" + name + ".svg")

# GPT-generated quiet paper, placed behind modal contents rather than their text.
static func grain(parent: Control) -> void:
	const PATH := "res://assets/ui/clean/paper-grain.png"
	if not ResourceLoader.exists(PATH): return
	var image := TextureRect.new()
	image.texture = load(PATH)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.modulate.a = 0.18
	image.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	parent.add_child(image)
	# Ignore container sizing; the texture follows the already laid-out parent.
	image.set_meta("paper_grain", true)
	parent.resized.connect(func(): image.size = parent.size; image.position = Vector2.ZERO)
	image.show_behind_parent = false
	parent.move_child(image, 0)

static func create() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei"])
	result.default_font = font
	result.default_font_size = 16
	result.set_color("font_color", "Label", INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color := Color.WHITE
		if state == "hover": color = Color("e9f1e6")
		if state == "pressed": color = Color("cbded6")
		if state == "disabled": color = Color("e6e4dc")
		var style := scrap(color)
		style.set_content_margin_all(9)
		result.set_stylebox(state, "Button", style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = TEAL
	focus.set_border_width_all(2)
	result.set_stylebox("focus", "Button", focus)
	result.set_color("font_color", "Button", INK)
	result.set_color("icon_normal_color", "Button", INK)
	result.set_color("icon_hover_color", "Button", TEAL)
	result.set_color("icon_pressed_color", "Button", INK)
	result.set_color("font_hover_color", "Button", INK)
	result.set_color("font_pressed_color", "Button", TEAL)
	result.set_color("font_disabled_color", "Button", Color("929c96"))
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_stylebox("panel", "PopupMenu", panel())
	result.set_stylebox("hover", "PopupMenu", scrap(Color("d4e4d8")))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", TEAL)
	result.set_stylebox("panel", "TooltipPanel", panel())
	result.set_color("font_color", "TooltipLabel", INK)
	result.set_stylebox("normal", "LineEdit", scrap(Color("f3f1e6")))
	result.set_stylebox("focus", "LineEdit", scrap(Color("dfebe0")))
	result.set_color("font_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_constant("separation", "HBoxContainer", 10)
	result.set_constant("separation", "VBoxContainer", 8)
	result.set_constant("h_separation", "GridContainer", 12)
	result.set_constant("v_separation", "GridContainer", 12)
	return result

# Opt in only from menus and modal panels; the cover and gameplay HUD keep create().
static func menu_font_size(base_size: int) -> int:
	return maxi(14, base_size + 2)

static func create_menu() -> Theme:
	var result := create()
	result.default_font_size = menu_font_size(16)
	result.set_color("font_placeholder_color", "LineEdit", MENU_MUTED)
	return result

static func primary(button: Button) -> void:
	for state in ["normal", "hover", "pressed"]:
		var color := TEAL if state == "normal" else Color("498080") if state == "hover" else Color("295655")
		var style := scrap(color)
		style.set_content_margin_all(10)
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, PAPER)

static func selected(button: Button, active: bool) -> void:
	if active:
		var style := surface(Color("e1eae3"), 9)
		style.border_color = TEAL
		style.set_content_margin_all(9)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_color_override("font_color", TEAL)
	else:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_color_override("font_color")

static func heading(label: Label) -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Kaiti SC", "STKaiti", "KaiTi", "Noto Serif CJK SC"])
	label.add_theme_font_override("font", font)
