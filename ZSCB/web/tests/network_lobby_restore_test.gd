extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var lobby=load("res://scenes/network_lobby.tscn").instantiate();root.add_child(lobby)
	lobby.session.profile={"address":"ws://127.0.0.1:51991/ws","token":"fixture","code":"12345678","world_id":"fixture-world"}
	lobby.address.text="ws://127.0.0.1:51992/ws"
	lobby._start("join",true)
	if lobby.session.address!="ws://127.0.0.1:51991/ws":print("FAIL: restore sent credentials to edited server");quit(1);return
	lobby.cancel_connection()
	lobby._start("create",false)
	if lobby.session.address!="ws://127.0.0.1:51992/ws" or lobby.session.token!="":print("FAIL: fresh request reused credentials");quit(1);return
	lobby.session.free();lobby.free()
	print("NETWORK_LOBBY_RESTORE_TEST: PASS");quit()
