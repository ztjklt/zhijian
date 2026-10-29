class_name PaperOnboarding
extends RefCounted

const PREFERENCES := "user://paper_castle_preferences.cfg"
var stage := 0
var visible := true
var start_x := 0.0
var persist := true

func _init(save_preferences: bool = true) -> void:
	persist = save_preferences
	if persist:
		var config := ConfigFile.new()
		if config.load(PREFERENCES) == OK:
			visible = not bool(config.get_value("guide", "seen", false))

func note_drawn() -> void:
	if stage == 0:
		stage = 1

func note_built() -> void:
	if stage < 2:
		stage = 2

func note_play(player_x: float) -> void:
	if stage == 2:
		stage = 3
		start_x = player_x

func note_movement(player_x: float) -> void:
	if stage == 3 and absf(player_x - start_x) >= 0.7:
		stage = 4
		_save(true)

func dismiss() -> void:
	visible = false
	_save(true)

func restart(has_objects: bool) -> void:
	stage = 2 if has_objects else 0
	visible = true
	_save(false)

func _save(seen: bool) -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	config.load(PREFERENCES)
	config.set_value("guide", "seen", seen)
	config.save(PREFERENCES)
