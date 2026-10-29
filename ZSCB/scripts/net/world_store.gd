class_name PaperWorldStore
extends RefCounted

const Codec := preload("res://scripts/net/codec.gd")
const Validation := preload("res://scripts/net/validation.gd")
const SCHEMA_VERSION := 1
const MAX_WORLD_POINTS := 131072
const MAPS := ["paper", "knowledge-v1", "nature-v1", "medieval-v1"]

var directory: String
var credential_directory: String

func _init(path: String = "user://network_worlds") -> void:
	directory = path.trim_suffix("/")
	credential_directory = directory + "_credentials"

static func token() -> String:
	var bytes := Crypto.new().generate_random_bytes(32)
	return bytes.hex_encode() if bytes.size() == 32 else ""

static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "data": {}}

static func _valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 96: return false
	for index in id.length():
		var code := id.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95): return false
	return true

static func _integer(value: Variant, minimum: int = 1) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floorf(float(value)) and value >= minimum and value <= 2147483647

static func _text(value: Variant, maximum: int = 128) -> bool:
	return value is String and not value.is_empty() and value.length() <= maximum

static func _contains_secret(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if key in ["owner_token", "member_credentials", "token", "reconnect_token", "credentials", "password"] or _contains_secret(value[key]): return true
	elif value is Array:
		for item in value:
			if _contains_secret(item): return true
	return false

static func _valid_data(data: Variant) -> bool:
	if not data is Dictionary or not data.get("objects") is Array or data.objects.size() > 600: return false
	if data.get("map_id", "paper") not in MAPS or data.get("paper", "draft") not in ["draft", "textbook"]: return false
	if not _integer(data.get("next_id", 1)): return false
	if data.has("owner_id") and not _text(data.owner_id): return false
	if data.has("world") and not data.world is Dictionary: return false
	if not preload("res://scripts/structure_links.gd").valid_state(data.get("world", {}).get("connections", []), data.objects): return false
	if data.get("map_id", "paper") == "medieval-v1" and not preload("res://scripts/medieval_world.gd").validate_snapshot(data.get("world",{})): return false
	if _contains_secret(data): return false
	var ids := {}
	var total := 0
	for object in data.objects:
		if not object is Dictionary or not Validation.object(object).ok: return false
		if object.has("damage_cuts") and not PaperObjectDamage.valid_cuts(object.damage_cuts):return false
		if not object.has("x") or not object.has("y"): return false
		if not _text(object.get("id")) or not _text(object.get("author")) or not _integer(object.get("version")): return false
		if ids.has(object.id): return false
		ids[object.id] = true
		for stat in ["health", "max_health"]:
			if not Validation._number(object.get(stat), 1000) or float(object[stat]) <= 0: return false
		if object.health > object.max_health: return false
		for path in object.paths:
			total += path.points.size()
			if total > MAX_WORLD_POINTS: return false
	return true

static func _valid_members(value: Variant, owner_id: String, owner_token: String) -> bool:
	if not value is Array or value.size() > 256: return false
	var ids := {}
	var tokens := {}
	for member in value:
		if not member is Dictionary or not _text(member.get("id"), 96) or not _text(member.get("token"), 256): return false
		if member.id == owner_id or member.token == owner_token or ids.has(member.id) or tokens.has(member.token): return false
		ids[member.id] = true
		tokens[member.token] = true
	return true

func save(id: String, data: Dictionary) -> Dictionary:
	if not _valid_id(id): return _failure("世界编号无效")
	if not _text(data.get("owner_token"), 256): return _failure("缺少世界所有者凭据")
	# Round-trip first limits arbitrary metadata, recursion and nonfinite values.
	var encoded := Codec.encode(data)
	if encoded.is_empty(): return _failure("世界数据超出限制或含无效值")
	var copy: Dictionary = Codec.decode(encoded)
	var owner_token: String = copy.owner_token
	copy.erase("owner_token")
	var members_provided := copy.has("member_credentials")
	var members: Variant = copy.get("member_credentials", [])
	copy.erase("member_credentials")
	if not _valid_data(copy): return _failure("世界数据无效，原存档已保留")
	var owner_id: String = copy.get("owner_id", "")
	if members_provided and not _valid_members(members, owner_id, owner_token): return _failure("世界成员凭据无效，原存档已保留")
	var content := Codec.encode({"schema": SCHEMA_VERSION, "data": copy})
	if content.is_empty(): return _failure("世界快照超出限制")
	if not _make_directory(directory) or not _make_directory(credential_directory): return _failure("无法创建世界存储目录")
	if not _protect(credential_directory, true): return _failure("无法保护所有者凭据目录")
	var credential_path := credential_directory.path_join(id + ".json")
	if FileAccess.file_exists(credential_path):
		var existing := _read_credentials(credential_path, owner_id)
		if not existing.ok or existing.data.owner_token != owner_token: return _failure("世界所有者凭据不匹配")
		if not members_provided: members = existing.data.member_credentials
	# Publish no world changes until the complete private credential record has
	# atomically replaced its predecessor. Missing optional members retain history.
	if members_provided or not FileAccess.file_exists(credential_path):
		var credential_content := Codec.encode({"schema": SCHEMA_VERSION, "owner_token": owner_token, "member_credentials": members})
		if credential_content.is_empty(): return _failure("世界成员凭据超出限制")
		var credential_result := _replace(credential_path, credential_content, true, false)
		if not credential_result.ok: return credential_result
	var path := directory.path_join(id + ".json")
	# Never rotate a corrupt primary over the last valid recovery snapshot.
	var backup_primary := false
	if FileAccess.file_exists(path):
		backup_primary = _read_world(path).ok
	return _replace(path, content, false, backup_primary)

func load_world(id: String) -> Dictionary:
	if not _valid_id(id): return _failure("世界编号无效")
	var path := directory.path_join(id + ".json")
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		var missing := _failure("没有找到世界存档")
		missing.not_found = true
		return missing
	var result := _read_world(path)
	if not result.ok:
		result = _read_world(path + ".bak")
		if not result.ok: return _failure("世界存档与备份均无效，未载入")
		result.recovered = true
	var credentials := _read_credentials(credential_directory.path_join(id + ".json"), result.data.get("owner_id", ""))
	if not credentials.ok: return _failure("世界所有者凭据不可用，未载入")
	result.data.owner_token = credentials.data.owner_token
	result.data.member_credentials = credentials.data.member_credentials
	return result

static func _read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	if file.get_length() > Codec.MAX_BYTES:
		file.close()
		return null
	var content := file.get_as_text()
	file.close()
	return Codec.decode(content)

static func _read_world(path: String) -> Dictionary:
	var payload: Variant = _read_file(path)
	if not payload is Dictionary or payload.get("schema") != SCHEMA_VERSION or not _valid_data(payload.get("data")): return _failure("世界存档格式无效")
	return {"ok": true, "error": "", "data": payload.data}

static func _read_credentials(path: String, owner_id: String = "") -> Dictionary:
	var payload: Variant = _read_file(path)
	if not payload is Dictionary or payload.get("schema") != SCHEMA_VERSION or not _text(payload.get("owner_token"), 256): return _failure("世界所有者凭据无效")
	var members: Variant = payload.get("member_credentials", [])
	if not _valid_members(members, owner_id, payload.owner_token): return _failure("世界成员凭据无效")
	payload.member_credentials = members
	return {"ok": true, "error": "", "data": payload}

static func _protect(path: String, is_directory: bool) -> bool:
	if OS.get_name() in ["macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "iOS"]:
		var flags := FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
		if is_directory: flags |= FileAccess.UNIX_EXECUTE_OWNER
		return FileAccess.set_unix_permissions(path, flags) == OK
	# Other platforms inherit the private per-user data directory's ACL.
	return true

static func _make_directory(path: String) -> bool:
	var ancestor := path
	while not ancestor.is_empty() and not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor): return false
		var parent := ancestor.get_base_dir()
		if parent == ancestor: break
		ancestor = parent
	return DirAccess.make_dir_recursive_absolute(path) == OK

static func _replace(path: String, content: String, secure: bool, backup: bool) -> Dictionary:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _failure("无法打开存档临时文件")
	if secure and not _protect(temporary, false):
		file.close()
		DirAccess.remove_absolute(temporary)
		return _failure("无法保护所有者凭据文件")
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("写入世界失败，原存档已保留")
	if backup:
		var backup_temporary := path + ".bak.tmp"
		if DirAccess.copy_absolute(path, backup_temporary) != OK or DirAccess.rename_absolute(backup_temporary, path + ".bak") != OK:
			DirAccess.remove_absolute(temporary)
			return _failure("备份世界失败，原存档已保留")
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("替换世界失败，原存档已保留")
	return {"ok": true, "error": ""}
