extends SceneTree

func _initialize() -> void:
	report.call_deferred()

func report() -> void:
	var service := root.get_node("ModelConnections")
	var shared: String = service.binding("companion")
	var ids := {}
	for row: Dictionary in service.list_connections(): ids[row.id] = row
	var success := not shared.is_empty()
	for role in ["companion", "priest", "war_god"]:
		var status: Dictionary = service.role_status(role)
		var row: Dictionary = ids.get(status.id,{})
		var official: bool = row.get("provider")=="deepseek-official" and row.get("model")=="deepseek-flash"
		print("%s  %s  %s" % [role, status.code, "DeepSeek 官方 Flash" if official else "其他或未绑定"])
		success = success and status.ready and official and status.id==shared
	print("三神共用同一官方连接且凭据就绪" if success else "三神尚未同时就绪或未共用官方 Flash")
	quit(0 if success else 3)
