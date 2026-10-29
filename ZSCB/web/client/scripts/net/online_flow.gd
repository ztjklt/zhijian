extends RefCounted
const PUBLIC_URL := "https://zhijian-web-production.up.railway.app/"
const DEFAULT_ADDRESS := "wss://paper-server-production-4b68.up.railway.app/ws"
static var entry_read := false
static var entry: Dictionary = {}
static var pixel_ratio := -1.0
static var measured_viewport := Vector2.ZERO

static func ui_scale(viewport: Vector2) -> float:
	if pixel_ratio<0 or viewport!=measured_viewport:
		measured_viewport=viewport
		pixel_ratio=clampf(float(JavaScriptBridge.eval("window.devicePixelRatio || 1")),1,3) if OS.has_feature("web") else 1.0
	return maxf(PaperGuiScale.factor(viewport),pixel_ratio)

static func parse_invite(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	var linked := text.begins_with("https://")
	if text.is_empty(): return {"error":"请粘贴朋友发来的邀请链接，或输入8位房间码。"}
	if linked:
		if not text.begins_with(PUBLIC_URL+"?"): return {"error":"这不是纸间的邀请链接，请向朋友索取房间码。"}
		var found := false
		for item in text.get_slice("?",1).get_slice("#",0).split("&"):
			var key := item.get_slice("=",0).uri_decode()
			if key not in ["room","release"]: return {"error":"邀请链接包含未知连接设置，请只填写8位房间码。"}
			if key=="room":
				if found: return {"error":"邀请链接包含多个房间，请只填写8位房间码。"}
				text=item.get_slice("=",1).uri_decode();found=true
		if not found: return {"error":"邀请链接缺少房间码，请让朋友重新复制邀请。"}
	text=text.strip_edges().to_upper()
	var pattern:=RegEx.new();pattern.compile("^[0-9A-F]{8}$")
	if pattern.search(text)==null: return {"error":"房间码是8位字母或数字，例如 A1B2C3D4；请检查是否漏字或多了空格。"}
	return {"code":text,"link":linked,"error":""}

static func invite_url(code: String) -> String:
	var parsed:=parse_invite(code)
	return PUBLIC_URL+"?room="+str(parsed.code) if parsed.error=="" else ""

static func entry_invite() -> Dictionary:
	if not entry_read:
		entry_read=true
		if OS.has_feature("web"):
			var query:=str(JavaScriptBridge.eval("window.location.search"))
			for item in query.trim_prefix("?").split("&"):
				if item.get_slice("=",0)=="room": entry={"present":true,"raw":item.get_slice("=",1).uri_decode()};break
	return entry

static func consume_entry() -> Dictionary:
	var requested:=entry_invite().duplicate()
	entry={}
	return requested
