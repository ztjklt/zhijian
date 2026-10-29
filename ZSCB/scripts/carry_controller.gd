extends RefCounted
## One transient local/replica carry state, independent of drawing and pointer state.
var game
var id := ""
var previous: Dictionary = {}

func _init(owner_game) -> void:
	game = owner_game

static func key(object: Dictionary) -> String:
	var wire := str(object.get("id", ""))
	return wire if wire != "" else str(object.get("structure_id", ""))

func index() -> int:
	if id == "": return -1
	for i in game.objects.size():
		if key(game.objects[i]) == id: return i
	return -1

func clear() -> void:
	id = ""
	previous.clear()

func reapply() -> void:
	if id == "": return
	var at := index()
	if at < 0 or at >= game.object_nodes.size(): clear(); return
	var body: RigidBody2D = game.object_nodes[at]
	if previous.is_empty():
		previous = {"layer":body.collision_layer,"mask":body.collision_mask,"freeze":body.freeze}
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0

func _restore_body() -> void:
	var at := index()
	if at < 0 or at >= game.object_nodes.size(): return
	var body: RigidBody2D = game.object_nodes[at]
	body.collision_layer = int(previous.get("layer", 8 if game.objects[at].get("kind", "") in ["gate","ladder"] else 1))
	body.collision_mask = 0 if game.network_session != null else int(previous.get("mask", 1|8|64|128))
	body.freeze = true if game.network_session != null else bool(previous.get("freeze", false))

func apply_remote(next_id: String) -> void:
	if next_id != id:
		if id != "": _restore_body()
		clear()
		id = next_id
	# Repeated snapshots can replace the body while retaining the same ID.
	reapply()
	if id != "": game.selected = index()

func toggle() -> bool:
	if game.network_session != null:
		var session = game.network_session
		if not session.ready_to_play or session.leaving or session.local_dead_time > 0:
			game.message("连接准备好后再拿起或放下部件")
			return false
		var at: int = index() if id != "" else game.selected
		if at >= 0 and at < game.objects.size() and game.can_cooperate(game.objects[at]):
			var object: Dictionary = game.objects[at]
			session.send_op("carry", {"action":"drop" if id != "" else "pick","id":object.id,"version":object.version})
			game.message("正在等待服务器确认携物操作…")
			return true
		game.message("先用 4 选中一个可搬动的部件")
		return false
	if id != "": return drop()
	if game.selected < 0 or game.selected >= game.objects.size():
		game.message("先用 4 选中一个部件")
		return false
	return pick(game.selected)

func pick(at: int) -> bool:
	if at < 0 or at >= game.objects.size() or at >= game.object_nodes.size(): return false
	var object: Dictionary = game.objects[at]
	if not game.can_cooperate(object): game.message("没有权限拿起这个部件"); return false
	if game.structure_links != null and game.structure_links.linked(object.get("structure_id", "")):
		game.message("部件已连接，请先解除连接再拿起"); return false
	if Vector2(object.x, object.y).distance_to(game.player.position) > DrawingRules.BUILD_RANGE:
		game.message("请走近部件，在 12 米内拿起"); return false
	var next_id := key(object)
	if next_id == "": return false
	clear()
	id = next_id
	reapply()
	game.selected = at
	step()
	game.message("已拿起部件 · G 放下 · 可继续移动")
	return true

func step() -> void:
	if id == "": return
	var at := index()
	if at < 0 or at >= game.object_nodes.size(): clear(); return
	var body: RigidBody2D = game.object_nodes[at]
	var target: Vector2 = game.carry_position()
	body.position = target
	body.rotation = float(game.objects[at].get("angle", 0.0))
	game.objects[at].x = target.x
	game.objects[at].y = target.y

func drop() -> bool:
	var at := index()
	if at < 0 or at >= game.object_nodes.size(): clear(); return false
	var object: Dictionary = game.objects[at]
	var body: RigidBody2D = game.object_nodes[at]
	var candidate := object.duplicate(true)
	candidate.x = body.position.x + float(game.facing) * game.CARRY_DROP_OFFSET
	candidate.y = body.position.y
	var placement := PaperCarryPlacement.resolve(game, candidate)
	if not placement.ok:
		reapply()
		game.message(str(placement.error))
		return false
	object.x = placement.object.x; object.y = placement.object.y
	body.position = Vector2(object.x, object.y)
	_restore_body()
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0
	clear()
	game.message("已放下部件")
	return true
