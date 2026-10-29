extends SceneTree
var session: PaperNetSession
var folder := ""
var invite := ""
var results: Dictionary = {}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--code="): invite=arg.trim_prefix("--code=")
		if arg.begins_with("--coord="): folder=arg.trim_prefix("--coord=")
	call_deferred("run")
func wait_until(condition: Callable, seconds: float=150) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if condition.call(): return true
		await process_frame
	return false
func note(name: String, value: String) -> void:
	var file:=FileAccess.open(folder.path_join(name),FileAccess.WRITE)
	file.store_string(value);file.close()
	print("BROWSER_PEER ",name,": ",value)
func fail(message: String) -> void:
	note("failed",message);quit(1)
func run() -> void:
	session=PaperNetSession.new();root.add_child(session)
	session.operation_finished.connect(func(result):results[int(result.get("seq",0))]=result)
	session.connect_room("wss://paper-server-production-4b68.up.railway.app/ws","join",invite,"网页验收乙","paper")
	if not await wait_until(func():return session.ready_to_play,30): fail("客户端没有完成握手："+session.status);return
	if session.remotes.size()!=1: fail("未显示浏览器玩家");return
	note("joined","2 real game clients, protocol2, shared authority")
	if not await wait_until(func():return session.game.objects.size()==1 and session.ready_to_play):fail("未收到浏览器生成的实体");return
	var object:Dictionary=session.game.objects[0]
	note("shared","browser object received; session ready")
	var seq:=session.send_op("delete",{"id":object.id,"version":object.version})
	if not await wait_until(func():return results.has(seq),15):fail("越权操作无回应");return
	if results[seq].ok:fail("能够删除浏览器玩家作品");return
	var game:PaperCastleMain=session.game
	if game.bag.entries.size()!=6:fail("个人图纸被浏览器玩家覆盖");return
	game.draw_mode=3
	var start:=game.player.position+Vector2(3,4)
	game.draft=[{"points":[start,start+Vector2(1,0),start+Vector2(1,.4),start+Vector2(0,.4),start]}]
	game.release_building()
	if not await wait_until(func():return game.objects.size()==2 and game.draft.is_empty(),20):fail("原生客户端生成未完成");return
	note("checked","browser spawn received; private bag preserved; ownership enforced; native spawn confirmed")
	if not await wait_until(func():return session.ended,300):fail("浏览器创建者未结束房间");return
	note("complete","owner close received")
	quit()
