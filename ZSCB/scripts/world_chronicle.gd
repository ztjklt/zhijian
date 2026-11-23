extends RefCounted
## Completed changes in this world, in insertion order. Time is shown in the
## player's local time by the reader. It is never used to settle a contract.
signal changed

const CAPACITY := 384
const TEXT_LIMITS := {"id":256,"kind":48,"role":64,"title":96,"detail":240,"subject_id":160}
var _events: Array = []
var _ids: Dictionary = {}

static func _point(value: Variant) -> Array:
	if value is Vector2 and value.is_finite():
		return [value.x, value.y]
	if value is Array and value.size() == 2:
		for coordinate in value:
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
				return []
		return [float(value[0]), float(value[1])]
	return []

static func valid_snapshot(value: Variant) -> bool:
	if not value is Array or value.size() > CAPACITY:
		return false
	var seen := {}
	for event in value:
		if not event is Dictionary or event.size() != TEXT_LIMITS.size() + 2:
			return false
		for field in TEXT_LIMITS:
			if not event.get(field) is String or event[field].length() > TEXT_LIMITS[field]:
				return false
		if event.id.is_empty() or event.kind.is_empty() or event.role.is_empty() or event.title.is_empty() or seen.has(event.id):
			return false
		var timestamp = event.get("when_unix")
		if not (timestamp is float or timestamp is int) or not is_finite(float(timestamp)) or timestamp < 0 or timestamp > 253402300799:
			return false
		if not event.get("at") is Array or (not event.at.is_empty() and _point(event.at).is_empty()):
			return false
		seen[event.id] = true
	return true

func restore(value: Array) -> void:
	_events = value.duplicate(true)
	_ids.clear()
	for event in _events:
		_ids[event.id] = true
	changed.emit()

func snapshot() -> Array:
	return _events.duplicate(true)

func record(key: String, kind: String, role: String, title: String, detail: String, at: Variant = null, subject_id: String = "") -> bool:
	if key.is_empty() or key.length() > TEXT_LIMITS.id or _ids.has(key) or title.strip_edges().is_empty() or role.is_empty() or kind.is_empty():
		return false
	var event := {"id":key,"kind":kind.left(TEXT_LIMITS.kind),"role":role.left(TEXT_LIMITS.role),
		"title":title.strip_edges().left(TEXT_LIMITS.title),"detail":detail.strip_edges().left(TEXT_LIMITS.detail),
		"at":_point(at),"subject_id":subject_id.left(TEXT_LIMITS.subject_id),"when_unix":int(Time.get_unix_time_from_system())}
	if _events.size() >= CAPACITY:
		# Keep a busy animal or guild from erasing every other role's history.
		var counts := {}
		for older in _events:
			counts[older.role] = int(counts.get(older.role,0)) + 1
		var busiest: String = counts.find_key(counts.values().max())
		for i in _events.size():
			if _events[i].role == busiest:
				_ids.erase(_events[i].id)
				_events.remove_at(i)
				break
	_events.append(event)
	_ids[key] = true
	changed.emit()
	return true

func recent(limit: int = 20) -> Array:
	var result: Array = []
	for i in range(_events.size()-1, maxi(-1, _events.size()-1-maxi(0,limit)), -1):
		result.append(_events[i].duplicate(true))
	return result

## Bounded public history for a role deciding in this world. Different kinds of
## activity share the page. Repeated effects from one subject occupy one entry.
func role_reports() -> Dictionary:
	var remaining := {"land":2, "life":2, "safety":2, "contract":3, "trade":1}
	var seen := {}
	var rows: Array = []
	for i in range(_events.size()-1, -1, -1):
		var event: Dictionary = _events[i]
		var kind: String = event.kind
		var section: String
		match kind:
			"terrain_extended", "paper_drawn", "building", "drawing", "scene_completed":
				section = "land"
			"birth", "revision", "grass", "ground_fruit", "bark", "feed", "plant_root", "hunger":
				section = "life"
			"injury", "hunt", "meat", "threat_defeated", "guild_protected":
				section = "safety"
			"guild_stall_trade":
				section = "trade"
			_:
				if kind != "guild" and not kind.begins_with("guild_"): continue
				section = "contract"
		if remaining[section] == 0: continue
		# For a contract, the latest transition supersedes earlier notices on that ticket.
		var group := [section if section == "contract" else kind, event.subject_id]
		if seen.has(group): continue
		seen[group] = true
		remaining[section] -= 1
		rows.append(event.duplicate(true))
		if rows.size() == 10: break
	if rows.is_empty(): return {}
	rows.reverse()
	return {"source":"本队公开世界手记，依发生先后列出。行动前用本轮现场、可达地点和公会报价复核。", "events":rows}

func highlights(limit: int = 8, since_unix: int = 0) -> Array:
	return _highlights(limit, since_unix, 0, _events.size())

static func _headline_weight(kind: String) -> int:
	match kind:
		"scene_completed","guild_settled","guild_stall_trade","threat_defeated","birth","revision","hunt","meat","injury","feed":
			return 2
		"building","ecology_review","guild_fed","guild_protected","guild_escorted","guild_crossed":
			return 1
		_:
			return 0

