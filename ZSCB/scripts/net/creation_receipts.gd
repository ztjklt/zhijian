extends RefCounted
## Server-confirmed creations awaiting a personal blueprint slot, never a retry
## queue for world commands. Submission gates bound this to one spawn + one equip.
var waiting: Array = []
var notice := ""
var retry_wait := 0.0

func persistent_items() -> Array:
	var items: Array = []
	for item in waiting:
		var checked := PaperNetValidation.weapon(item.object) if item.request.op == "equip_drawing" else PaperNetValidation.object(item.object)
		var object: Dictionary = checked.get("weapon" if item.request.op == "equip_drawing" else "object", item.object).duplicate(true)
		object.x = 0; object.y = 0; object.angle = 0
		items.append({"op": item.request.op, "object": object})
	return items

func restore(items: Array) -> void:
	waiting.clear(); notice = ""; retry_wait = 0
	for item in items:
		# Restored personal data has no authority over the new world's workflow.
		waiting.append({"object": item.object.duplicate(true), "request": {"op": item.op, "draft": [], "draw_mode": -1, "restored": true}})

func capture(session) -> Dictionary:
	return {"context": session.game.creation_context, "selection": session.game.blueprint_selection_context, "epoch": session.epoch, "world": session.world_id}

func blocked(session) -> bool:
	if waiting.is_empty(): return false
	retry_wait = 0
	retry(session)
	if not waiting.is_empty():
		notice = "已确认的图纸尚未收入背包；请先整理，完整草稿已保留"
		session.game.message(notice)
	# This click may have just completed an earlier request locally. It must not
	# also send a second world operation using the same retained ink.
	return true

func complete(session, request: Dictionary, object: Dictionary) -> void:
	if request.get("blueprint", -1) >= 0:
		finish(session, request, object, {})
		return
	waiting.append({"request": request, "object": object.duplicate(true)})
	if session.game.bag.entries.size() < BlueprintBag.MAX_ENTRIES:
		retry(session)
		return
	var saved: bool = session._save_profile()
	var confirmed := "武器已装备" if request.op == "equip_drawing" else "造物已生成"
	notice = confirmed + "，但图纸未保存：背包已满；完整草稿保留。" + ("待收入图纸已存本机，腾位后补存，不会再次生成或扣墨" if saved else "待收入保存失败，请勿关闭；" + session.profile_error)
	session.game.message(notice)

func retry(session, delta: float = 0.0) -> void:
	retry_wait = maxf(0, retry_wait - delta)
	if retry_wait > 0: return
	if waiting.is_empty() or not is_instance_valid(session.game): return
	while not waiting.is_empty() and session.game.bag.entries.size() < BlueprintBag.MAX_ENTRIES:
		var item: Dictionary = waiting[0]
		var previous: Dictionary = session.game.bag.duplicate(true)
		var entry := BlueprintBag.add_entry(session.game.bag, item.object)
		if entry.error != "": return
		waiting.pop_front()
		if not session._save_profile():
			waiting.push_front(item)
			session.game.bag = previous; session.profile.bag = previous
			session.profile.pending_blueprints = persistent_items()
			retry_wait = 1.0
			notice = "图纸补存失败，待收入和完整草稿已保留；" + session.profile_error
			session.game.message(notice); session.game.backpack_ui.refresh()
			return
		finish(session, item.request, item.object, entry.entry, true)
	if waiting.is_empty():
		if notice != "" and session.game.toolbar.status_text == notice:
			session.game.message("已确认的图纸已补存，当前操作保留")
		notice = ""

func finish(session, request: Dictionary, object: Dictionary, entry: Dictionary, persisted: bool = false) -> void:
	var game = session.game
	var source: Dictionary = request.get("creation", {})
	var same_world: bool = not request.get("restored", false) and source.get("epoch") == session.epoch and source.get("world") == session.world_id
	var owns: bool = same_world and source.get("context", -1) == game.creation_context and game.draw_mode == request.draw_mode
	var same_ink: bool = game.draft == request.draft
	var reused: bool = request.get("blueprint", -1) >= 0
	if owns and source.get("selection", -1) == game.blueprint_selection_context and not entry.is_empty(): game.selected_blueprint_id = entry.id
	if owns and reused:
		# Reuse consumes the placement intent, never the tool's unrelated draft.
		if game.placing_blueprint_id == request.blueprint: game.placing_blueprint_id = -1
	if owns and same_ink and not reused:
		game.draft = []
		if request.op == "equip_drawing":
			game.refine_model_fill = null
			game.cancel_weapon_grip(false)
		else:
			game.clear_candidate()
			game.pending_building = {}
			game.placement_preview = {}
			game.placing_blueprint_id = -1
	if not reused and same_world and game.mode_drafts.get(request.draw_mode, []) == request.draft and (owns or game.draw_mode != request.draw_mode):
		game.mode_drafts[request.draw_mode] = []
	game.backpack_ui.refresh(); game.refresh_buttons()
	if request.op == "equip_drawing":
		if same_world: game.feedback.emit_event("create", game.player.position + Vector2(game.facing * .25, .1), "FORGED!")
		if owns: game.message("服务器已确认装备 · 武器图纸已收入个人背包")
	else:
		if same_world: game.celebrate_creation(object)
		if owns: game.message("造物已由服务器确认，图纸已收入个人背包")
	if not persisted: session._save_profile()
