class_name PaperNetCodec
extends RefCounted

# Bump when authority rules, map geometry, or the wire contract changes.
const PROTOCOL := 11
const RELEASE := "20261030-r22 · 创作与携物候选"

# One codec is shared by commands, chunked snapshots and persisted worlds. Never
# use str_to_var/bytes_to_var on peer input: those formats can construct objects.
const MAX_BYTES := 16 * 1024 * 1024
const MAX_DEPTH := 32
const MAX_NODES := 750000
const MAX_STRING := 1024 * 1024
const MAX_COLLECTION := 131072
const MAX_EXACT_INTEGER := 9007199254740991

static func encode(value: Variant) -> String:
	var budget := {"ok": true, "nodes": 0}
	var plain: Variant = _convert(value, 0, budget, false)
	if not budget.ok: return ""
	var result := JSON.stringify(plain, "", true, true)
	return result if result.to_utf8_buffer().size() <= MAX_BYTES else ""

static func decode(text: String) -> Variant:
	if text.length() > MAX_BYTES or text.to_utf8_buffer().size() > MAX_BYTES or not _safe_depth(text): return null
	var json := JSON.new()
	if json.parse(text) != OK: return null
	var budget := {"ok": true, "nodes": 0}
	var result: Variant = _convert(json.data, 0, budget, true)
	return result if budget.ok else null

static func _safe_depth(text: String) -> bool:
	var depth := 0
	var quoted := false
	var escaped := false
	for index in text.length():
		var code := text.unicode_at(index)
		if quoted:
			if escaped: escaped = false
			elif code == 92: escaped = true
			elif code == 34: quoted = false
		elif code == 34: quoted = true
		elif code == 91 or code == 123:
			depth += 1
			if depth > MAX_DEPTH: return false
		elif code == 93 or code == 125:
			depth -= 1
			if depth < 0: return false
		elif code == 69 or code == 101:
			# Guard parser overflow warnings too: untrusted input must not flood logs.
			var cursor := index + 1
			if cursor < text.length() and text.unicode_at(cursor) in [43, 45]: cursor += 1
			var start := cursor
			while cursor < text.length() and text.unicode_at(cursor) >= 48 and text.unicode_at(cursor) <= 57: cursor += 1
			var exponent := text.substr(start, cursor - start).trim_prefix("0")
			if exponent.length() > 3 or int(exponent) > 308: return false
	return not quoted and depth == 0

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value)) <= MAX_EXACT_INTEGER

static func _convert(value: Variant, depth: int, budget: Dictionary, restoring: bool) -> Variant:
	budget.nodes += 1
	if not budget.ok or depth > MAX_DEPTH or budget.nodes > MAX_NODES:
		budget.ok = false
		return null
	if value == null or value is bool: return value
	if value is float or value is int:
		if not _number(value): budget.ok = false
		return value
	if value is String:
		if value.length() > MAX_STRING: budget.ok = false
		return value
	if not restoring and value is Vector2:
		if depth + 2 > MAX_DEPTH or not _number(value.x) or not _number(value.y): budget.ok = false
		return {"_v": [value.x, value.y]}
	if not restoring and value is Color:
		if depth + 2 > MAX_DEPTH: budget.ok = false
		for component in [value.r, value.g, value.b, value.a]:
			if not _number(component): budget.ok = false
		return {"_c": [value.r, value.g, value.b, value.a]}
	if value is Array or (not restoring and value is PackedVector2Array):
		if depth >= MAX_DEPTH or value.size() > MAX_COLLECTION:
			budget.ok = false
			return null
		var array: Array = []
		for item in value:
			array.append(_convert(item, depth + 1, budget, restoring))
			if not budget.ok: return null
		return array
	if value is Dictionary:
		if depth >= MAX_DEPTH or value.size() > MAX_COLLECTION:
			budget.ok = false
			return null
		if value.has("_v") or value.has("_c"):
			var marker := "_v" if value.has("_v") else "_c"
			var parts: Variant = value[marker]
			if value.size() != 1 or not parts is Array or parts.size() != (2 if marker == "_v" else 4):
				budget.ok = false
				return null
			for part in parts:
				if not _number(part):
					budget.ok = false
					return null
			if restoring:
				return Vector2(parts[0], parts[1]) if marker == "_v" else Color(parts[0], parts[1], parts[2], parts[3])
		var dictionary := {}
		for key in value:
			if not (key is String or key is StringName):
				budget.ok = false
				return null
			# Godot's dictionary dot writes use StringName, including world.maps.
			# Normalize all textual keys before JSON and reject lossy collisions.
			var normalized := String(key)
			if normalized.length() > 256 or dictionary.has(normalized):
				budget.ok = false
				return null
			dictionary[normalized] = _convert(value[key], depth + 1, budget, restoring)
			if not budget.ok: return null
		return dictionary
	budget.ok = false
	return null
