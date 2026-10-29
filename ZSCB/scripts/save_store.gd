class_name SaveStore

const SAVE_PATH := "user://paper_castle_v3.json"
const MEDIEVAL_SAVE_PATH := "user://paper_castle_medieval_v1.json"
const LEGACY_SAVE_PATH := "user://paper_castle_v1.json"

static func _valid_point(p: Variant) -> bool:
	if not p is Dictionary:
		return false
	if not p.has("x") or not p.has("y"):
		return false
	if not p.x is float and not p.x is int:
		return false
	if not p.y is float and not p.y is int:
		return false
	var x: float = p.x
	var y: float = p.y
	return x == x and y == y and absf(x) < 200 and absf(y) < 200

static func _valid_path(path: Variant) -> bool:
	if not path is Dictionary or not path.has("points"):
		return false
	var points: Array = path.points
	if points.size() < 2 or points.size() > DrawingRules.MAX_POINTS:
		return false
	for p in points:
		if not _valid_point(p):
			return false
	return true

static func _valid_object(obj: Variant) -> bool:
	if not obj is Dictionary:
		return false
	if not obj.has("x") or not obj.has("y"):
		return false
	if not obj.x is float and not obj.x is int:
		return false
	if not obj.y is float and not obj.y is int:
		return false
	var x: float = obj.x
	var y: float = obj.y
	if x != x or y != y:
		return false
	if absf(x) > 1000000000 or absf(y) > 1000000000:
		return false
	if not obj.has("paths") or not obj.paths is Array:
		return false
	if obj.paths.size() > 128:
		return false
	if obj.has("angle"):
		var angle = obj.angle
		if not angle is float and not angle is int:
			return false
		if absf(angle) > 1000000:
			return false
	for path in obj.paths:
		if not _valid_path(path):
			return false
	return true

static func _valid_bag(bag: Variant) -> bool:
	if not bag is Dictionary:
		return false
	if not bag.has("entries") or not bag.entries is Array:
		return false
	if bag.entries.size() > 128:
		return false
	if not bag.has("next_id") or not bag.next_id is float and not bag.next_id is int:
		return false
	if bag.next_id < 1:
		return false
	if not bag.has("hotbar") or not bag.hotbar is Array:
		return false
	if bag.hotbar.size() != 6:
		return false
	var ids := {}
	for entry in bag.entries:
		if not entry is Dictionary:
			return false
		if not entry.has("id") or not entry.id is float and not entry.id is int:
			return false
		if ids.has(entry.id):
			return false
		if not entry.has("name") or not entry.name is String:
			return false
		if entry.name.length() > 72:
			return false
		if entry.get("category", "") not in ["建筑", "地形", "武器"]:
			return false
		if not entry.has("paths") or not entry.paths is Array:
			return false
		if entry.paths.size() > 128:
			return false
		ids[entry.id] = true
		for path in entry.paths:
			if not _valid_path(path):
				return false
	for slot in range(6):
		var id = bag.hotbar[slot]
		if not id is float and not id is int:
			return false
		if id != 0 and not ids.has(id):
			return false
	return true

static func _json_value(value: Variant) -> Variant:
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _json_value(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_json_value(item))
		return result
	return value

static func _restore_vectors(data: Dictionary) -> void:
	for object in data.get("objects", []):
		for path in object.get("paths", []):
			var restored: Array = []
			for point in path.get("points", []):
				restored.append(Vector2(float(point.x), float(point.y)))
			path.points = restored
	for entry in data.get("bag", {}).get("entries", []):
		if entry.has("grip"):
			entry.grip = Vector2(float(entry.grip.x), float(entry.grip.y))
		for path in entry.get("paths", []):
			var restored: Array = []
			for point in path.get("points", []):
				restored.append(Vector2(float(point.x), float(point.y)))
			path.points = restored

