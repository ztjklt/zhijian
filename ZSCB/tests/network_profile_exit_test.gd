extends "res://tests/network_creation_receipt_test.gd"
func run() -> void:
	setup(); session.is_owner = true
	session._save_profile()
	DirAccess.make_dir_recursive_absolute(PaperNetSession.PROFILE + ".tmp")
	var spawn := draw_building(); full_bag(); reply(spawn)
	check(session.creation_receipts.waiting.size() == 1 and session.profile_error != "", "actual disk obstacle leaves confirmed data only in memory")
	var ticket: int = session.request_save()
	check(commands("save").is_empty() and session.save_request.completed.has(ticket) and not session.save_request.completed[ticket].ok, "local failure rejects a combined save before claiming cloud success")
	session._result({"op": "save", "seq": session.seq, "ok": true})
	check(game.toolbar.status_text.contains("失败"), "unrelated cloud receipt cannot hide local failure")
	session.leave()
	check(not session.leaving and not session.ended and commands("leave").is_empty(), "ordinary leave preserves unsaved personal data and room")
	await session.return_to_selector("res://scenes/map_select.tscn", true)
	check(is_instance_valid(game) and not session.navigation_pending and commands("leave").is_empty(), "save-return caller consumes local leave failure and keeps the scene")
	DirAccess.remove_absolute(PaperNetSession.PROFILE + ".tmp")
	session.leave()
	check(session.leaving and commands("leave").size() == 1, "after storage repair normal confirmed leave is available")
	cleanup()
	setup(); session.is_owner = true
	var active_ticket: int = session.request_save(); var active_seq: int = session.save_request.sequence
	DirAccess.make_dir_recursive_absolute(PaperNetSession.PROFILE + ".tmp")
	var refused_ticket: int = session.request_save()
	check(refused_ticket == active_ticket and not session.save_request.completed[active_ticket].ok and commands("save").size() == 1, "local failure terminates an existing save waiter without sending another save")
	session._result({"op": "save", "seq": active_seq, "ok": true})
	check(game.toolbar.status_text.contains("失败") and not session.save_request.completed[active_ticket].ok, "late success of an already-sent cloud save cannot erase local failure")
	DirAccess.remove_absolute(PaperNetSession.PROFILE + ".tmp")
	var retried: int = session.request_save()
	session._result({"op": "save", "seq": session.save_request.sequence, "ok": true})
	check(retried > active_ticket and session.save_request.completed[retried].ok, "explicit save retry succeeds normally after local storage repair")
	cleanup()
	setup(); session.is_owner = true; session._save_profile()
	session.return_to_selector("res://scenes/map_select.tscn", true)
	await process_frame
	DirAccess.make_dir_recursive_absolute(PaperNetSession.PROFILE + ".tmp")
	session._result({"op": "leave", "seq": session.leave_seq, "ok": true})
	for i in 3: await process_frame
	check(is_instance_valid(session) and is_instance_valid(game), "IO failure after sending leave cannot destroy the current scene")
	if is_instance_valid(session):
		check(not session.navigation_pending and game.toolbar.status_text.contains("失败"), "final navigation boundary rechecks personal persistence")
		DirAccess.remove_absolute(PaperNetSession.PROFILE + ".tmp")
		cleanup()
	await process_frame
	print("NETWORK PROFILE EXIT: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
