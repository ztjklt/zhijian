extends Node
## Device-local connection metadata. Keys are scoped to the endpoint and stay in memory or the macOS login keychain.
signal changed
signal role_changed(role: String)
signal connection_changed(id: String)

const Roles := preload("res://scripts/divine_roles.gd")
const ROLES := Roles.ALL
const OFFICIAL := "https://api.deepseek.com"
const STORE := "user://harness_connections.json"
const BLOCKING := ["credentials_rejected","permission_denied","quota","rate_limited","tools_unsupported","bad_endpoint"]
const TURN_RETRY_SECONDS := [5, 15, 30, 60]
const STATUS := {
	"not_configured":"请在设置中为这个角色绑定模型连接。",
	"needs_key":"请为这条连接输入本次会话的 API Key。",
	"ready":"连接可用",
	"credentials_rejected":"服务商拒绝了 API Key，请更换或验证 Key。",
	"permission_denied":"此 API Key 无权调用所选模型或端点，请检查服务商权限。",
	"quota":"服务商显示余额或额度不足，请检查账户后验证连接。",
	"rate_limited":"请求频率受限，请稍后验证连接。",
	"tools_unsupported":"服务商明确拒绝所选端点或模型的函数工具。",
	"no_tool_action":"模型本回合没有提交工具动作，连接保留。",
	"request_rejected":"服务商拒绝了本回合的请求，连接保留。",
	"bad_endpoint":"请核对 API 根地址和模型 ID。",
	"reconfigured":"本次请求已取消，连接现在使用新的设置。"
}
var _connections: Dictionary = {}
var _bindings: Dictionary = {}
var _night_adventurer := ""
var _keys: Dictionary = {}
var _remembered := {}
var _vault_errors := {}
var _vault := preload("res://scripts/macos_credentials.gd").new()
var _blocks: Dictionary = {}
var _turn_delays: Dictionary = {}
var _checks: Dictionary = {}
var _generations: Dictionary = {}
var _revisions: Dictionary = {}
var _endpoint := RegEx.create_from_string("^https?://(?:[A-Za-z0-9][A-Za-z0-9.-]*|\\[::1\\])(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~/-]*)?$")
var _model := RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$")
var _id := RegEx.create_from_string("^[0-9a-f]{24}$")
var _key := RegEx.create_from_string("^[A-Za-z0-9._~+/=-]{8,2048}$")

func _ready() -> void:
	set_process(false)
	for role in ROLES: _generations[role]=1
	if not FileAccess.file_exists(STORE): return
	var file := FileAccess.open(STORE,FileAccess.READ)
	if file==null or file.get_length()>65536: return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version")!=1: return
	var rows: Variant = data.get("connections")
	if rows is Array:
		for row in rows.slice(0,32):
			if not row is Dictionary or not row.get("id") is String or _id.search(row.id)==null: continue
			var clean := _config(row)
			if not clean.is_empty():
				if row.get("key_storage") in ["remember","session"]:
					clean.key_storage=row.key_storage
				_connections[row.id]=clean
				_revisions[row.id]=1
	var saved: Variant = data.get("bindings")
	if saved is Dictionary:
		for role in ROLES:
			if _connections.has(saved.get(role)): _bindings[role]=saved[role]
	if OS.get_name() == "macOS" and not ProjectSettings.get_setting("paper/divine_demo",false):
		var check_only := OS.get_cmdline_user_args().has("--zhijian-readiness")
		for row: Dictionary in _connections.values():
			if not check_only or row.id in [binding("companion"),binding("priest"),binding("war_god")]:
				_restore_key(row)

func _restore_key(row: Dictionary) -> void:
	var result := _vault.request("restore",row)
	if result.state == "ok" and _key.search(result.get("key","")) != null:
		_keys[row.id] = result.key
		_remembered[row.id] = true
	elif result.state != "missing":
		_vault_errors[row.id] = _vault_failure(result.state).error

