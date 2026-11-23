extends SceneTree

const Slots := preload("res://scripts/team_worlds.gd")
const Worlds := preload("res://scripts/showcase_worlds.gd")
const SHOWCASE := "guild_shores"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func run() -> void:
	if not check(str(ProjectSettings.get_setting("application/config/name")).begins_with("PaperCastleCheck_"), "Run with tests/run_isolated.py to use a temporary save profile."):
		return

	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/title_menu.tscn")
	await process_frame
	await process_frame
	var cover = current_scene
	if not check(is_instance_valid(cover) and cover.trial_button.visible, "The cover has a showcase button."):
		return

	cover.trial_button.pressed.emit()
	await process_frame
	var catalog = cover.team_panel.showcases
	if not check(catalog.visible and catalog.choices.has(SHOWCASE), "The Three Shores showcase is listed."):
		return

	catalog.choices[SHOWCASE].pressed.emit()
	catalog.enter.pressed.emit()
	await process_frame
	var game = current_scene
	if not check(game.scene_file_path.ends_with("/medieval.tscn") and game.team_slot.get("showcase_id") == SHOWCASE, "The showcase opens as a playable sandbox."):
		return
	if not check(game.medieval_world.paper_strokes_snapshot().size() > 0, "The showcase terrain is loaded."):
		return
	if not check(game.save_game(), "The showcase can be saved locally."):
		return

	var saved := Slots.load_slot(Worlds.slot_id(SHOWCASE))
	if not check(saved.error.is_empty() and saved.card.revision >= 2, "The saved showcase loads again."):
		return

	print("DESKTOP SMOKE PASSED")
	quit()
