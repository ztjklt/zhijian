extends RefCounted
## Local personal data only. This format never supplies world commands.
const Codec := preload("res://scripts/net/codec.gd")
const VERSION := 1

static func valid_bag(bag: Variant) -> bool:
	if not bag is Dictionary: return false
	var plain: Dictionary = SaveStore._json_value(bag)
	if not SaveStore._valid_bag(plain): return false
	var highest := 0
	for entry in plain.entries:
		if not Codec._number(entry.id) or entry.id < 1 or entry.id != floorf(entry.id) or not SaveStore._valid_stats(entry): return false
		highest = maxi(highest, int(entry.id))
		var total := 0
		for path in entry.paths: total += path.points.size()
		if total > DrawingRules.MAX_POINTS: return false
	return Codec._number(plain.next_id) and plain.next_id == floorf(plain.next_id) and plain.next_id > highest

static func valid_pending(items: Variant) -> bool:
	if not items is Array or items.size() > 2: return false
	for item in items:
		if not item is Dictionary or item.size() != 2 or item.get("op", "") not in ["spawn", "equip_drawing"]: return false
		var object: Variant = item.get("object")
		if not object is Dictionary: return false
		if item.op == "equip_drawing":
			if not PaperNetValidation.weapon(object).ok: return false
		else:
			if not PaperNetValidation.object(object).ok: return false
	return true

static func valid(profile: Variant) -> bool:
	if not profile is Dictionary: return false
	var version: Variant = profile.get("profile_version", 0)
	if not Codec._number(version) or (version != 0 and version != VERSION): return false
	if profile.has("bag") and not valid_bag(profile.bag): return false
	if not valid_pending(profile.get("pending_blueprints", [])): return false
	if not profile.get("pending_blueprints", []).is_empty() and not profile.has("bag"): return false
	var weapon: Variant = profile.get("weapon", {})
	if not weapon is Dictionary: return false
	if not weapon.is_empty():
		var plain: Dictionary = SaveStore._json_value(weapon)
		plain.x = 0; plain.y = 0
		if not SaveStore._valid_object(plain) or not SaveStore._valid_stats(plain): return false
	return true

static func read_one(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false}
	if file.get_length() > Codec.MAX_BYTES: return {"ok": false}
	var profile: Variant = Codec.decode(file.get_as_text())
	if profile is Dictionary and profile.get("profile_version", 0) != 0 and profile.get("profile_version", 0) != VERSION: return {"ok": false, "future": true}
	return {"ok": true, "profile": profile} if valid(profile) else {"ok": false}

static func load_profile(path: String) -> Dictionary:
	var exists := FileAccess.file_exists(path)
	var primary := read_one(path) if exists else {"ok": false}
	if primary.ok: return {"ok": true, "profile": primary.profile, "error": ""}
	if primary.get("future", false): return {"ok": false, "profile": {}, "error": "个人资料来自更新版本，原文件已保留，请使用匹配版本"}
	var backup := read_one(path + ".bak") if FileAccess.file_exists(path + ".bak") else {"ok": false}
	if backup.ok: return {"ok": true, "profile": backup.profile, "error": "已从上次有效个人资料恢复"}
	if not exists and not FileAccess.file_exists(path + ".bak"): return {"ok": true, "profile": {}, "error": ""}
	return {"ok": false, "profile": {}, "error": "个人资料及备份无法读取，原文件已保留，自动覆盖已停止"}

static func protect(path: String) -> bool:
	if OS.get_name() in ["Linux", "macOS", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		return FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER) == OK
	return true

static func save_profile(path: String, profile: Dictionary) -> Dictionary:
	var snapshot := profile.duplicate(true)
	snapshot.profile_version = VERSION
	if not valid(snapshot): return {"ok": false, "error": "个人资料校验失败，原资料已保留"}
	var content := Codec.encode(snapshot)
	if content == "": return {"ok": false, "error": "个人图纸超出本机存储容量，原资料已保留"}
	var previous := read_one(path) if FileAccess.file_exists(path) else {"ok": false}
	if previous.get("future", false): return {"ok": false, "error": "个人资料版本不匹配，原资料已保留"}
	var temporary := path + ".tmp"
	if DirAccess.dir_exists_absolute(temporary): return {"ok": false, "error": "个人资料临时路径不可写"}
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法打开个人资料临时文件"}
	if not protect(temporary): file.close(); return {"ok": false, "error": "无法保护个人资料文件"}
	file.store_string(content); file.flush()
	var error := file.get_error(); file.close()
	if error != OK: return {"ok": false, "error": "个人资料写入失败，原资料已保留"}
	# A corrupt primary must never displace the last valid recovery version.
	if previous.ok:
		var backup := path + ".bak.tmp"
		if DirAccess.dir_exists_absolute(backup) or DirAccess.copy_absolute(path, backup) != OK or not protect(backup) or DirAccess.rename_absolute(backup, path + ".bak") != OK:
			return {"ok": false, "error": "个人资料备份失败，原资料已保留"}
	if DirAccess.rename_absolute(temporary, path) != OK: return {"ok": false, "error": "个人资料替换失败，原资料已保留"}
	return {"ok": true, "error": ""}
