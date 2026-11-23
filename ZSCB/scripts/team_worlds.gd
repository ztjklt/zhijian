extends RefCounted

const Session := preload("res://scripts/world_session.gd")
const ROOT := "user://team_worlds_v1"
const MEMBERS := {"player":"玩家", "companion":"画家阿靛", "priest":"牧师", "adventurer-lizhou":"冒险者砾舟", "war_god":"战神"}

static func _id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func _valid_id(id: Variant) -> bool:
	return id is String and id.length() == 32 and id.is_valid_hex_number(false)

static func new_slot(label: String, parent: Dictionary = {}) -> Dictionary:
	return {"schema":1, "slot_id":_id(), "world_id":_id(), "team_id":parent.get("team_id",_id()),
		"parent_slot_id":parent.get("slot_id",""), "name":label.strip_edges().left(48), "revision":0}

static func _latest(id: String) -> int:
	if not _valid_id(id): return 0
	var dir := DirAccess.open(ROOT.path_join(id))
	if dir == null: return 0
	var latest := 0
	for entry in dir.get_directories():
		if entry.length() == 9 and entry.is_valid_int() and entry == "%09d" % int(entry):
			latest = maxi(latest, int(entry))
	return latest

static func _path(id: String, revision: int) -> String:
	return ROOT.path_join(id).path_join("%09d" % revision)

static func _card(id: String, revision: int) -> Dictionary:
	if revision < 1: return {}
	var path := _path(id,revision).path_join("card.json")
	var value = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not value is Dictionary or value.get("slot_id") != id or value.get("revision") != revision or value.get("schema") != 1: return {}
	if not _valid_id(value.get("team_id")) or not _valid_id(value.get("world_id")) or not value.get("name") is String: return {}
	return value

static func slots() -> Array:
	var result := []
	var dir := DirAccess.open(ROOT)
	if dir == null: return result
	for id in dir.get_directories():
		if not _valid_id(id): continue
		var card := _card(id,_latest(id))
		if not card.is_empty(): result.append(card)
	result.sort_custom(func(a,b): return a.updated > b.updated)
	return result

# Foreground visits are independent of autosaves made by the night process.
const RECENT_VISIT := ROOT + "/.foreground-visit"

static func mark_played(id: String) -> void:
	if not _valid_id(id): return
	var temp := RECENT_VISIT + "-" + _id()
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return
	var wrote := file.store_string(id)
	file.close()
	if not wrote or DirAccess.rename_absolute(temp, RECENT_VISIT) != OK:
		DirAccess.remove_absolute(temp)

static func cover_slot() -> Dictionary:
	if FileAccess.file_exists(RECENT_VISIT):
		var id := FileAccess.get_file_as_string(RECENT_VISIT).strip_edges()
		var card := _card(id, _latest(id))
		if not card.is_empty(): return {"card":card, "played":true}
	var available := slots()
	return {} if available.is_empty() else {"card":available.front(), "played":false}

static func load_slot(id: String) -> Dictionary:
	var revision := _latest(id)
	var card := _card(id,revision)
	if card.is_empty(): return {"error":"找不到该队的完整存档。"}
	var result := SaveStore.read_work(_path(id,revision).path_join("world.json"),"medieval-v1")
	if result.error != "": return result
	var identity = result.data.get("team_slot",{})
	for key in ["schema","slot_id","team_id","world_id","revision"]:
		if not identity is Dictionary or identity.get(key) != card.get(key): return {"error":"队伍记录与世界文件身份不一致。"}
	result.card = card
	return result