func _vault_failure(state: String) -> Dictionary:
	return _fail("keychain_unavailable","请先解锁本机登录钥匙串，再重试。" if state == "locked" else "无法访问本机登录钥匙串，请检查凭据程序并重试。")

func _missing_key(id: String) -> Dictionary:
	if _vault_errors.has(id):
		return {"id":id,"code":"keychain_unavailable","message":_vault_errors[id],"ready":false}
	return {"id":id,"code":"needs_key","message":STATUS.needs_key,"ready":false}

func _config(config: Dictionary, for_discovery := false) -> Dictionary:
	for field in ["provider","label","model","base_url","reasoning"]:
		if config.has(field) and not config[field] is String: return {}
	var provider: String = config.get("provider","deepseek-official")
	if provider not in ["deepseek-official","compatible"]: return {}
	var label: String = config.get("label","").strip_edges()
	if label.is_empty(): label="DeepSeek" if provider=="deepseek-official" else "兼容连接"
	if label.length()>60: return {}
	var root: String = config.get("base_url","").strip_edges().rstrip("/")
	if provider=="deepseek-official":
		if not root.is_empty() and root!=OFFICIAL: return {}
		root=OFFICIAL
	elif root.length()>400 or _endpoint.search(root)==null:
		return {}
	var delimiter := root.find("://")
	var slash := root.find("/",delimiter+3)
	var authority := root.substr(delimiter+3,slash-delimiter-3 if slash>=0 else -1)
	var path := "" if slash<0 else root.substr(slash)
	var port_at := authority.rfind(":")
	if port_at>=0 and not authority.ends_with("]"):
		var port := int(authority.substr(port_at+1))
		if port<1 or port>65535: return {}
	for segment in path.split("/"):
		if segment in [".",".."]: return {}
	if path.contains("//"): return {}
	if root.begins_with("http://") and not (authority=="127.0.0.1" or authority.begins_with("127.0.0.1:") or authority=="localhost" or authority.begins_with("localhost:") or authority=="[::1]" or authority.begins_with("[::1]:")):
		return {}
	root=root.substr(0,delimiter+3)+authority.to_lower()+path
	var model: String = config.get("model","").strip_edges()
	if for_discovery: model="model-list"
	elif provider=="deepseek-official" and model.is_empty(): model="deepseek-flash"
	if _model.search(model)==null: return {}
	var reasoning: String = config.get("reasoning","off")
	if reasoning not in (["off","low","high","max"] if provider=="deepseek-official" else ["off","low","medium","high"]): return {}
	return {"id":config.get("id",""),"label":label,"provider":provider,"base_url":root,"model":model,"reasoning":reasoning}

func _fail(code: String, message: String) -> Dictionary:
	return {"ok":false,"code":code,"error":message}

func _contains_secret(config: Dictionary, key: String) -> bool:
	if key.is_empty(): return false
	for field in ["label","provider","base_url","model"]:
		if str(config.get(field,"")).contains(key): return true
	return false

func _persist(rows: Dictionary, bindings: Dictionary) -> bool:
	var file := FileAccess.open(STORE+".tmp",FileAccess.WRITE)
	if file==null: return false
	if not file.store_string(JSON.stringify({"version":1,"connections":rows.values(),"bindings":bindings})):
		file.close()
		return false
	file.flush()
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(STORE+".tmp"),ProjectSettings.globalize_path(STORE))==OK

func list_connections() -> Array:
	var result := []
	for id in _connections:
		var row: Dictionary = _connections[id].duplicate()
		row.has_key=_keys.has(id)
		row.remembered=_remembered.has(id)
		row.vault_error=_vault_errors.has(id)
		result.append(row)
	return result

func binding(role: String) -> String:
	return str(_bindings.get(role,_night_adventurer if role=="adventurer-lizhou" else ""))

