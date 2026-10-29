class_name BlueprintBag

const MAX_ENTRIES := 128
const PAGE_SIZE := 12

const NAMES := {
	"wall": "城墙", "tower": "塔楼", "gate": "门洞", "ramp": "斜坡",
	"platform": "平台", "ladder": "梯子", "freehand": "手绘建筑", "weapon": "手绘武器",
	"circle": "圆形", "ellipse": "椭圆", "rectangle": "矩形", "triangle": "三角形", "line": "直线",
}

static func _copy(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _copy(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_copy(item))
		return result
	return value

static func new_bag() -> Dictionary:
	return {"entries": [], "next_id": 1, "hotbar": [0, 0, 0, 0, 0, 0]}

static func find_entry(bag: Dictionary, id: int) -> Dictionary:
	for entry in bag.entries:
		if entry.id == id:
			return entry
	return {}

static func find_index(bag: Dictionary, id: int) -> int:
	for i in bag.entries.size():
		if bag.entries[i].id == id:
			return i
	return -1

static func add_entry(bag: Dictionary, object: Dictionary) -> Dictionary:
	if bag.entries.size() >= MAX_ENTRIES:
		return {"entry": {}, "error": "图纸背包已满，请先整理"}
	var id: int = bag.next_id
	bag.next_id = id + 1
	var kind: String = object.get("kind", "freehand")
	var entry := {
		"id": id,
		"name": (AutoSculpt.label(kind) if object.get("source", "") == "sculpt" else NAMES.get(kind, "手绘作品")) + " " + str(id),
		"category": "地形" if kind == "ramp" or kind == "platform" else "建筑",
		"source": object.get("source", "own"),
		"kind": kind,
		"paths": _copy(object.paths),
		"favorite": false,
	}
	for key in ["role", "reach", "damage", "cooldown", "dynamic", "health", "max_health", "grip", "weapon_type", "model_fill"]:
		if object.has(key): entry[key] = object[key]
	if object.get("role", "") == "weapon":
		entry.category = "武器"
		entry.name = "手绘" + PaperWeaponTypes.label(object) + " " + str(id)
	bag.entries.append(entry)
	for slot in range(6):
		if bag.hotbar[slot] == 0:
			bag.hotbar[slot] = id
			break
	return {"entry": entry, "error": ""}

static func duplicate_entry(bag: Dictionary, id: int) -> Dictionary:
	var source := find_entry(bag, id)
	if source.is_empty():
		return {"entry": {}, "error": "图纸不存在"}
	if bag.entries.size() >= MAX_ENTRIES:
		return {"entry": {}, "error": "图纸背包已满"}
	var clone: Dictionary = _copy(source)
	clone.id = bag.next_id
	bag.next_id += 1
	clone.name = source.name + " 副本"
	if clone.name.length() > 72:
		clone.name = "图纸副本 " + str(clone.id)
	clone.favorite = false
	bag.entries.append(clone)
	return {"entry": clone, "error": ""}

static func remove_entry(bag: Dictionary, id: int) -> bool:
	var index := find_index(bag, id)
	if index < 0:
		return false
	bag.entries.remove_at(index)
	for slot in range(6):
		if bag.hotbar[slot] == id:
			bag.hotbar[slot] = 0
	return true

static func bind_hotbar(bag: Dictionary, slot: int, id: int) -> bool:
	if slot < 0 or slot > 5:
		return false
	if find_entry(bag, id).is_empty():
		return false
	bag.hotbar[slot] = id
	return true

static func filter_entries(bag: Dictionary, category: String, query: String) -> Array:
	var result: Array = []
	var search := query.to_lower()
	for entry in bag.entries:
		if (category == "全部" or entry.category == category) \
			and (search.is_empty() or entry.name.to_lower().contains(search)):
			result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.favorite != b.favorite:
			return a.favorite
		return a.id > b.id
	)
	return result

static func make_object(entry: Dictionary, x: float, y: float) -> Dictionary:
	var obj := {
		"source": entry.source, "kind": entry.kind,
		"x": x, "y": y,
		"paths": _copy(entry.paths),
		"dynamic": true,
		"angle": 0.0,
		"blueprint_id": entry.id,
	}

	for key in ["role", "reach", "damage", "cooldown", "dynamic", "health", "max_health", "grip", "weapon_type", "model_fill"]:
		if entry.has(key): obj[key] = entry[key]
	if obj.get("role", "") == "building": obj.health = obj.get("max_health", 120.0)
	return obj
