class_name MedievalCatalog
extends RefCounted
## Generated object definitions; cached once and returned by value.
const WORLD_LENGTH := 180.0
const MANIFEST := "res://assets/medieval/expansion/manifest.json"
const FAUNA_MANIFEST := "res://assets/medieval/fauna/manifest.json"
static var _entries: Dictionary = {}
static func _ensure_loaded() -> void:
	if not _entries.is_empty(): return
	for path in [MANIFEST,FAUNA_MANIFEST]:
		if not FileAccess.file_exists(path): continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: _entries.merge(parsed.get("entries",{}))
static func entries() -> Dictionary:
	_ensure_loaded()
	return _entries.duplicate(true)
static func has_kind(kind: String) -> bool:
	_ensure_loaded()
	return _entries.has(kind)
static func definition(kind: String) -> Dictionary:
	_ensure_loaded()
	return _entries.get(kind,{}).duplicate(true)
static func dimensions(kind: String) -> Vector2:
	var d := definition(kind)
	return Vector2(d.get("width",1),d.get("height",1))
static func health(kind: String) -> float: return float(definition(kind).get("health",80))
static func category(kind: String) -> String: return str(definition(kind).get("category","prop"))
static func walk_edges(kind: String) -> Array: return definition(kind).get("walk_edges",[])