# Explicitly opted-in night slot only. This override lives in the worker process.
func share_night_adventurer() -> void:
	if not binding("adventurer-lizhou").is_empty(): return
	var id := binding("companion")
	if id.is_empty() or binding("war_god") != id or binding("priest") != id: return
	var row: Dictionary = _connections.get(id,{})
	if row.get("provider")=="deepseek-official" and row.get("model")=="deepseek-flash":
		_night_adventurer=id

func role_status(role: String) -> Dictionary:
	if ProjectSettings.get_setting("paper/divine_demo", false):
		return {"id":"","code":"manuscript","message":"演示档使用已生成笔稿。","ready":false}
	var id := binding(role)
	if not id.is_empty() and not _keys.has(id): return _missing_key(id)
	var code := "not_configured" if id.is_empty() else str(_blocks.get(role,"ready"))
	if code == "ready" and _turn_delays.has(role):
		var delay: Dictionary = _turn_delays[role]
		var remaining := int(delay.until) - Time.get_ticks_msec()
		if remaining > 0:
			return {"id":id, "code":delay.code, "ready":false, "retry_after_ms":remaining,
				"message":"%s 等待 %d 秒后可继续。" % [STATUS[delay.code],ceili(remaining / 1000.0)]}
	return {"id":id,"code":code,"message":STATUS.get(code,"模型连接暂不可用。"),"ready":code=="ready"}

# A world handed to a fresh engine keeps this provider's stop or backoff.
# The public route stamp contains no credential material.
func _route_stamp(role: String) -> String:
	var row: Dictionary = _connections.get(binding(role),{})
	return JSON.stringify([row.get("id"),row.get("provider"),row.get("base_url"),row.get("model"),row.get("reasoning")]).sha256_text()

func handoff_limits() -> Dictionary:
	var limits := {}
	for role in ROLES:
		if _blocks.has(role):
			limits[role] = {"route":_route_stamp(role),"code":_blocks[role]}
		elif _turn_delays.has(role):
			var delay: Dictionary = _turn_delays[role]
			var remaining := int(delay.until) - Time.get_ticks_msec()
			if remaining > 0:
				limits[role] = {"route":_route_stamp(role),"code":delay.code,"attempt":delay.attempt,
					"until":Time.get_unix_time_from_system()+remaining/1000.0}
	return limits

func restore_handoff_limits(limits: Dictionary) -> void:
	for role in ROLES:
		var row = limits.get(role)
		if not row is Dictionary or row.get("route") != _route_stamp(role) or binding(role).is_empty(): continue
		if int(_generations.get(role,1)) > 1 or _checks.has(binding(role)): continue
		if row.get("code") in BLOCKING:
			_blocks[role] = row.code
		elif row.get("code") in ["no_tool_action","request_rejected"] and not _blocks.has(role):
			var remaining := clampf(float(row.get("until",0))-Time.get_unix_time_from_system(),0,60)
			if remaining > 0:
				_turn_delays[role] = {"code":row.code,"attempt":clampi(int(row.get("attempt",1)),1,4),
					"owner_id":0,"until":Time.get_ticks_msec()+roundi(remaining*1000)}
				set_process(true)

func connection_status(id: String, for_role := "") -> Dictionary:
	if not _connections.has(id): return {"id":id,"ready":false,"code":"not_configured","message":"找不到连接。"}
	if not _keys.has(id): return _missing_key(id)
	var status: Dictionary = _checks.get(id,{"code":"ready","message":STATUS.ready})
	for role in ROLES:
		if (for_role.is_empty() or role==for_role) and binding(role)==id and _blocks.has(role):
			var code: String = _blocks[role]
			return {"id":id,"ready":false,"code":code,"message":STATUS.get(code,"模型连接暂停。")}
	return {"id":id,"ready":status.code in ["ready","verified","tool_probe_inconclusive"],"code":status.code,"message":status.message}

