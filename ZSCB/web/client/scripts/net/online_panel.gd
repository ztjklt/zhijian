extends CanvasLayer
const Dialog:=preload("res://scripts/net/flow_dialog.gd")
const Flow := preload("res://scripts/net/online_flow.gd")
var session: PaperNetSession
var panel: PanelContainer
var heading: Label
var connection: Label
var peer: Label
var notice: Label
var menu: VBoxContainer
var retry_button: Button
var dialog
var dialog_action: Callable
var invite_dialog
var invite_field: LineEdit
var copy_status: Label
var invite_intro: Label
var copy_button: Button
var invite_details: Label
var copy_ok: JavaScriptObject
var copy_failed: JavaScriptObject
var notice_time := 0.0
var last_active := false

func _ready()->void:
	layer=6
	panel=PanelContainer.new();panel.theme=PaperTheme.create();add_child(panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",5);panel.add_child(column)
	heading=_label(column,"",15);connection=_label(column,"",13);peer=_label(column,"",13)
	var row:=HBoxContainer.new();column.add_child(row)
	_button(row,"邀请朋友",show_invite)
	_button(row,"房间菜单",func():menu.visible=not menu.visible)
	retry_button=_button(column,"立即重连 · 保留草稿",func():session.retry_now())
	notice=_label(column,"",12);notice.hide()
	menu=VBoxContainer.new();menu.theme=PaperTheme.create_menu();menu.add_theme_constant_override("separation",5);menu.hide();column.add_child(menu)
	if session.is_owner:
		_button(menu,"保存云端世界",request_save)
		_button(menu,"导入单人作品…",request_import)
	_label(menu,"房主结束会让朋友离开；请用下方按钮保存退出。" if session.is_owner else "你离开后，房主可以继续游玩。个人图纸独立保存。",12)
	_button(menu,"结束房间并保存…" if session.is_owner else "离开房间…",func():request_exit("res://scenes/network_lobby.tscn"))
	dialog=Dialog.new();add_child(dialog);dialog.get_cancel_button().text="继续游玩"
	dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dialog.confirmed.connect(_confirm);dialog.canceled.connect(_close_modal)
	invite_dialog=Dialog.new();add_child(invite_dialog);invite_dialog.title="邀请朋友一起玩";invite_dialog.cancel_visible=false;invite_dialog.get_ok_button().text="关闭"
	invite_dialog.confirmed.connect(_close_modal);invite_dialog.canceled.connect(_close_modal)
	var invite_content:=VBoxContainer.new();invite_content.add_theme_constant_override("separation",12);invite_dialog.content.add_child(invite_content)
	invite_intro=_label(invite_content,"把链接发给朋友：打开后确认昵称，点击加入即可。",15)
	invite_field=LineEdit.new();invite_field.editable=false;invite_field.custom_minimum_size=Vector2(260,44);invite_content.add_child(invite_field)
	copy_button=_button(invite_content,"复制邀请链接",_copy_invite)
	copy_status=_label(invite_content,"也可以选中链接，按 Ctrl/Cmd+C 手动复制。",13)
	invite_details=_label(invite_content,"",14)
	session.operation_finished.connect(_on_result)
	_configure_works_menu()

func blocks_canvas(point:Vector2)->bool:
	return panel.is_visible_in_tree() and panel.get_global_rect().has_point(point)

func _label(parent:Node,text:String,font_size:int)->Label:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var modal:bool=parent==menu or (invite_dialog!=null and invite_dialog.is_ancestor_of(parent))
	label.add_theme_font_size_override("font_size",PaperTheme.menu_font_size(font_size) if modal else font_size);parent.add_child(label);return label
func _button(parent:Node,text:String,action:Callable)->Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=36;button.focus_mode=Control.FOCUS_NONE
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.pressed.connect(action);parent.add_child(button);return button
func _notify(text:String,error:bool=false)->void:
	notice.text=text;notice.show();notice_time=6
	notice.add_theme_color_override("font_color",Color("a54242") if error else PaperTheme.TEAL)
func request_save()->void:
	if session.has_method("save_feedback"):
		session.game.save_game()
		var current:Dictionary=session.save_feedback()
		if not current.is_empty():_notify(current.text,current.error)
		return
	# Legacy frozen clients do not own the new queued-save state machine.
	if not session.ready_to_play:_notify("连接尚未恢复，不能确认云端保存。",true);return
	session.game.save_game();_notify("正在保存，等待服务器确认…")

func _on_result(result:Dictionary)->void:
	if result.get("op","")=="save":
		if session.has_method("save_feedback"):
			var current: Dictionary = session.save_feedback()
			if not current.is_empty():
				_notify(current.text,current.error)
				return
		_notify("云端世界已保存。下次从「继续游玩」打开。" if result.get("ok",false) else str(result.get("error","保存失败；上次有效作品保留，请重试。")),not result.get("ok",false))
func _configure_works_menu()->void:
	var popup:PopupMenu=session.game.toolbar.works.get_popup()
	for id in [5,6,7,8]:
		var index:int=popup.get_item_index(id)
		if index>=0:popup.remove_item(index)
	popup.set_item_text(popup.get_item_index(0),"保存云端世界" if session.is_owner else "个人图纸自动保存")
	popup.set_item_disabled(popup.get_item_index(0),not session.is_owner)
	popup.set_item_text(popup.get_item_index(1),"导入单人作品…")
	popup.set_item_disabled(popup.get_item_index(1),not session.is_owner)
	popup.set_item_text(popup.get_item_index(9),"结束房间并保存…" if session.is_owner else "离开房间…")

func _show_dialog(title:String,text:String,ok_text:String,action:Callable)->void:
	if dialog.visible or invite_dialog.visible:return
	dialog.title=title;dialog.dialog_text=text;dialog.get_ok_button().text=ok_text;dialog_action=action
	dialog.get_cancel_button().text="留在当前画面" if session.ended else "继续游玩"
	session.set_meta("flow_modal",true)
	_popup(dialog,500,240)
func _popup(window:Control,width:float,height:float)->void:
	window.popup_centered(Vector2i(width,height))
func _confirm()->void:
	_close_modal()
	if dialog_action.is_valid():dialog_action.call()
func _close_modal()->void:session.set_meta("flow_modal",false)
func request_exit(destination:String)->void:
	if session.save_exit_pending or session.navigation_pending:return
	if session.ended:
		_show_dialog("返回联机大厅？","本次连接已结束。已生成的作品以云端最近保存为准；返回后，尚未提交的草稿将离开当前窗口。\n可以先取消并尝试重连，继续保留草稿。","返回大厅",func():session.return_to_selector(destination))
	elif session.is_owner:
		_show_dialog("结束房间并保存？","你是房主。确认后会保存云端世界，并让朋友离开。\n下次从「继续游玩」打开作品，再发送新的邀请。尚未生成的草稿不会保存到云端。","保存并结束",func():session.save_and_return_to_selector(destination))
	else:
		_show_dialog("离开这个房间？","朋友可以继续游玩。你的个人图纸会保留；尚未生成的草稿不会保存。\n想回来时，在房间仍开放的情况下使用原邀请或重连。","离开房间",func():session.save_and_return_to_selector(destination))
func request_import()->void:
	if not session.is_owner:_notify("只有房主能导入作品。",true);return
	_show_dialog("用单人作品替换当前世界？","这会用当前地图的本机作品替换房间内的造物，朋友也会重新同步。双方个人图纸保持独立。\n请确认你要替换整个房间世界。","确认替换",func():session.import_local())
func show_invite()->void:
	if dialog.visible or invite_dialog.visible:return
	if session.ended:_notify("房间已结束，请回大厅重新打开作品并生成新邀请。",true);return
	var custom:=session.address!=Flow.DEFAULT_ADDRESS
	invite_field.text=session.code if custom else Flow.invite_url(session.code)
	invite_intro.text="请朋友在高级连接设置填写同一服务器，再输入房间码。" if custom else "把链接发给朋友：打开后确认昵称，点击加入即可。"
	copy_button.text="复制房间码" if custom else "复制邀请链接"
	invite_details.text="服务器："+session.address if custom else "房间码："+session.code+"  ·  最多2人\n邀请里只有房间码，没有你的身份信息。"
	copy_status.text="也可以选中链接，按 Ctrl/Cmd+C 手动复制。"
	session.set_meta("flow_modal",true);_popup(invite_dialog,540,280)
	invite_field.grab_focus();invite_field.select_all()
func _copy_invite()->void:
	if not OS.has_feature("web"):
		DisplayServer.clipboard_set(invite_field.text);copy_status.text="邀请已复制，发给朋友即可。";return
	if not bool(JavaScriptBridge.eval("!!(navigator.clipboard && window.isSecureContext)")):
		copy_status.text="浏览器不支持自动复制，请选中链接后手动复制。";return
	copy_ok=JavaScriptBridge.create_callback(func(_args):
		if is_instance_valid(copy_status):copy_status.text="邀请已复制，发给朋友即可。")
	copy_failed=JavaScriptBridge.create_callback(func(_args):
		if is_instance_valid(copy_status):copy_status.text="浏览器没有允许自动复制，请选中链接后手动复制。")
	JavaScriptBridge.get_interface("navigator").clipboard.writeText(invite_field.text).then(copy_ok).catch(copy_failed)

func _process(delta:float)->void:
	if not is_instance_valid(session) or not is_instance_valid(session.game):return
	var game:=session.game
	if session.hud!=null:session.hud.hide()
	if session.invite_button!=null:session.invite_button.hide()
	panel.visible=not game.bag_open and not (game.experience!=null and game.experience.visible) and not ("weapon_lab_panel" in game and game.weapon_lab_panel!=null and game.weapon_lab_panel.visible) and not ("cooperation_panel" in game and game.cooperation_panel!=null and game.cooperation_panel.visible)
	var size:=game.get_viewport_rect().size
	var amount:=Flow.ui_scale(size)
	var width:=minf(350,(size.x-24)/amount)
	panel.scale=Vector2(amount,amount);panel.custom_minimum_size.x=width
	var top:float=game.toolbar.header.get_global_rect().end.y+8*amount
	var logical:=size/amount
	if logical.x<900 or logical.y<500:
		top=maxf(top,game.toolbar.bottom.get_global_rect().end.y+12*amount)
		var controls=game.knowledge_world.controls if game.knowledge_world!=null else game.map_controls
		if controls!=null and controls.panel.is_visible_in_tree():top=maxf(top,controls.panel.get_global_rect().end.y+12*amount)
	panel.size=Vector2(width,0);panel.position=Vector2(size.x-width*amount-12*amount,top)
	heading.text="房间 "+session.code+" · "+("房主" if session.is_owner else "客人")
	connection.text=("已连接 · %dms" % session.round_trip_ms if session.round_trip_ms>=0 else "已连接") if session.ready_to_play else session.status
	if session.ready_to_play:
		connection.text+=" · 生命 %d/100" % int(game.combat.health)
		if session.local_protection>0:connection.text+=" · 保护中"
	if session.local_dead_time>0:connection.text="%.1f秒后重生 · 图纸与装备保留" % session.local_dead_time
	peer.text=session.peer_status
	retry_button.visible=not session.ready_to_play and not session.room_closed and not session.leaving
	retry_button.disabled=not session.ended and session.retry_clock<0 and session.socket!=null and session.socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING,WebSocketPeer.STATE_OPEN]
	notice_time-=delta
	if notice_time<=0:notice.hide()
	var active:=not session.ended
	if active!=last_active and OS.has_feature("web"):
		JavaScriptBridge.eval("window.paperOnlineActive = "+("true" if active else "false"),true)
	last_active=active
func _exit_tree()->void:
	if OS.has_feature("web"):JavaScriptBridge.eval("window.paperOnlineActive = false",true)