static func _valid_world(world: Variant) -> bool:
	if not world is Dictionary or world.get("id", "") not in ["paper", "knowledge-v1", "medieval-v1", "nature-v1"]: return false
	for key in ["player_y", "camera_y"]:
		if not world.has(key) or not (world[key] is float or world[key] is int): return false
		if not is_finite(float(world[key])) or absf(world[key]) > 1000000: return false
	if world.id in ["knowledge-v1", "nature-v1"]:
		if not _valid_point(world.get("checkpoint")): return false
		if not world.get("bookmarks") is Array or world.bookmarks.size() > 6: return false
		for id in world.bookmarks:
			if not (id is float or id is int) or not is_finite(float(id)) or id != int(id) or id < 0 or id > 5: return false
	if world.id == "medieval-v1":
		if not preload("res://scripts/medieval_world.gd").validate_snapshot(world): return false
	if world.has("maps"):
		if not world.maps is Dictionary or world.maps.size() > 4: return false
		for id in world.maps:
			var slot = world.maps[id]
			if id not in ["paper", "knowledge-v1", "nature-v1", "medieval-v1"] or not slot is Dictionary: return false
			if not slot.get("world") is Dictionary or slot.world.has("maps") or slot.world.get("id") != id or not _valid_world(slot.world): return false
			for field in ["player_x", "camera_x"]:
				if not (slot.get(field) is float or slot.get(field) is int) or not is_finite(float(slot[field])) or absf(slot[field]) > 1000000000: return false
			if not slot.get("objects") is Array or slot.objects.size() > 600: return false
			for object in slot.objects:
				if not _valid_object(object) or not _valid_stats(object): return false
			if not preload("res://scripts/structure_links.gd").valid_state(slot.world.get("connections", []), slot.objects): return false
	return true

static func save_game(paper: String, objects: Array, bag: Dictionary, camera_x: float, player_x: float, equipped_weapon: Dictionary = {}, world: Dictionary = {}) -> Dictionary:
	var world_data: Dictionary = _json_value(world)
	if not world.is_empty() and not _valid_world(world_data):
		return {"ok": false, "message": "地图存档状态无效，原作品已保留"}
	var payload := {
		"version": 2 if world.is_empty() else 3,
		"paper": paper,
		"objects": objects,
		"bag": bag,
		"cameraX": camera_x,
		"playerX": player_x,
		"equipped_weapon": equipped_weapon,
	}
	if not world.is_empty(): payload.world = world_data
	var encoded: Dictionary = _json_value(payload)
	if paper not in ["draft", "textbook"] or objects.size() > 600 or not _valid_bag(encoded.bag):
		return {"ok": false, "message": "作品数据无效，原作品已保留"}
	if not is_finite(camera_x) or not is_finite(player_x) or absf(camera_x) > 1000000000 or absf(player_x) > 1000000000:
		return {"ok": false, "message": "作品位置无效，原作品已保留"}
	for object in encoded.objects:
		if not _valid_object(object) or not _valid_stats(object):
			return {"ok": false, "message": "造物数据无效，原作品已保留"}
	if not preload("res://scripts/structure_links.gd").valid_state(world_data.get("connections", []), encoded.objects):
		return {"ok": false, "message": "结构连接无效，原作品已保留"}
	for entry in encoded.bag.entries:
		if not _valid_stats(entry): return {"ok": false, "message": "图纸数据无效，原作品已保留"}
	if not equipped_weapon.is_empty() and (encoded.equipped_weapon.get("role", "") != "weapon" or not _valid_object(encoded.equipped_weapon) or not _valid_stats(encoded.equipped_weapon)):
		return {"ok": false, "message": "装备数据无效，原作品已保留"}
	var save_path := MEDIEVAL_SAVE_PATH if world.get("id", "") == "medieval-v1" else SAVE_PATH
	var json := JSON.stringify(encoded)
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return {"ok": false, "message": "无法打开本地存档"}
	file.store_string(json)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "message": "写入作品失败，原作品已保留"}
	if FileAccess.file_exists(save_path):
		if DirAccess.copy_absolute(save_path, save_path + ".bak") != OK:
			return {"ok": false, "message": "备份作品失败，原作品已保留"}
	if DirAccess.rename_absolute(temporary, save_path) != OK:
		return {"ok": false, "message": "保存作品失败，原作品已保留"}
	return {"ok": true, "message": "城堡已保存在本机"}