func save_connection(config: Dictionary, key := "", storage := "keep") -> Dictionary:
	var clean := _config(config)
	if clean.is_empty(): return _fail("invalid_connection","请填写有效的服务地址和模型 ID。")
	if not key.is_empty() and _key.search(key)==null: return _fail("invalid_key","请填写 8 到 2048 字符的 Bearer Key，避免空格与换行。")
	var id = clean.id
	if not id is String: return _fail("invalid_connection","连接编号无效。")
	var previous: Dictionary = _connections.get(id,{})
	if id.is_empty():
		if _connections.size()>=32: return _fail("connection_limit","最多保存 32 条连接。")
		id=Crypto.new().generate_random_bytes(12).hex_encode()
	elif previous.is_empty(): return _fail("invalid_connection","找不到该连接。")
	if _contains_secret(clean,key if not key.is_empty() else str(_keys.get(id,""))):
		return _fail("invalid_connection","请只在 API Key 输入框填写密钥。")
	clean.id=id
	var rows := _connections.duplicate()
	rows[id]=clean
	var scope_changed: bool = previous.get("base_url")!=clean.base_url or previous.get("provider")!=clean.provider
	var route_changed: bool = scope_changed or previous.get("model")!=clean.model or previous.get("reasoning")!=clean.reasoning or not key.is_empty()
	if storage not in ["keep","session","remember"]: return _fail("invalid_connection","请选择 Key 的保存方式。")
	var value := key if not key.is_empty() else "" if scope_changed else str(_keys.get(id,""))
	var remember := storage=="remember" or (storage=="keep" and _remembered.has(id) and not scope_changed)
	if storage != "keep": clean.key_storage = storage
	elif previous.has("key_storage"): clean.key_storage = previous.key_storage
	var prior: Dictionary = {}
	var old_scope_removed := false
	var touched_new := false
	if OS.get_name()=="macOS":
		# Probe the exact former entry, including entries installed since this process started.
		if not previous.is_empty():
			prior = _vault.request("restore",previous)
			if prior.state not in ["ok","missing"]: return _vault_failure(prior.state)
			if prior.state=="ok" and not scope_changed:
				if value.is_empty(): value = prior.key
				if storage=="keep": remember = true
		# A destination from an earlier edit is a distinct credential. Do not
		# silently revive it if the endpoint is changed back without a new key.
		if scope_changed and not previous.is_empty() and value.is_empty():
			var cleared := _vault.request("remove",clean)
			if cleared.state not in ["ok","missing"]: return _vault_failure(cleared.state)
		if remember and not value.is_empty():
			var stored := _vault.request("store",clean,value)
			if stored.state!="ok": return _vault_failure(stored.state)
			touched_new = true
		if prior.get("state")=="ok" and (scope_changed or not remember):
			var removed := _vault.request("remove",previous)
			if removed.state!="ok":
				if touched_new and scope_changed: _vault.request("remove",clean)
				return _vault_failure(removed.state)
			old_scope_removed = true
	elif remember:
		return _vault_failure("unavailable")
	if not _persist(rows,_bindings):
		if touched_new: _vault.request("remove",clean)
		if prior.get("state")=="ok" and (touched_new or old_scope_removed):
			_vault.request("store",previous,prior.key)
		return _fail("write_error","无法保存这台设备的连接设置。")
	route_changed = route_changed or value != str(_keys.get(id,""))
	_connections=rows
	_remembered.erase(id)
	_vault_errors.erase(id)
	if remember and not value.is_empty(): _remembered[id] = true
	if value.is_empty(): _keys.erase(id)
	else: _keys[id]=value
	if route_changed: _reconfigure(id)
	else: changed.emit()
	return {"ok":true,"id":id}

func set_key(id: String, key: String) -> Dictionary:
	if not _connections.has(id): return _fail("invalid_connection","找不到该连接。")
	if key.is_empty() or _key.search(key)==null: return _fail("invalid_key","请输入有效的 API Key。")
	if _contains_secret(_connections[id],key): return _fail("invalid_connection","请从连接名称、模型或地址中移除密钥。")
	return save_connection(_connections[id],key)

