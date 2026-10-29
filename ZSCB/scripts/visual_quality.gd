class_name PaperVisualQuality
extends CanvasLayer
## World-only sharpening. GUI remains on the higher UILayer; no input interception.

func _ready() -> void:
	layer = 1
	add_to_group("paper_visual_quality")
	var screen := ColorRect.new()
	screen.name = "WorldSharpening"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var effect := ShaderMaterial.new()
	effect.shader = preload("res://scripts/world_sharpen.gdshader")
	effect.set_shader_parameter("strength", 0.18)
	screen.material = effect
	add_child(screen)
	var preferences := preload("res://scripts/preferences.gd")
	preferences.apply(get_viewport(), preferences.read())

func set_sharpening(enabled: bool) -> void:
	visible = enabled and get_parent().process_mode != Node.PROCESS_MODE_DISABLED