static func load_game(expected_world_id: String = "") -> Dictionary:
	var source := MEDIEVAL_SAVE_PATH if expected_world_id == "medieval-v1" else SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else LEGACY_SAVE_PATH
	if not FileAccess.file_exists(source):
		return {"data": {}, "error": "还没有存档"}
	var file := FileAccess.open(source, FileAccess.READ)
	if not file:
		return {"data": {}, "error": "无法读取本地存档"}
	var payload := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(payload) != OK:
		return {"data": {}, "error": "存档格式无效"}
	var data = json.data
	if not data is Dictionary:
		return {"data": {}, "error": "存档格式无效"}
	if not data.has("version") or (data.version != 1 and data.version != 2 and data.version != 3):
		return {"data": {}, "error": "存档格式无效"}
	if data.version == 3 and not _valid_world(data.get("world")):
		return {"data": {}, "error": "存档中的地图状态无效"}
	var saved_id: String = data.world.id if data.version == 3 else "paper"
	if (not expected_world_id.is_empty() and saved_id != expected_world_id) or (expected_world_id.is_empty() and saved_id == "medieval-v1"):
		return {"data": {}, "error": "存档属于另一张地图，未读取"}
	if data.get("paper", "") != "draft" and data.get("paper", "") != "textbook":
		return {"data": {}, "error": "存档格式无效"}
	if not data.has("objects") or not data.objects is Array:
		return {"data": {}, "error": "存档格式无效"}
	if data.objects.size() > 600:
		return {"data": {}, "error": "存档格式无效"}
	for obj in data.objects:
		if not _valid_object(obj):
			return {"data": {}, "error": "存档中的部件无效"}
	if not preload("res://scripts/structure_links.gd").valid_state(data.get("world", {}).get("connections", []), data.objects):
		return {"data": {}, "error": "存档中的结构连接无效"}
	if data.version == 1:
		data.bag = {"entries": [], "next_id": 1, "hotbar": [0, 0, 0, 0, 0, 0]}
	if data.version >= 2:
		if not data.has("bag"):
			data.bag = {"entries": [], "next_id": 1, "hotbar": [0, 0, 0, 0, 0, 0]}
		if not data.bag.has("hotbar"):
			data.bag.hotbar = [0, 0, 0, 0, 0, 0]
			for i in range(min(6, data.bag.get("entries", []).size())):
				var entry = data.bag.entries[i]
				data.bag.hotbar[i] = entry.get("id", 0) if entry is Dictionary else 0
		if not _valid_bag(data.bag):
			return {"data": {}, "error": "存档中的图纸背包无效"}
		if not data.has("cameraX") or not data.cameraX is float and not data.cameraX is int:
			return {"data": {}, "error": "存档中的位置无效"}
		if not data.has("playerX") or not data.playerX is float and not data.playerX is int:
			return {"data": {}, "error": "存档中的位置无效"}
		if absf(data.cameraX) > 1000000000 or absf(data.playerX) > 1000000000:
			return {"data": {}, "error": "存档中的位置无效"}
	var weapon_data = data.get("equipped_weapon", {})
	if not weapon_data is Dictionary or (not weapon_data.is_empty() and (weapon_data.get("role", "") != "weapon" or not _valid_object(weapon_data) or not _valid_stats(weapon_data))):
		return {"data": {}, "error": "存档中的武器无效"}
	for obj in data.objects:
		if not _valid_stats(obj): return {"data": {}, "error": "存档中的部件属性无效"}
	for entry in data.bag.entries:
		if not _valid_stats(entry): return {"data": {}, "error": "存档中的图纸属性无效"}
	data.equipped_weapon = weapon_data
	_restore_vectors(data)
	for slot in data.get("world", {}).get("maps", {}).values():
		_restore_vectors({"objects": slot.objects})
	if not weapon_data.is_empty():
		if weapon_data.has("grip"):
			weapon_data.grip = Vector2(float(weapon_data.grip.x), float(weapon_data.grip.y))
		for path in weapon_data.paths:
			var points: Array = []
			for point in path.points: points.append(Vector2(float(point.x), float(point.y)))
			path.points = points
	return {"data": data, "error": ""}

static func _valid_stats(data: Dictionary) -> bool:
	if data.has("damage_cuts") and not PaperObjectDamage.valid_cuts(data.damage_cuts):return false
	if data.has("weapon_type") and not PaperWeaponTypes.valid(data.weapon_type): return false
	if data.has("grip") and not _valid_point(data.grip): return false
	if data.get("role", "") not in ["", "weapon", "building"]: return false
	if data.has("dynamic") and not data.dynamic is bool: return false
	for key in ["reach", "damage", "cooldown", "health", "max_health"]:
		if data.has(key):
			if not data[key] is float and not data[key] is int: return false
			if not is_finite(float(data[key])) or data[key] <= 0: return false
	if data.get("role", "") == "weapon":
		return data.has("paths") and not data.paths.is_empty() and data.get("reach", 0) >= 0.8 and data.get("reach", 100) <= 2.7 and data.get("damage", 100) <= 40 and data.get("cooldown", 0) >= 0.3 and data.get("cooldown", 100) <= 1
	if data.get("role", "") == "building":
		return data.has("dynamic") and data.get("health", 0) > 0 and data.get("max_health", 10000) <= 1000
	return true