func clear_key(id: String) -> Dictionary:
	if not _connections.has(id): return _fail("invalid_connection","找不到该连接。")
	var removed := _vault.request("remove",_connections[id])
	if removed.state not in ["ok","missing"]: return _vault_failure(removed.state)
	_keys.erase(id)
	_remembered.erase(id)
	_vault_errors.erase(id)
	_reconfigure(id)
	return {"ok":true,"id":id}

func remove_connection(id: String) -> Dictionary:
	if not _connections.has(id): return _fail("invalid_connection","找不到该连接。")
	var rows := _connections.duplicate()
	var bindings := _bindings.duplicate()
	var affected := []
	rows.erase(id)
	for role in ROLES:
		if binding(role)==id:
			bindings.erase(role)
			affected.append(role)
	var prior := _vault.request("restore",_connections[id])
	if prior.state not in ["ok","missing"]: return _vault_failure(prior.state)
	if prior.state=="ok":
		var removed := _vault.request("remove",_connections[id])
		if removed.state!="ok": return _vault_failure(removed.state)
	if not _persist(rows,bindings):
		if prior.state=="ok": _vault.request("store",_connections[id],prior.key)
		return _fail("write_error","无法保存这台设备的连接设置。")
	_remembered.erase(id)
	_vault_errors.erase(id)
	_connections=rows
	_bindings=bindings
	_keys.erase(id)
	_checks.erase(id)
	_revisions.erase(id)
	connection_changed.emit(id)
	for role in affected: _refresh_role(role)
	changed.emit()
	return {"ok":true}

func bind_unassigned_gods(id: String) -> Dictionary:
	var record: Dictionary=_connections.get(id,{})
	if record.get("provider")!="deepseek-official" or record.get("model")!="deepseek-flash":
		return _fail("invalid_connection","请选择已添加的 DeepSeek 官方 Flash 连接。")
	var bindings:=_bindings.duplicate()
	var added: Array[String]=[]
	for role in Roles.enabled():
		if binding(role).is_empty():
			bindings[role]=id
			added.append(role)
	if added.is_empty():return {"ok":true,"roles":added}
	if not _persist(_connections,bindings):return _fail("write_error","无法保存角色绑定。")
	_bindings=bindings
	for role in added:_refresh_role(role)
	changed.emit()
	return {"ok":true,"roles":added}

func bind(role: String, id: String) -> Dictionary:
	if role not in ROLES or not id.is_empty() and not _connections.has(id):
		return _fail("invalid_connection","请选择实际角色和已添加的连接。")
	if id==binding(role): return {"ok":true,"id":id}
	var bindings := _bindings.duplicate()
	if id.is_empty(): bindings.erase(role)
	else: bindings[role]=id
	if not _persist(_connections,bindings): return _fail("write_error","无法保存角色绑定。")
	_bindings=bindings
	_refresh_role(role)
	changed.emit()
	return {"ok":true,"id":id}

func _refresh_role(role: String) -> void:
	_generations[role]=int(_generations.get(role,0))+1
	_blocks.erase(role)
	_turn_delays.erase(role)
	role_changed.emit(role)

func _reconfigure(id: String) -> void:
	_revisions[id]=int(_revisions.get(id,0))+1
	_checks.erase(id)
	connection_changed.emit(id)
	for role in ROLES:
		if binding(role)==id: _refresh_role(role)
	changed.emit()

func _grant(id: String, role: String, generation: int) -> Dictionary:
	var config: Dictionary = _connections.get(id,{})
	if config.is_empty() or not _keys.has(id): return {}
	return {"id":id,"role":role,"generation":generation,"provider":config.provider,
		"base_url":config.base_url,"model":config.model,"reasoning":config.reasoning,"key":_keys[id]}

# For the trusted worker bridge only. Never return or log the grant in a panel.
func worker_grant(role: String) -> Dictionary:
	if not role_status(role).ready: return {}
	return _grant(binding(role),role,int(_generations[role]))

func is_current(stamp: Dictionary) -> bool:
	var role: String = stamp.get("role","")
	return role in ROLES and binding(role)==stamp.get("id") and int(_generations[role])==int(stamp.get("generation",-1))

