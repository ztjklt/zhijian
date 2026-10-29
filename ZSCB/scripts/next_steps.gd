extends Control
## Optional routes into existing activities. Opening never changes the world.
var game
var panel:PanelContainer
var notice:Label
var buttons:Dictionary={}
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;theme=PaperTheme.create_menu()
	theme.set_color("font_focus_color","Button",PaperTheme.INK)
	var shade:=ColorRect.new();shade.color=Color(.12,.18,.18,.32);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	panel=PanelContainer.new();add_child(panel)
	var style:=PaperTheme.panel();style.set_content_margin_all(16);panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);panel.add_child(column)
	label(column,"接下来做什么",22)
	label(column,"挑一个想试的方向，也可以继续自由创作。",14)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",8);scroll.add_child(content)
	button(content,"trial","画一座能承重的桥",show_trial)
	label(content,"墨线边境 · 磨坊渡口约129米。画桥或组合支撑，再由你布置试桥台、投放货物。",14)
	button(content,"structure","把两个部件连接起来",func():
		close();game.set_draw_mode(4);game.set_connection_tool("fixed");game.message("先画两个相邻部件，再用4的固定连接依次点中两件材料接缝；也可切换转轴。"))
	label(content,"自由搭建 · 先分别画部件，再用固定连接或转轴试试结构。已连接部件先解除再搬动。",14)
	button(content,"weapon","试打自己的武器",func():close();game.open_weapon_lab())
	label(content,"武器试打 · 由你布置临时试靶，实际攻击并保留方案对照；不替换当前武器。",14)
	notice=label(column,"",14);notice.add_theme_color_override("font_color",PaperTheme.TEAL)
	button(column,"free","继续自由创作",close)
	# Wrapped CJK labels can initially report a tall minimum at zero width.
	# Fit again after containers establish their real widths and minima.
	panel.minimum_size_changed.connect(_layout.call_deferred)
	get_viewport().size_changed.connect(_layout);_layout();hide()
func label(parent:Node,text:String,font_size:int)->Label:
	var item:=Label.new();item.text=text;item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;item.add_theme_font_size_override("font_size",font_size);parent.add_child(item);return item
func button(parent:Node,key:String,text:String,action:Callable)->void:
	var item:=Button.new();item.text=text;item.custom_minimum_size=Vector2(0,44);item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(item);item.pressed.connect(action);buttons[key]=item
func open()->void:
	game.close_personal_overlay()
	if game.bag_open:game.toggle_bag()
	game.retain_active_stroke();game.cancel_pointer();game.combat.cancel_draw();game.touch_controls.reset()
	notice.text="";show();_layout();buttons.free.grab_focus()
func close()->void:
	hide();get_viewport().gui_release_focus()
	if game.touch_controls!=null:game.touch_controls.reset()
func show_trial()->void:
	if game.medieval_world==null:
		notice.text="磨坊试桥在「墨线边境」。可从地图选择手动进入；当前作品会保留。";return
	close();game.toolbar.navigation_open=true
	game.message("磨坊试桥在磨坊渡口约129米，沿路前往；到达后可布置试桥台。")
func _layout()->void:
	if panel==null:return
	var viewport:=PaperGuiScale.apply(self)
	panel.size=Vector2(minf(600,viewport.x-24),minf(600,viewport.y-24));panel.position=(viewport-panel.size)*.5
