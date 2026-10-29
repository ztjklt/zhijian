extends RefCounted
## Device preferences never share a file with a world save.
const PATH := "user://preferences.cfg"
static func read() -> Dictionary:
	var config := ConfigFile.new()
	config.load(PATH)
	return {"volume": clampf(float(config.get_value("audio", "volume", 80.0)), 0, 100),
		"antialias": bool(config.get_value("video", "antialias", true)),
		"sharpen": bool(config.get_value("video", "sharpen", true))}
static func save(values: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", values.volume)
	config.set_value("video", "antialias", values.antialias)
	config.set_value("video", "sharpen", values.sharpen)
	return config.save(PATH)
static func apply(viewport: Viewport, values: Dictionary) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(values.volume) / 100.0)))
	AudioServer.set_bus_mute(0, values.volume <= 0)
	viewport.msaa_2d = Viewport.MSAA_4X if values.antialias else Viewport.MSAA_DISABLED
	for effect in viewport.get_tree().get_nodes_in_group("paper_visual_quality"):
		effect.set_sharpening(values.sharpen)