func clear_owner_delay(role: String, owner_id: int) -> void:
	var delay: Dictionary = _turn_delays.get(role,{})
	if delay.get("owner_id") == owner_id:
		_turn_delays.erase(role)
		changed.emit()

func note_success(stamp: Dictionary) -> void:
	if is_current(stamp) and _turn_delays.erase(stamp.role):
		changed.emit()

func note_failure(stamp: Dictionary, code: String) -> void:
	if not is_current(stamp): return
	var role: String = stamp.role
	if code in ["no_tool_action","request_rejected"]:
		var previous: Dictionary = _turn_delays.get(role,{})
		var attempt := mini(int(previous.get("attempt",0)) + 1, TURN_RETRY_SECONDS.size())
		var until := Time.get_ticks_msec() + int(TURN_RETRY_SECONDS[attempt-1]) * 1000
		_turn_delays[role] = {"attempt":attempt,"until":until,"code":code,"owner_id":stamp.get("owner_id")}
		set_process(true)
	elif code in BLOCKING:
		_turn_delays.erase(role)
		_blocks[role] = code
	else: return
	changed.emit()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var waiting := false
	var expired := false
	for delay: Dictionary in _turn_delays.values():
		if int(delay.until) > now:
			waiting = true
		elif int(delay.until) != 0:
			delay.until = 0
			expired = true
	set_process(waiting)
	if expired: changed.emit()

func test_connection(id: String) -> Dictionary:
	var grant := _grant(id,"diagnostic",int(_revisions.get(id,1)))
	var result := await _probe(grant,"test")
	if _connections.has(id) and int(_revisions[id])==int(grant.get("generation",-1)):
		_checks[id]={"code":"verified" if result.get("ok",false) else result.get("code","network"),
			"message":"函数工具测试通过" if result.get("ok",false) else result.get("error","连接测试失败。")}
		for role in ROLES:
			if binding(role)!=id: continue
			if result.get("ok",false) and _blocks.has(role): _refresh_role(role)
			elif result.get("code") in BLOCKING: _blocks[role]=result.code
		changed.emit()
	return result

func list_models(id: String) -> Dictionary:
	return await _probe(_grant(id,"diagnostic",int(_revisions.get(id,1))),"models")

func list_draft_models(config: Dictionary, key := "") -> Dictionary:
	var clean := _config(config,true)
	if clean.is_empty(): return _fail("invalid_connection","请填写有效的服务地址。")
	var id = clean.id
	if not id is String: return _fail("invalid_connection","连接编号无效。")
	if key.is_empty():
		var old: Dictionary = _connections.get(id,{})
		if old.get("provider")==clean.provider and old.get("base_url")==clean.base_url: key=str(_keys.get(id,""))
	if key.is_empty(): return _fail("needs_key",STATUS.needs_key)
	if _key.search(key)==null: return _fail("invalid_key","请输入有效的 API Key。")
	if _contains_secret(clean,key): return _fail("invalid_connection","请只在 API Key 输入框填写密钥。")
	var request := {"id":id if _id.search(id)!=null else Crypto.new().generate_random_bytes(12).hex_encode(),
		"role":"diagnostic","generation":int(_revisions.get(id,1)),"provider":clean.provider,
		"base_url":clean.base_url,"model":clean.model,"key":key}
	return await _probe(request,"models")

func _probe(grant: Dictionary, operation: String) -> Dictionary:
	if grant.is_empty(): return _fail("needs_key",STATUS.needs_key)
	var transport = load("res://scripts/east_painter.gd").new()
	add_child(transport)
	if not transport.request_diagnostic(grant,operation):
		transport.queue_free()
		return _fail("network","无法启动模型连接验证。")
	var response: Array = await transport.finished
	var code: String = transport.last_error_code
	transport.queue_free()
	if not str(response[2]).is_empty(): return _fail(code,str(response[2]))
	return response[1]
