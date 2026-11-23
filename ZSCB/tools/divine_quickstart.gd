extends SceneTree

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	change_scene_to_file("res://scenes/map_select.tscn")
	await scene_changed
	var selector := current_scene
	var demo: bool = ProjectSettings.get_setting("paper/divine_demo", false)
	var resume: bool = not demo and not selector.continue_buttons["medieval-v1"].disabled
	selector.start_map("medieval-v1", resume)
	if demo:
		current_scene.get_window().title = "纸间 · 已生成笔稿 · 独立演示"
		current_scene.open_divine_status()
