extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var session=PaperNetSession.new();root.add_child(session)
	# An old server does not echo a protocol version. Reject before saving identity.
	session._receive({"type":"welcome","player_id":"old","token":"test-private","owner":true,"code":"OLD123","world_id":"old-world","epoch":"old-epoch"})
	if not session.ended or not session.profile.get("token","").is_empty():
		print("FAIL: legacy server welcome accepted and identity persisted");session.queue_free();await process_frame;quit(1);return
	if not session.status.contains("版本"):
		print("FAIL: incompatible server lacks a readable version explanation");quit(1);return
	session.queue_free();await process_frame
	print("NETWORK VERSION: PASS");quit()