func _highlights(limit: int, since_unix: int, first_index: int, end_index: int) -> Array:
	if limit <= 0:
		return []
	# A new notice or patrol stop should not displace a completed commission or rescue.
	# Within each tier prefer the most recent witnessed outcome.
	var tiers := [[],[],[]]
	for i in range(end_index-1, first_index-1, -1):
		var event: Dictionary = _events[i]
		if event.kind not in ["night_started","player_returned"] and event.when_unix >= since_unix:
			tiers[_headline_weight(event.kind)].append(i)
	var candidates: Array = tiers[2] + tiers[1] + tiers[0]
	var roles := {}
	var topics := {}
	var selected := {}
	for first_per_role in [true, false]:
		for i in candidates:
			var event: Dictionary = _events[i]
			var topic := [event.kind,event.subject_id]
			if event.kind in ["patrol_arrived","terrain_extended","guild_posted","guild_closed"]:
				topic = [event.kind,event.role]
			if topics.has(topic) or (first_per_role and roles.has(event.role)):
				continue
			roles[event.role] = true
			topics[topic] = true
			selected[i] = true
			if selected.size() >= limit:
				break
		if selected.size() >= limit:
			break
	var indices := selected.keys()
	indices.sort()
	indices.reverse()
	var result: Array = []
	for index in indices:
		result.append(_events[index].duplicate(true))
	return result

func _last_night() -> Vector2i:
	var begin := -1
	var end := -1
	for i in _events.size():
		match _events[i].kind:
			"night_started":
				if begin < 0 or end >= 0:
					begin = i
					end = -1
			"player_returned":
				if begin >= 0 and end < 0:
					end = i
	return Vector2i(begin, end)

func note_player_return() -> void:
	var span := _last_night()
	if span.x >= 0 and span.y < 0:
		var start_id: String = _events[span.x].id
		record("return:" + start_id, "player_returned", "world", "回到队伍", "玩家接回了这个世界。")

func overnight(limit: int = 8) -> Array:
	var span := _last_night()
	if span.x < 0:
		return highlights(limit)
	var end := _events.size() if span.y < 0 else span.y
	return _highlights(limit, 0, span.x+1, end)

func record_scene(project: Dictionary, at: Variant) -> bool:
	if project.get("stage") != "complete" or project.get("work_ids",[]).is_empty() or _point(at).is_empty():
		return false
	var id: String = project.get("project_id","")
	var verified := false
	var traded := false
	for row in project.get("outcomes",[]):
		if row.get("ok") != true:
			continue
		if row.get("phase") == "verify" and row.get("tool") == "verify_scene":
			verified = true
		if row.get("phase") == "trade":
			var trade: Dictionary = row.get("trade",{})
			var scope: Dictionary = project.get("scope",{})
			if trade.get("action") == "stall_trade" and trade.get("target") in project.get("trade_targets",[]) and trade.get("world_id") == scope.get("world_id") and trade.get("team_id") == scope.get("team_id"):
				traded = true
	if id.is_empty() or not verified or (project.get("trade",false) and not traded):
		return false
	var title := "阿靛画成了「%s」" % project.get("title","无题")
	var detail := "阿靛从原路走到了新作。" + (" 摊位已做成第一笔生意。" if traded else "")
	return record("scene:"+id,"scene_completed","companion",title,detail,at,id)

func record_frontier(segment: Dictionary) -> void:
	var work_id: String = segment.get("work_id","")
	if work_id.is_empty():
		return
	var first: Array = segment.points.front()
	var last: Array = segment.points.back()
	record("edge:" + work_id, "terrain_extended", segment.get("author_id","companion"),
		"东侧新路 · " + str(segment.name),
		"从 %.1f 米接到 %.1f 米。%s" % [first[0],last[0],segment.get("landmark","")], last, work_id)

func record_paper(records: Array, results: Array) -> void:
	var drawn: Array = []
	for i in results.size():
		if results[i].changed:
			drawn.append(records[i])
	if drawn.is_empty():
		return
	var line: Dictionary = drawn.front()
	if line.get("author_id") not in ["player","companion"]:
		return
	var modes: PackedStringArray = []
	for stroke in drawn:
		var name: String = preload("res://scripts/paper_world_pen.gd").MODES.get(stroke.mode,stroke.mode)
		if not modes.has(name):
			modes.append(name)
	var title: String = line.get("name","")
	record("paper:" + str(line.work_id),"paper_drawn",line.author_id,
		title if not title.is_empty() else "新的地貌", "%d 笔落成 · %s" % [drawn.size(),"、".join(modes)],
		line.anchor.at,line.work_id)

func record_object(object: Dictionary) -> void:
	var work_id: String = object.get("work_id", "")
	if work_id.is_empty():
		return
	var building: Dictionary = object.get("built_plan", {})
	var detail := "阿靛在此留下了 %d 笔。" % object.get("paths", []).size()
	if not building.is_empty():
		detail += " 建筑图纸可在本队图鉴查阅。"
	record("object:" + work_id, "building" if not building.is_empty() else "drawing", "companion",
		str(object.get("name","手稿")), detail, Vector2(object.x,object.y), work_id)
