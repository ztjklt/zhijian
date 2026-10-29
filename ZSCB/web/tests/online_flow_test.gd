extends SceneTree
var failed: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed.append(label); print("FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path := "res://scripts/net/online_flow.gd"
	check(ResourceLoader.exists(path),"invitation parsing and safe links are available")
	if ResourceLoader.exists(path):
		var flow=load(path)
		for raw in [" a1b2c3d4 ","https://zhijian-web-production.up.railway.app/?room=A1B2C3D4","https://zhijian-web-production.up.railway.app/?release=one&room=a1b2c3d4"]:
			check(flow.parse_invite(raw).get("code","")=="A1B2C3D4","valid room code and invitation normalize")
		for raw in ["","123","ABCDEFGZ","https://evil.example/?room=A1B2C3D4","https://zhijian-web-production.up.railway.app/?room=A1B2C3D4&server=wss://evil.example/ws"]:
			check(flow.parse_invite(raw).get("error","")!="","invalid code or server-changing invitation rejected")
		check(flow.invite_url("A1B2C3D4")=="https://zhijian-web-production.up.railway.app/?room=A1B2C3D4","invitation contains only public room code")
	var lobby=load("res://scenes/network_lobby.tscn").instantiate()
	root.add_child(lobby)
	lobby.address.text="ws://127.0.0.1:51991/ws"
	lobby.invite.text=""
	lobby._start("join")
	check(lobby.session.socket==null,"blank invite rejected before network connection")
	if lobby.session.socket!=null: lobby.session.socket.close();lobby.session.socket=null
	lobby._start("create")
	var first=lobby.session.socket
	lobby._start("create")
	check(lobby.session.socket==first,"repeated create click cannot open a second connection")
	if lobby.has_method("cancel_connection"):
		lobby.cancel_connection()
		check(lobby.session.socket==null and not lobby.busy,"cancel returns to editable lobby")
		lobby.invite.text="https://zhijian-web-production.up.railway.app/?room=A1B2C3D4"
		lobby._start("join")
		check(lobby.session.code=="A1B2C3D4","pasted invitation joins its room")
		lobby.session._fail("测试连接失败")
		await process_frame
		await process_frame
		check(not lobby.busy,"failed connection releases controls for retry")
		lobby.session.profile={"address":"ws://127.0.0.1:51992/ws","token":"fixture","code":"11223344","world_id":"fixture-world"}
		lobby.address.text="ws://127.0.0.1:51993/ws"
		lobby._start("join",true)
		check(lobby.session.address=="ws://127.0.0.1:51992/ws","restore credentials stay on original server")
		lobby.cancel_connection()
	else: check(false,"connecting has an explicit cancel action")
	lobby.session.free();lobby.free()
	print("ONLINE_FLOW: ",checks," checks, ",failed.size()," failures")
	quit(0 if failed.is_empty() else 1)
