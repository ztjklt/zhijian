extends Control
## A personal view of room-only, per-piece lending.
var game
var panel:PanelContainer
var list:ItemList
var close_button:Button
var share_button:Button
var build_button:Button
var notice_label:Label
var details:Label
var ids:Array=[]
var selected_id:=""
var signature:=""
var clock:=0.0
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP;theme=PaperTheme.create_menu()
	var shade:=ColorRect.new();shade.color=Color(.12,.18,.18,.32);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	panel=PanelContainer.new();add_child(panel);var style:=PaperTheme.panel();style.set_content_margin_all(12);panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);panel.add_child(column)
	var heading:=HBoxContainer.new();column.add_child(heading)
	var title:=label(heading,"双人共同搭建",18);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	close_button=button(heading,"关闭",close);close_button.custom_minimum_size.x=64
	label(column,"逐件允许朋友搬动／连接，拆除仍归作者。\n当前房间有效；任一人断线会撤回许可，完成的结构保留。",14)
	list=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;list.custom_minimum_size.y=55;list.add_theme_font_size_override("font_size",15);column.add_child(list)
	var paper:=StyleBoxFlat.new();paper.bg_color=Color("f3f1e8");paper.border_color=Color("cbd3c7");paper.set_border_width_all(1);paper.set_corner_radius_all(4);paper.set_content_margin_all(6)
	var chosen:=StyleBoxFlat.new();chosen.bg_color=Color("dbe8de");chosen.set_corner_radius_all(3);chosen.set_content_margin_all(4)
	list.add_theme_stylebox_override("panel",paper);list.add_theme_stylebox_override("selected",chosen);list.add_theme_stylebox_override("selected_focus",chosen)
	list.add_theme_color_override("font_color",PaperTheme.INK);list.add_theme_color_override("font_selected_color",PaperTheme.INK)
	list.item_selected.connect(func(index:int):selected_id=ids[index];refresh())
	details=label(column,"",14)
	share_button=button(column,"允许朋友搬动／连接",func():
		var object:Dictionary=find_object(selected_id)
		if not object.is_empty():game.cooperation_action(selected_id,selected_id not in game.cooperation.get("shared",[])))
	build_button=button(column,"回到4移动／连接，继续搭建",func():close();game.set_draw_mode(4))
	notice_label=label(column,"进入双人房间后，走近自己画的部件。",14)
	get_viewport().size_changed.connect(_layout);_layout();visible=false
func label(parent:Node,text:String,size:int)->Label:
	var result:=Label.new();result.text=text;result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;result.add_theme_font_size_override("font_size",size);parent.add_child(result);return result
func button(parent:Node,text:String,callback:Callable)->Button:
	var result:=Button.new();result.text=text;result.focus_mode=Control.FOCUS_NONE;result.custom_minimum_size.y=36;result.add_theme_font_size_override("font_size",14);parent.add_child(result);result.pressed.connect(callback);return result
func find_object(id:String)->Dictionary:
	for object in game.objects:
		if object.get("id","")==id:return object
	return {}
func refresh()->void:
	var rows:Array=[];var next_ids:Array=[];var online:bool=game.network_session!=null
	if online:
		for object in game.objects:
			var id:String=object.get("id","");var own:bool=object.get("author","")==game.network_session.player_id
			var shared:bool=id in game.cooperation.get("shared",[])
			var distance:float=Vector2(object.x,object.y).distance_to(game.player.position)
			if (own and (distance<=12 or shared)) or (shared and distance<=12):
				next_ids.append(id);rows.append("%s部件 %s · %.1f米 · %s"%["我的" if own else "朋友的",id,distance,"已开放" if shared else "未开放"])
	var state:String=str([rows,next_ids])
	if signature!=state:
		signature=state;ids=next_ids;list.clear()
		for row in rows:list.add_item(row)
		if selected_id not in ids:selected_id=ids[0] if not ids.is_empty() else ""
		if selected_id in ids:list.select(ids.find(selected_id))
	var object:Dictionary=find_object(selected_id)
	share_button.disabled=true;share_button.text="允许朋友搬动／连接"
	if object.is_empty():details.text="附近没有可协作部件；先画出一件，再走近它。" if online else "单人作品照常保留；进入双人房间后可逐件开放。"
	else:
		var own:bool=object.get("author","")==game.network_session.player_id
		var shared:bool=selected_id in game.cooperation.get("shared",[])
		var holder:String=game.cooperation.get("locks",{}).get(selected_id,"")
		details.text=("由我创作" if own else "由朋友创作 · 我可搬动／连接，不能拆除")+(" · 朋友正在编辑" if holder!="" and holder!=game.network_session.player_id else "")
		share_button.text="撤回这件部件的协作许可" if shared and own else "朋友已允许搬动／连接" if shared else "允许朋友搬动／连接"
		share_button.disabled=not own or not game.network_session.ready_to_play or (not shared and Vector2(object.x,object.y).distance_to(game.player.position)>12)
	if not online:notice_label.text="请先进入双人房间；此处不会改变单人作品。"
	_layout.call_deferred()
func open()->void:
	if game.bag_open:game.toggle_bag()
	game.close_personal_overlay();game.retain_active_stroke();game.cancel_pointer();game.cancel_weapon_grip(false);game.combat.cancel_draw();game.touch_controls.reset()
	visible=true;refresh();_layout()
func close()->void:
	visible=false
	if game.touch_controls!=null:game.touch_controls.reset()
func _process(delta:float)->void:
	if not visible:return
	clock-=delta
	if clock<=0:clock=.2;refresh()
func _layout()->void:
	if panel==null:return
	var viewport:=PaperGuiScale.apply(self)
	panel.position=Vector2(12,12);panel.size=Vector2(minf(740,viewport.x-24),minf(560,viewport.y-24));panel.position=(viewport-panel.size)*.5
