extends VBoxContainer
## UI receives only public summaries; the model service owns keys and requests.
signal edit_state_changed

const OFFICIAL := "deepseek-official"
const OFFICIAL_URL := "https://api.deepseek.com"
const Roles := preload("res://scripts/divine_roles.gd")
const ACTORS := [
	{"node":"SandboxCompanion","id":"companion","title":"画家 · 阿靛"},
	{"node":"SandboxPriest","id":"priest","title":"牧师"},
	{"node":"SandboxWarGod","id":"war_god","title":"战神"},
	{"node":"SandboxAdventurer","id":"adventurer-lizhou","title":"冒险者 · 砾舟"}
]
var game
var service
var content: VBoxContainer
var notice: Label
var connections: Array = []
var role_pickers := {}
var editor := false
var editing_id := ""
var editing_record := {}
var form: GridContainer
var reasoning: OptionButton
var provider: OptionButton
var label_input: LineEdit
var address: LineEdit
var model_input: LineEdit
var remember_key: CheckButton
var key_input: LineEdit
var choices: OptionButton
var destination: Label
var feedback: Label
var serial := 0
var busy := false
var refresh_queued := false
var actions: Array[BaseButton] = []
var editors: Array[LineEdit] = []

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",8)
	add_child(content)
	notice = _label(self,"")
	resized.connect(_form_layout)
	service = get_node_or_null("/root/ModelConnections")
	if service != null and service.has_signal("changed"):
		service.changed.connect(_service_changed)

func _label(parent: Control, value: String) -> Label:
	var item := Label.new()
	item.text = value
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(item)
	return item

func _heading(value: String) -> void:
	var item := _label(content,value)
	item.add_theme_font_size_override("font_size",20)
	item.add_theme_color_override("font_color",PaperTheme.TEAL)

