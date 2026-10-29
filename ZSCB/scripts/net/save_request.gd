extends RefCounted
## One user save at a time, scoped to this room/world. No automatic wire retry.
const READY_TIMEOUT := 10.0
const RECEIPT_TIMEOUT := 3.0
var ticket := 0
var sequence := -1
var active := false
var phase := "idle"
var text := ""
var epoch := ""
var world_id := ""
var age := 0.0
var completed: Dictionary = {}

func refuse_local(session, reason: String) -> int:
	if not active:
		ticket += 1; sequence = -1; age = 0
		epoch = session.epoch; world_id = session.world_id
	elif sequence > 0:
		reason += "；先前云端请求可能已执行，当前画面保留"
	_finish(session, "failed", false, reason)
	return ticket

func begin(session) -> int:
	if active: return ticket
	ticket += 1; sequence = -1; age = 0
	epoch = session.epoch; world_id = session.world_id
	active = true; phase = "waiting"
	if not session.is_owner:
		_finish(session,"failed",false,"只有创建者能保存房间世界；个人图纸不受影响")
	elif session.ended or session.leaving:
		_finish(session,"failed",false,"当前房间正在结束或已断开；未发送保存，画面与草稿保留")
	else:
		_show(session,"保存请求已记录，等待同步完成后发送…")
		step(session,0)
	return ticket

func step(session, delta: float) -> void:
	if not active: return
	if session.epoch != epoch or session.world_id != world_id:
		cancel(session,"共享世界已切换，请在当前世界重新保存")
		return
	if session.ended or session.leaving:
		cancel(session,"房间已结束或正在离开，保存未确认；当前画面与草稿保留")
		return
	age += delta
	if phase == "waiting":
		if session.ready_to_play and not session.syncing:
			sequence = session.send_op("save")
			if sequence > 0:
				phase = "saving"; age = 0
				_show(session,"正在保存，等待服务器确认…")
		elif age >= READY_TIMEOUT:
			_finish(session,"failed",false,"同步等待超时，尚未发送保存；请稍后重试，草稿已保留")
	elif phase == "saving" and age >= RECEIPT_TIMEOUT:
		_finish(session,"unknown",false,"尚未收到服务器保存确认，结果暂不确定；画面与草稿已保留，可重试")

func receive(session, result: Dictionary) -> bool:
	if result.get("op","") != "save" or ticket == 0: return false
	# Once this UI owns save requests, stale/unrelated receipts cannot replace
	# the latest request's feedback. The session still emits every raw receipt.
	if sequence < 1 or int(result.get("seq",-1)) != sequence: return true
	if session.epoch != epoch or session.world_id != world_id: return true
	if not active and phase != "unknown": return true
	if result.get("ok",false):
		_finish(session,"saved",true,"房间世界已保存到服务器")
	else:
		_finish(session,"failed",false,str(result.get("error","保存失败，上次有效作品与当前草稿保留")))
	return true

func disconnected(session) -> void:
	if active and phase == "saving":
		_finish(session,"unknown",false,"连接中断，尚未收到保存确认；当前画面与草稿已保留，重连后可重试")

func cancel(session, reason: String) -> void:
	if active: _finish(session,"unknown" if sequence>0 else "failed",false,reason)

func feedback() -> Dictionary:
	return {} if ticket == 0 else {"text":text,"error":phase in ["failed","unknown"],"phase":phase}

func _show(session, message: String) -> void:
	text = message
	session.status = message
	if session.game != null: session.game.message(message)

func _finish(session, state: String, ok: bool, message: String) -> void:
	phase = state; active = false
	# A timed-out exit consumes its first terminal result, even if feedback later confirms.
	if not completed.has(ticket):
		completed[ticket] = {"ok":ok,"error":"" if ok else message,"unknown":state=="unknown"}
	while completed.size()>8: completed.erase(completed.keys().front())
	_show(session,message)
