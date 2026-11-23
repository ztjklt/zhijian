extends Control
const Flow := preload("res://scripts/net/online_flow.gd")
const DEFAULT_ADDRESS := Flow.DEFAULT_ADDRESS
var session: PaperNetSession
var address: LineEdit
var nickname: LineEdit
var invite: LineEdit
var maps: OptionButton
var status: Label
var scroll: ScrollContainer
var content: VBoxContainer
var tabs: TabContainer
var busy := false
var cancel_button: Button
var actions: Array[Button]=[]
var landscape_guard: PaperLandscapeGuard
var heading: Label
var back_at_top: Button
var back_at_bottom: Button
var form_rows: Array[BoxContainer] = []
var detailed_guidance: Array[Label] = []

func _ready() -> void:
	get_window().title="纸间 · 和朋友一起玩"
	get_window().content_scale_size=Vector2i.ZERO
	theme=PaperTheme.create_menu()
	session=PaperNetSession.new();get_tree().root.add_child(session)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	scroll.follow_focus=true
	content=VBoxContainer.new();content.add_theme_constant_override("separation",14);scroll.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	heading = _label(header, "双人对战 · 课本世界", 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_at_top = _button(header, "返回封面", _return_to_title)
	detailed_guidance.append(_label(content, "一人创建房间，把邀请发给朋友。两个人就在同一张纸上。", 16))
	var nickname_row := _form_row(content)
	var nickname_label := _label(nickname_row, "你的昵称", 14)
	nickname_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	nickname_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nickname = _edit(nickname_row, str(session.profile.get("name", "画家")), "朋友会看到这个名字")
	nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nickname.max_length=24
	tabs=TabContainer.new();content.add_child(tabs)
	tabs.add_theme_stylebox_override("panel",PaperTheme.panel())
	tabs.add_theme_stylebox_override("tab_selected",PaperTheme.scrap(Color("d9e7dc")))
	tabs.add_theme_stylebox_override("tab_unselected",PaperTheme.scrap(Color("f3f0e5")))
	tabs.add_theme_color_override("font_selected_color",PaperTheme.INK)
	tabs.add_theme_color_override("font_unselected_color",PaperTheme.MENU_MUTED)
	var tab_bar:=tabs.get_tab_bar()
	tab_bar.add_theme_stylebox_override("tab_selected",PaperTheme.scrap(Color("d9e7dc")))
	tab_bar.add_theme_stylebox_override("tab_unselected",PaperTheme.scrap(Color("f3f0e5")))
	tab_bar.add_theme_color_override("font_selected_color",PaperTheme.INK)
	tab_bar.add_theme_color_override("font_unselected_color",PaperTheme.MENU_MUTED)
	var create:=_tab("创建房间")
	detailed_guidance.append(_label(create, "选一张地图", 18))
	var create_row := _form_row(create)
	maps=OptionButton.new();maps.custom_minimum_size.y=44
	maps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps.add_item("山野沙盒 · 自由联机");maps.add_item("双人对战 · 课本世界");maps.add_item("平地创作 · 自由搭建")
	maps.select(1)
	if get_tree().has_meta("paper_entry_map"): get_tree().remove_meta("paper_entry_map")
	create_row.add_child(maps)
	_action(create_row, "开始建房", func(): _start("create"))
	detailed_guidance.append(_label(create, "你是房主：结束时会保存云端世界，并让朋友离开。下次可从「继续游玩」重新打开。", 13))
	var join:=_tab("加入朋友")
	detailed_guidance.append(_label(join, "粘贴邀请链接，或输入8位房间码", 18))
	var join_row := _form_row(join)
	invite = _edit(join_row, "", "邀请链接或 8 位房间码")
	invite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite.text_submitted.connect(func(_text):_start("join"))
	_action(join_row, "加入房间", func(): _start("join"))
	detailed_guidance.append(_label(join, "地图由房主决定。你可以随时离开，朋友仍能继续；个人图纸只属于你。", 13))
	var feedback_row := _form_row(content)
	var create_help := "进入房间后，点「邀请朋友」发送链接。"
	status = _label(feedback_row, create_help, 14)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_theme_color_override("font_color",PaperTheme.TEAL)
	tabs.tab_changed.connect(func(index):
		if not busy:status.text=create_help if index==0 else "粘贴邀请链接或8位房间码，确认昵称后加入。")
	cancel_button = _button(feedback_row, "取消连接", cancel_connection)
	cancel_button.hide()
	if session.profile.get("token","")!="":
		var resume:=VBoxContainer.new();resume.add_theme_constant_override("separation",10);resume.hide()
		_button(content,"继续游玩",func():resume.visible=not resume.visible)
		content.add_child(resume)
		_label(resume,"短暂断线：重连上次房间。房间已结束：重新打开已保存的作品，再发送新的邀请。",13)
		_action(resume,"重连上次房间",func():_start("join",true))
		var saved_worlds:Array=session.profile.get("saved_worlds",[])
		for saved in saved_worlds:
			var title:String={"medieval-v1":"墨线边境","knowledge-v1":"课本漫游","paper":"平地创作"}.get(saved.get("map_id","paper"),"纸上世界")
			_action(resume,"继续作品 · "+title+" · "+str(saved.world_id).left(6),func():_connect_saved(saved))
	var advanced:=VBoxContainer.new();advanced.add_theme_constant_override("separation",10);advanced.hide()
	_button(content,"高级连接设置",func():advanced.visible=not advanced.visible)
	content.add_child(advanced)
	_label(advanced,"正常游玩无需修改。更换服务器不会带走原服务器上的作品。",13)
	address=_edit(advanced,DEFAULT_ADDRESS,"wss://服务器域名/ws")
	_button(advanced,"恢复纸间默认服务器",func():address.text=DEFAULT_ADDRESS)
	_label(content,"保存与身份保存在当前浏览器。请使用同一浏览器继续作品，避免清除网站数据。",12)
	back_at_bottom = _button(content, "返回封面", _return_to_title)
	var requested:=Flow.consume_entry()
	if requested.get("present",false):
		tabs.current_tab=1;invite.text=str(requested.raw)
		var parsed:=Flow.parse_invite(invite.text)
		status.text="朋友邀请你加入房间 "+str(parsed.code)+"。确认昵称后，点击加入。" if parsed.error=="" else parsed.error
	get_viewport().size_changed.connect(_layout);_layout()
	landscape_guard = PaperLandscapeGuard.install(self)

func _form_row(parent: Control) -> BoxContainer:
	var row := BoxContainer.new()
	parent.add_child(row)
	form_rows.append(row)
	return row

func _tab(title:String)->VBoxContainer:
	var page:=VBoxContainer.new();page.name=title;page.add_theme_constant_override("separation",14)
	tabs.add_child(page);return page
func _label(parent:Node,text:String,font_size:int)->Label:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",PaperTheme.menu_font_size(font_size));parent.add_child(label);return label
func _edit(parent:Node,value:String,hint:String)->LineEdit:
	var edit:=LineEdit.new();edit.text=value;edit.placeholder_text=hint;edit.custom_minimum_size.y=44;edit.max_length=512
	parent.add_child(edit);return edit
func _button(parent:Node,text:String,action:Callable)->Button:
	var button:=PaperSealButton.new();button.text=text;button.custom_minimum_size.y=44
	button.pressed.connect(action);parent.add_child(button);return button
func _action(parent:Node,text:String,action:Callable)->void:
	var button:=_button(parent,text,action);PaperTheme.primary(button);actions.append(button)
func _set_busy(value:bool)->void:
	busy=value;cancel_button.visible=value
	for button in actions:button.disabled=value
	for edit in [address,nickname,invite]:edit.editable=not value
	maps.disabled=value
func _start(action:String,restore:bool=false)->void:
	if busy:return
	var credential:=str(session.profile.get("token","")) if restore else ""
	var saved:=str(session.profile.get("world_id","")) if restore and action=="create" else ""
	var room_code:=str(session.profile.get("code","")) if restore else ""
	var target:=str(session.profile.get("address",DEFAULT_ADDRESS)) if restore else address.text
	var map_id:String=str(session.profile.get("map_id","paper")) if restore else ["medieval-v1","knowledge-v1","paper"][maps.selected]
	if action=="join" and not restore:
		var parsed:=Flow.parse_invite(invite.text)
		if parsed.error!="":status.text=parsed.error;invite.grab_focus();return
		room_code=parsed.code
		if parsed.link:target=DEFAULT_ADDRESS;address.text=DEFAULT_ADDRESS
	_begin(target,action,room_code,map_id,credential,saved)
func _connect_saved(saved:Dictionary)->void:
	if busy:return
	_begin(str(saved.address),"create","",str(saved.map_id),str(saved.token),str(saved.world_id))
func _begin(target:String,action:String,room_code:String,map_id:String,credential:String,saved:String)->void:
	_set_busy(true)
	var result:=session.connect_room(target,action,room_code,nickname.text.strip_edges().left(24) if not nickname.text.strip_edges().is_empty() else "画家",map_id,credential,saved)
	status.text=session.status
	if result!=OK:_set_busy(false)
func cancel_connection()->void:
	if session.socket!=null:session.socket.close();session.socket=null
	session.ended=true;session.retry_clock=-1;session.ready_to_play=false
	_set_busy(false);status.text="已取消连接。你可以修改信息后重试。"
func _return_to_title()->void:
	cancel_connection();session.queue_free();get_tree().change_scene_to_file.call_deferred("res://scenes/title_menu.tscn")
func _unhandled_input(event:InputEvent)->void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		if busy:cancel_connection()
		else:_return_to_title()
func _process(_delta:float)->void:
	if busy:
		status.text=session.status
		if session.ended:_set_busy(false)
func _layout()->void:
	var viewport_size := get_viewport_rect().size
	var amount := Flow.ui_scale(viewport_size)
	var bounds := PaperGuiScale.safe_rect(self)
	var safe_scale := PaperGuiScale.factor(viewport_size) / amount
	bounds = Rect2(bounds.position * safe_scale, bounds.size * safe_scale)
	var compact := bounds.size.y <= 500 and bounds.size.x >= 440
	var spacing := 8 if compact else 14
	var margin := 12 if compact else 16
	for row in form_rows:
		row.vertical = not compact
		row.add_theme_constant_override("separation", spacing)
	for label in detailed_guidance:
		label.visible = not compact
	heading.text = "双人对战" if compact else "双人对战 · 课本世界"
	back_at_top.visible = compact
	back_at_bottom.visible = not compact
	content.add_theme_constant_override("separation", spacing)
	var width := minf(620, bounds.size.x - 24)
	content.custom_minimum_size.x = maxf(260, width - 16)
	scroll.scale = Vector2.ONE * amount
	scroll.reset_size()
	scroll.position = (bounds.position + Vector2((bounds.size.x - width) * 0.5, margin)) * amount
	scroll.size = Vector2(width, bounds.size.y - margin * 2)
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and scroll.is_ancestor_of(focused):
		scroll.ensure_control_visible.call_deferred(focused)
func _draw()->void:draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),Color("f7f2e3"))
