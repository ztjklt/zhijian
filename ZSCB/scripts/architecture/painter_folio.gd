extends MenuButton
## One portrait, one notebook. Building placements never touch the player's draft.
const OWNER := "companion"
const Plans := preload("res://scripts/architecture/building_plans.gd")
const PAIRED_POSITION_TOLERANCE := .10
var controls
var page_view
var pending_id := -1
var choices := {}
var last_placement := {}
var last_transfer := {}

func _ready() -> void:
	text = "阿靛的图纸包"
	focus_mode = Control.FOCUS_NONE
	about_to_popup.connect(refresh_pages)
	get_popup().id_pressed.connect(choose)
	page_view = preload("res://scripts/architecture/painter_plan_view.gd").new()
	controls.add_child.call_deferred(page_view)

func pages() -> Array:
	return plans().list_plans(controls.game, OWNER)

func plans():
	return load("res://scripts/architecture/building_plans.gd")

func refresh_pages() -> void:
	var popup := get_popup()
	popup.clear()
	choices.clear()
	popup.add_item("依这段话设计新建筑",0)
	var painter = controls.companion()
	if painter != null and not painter.unfinished_building.is_empty():
		popup.add_item("续改上次未完成的图稿",8999)
	for page in pages():
		var number := int(page.id)
		var title := "%s（图 %d）" % [page.name,number]
		popup.add_separator()
		for entry in [["view","看图 · "+title],["build","在地上选址建「%s」" % title],["variant","依这段话改「%s」并另存" % title]]:
			var action_id := choices.size()+1
			choices[action_id] = {"verb":entry[0],"id":number}
			popup.add_item(entry[1],action_id)
	var station := nearby_access()
	if not station.is_empty():
		popup.add_separator()
		popup.add_item("请阿靛到这处使用位",9000)
		if controls.game.medieval_world.survival.inventory("player").fruit > 0:
			popup.add_item("在此递给阿靛一枚朱果",9001)

func choose(index: int) -> void:
	var game = controls.game
	var painter = controls.companion()
	if painter == null or painter.actor == null: return
	if index == 8999:
		if painter.retry_building(): game.toolbar.navigation_open = false
		return
	if index >= 9000:
		var station := nearby_access()
		if station.is_empty():
			game.message("走近建筑的使用位再试")
			return
		var spot: Vector2 = station.at
		if station.paired:
			spot.x += Plans.PAIRED_SHIFT if game.player.position.x<=spot.x else -Plans.PAIRED_SHIFT
		if index == 9000:
			if painter.wait_at_plan_access(spot,station): game.toolbar.navigation_open = false
		elif index == 9001:
			last_transfer = transfer(station)
			game.message(last_transfer.get("message",last_transfer.get("error","")))
			if last_transfer.get("ok",false): game.toolbar.navigation_open = false
		return
	var action: Dictionary = choices.get(index,{"verb":"design","id":-1} if index == 0 else {})
	if action.is_empty(): return
	if action.verb == "view":
		var entry := BlueprintBag.find_entry(plans().bag_for(game,OWNER),action.id)
		if not entry.is_empty(): page_view.show_entry(entry)
		return
	if action.verb == "build":
		if not painter.available_for_plan(): return
		pending_id = action.id
		controls.pending_pattern = -1
		game.toolbar.navigation_open = false
		game.message("点地面指定建筑底部 · 阿靛会检查附近空位，Esc 取消")
		return
	var words: String = controls.chat_line.text.strip_edges()
	if words.is_empty():
		controls.chat_line.placeholder_text = "写下建筑用途和外观要求，再从图纸包选设计或改稿"
		controls.chat_line.grab_focus()
		return
	if painter.invite("building_variant" if action.verb == "variant" else "building_design",words,action.id):
		controls.chat_line.clear()
		controls.chat_line.release_focus()
		game.toolbar.navigation_open = false

func place(at: Vector2) -> bool:
	if pending_id < 0: return false
	var id := pending_id
	pending_id = -1
	var game = controls.game
	var origin := Vector2(at.x,game.medieval_world.travel_height(at.x))
	last_placement = controls.companion().build_from_plan(id,origin)
	if not last_placement.get("ok",false): game.message(last_placement.get("error","这块地无法落笔"))
	return true

func nearby_access() -> Dictionary:
	var game = controls.game
	if game.medieval_world == null: return {}
	var closest := 4.2
	var answer := {}
	for object in game.objects:
		var record: Dictionary = object.get("built_plan",object.get("plan",{}))
		if record.is_empty(): continue
		var origin = record.get("offset",[])
		if not origin is Array or origin.size() != 2: continue
		for pair in record.get("layout",{}).get("access",[]):
			var at: Vector2 = game.object_point(object,Vector2(origin[0]+pair[0],origin[1]+pair[1]))
			var distance: float = game.player.position.distance_to(at+Vector2(0,.65))
			if distance < closest:
				closest = distance
				answer = {"at":at,"id":object.structure_id,"plan_id":record.get("id",-1),"paired":Plans.paired_station(record.layout,float(pair[0]))}
	return answer

func transfer(station: Dictionary) -> Dictionary:
	var game = controls.game
	var painter = controls.companion()
	var at: Vector2 = station.at
	var use_spot := at+Vector2(0,0.65)
	if game.player.position.distance_to(use_spot) > 1.5 or painter.actor.player.position.distance_to(use_spot) > 1.5:
		return {"error":"请和阿靛一起走到使用位再交果"}
	if station.paired:
		var player_x: float = game.player.position.x-at.x
		var artist_x: float = painter.actor.player.position.x-at.x
		if player_x*artist_x>=0 or absf(absf(player_x)-Plans.PAIRED_SHIFT)>PAIRED_POSITION_TOLERANCE or absf(absf(artist_x)-Plans.PAIRED_SHIFT)>PAIRED_POSITION_TOLERANCE:
			return {"error":"请在棚下分站两侧，朝阿靛伸手交果"}
	var service = game.medieval_world.survival
	var result: Dictionary = service.act("player","give",{"to":OWNER})
	if result.get("ok",false):
		result.merge({"structure_id":station.id,"plan_id":station.plan_id,"access":[at.x,at.y],"from":"player","to":OWNER})
	return result
