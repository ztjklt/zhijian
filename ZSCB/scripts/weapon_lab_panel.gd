extends Control
var game
var panel:PanelContainer
var actions:GridContainer
var comparison:GridContainer
var current_label:Label
var baseline_label:Label
var notice_label:Label
var buttons:Dictionary={}
var clock:=0.0
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP;theme=PaperTheme.create_menu()
	var shade:=ColorRect.new();shade.color=Color(0.12,.18,.18,.32);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	panel=PanelContainer.new();add_child(panel)
	var style:=PaperTheme.panel();style.set_content_margin_all(12);panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",6);panel.add_child(column)
	var heading:=HBoxContainer.new();column.add_child(heading)
	var title:=label(heading,"武器试打 · 方案对照",18);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(heading,"close","关闭",close)
	buttons.close.size_flags_horizontal=Control.SIZE_SHRINK_END;buttons.close.custom_minimum_size.x=64
	label(column,"关面板后攻击试靶 · 记录仅本次会话",13)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	comparison=GridContainer.new();comparison.size_flags_horizontal=Control.SIZE_EXPAND_FILL;comparison.add_theme_constant_override("h_separation",18);scroll.add_child(comparison)
	current_label=label(comparison,"",15);baseline_label=label(comparison,"",15)
	actions=GridContainer.new();actions.add_theme_constant_override("h_separation",6);actions.add_theme_constant_override("v_separation",6);column.add_child(actions)
	for distance in [1.2,2.5,5.0]:
		var d:float=distance
		button(actions,"start_"+str(distance),"布靶 %.1f 米"%distance,func():game.weapon_lab_action({"action":"start","distance":d}))
	button(actions,"keep","保留当前对照",func():game.weapon_lab_action({"action":"keep"}))
	button(actions,"reset","清空本轮记录",func():game.weapon_lab_action({"action":"reset"}))
	button(actions,"stop","撤下试靶",func():game.weapon_lab_action({"action":"stop"}))
	button(actions,"copy","复制回画布修改",func():
		if game.refine_weapon():close())
	notice_label=label(column,"先布靶，再用自己的武器实际命中。",13)
	get_viewport().size_changed.connect(_layout);_layout();visible=false
func label(parent:Node,text:String,size:int)->Label:
	var result:=Label.new();result.text=text;result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;result.size_flags_horizontal=Control.SIZE_EXPAND_FILL;result.add_theme_font_size_override("font_size",size);parent.add_child(result);return result
func button(parent:Node,key:String,text:String,callback:Callable)->Button:
	var result:=Button.new();result.text=text;result.focus_mode=Control.FOCUS_NONE;result.custom_minimum_size=Vector2(0,36);result.size_flags_horizontal=Control.SIZE_EXPAND_FILL;result.add_theme_font_size_override("font_size",14);parent.add_child(result);result.pressed.connect(callback);buttons[key]=result;return result
func describe(data:Dictionary,title:String)->String:
	if data.is_empty():return title+"\n尚未保留实际试打结果"
	var hits:int=data.get("hits",0)
	return "%s · %s%s\n握点最远 %.2f米 · 冷却 %.2f秒\n实测命中 %d 次\n最近 %.1f · 平均 %.1f\n最高 %.1f · 最远接触 %.2f米"%[title,PaperWeaponTypes.LABELS.get(data.get("kind","sword"),"武器"),"（试用短弓）" if data.get("trial",false) else "",data.get("reach",0),data.get("cooldown",0),hits,data.get("last",0),float(data.get("total",0))/maxi(1,hits),data.get("maximum",0),data.get("farthest",0)]
func refresh()->void:
	current_label.text=describe(game.weapon_lab.current,"当前方案")
	baseline_label.text=describe(game.weapon_lab.baseline,"保留对照")
	buttons.keep.disabled=game.weapon_lab.current.get("hits",0)==0
	# Wrapped labels initially measure at zero width. Fit once their container
	# has assigned column widths, so that stale minimum height cannot stick.
	_layout.call_deferred()
func notice(text:String)->void:
	notice_label.text=text
func open()->void:
	if game.cooperation_open():game.cooperation_panel.close()
	if game.bag_open:game.toggle_bag()
	if game.experience!=null:game.experience.close()
	game.retain_active_stroke();game.cancel_pointer();game.cancel_weapon_grip(false);game.combat.cancel_draw();game.touch_controls.reset()
	if game.network_session==null:game.weapon_lab.select(game.weapon_lab.effective_weapon())
	else:game.weapon_lab_action({"action":"inspect"})
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
	actions.columns=2 if viewport.x<600 else 3;comparison.columns=1 if viewport.x<600 else 2
	panel.position=Vector2(12,12);panel.size=Vector2(minf(820,viewport.x-24),minf(600,viewport.y-24))
	panel.position=(viewport-panel.size)*.5
