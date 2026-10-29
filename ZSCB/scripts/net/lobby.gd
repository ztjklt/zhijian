extends Control
const DEFAULT_ADDRESS := "wss://paper-server-production-4b68.up.railway.app/ws"
var session: PaperNetSession
var address: LineEdit
var nickname: LineEdit
var invite: LineEdit
var maps: OptionButton
var status: Label
var scroll: ScrollContainer
var content: VBoxContainer
func _ready() -> void:
	get_window().content_scale_size=Vector2i.ZERO
	theme=PaperTheme.create_menu()
	session=PaperNetSession.new()
	get_tree().root.add_child(session)
	scroll=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content=VBoxContainer.new(); content.add_theme_constant_override("separation",14)
	scroll.add_child(content)
	_label("纸间 / ONLINE · 对战协议%d · %s" % [PaperNetCodec.PROTOCOL, PaperNetCodec.RELEASE],14)
	_label("和朋友，在同一张纸上。",28)
	_label("双人私人房间 · 每人用自己的电脑打开游戏，通过服务器共享世界。",15)
	_label("实时互伤 · 3秒重生 · 图纸与装备保留。双方建议使用同一客户端，联机协议须一致。",14)
	_label("创建者结束房间时保存；客人退出后房间继续。更新服务前，旧云端可能提示版本不匹配。",14)
	_label("联机服务器地址",14)
	address=_edit(str(session.profile.get("address",DEFAULT_ADDRESS)),"wss://你的服务器域名/ws")
	_button("使用纸间云服务器",func(): address.text=DEFAULT_ADDRESS)
	_button("使用本机测试服务器",func(): address.text="ws://127.0.0.1:9080/ws")
	_label("你的名字",14)
	nickname=_edit(str(session.profile.get("name","画家")),"名字")
	_label("创建新房间",20)
	maps=OptionButton.new()
	maps.add_item("墨线边境 · 纸上山野"); maps.add_item("课本漫游"); maps.add_item("平地创作")
	content.add_child(maps)
	_button("创建双人房间",func(): _start("create"))
	_label("加入朋友",20)
	invite=_edit("","输入朋友提供的房间码")
	_button("加入房间",func(): _start("join"))
	if session.profile.get("token","")!="":
		_button("重连上次房间",func(): _start("join",true))
		if session.profile.get("owner",false): _button("重新打开我的云端作品",func(): _start("create",true))
	var saved_worlds:Array=session.profile.get("saved_worlds",[])
	if not saved_worlds.is_empty():
		_label("我的云端作品",20)
		for saved in saved_worlds:
			var title:String={"medieval-v1":"墨线边境","knowledge-v1":"课本漫游","paper":"平地创作"}.get(saved.get("map_id","paper"),"纸上世界")
			_button(title+" · "+str(saved.world_id).left(8),func(): session.connect_room(saved.address,"create","",nickname.text,saved.map_id,saved.token,saved.world_id))
	status=_label("创建后把服务器地址和房间码发给朋友。创建者离开会保存并结束本次房间。",14)
	_button("返回选择地图",func():
		session.leave(); session.queue_free()
		get_tree().change_scene_to_file("res://scenes/map_select.tscn"))
	_button("返回封面", _return_to_title)
	get_viewport().size_changed.connect(_layout)
	_layout()
func _return_to_title() -> void:
	session.leave()
	session.queue_free()
	get_tree().change_scene_to_file("res://scenes/title_menu.tscn")
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_return_to_title()
func _label(text: String, font_size: int) -> Label:
	var label:=Label.new(); label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",PaperTheme.menu_font_size(font_size))
	content.add_child(label)
	return label
func _edit(value: String, hint: String) -> LineEdit:
	var edit:=LineEdit.new(); edit.text=value; edit.placeholder_text=hint
	edit.custom_minimum_size.y=40; edit.max_length=512
	content.add_child(edit); return edit
func _button(text: String, action: Callable) -> void:
	var button:=Button.new(); button.text=text; button.custom_minimum_size.y=43
	button.pressed.connect(action); content.add_child(button)
func _start(action: String, restore: bool=false) -> void:
	if session.socket!=null: session.socket.close()
	var credential:=str(session.profile.get("token","")) if restore else ""
	var saved:=str(session.profile.get("world_id","")) if restore and action=="create" else ""
	var room_code:=str(session.profile.get("code","")) if restore else invite.text
	var map_id:String=["medieval-v1","knowledge-v1","paper"][maps.selected]
	# Saved credentials belong to the original server, even after editing the field.
	var target_address:=str(session.profile.get("address",address.text)) if restore else address.text
	session.connect_room(target_address,action,room_code,nickname.text,map_id,credential,saved)
func _process(_delta: float) -> void:
	if session!=null and session.status!="等待连接": status.text=session.status
func _layout() -> void:
	var size:=get_viewport_rect().size
	var width:=minf(660,size.x-32)
	content.custom_minimum_size.x=maxf(260,width-16)
	scroll.reset_size(); scroll.position=Vector2((size.x-width)*.5,24)
	scroll.size=Vector2(width,size.y-48)
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),Color("f7f2e3"))
