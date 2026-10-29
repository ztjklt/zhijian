extends "res://tests/network_creation_receipt_test.gd"
class CountedSession extends PaperNetSession:
	var outgoing: Array = []
	var writes := 0
	func _send(message: Dictionary) -> void: outgoing.append(message.duplicate(true))
	func _save_profile() -> bool:
		writes += 1
		return super._save_profile()
func setup() -> void:
	game = load("res://scenes/main.tscn").instantiate(); game.onboarding.persist = false; root.add_child(game)
	game.set_physics_process(false); game.combat.set_natives(false)
	session = CountedSession.new(); root.add_child(session); session.set_process(false)
	session.game = game; game.network_session = session; session.ready_to_play = true; session.epoch = "io"; session.world_id = "io-world"
func run() -> void:
	setup()
	var spawn := draw_building(); var ink: Array = game.draft.duplicate(true); full_bag(); reply(spawn)
	var before := FileAccess.get_file_as_string(PaperNetSession.PROFILE)
	DirAccess.make_dir_recursive_absolute(PaperNetSession.PROFILE + ".tmp")
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id)
	var next_id: int = game.bag.next_id
	session.tick(.01)
	check(game.bag.entries.size() == 127 and game.bag.next_id == next_id and session.creation_receipts.waiting.size() == 1, "failed archive rolls back bag and ID while retaining pending")
	check(game.draft == ink and game.toolbar.status_text.contains("失败"), "failed local archive retains source and explains failure")
	check(FileAccess.get_file_as_string(PaperNetSession.PROFILE) == before, "failed archive preserves the exact last complete disk transaction")
	var writes: int = session.writes
	for i in 60: session.tick(.001)
	check(session.writes == writes, "write failure is throttled instead of retried every render frame")
	DirAccess.remove_absolute(PaperNetSession.PROFILE + ".tmp")
	session.tick(1.01)
	check(game.bag.entries.size() == 128 and game.bag.entries.back().paths == spawn.object.paths and session.creation_receipts.waiting.is_empty(), "writable storage recovers the same item once")
	check(game.draft.is_empty() and commands("spawn").size() == 1, "recovered local commit clears only original ink without a new spawn")
	cleanup(); await process_frame
	print("NETWORK PENDING IO: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