func _button(parent: Control, title: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = title
	item.custom_minimum_size.y = 36
	item.pressed.connect(action)
	parent.add_child(item)
	actions.append(item)
	return item

func _field(title: String, value: String, hint := "") -> LineEdit:
	_form_label(title)
	var input := LineEdit.new()
	input.text = value
	input.placeholder_text = hint
	input.custom_minimum_size.y = 34
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(input)
	editors.append(input)
	return input

func _form_label(title: String) -> void:
	var item := Label.new()
	item.text=title
	form.add_child(item)

func _form_layout() -> void:
	if is_instance_valid(form): form.columns=2 if size.x>=480 else 1

func _flow() -> HFlowContainer:
	var row := HFlowContainer.new()
	content.add_child(row)
	return row

func _reset() -> void:
	if is_instance_valid(key_input):
		key_input.clear()
		key_input = null
	form=null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	actions.clear()
	editors.clear()
	role_pickers.clear()

func open_page() -> void:
	serial += 1
	busy = false
	editor = false
	notice.text = ""
	_overview()
	edit_state_changed.emit()

func leave_page() -> void:
	serial += 1
	editor = false
	busy = false
	_reset()
	notice.text = ""
	edit_state_changed.emit()

func cancel_edit() -> bool:
	if not editor: return false
	open_page()
	return true

func _service_changed() -> void:
	if refresh_queued: return
	refresh_queued = true
	_refresh_if_open.call_deferred()

func _refresh_if_open() -> void:
	refresh_queued = false
	if is_visible_in_tree() and not editor and not busy:
		_overview()

func _actors() -> Array:
	var result := []
	for actor in ACTORS:
		if actor.id == "war_god" and actor.id not in Roles.enabled(): continue
		if game != null:
			if game.medieval_world == null or not game.medieval_world.has_node(actor.node): continue
		elif actor.id != "companion" and OS.get_name() != "macOS": continue
		result.append(actor)
	return result

func _overview() -> void:
	_reset()
	if service == null:
		_label(content,"当前安装未包含桌面模型连接服务。")
		return
	connections = service.list_connections()
	_heading("本局角色" if game != null else "沙盒角色")
	for actor in _actors(): _role(actor)
	content.add_child(HSeparator.new())
	_heading("服务连接")
	_label(content,"模型请求由所选服务商向你的账户计费。同一连接可供多位角色使用。")
	for record in connections: _connection(record)
	_button(content,"添加连接",func(): _edit({}))

func _role(actor: Dictionary) -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	var who := _label(row,actor.title)
	who.size_flags_stretch_ratio = 0.7
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	row.add_child(picker)
	picker.add_item("未配置")
	picker.set_item_metadata(0,"")
	var binding: String = service.binding(actor.id)
	var chosen: Dictionary = {}
	for record in connections:
		picker.add_item("%s · %s" % [record.label,record.model])
		var i := picker.item_count-1
		picker.set_item_metadata(i,record.id)
		if record.id == binding:
			picker.select(i)
			chosen=record
	var status: Dictionary = service.role_status(actor.id)
	var participant: Node = game.medieval_world.get_node_or_null(actor.node) if game != null and game.medieval_world != null else null
	if participant != null and participant.has_method("divine_connection_status"):
		status = participant.divine_connection_status()
	var details: String = status.get("message","未配置")
	if not chosen.is_empty():
		if status.get("code")=="ready":
			details = _connection_message(chosen.id,actor.id)
		_label(content,details+"  ·  "+str(chosen.base_url))
		if status.code in ["needs_key","keychain_unavailable"]:
			_button(content,"为%s补本次 Key" % actor.title,open_key_field.bind(actor.id))
	role_pickers[actor.id] = picker
	actions.append(picker)
	picker.item_selected.connect(func(i):
		var result: Dictionary = service.bind(actor.id,picker.get_item_metadata(i))
		notice.text = "已更新%s的连接" % actor.title if result.get("ok",false) else _error(result)
		_overview())

func _connection(record: Dictionary) -> void:
	var row := _flow()
	var title := Label.new()
	title.text = "%s · %s" % [record.label,record.model]
	row.add_child(title)
	_button(row,"编辑",_edit.bind(record))
	if record.provider==OFFICIAL and record.model=="deepseek-flash" and Roles.enabled().any(func(id): return service.binding(id) == ""):
		_button(row,"给未绑定的至高神使用",func():
			var result:Dictionary=service.bind_unassigned_gods(record.id)
			notice.text="已为未绑定的至高神选择此官方 Flash 连接。" if result.ok else _error(result))
	var test := _button(row,"测试此连接",_test.bind(record))
	test.disabled = not record.has_key
	var storage_note := " · 本机钥匙串" if record.get("remembered",false) else " · 仅本次" if record.has_key else ""
	_label(content,"%s  ·  %s%s" % [record.base_url,_connection_message(record.id),storage_note])

func _connection_message(id: String, role := "") -> String:
	var summary: Dictionary = service.connection_status(id,role)
	return "已输入 Key · 尚未测试" if summary.get("code")=="ready" else str(summary.get("message",""))

func open_key_field(role: String) -> void:
	for record in service.list_connections():
		if record.id == service.binding(role) and not record.has_key:
			_edit(record)
			key_input.grab_focus()
			get_parent().call_deferred("ensure_control_visible",key_input)
			return

func _edit(record: Dictionary) -> void:
	if busy: return
	_reset()
	serial += 1
	editor = true
	get_parent().set_deferred("scroll_vertical",0)
	editing_record = record
	editing_id = record.get("id","")
	notice.text = ""
	var has_key: bool = record.get("has_key",false)
	_heading("添加连接" if editing_id.is_empty() else "编辑连接")
	form=GridContainer.new()
	form.add_theme_constant_override("h_separation",14)
	form.add_theme_constant_override("v_separation",6)
	content.add_child(form)
	_form_layout()
	label_input = _field("连接名称",record.get("label",""),"例如 我的绘画账户")
	_form_label("服务商")
	provider = OptionButton.new()
	provider.add_item("DeepSeek 官方")
	provider.add_item("自定义兼容服务")
	provider.select(0 if record.get("provider",OFFICIAL)==OFFICIAL else 1)
	provider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(provider)
	actions.append(provider)
	address = _field("API 根地址",record.get("base_url",OFFICIAL_URL),"https://example.com/v1")
	address.editable = provider.selected==1
	key_input = _field("API Key", "", "已有 Key · 留空沿用，输入新值可替换" if has_key else "输入服务商提供的 Key")
	key_input.secret = true
	remember_key = null
	if OS.get_name()=="macOS":
		_form_label("Key 保存方式")
		remember_key = CheckButton.new()
		remember_key.text = "记在此 Mac 的登录钥匙串"
		remember_key.button_pressed = record.get("remembered",false) or record.get("key_storage","" if has_key else "remember") == "remember"
		form.add_child(remember_key)
		actions.append(remember_key)
		_label(content,"打开后，使用这条连接的角色可在重启时恢复。关闭后仅本次启动有效。")
	model_input = _field("模型 ID",record.get("model","deepseek-flash"),"输入模型 ID，或从服务商获取")
	_form_label("推理强度")
	reasoning = OptionButton.new()
	form.add_child(reasoning)
	actions.append(reasoning)
	_reasoning_choices(str(record.get("reasoning","off")))
	destination = _label(content,"")
	_update_destination()
	var row := _flow()
	_button(row,"获取可选模型",_models)
	choices = OptionButton.new()
	choices.fit_to_longest_item = false
	choices.custom_minimum_size.x = 230
	choices.hide()
	row.add_child(choices)
	actions.append(choices)
	choices.item_selected.connect(func(i): model_input.text=choices.get_item_metadata(i))
	feedback = _label(content,"")
	if not editing_id.is_empty():
		var buttons := _flow()
		if has_key or record.get("vault_error",false): _button(buttons,"清除 Key",_confirm.bind(false,record))
		_button(buttons,"删除连接",_confirm.bind(true,record))
	var custom := str(record.get("base_url","")) if provider.selected==1 else ""
	provider.item_selected.connect(func(i):
		_reasoning_choices("off")
		address.editable = i==1
		address.text = OFFICIAL_URL if i==0 else custom
		model_input.text = "deepseek-flash" if i==0 else ""
		key_input.clear()
		_inputs_changed())
	address.text_changed.connect(func(_v):
		key_input.clear()
		_inputs_changed())
	key_input.text_changed.connect(func(_v): choices.hide())
	label_input.grab_focus()
	edit_state_changed.emit()

func _inputs_changed() -> void:
	var same_address: bool = provider.selected==(0 if editing_record.get("provider")==OFFICIAL else 1) and address.text.strip_edges().rstrip("/")==editing_record.get("base_url","")
	key_input.placeholder_text = "已有 Key · 留空沿用，输入新值可替换" if same_address and editing_record.get("has_key",false) else "输入此服务地址对应的 Key"
	choices.hide()
	feedback.text = ""
	_update_destination()

func _update_destination() -> void:
	var endpoint := address.text.strip_edges()
	if endpoint.contains("@") or endpoint.contains("?") or endpoint.contains("#"):
		destination.text = "请填写不含账号、查询参数或片段的 API 根地址。"
	else:
		destination.text = "请求地址  %s\n获取模型和测试会联系此地址，模型调用由该服务商按你的账户计费。" % (endpoint if not endpoint.is_empty() else "待填写")

func _reasoning_choices(value: String) -> void:
	reasoning.clear()
	var levels := ["off","low","high","max"] if provider.selected==0 else ["off","low","medium","high"]
	for level in levels:
		reasoning.add_item({"off":"关闭","low":"低","medium":"中","high":"高","max":"最高"}[level])
		reasoning.set_item_metadata(reasoning.item_count-1,level)
	reasoning.select(maxi(0,levels.find(value)))

func _config() -> Dictionary:
	return {"id":editing_id,"label":label_input.text.strip_edges(),"provider":OFFICIAL if provider.selected==0 else "compatible",
		"base_url":address.text.strip_edges(),"model":model_input.text.strip_edges(),"reasoning":reasoning.get_item_metadata(reasoning.selected)}

func _error(result: Dictionary) -> String:
	return str(result.get("error",result.get("message","操作未完成")))

func _lock(value: bool) -> void:
	busy=value
	for button in actions:
		button.disabled=value
	for input in editors:
		input.editable=not value
	if editor: address.editable=not value and provider.selected==1
	edit_state_changed.emit()

func save_edit() -> void:
	if busy: return
	var config := _config()
	if config.model.is_empty():
		feedback.text="请填写模型 ID，或从服务商获取后选择。"
		return
	var storage := "remember" if is_instance_valid(remember_key) and remember_key.button_pressed else "session"
	var result: Dictionary = service.save_connection(config,key_input.text,storage)
	key_input.clear()
	if not result.get("ok",false):
		feedback.text=_error(result)
		return
	open_page()
	notice.text="连接已保存"

func _confirm(remove: bool, record: Dictionary) -> void:
	var names := PackedStringArray()
	for actor in ACTORS:
		if actor.id == "war_god" and actor.id not in Roles.enabled(): continue
		if service.binding(actor.id)==record.id: names.append(actor.title)
	var affected := "、".join(names) if not names.is_empty() else "无已绑定角色"
	var question := ConfirmationDialog.new()
	question.title = "删除连接" if remove else "清除 Key"
	question.dialog_text = ("删除后解除角色绑定" if remove else "清除后需重新输入 Key 才能使用")+"。\n"+affected
	question.ok_button_text = question.title
	question.cancel_button_text = "取消"
	add_child(question)
	question.canceled.connect(question.queue_free)
	question.confirmed.connect(func():
		question.queue_free()
		var result: Dictionary = service.remove_connection(record.id) if remove else service.clear_key(record.id)
		if not result.get("ok",false):
			feedback.text=_error(result)
			return
		open_page()
		notice.text="连接已删除" if remove else "Key 已清除")
	question.popup_centered()

func _models() -> void:
	if busy: return
	var ticket := serial
	var config := _config()
	_lock(true)
	feedback.text="正在从所示服务地址读取模型…"
	var result: Dictionary = await service.list_draft_models(config,key_input.text)
	if ticket!=serial: return
	_lock(false)
	choices.clear()
	choices.hide()
	if not result.get("ok",false):
		feedback.text=_error(result)
		return
	var models: Array=result.get("models",[])
	choices.add_item("选择服务商模型")
	for value in models:
		choices.add_item(str(value))
		choices.set_item_metadata(choices.item_count-1,str(value))
	choices.set_item_disabled(0,true)
	choices.visible=not models.is_empty()
	feedback.text="服务商返回 %d 个模型，可选择或手填。" % models.size()

func _test(record: Dictionary) -> void:
	if busy or not record.has_key: return
	var ticket := serial
	_lock(true)
	notice.text="正在测试 %s 的工具调用 · %s" % [record.model,record.base_url]
	var result: Dictionary = await service.test_connection(record.id)
	if ticket!=serial: return
	busy=false
	var summary: String = "工具调用测试通过" if result.get("ok",false) else _error(result)
	_overview()
	notice.text=str(record.label)+" · "+summary