static func _write(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	var ok := file.store_string(JSON.stringify(value))
	file.flush()
	ok = ok and file.get_error() == OK
	file.close()
	return ok

static func _discard_stage(path: String) -> void:
	for file in ["card.json","world.json"]:
		if FileAccess.file_exists(path.path_join(file)): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

static func _compressed_stage(stage: String) -> String:
	# The OS expands these files on normal reads, including in older games
	# and in a world.json copied out of its slot. Keep the original on failure.
	if OS.get_name() != "macOS" or not FileAccess.file_exists("/usr/bin/ditto"):
		return stage
	var packed := stage + "-packed"
	var absolute := ProjectSettings.globalize_path(stage)
	if OS.execute("/usr/bin/ditto", ["--hfsCompression", absolute, absolute + "-packed"]) == 0:
		var verified := true
		for name in ["world.json", "card.json"]:
			var digest := FileAccess.get_sha256(stage.path_join(name))
			if digest.is_empty() or digest != FileAccess.get_sha256(packed.path_join(name)):
				verified = false
				break
		if verified: return packed
	_discard_stage(packed)
	return stage

static func commit(slot: Dictionary, encoded: Dictionary, compress: bool = false) -> Dictionary:
	var id: String = str(slot.get("slot_id",""))
	if not _valid_id(id): return {"ok":false,"message":"队伍编号无效。"}
	var needs_release := not Session.held.has(id) and Session.available()
	if needs_release:
		var acquired := Session.claim(id)
		if not acquired.ok: return acquired
	var saved := _commit_owned(slot,encoded,compress)
	if needs_release: Session.release(id)
	return saved

static func _commit_owned(slot: Dictionary, encoded: Dictionary, compress: bool = false) -> Dictionary:
	if not _valid_id(slot.get("slot_id")) or not _valid_id(slot.get("world_id")) or not _valid_id(slot.get("team_id")) or str(slot.get("name","")).strip_edges().is_empty():
		return {"ok":false,"message":"请填写队伍或分支名称。"}
	var expected := int(slot.revision)
	var previous := _latest(slot.slot_id)
	if previous != expected: return {"ok":false,"message":"该队存档已由其他窗口更新。可另存分支保留眼前的进度。"}
	if expected > 0:
		var prior := _card(slot.slot_id,expected)
		if prior.get("team_id") != slot.team_id or prior.get("world_id") != slot.world_id:
			return {"ok":false,"message":"存档身份不一致。"}
	var parent := ROOT.path_join(slot.slot_id)
	var stage := parent.path_join(".writing-" + _id())
	if DirAccess.make_dir_recursive_absolute(stage) != OK: return {"ok":false,"message":"无法建立队伍存档目录。"}
	var card := slot.duplicate()
	card.revision = expected + 1
	card.updated = Time.get_unix_time_from_system()
	# An accepted but unfinished local painting moves with a branch. External
	# requests never cross worlds; completed work keeps its original provenance.
	if expected==0:
		var ink = encoded.world.get("companion",{}).get("local_action",{}).get("ink",{})
		if ink is Dictionary and ink.get("paper_records") is Array:
			for stroke in ink.paper_records:
				if stroke is Dictionary and stroke.get("author_id")=="companion":
					stroke.team_id = card.team_id
					stroke.world_id = card.world_id
	var works := _catalog(encoded,card)
	card.works = works
	var guard_order: Dictionary = encoded.world.get("war_god", {}).get("action", {})
	var priest: Dictionary = encoded.world.get("priest_work", {})
	var activity: String = priest.get("activity", "")
	card.watch_priest = activity == "travel" or (activity in ["survey","tend","draw"] and absf(float(priest.get("destination",0)) - float(priest.get("x",0))) > .04)
	card.watch_guard = guard_order.get("tool", "") == "intercept" and not str(guard_order.get("call_id","")).is_empty()
	card.members = {}
	for role in MEMBERS:
		if role != "war_god" or ProjectSettings.get_setting("paper/war_god_enabled",true) or encoded.world.has("war_god"):
			card.members[role] = card.team_id+"/"+role
	encoded.team_slot = {"schema":1,"slot_id":card.slot_id,"team_id":card.team_id,"world_id":card.world_id,"revision":card.revision}
	if not _write(stage.path_join("world.json"),encoded) or not _write(stage.path_join("card.json"),card):
		_discard_stage(stage)
		return {"ok":false,"message":"写入失败，上次存档仍可继续。"}
	# Publishing a populated directory cannot replace another populated revision.
	var publish_from := _compressed_stage(stage) if compress else stage
	var published := DirAccess.rename_absolute(publish_from,_path(slot.slot_id,card.revision))
	if publish_from != stage: _discard_stage(stage)
	if published != OK:
		_discard_stage(publish_from)
		return {"ok":false,"message":"此版本未能提交。请检查磁盘，或把本局另存为分支。"}
	return {"ok":true,"card":card,"message":"已保存「%s」 · 第 %d 次存档" % [card.name,card.revision]}

static func _entry(list: Array, data: Dictionary, fallback: String, role: String, name: String, kind: String) -> void:
	if not data.has("work_id"): data.work_id = fallback
	if not data.has("author_id"): data.author_id = role
	var id := str(data.work_id)
	list.append({"work_id":id,"author_id":str(data.get("author_id",role)),"name":name,"kind":kind})

static func _catalog(data: Dictionary, card: Dictionary) -> Array:
	var list := []
	var world: Dictionary = data.world
	var chain:Array=preload("res://scripts/east_paper_pages.gd").joined(world)
	for i in chain.size():
		var segment: Dictionary = chain[i]
		_entry(list,segment,"legacy-east-"+JSON.stringify([segment.get("revision",i),segment.get("name",""),segment.get("points",[])]).sha256_text().left(24),"companion",segment.get("name","东侧地形"),"地形")
	for stroke in world.get("paper_space",{}).get("works",[]):
		if stroke.get("author_id","map")=="map": continue
		_entry(list,stroke,stroke.work_id,stroke.author_id,str(stroke.get("name",preload("res://scripts/paper_world_pen.gd").MODES.get(stroke.mode,"区块笔划"))),"地貌")
	var priest: Dictionary = world.get("priest_work",{})
	var species = priest.get("blueprints", [])
	for blueprint in species if species is Array else []:
		if not blueprint is Dictionary or not blueprint.get("name") is String: continue
		var id := str(blueprint.get("blueprint_id", ""))
		if not id.is_empty():
			list.append({"work_id":id, "author_id":"priest", "name":str(blueprint.name), "kind":"物种图纸"})
	var animals: Array = priest.get("works",[priest] if priest.has("design") else [])
	for animal in animals:
		var call_id := str(animal.get("call_id",""))
		var legacy_id := "legacy-"+(call_id if not call_id.is_empty() else JSON.stringify(animal.get("design",{}))).sha256_text().left(24)
		_entry(list,animal,legacy_id,"priest",str(animal.get("design",{}).get("name","小兽")),"生物")
	for plan in data.bag.get("entries",[]):
		if plan.get("source")=="library": continue
		_entry(list,plan,"plan-%s-player-%d"%[card.team_id,int(plan.id)],"player",str(plan.name),"图纸")
	for plan in world.get("companion",{}).get("blueprints",{}).get("entries",[]):
		_entry(list,plan,"plan-%s-%s"%[card.team_id,plan.id],"companion",plan.name,"图纸")
	for obj in data.objects:
		var role := str(obj.get("artist","player"))
		if role == "painter": role = "companion"
		if not obj.has("structure_id"): preload("res://scripts/structure_links.gd").ensure_key(obj)
		if not obj.has("work_id"): obj.work_id = "ink-"+str(obj.structure_id)
		if not obj.has("author_id"): obj.author_id = role
		var title := str(obj.get("name",BlueprintBag.NAMES.get(obj.get("kind",""),"手绘造物")))
		var plan_info: Dictionary = obj.get("built_plan",{})
		if not plan_info.is_empty():
			var plans: Dictionary = world.get("companion",{}).get("blueprints",{}) if plan_info.owner=="companion" else data.bag
			var plan := BlueprintBag.find_entry(plans if plans.has("entries") else BlueprintBag.new_bag(),plan_info.id)
			if not plan.is_empty(): title = plan.name
		_entry(list,obj,obj.work_id,role,title,"建筑" if not plan_info.is_empty() else "造物")
	return list

static func import_copy(path: String, label: String) -> Dictionary:
	var result := SaveStore.read_work(path,"medieval-v1")
	if result.error != "": return {"ok":false,"message":result.error}
	var data: Dictionary = result.data
	# Rebuild from game fields; connection settings and file-level extensions never enter a slot.
	var encoded := SaveStore.encode_work(data.paper,data.objects,data.bag,data.cameraX,data.playerX,data.equipped_weapon,data.world)
	if not encoded.ok: return encoded
	return commit(new_slot(label),encoded.data)
