class_name BackpackPanel
extends PanelContainer
const CARDS_PER_PAGE := 6
var game = null
var category := "全部"
var query := ""
var page := 0
var title_label: Label
var grid: GridContainer
var details: Label
var name_field: LineEdit
var search_field: LineEdit
var page_label: Label
var hotbar: GridContainer
var filters: Array[Button] = []
var cards_scroll: ScrollContainer
var place_button: Button
var selection_buttons: Array[Button] = []
var empty_label: Label
var purpose: Label
var binding_hint: Label
var shade: ColorRect
var body: BoxContainer
var right: VBoxContainer
var action_row: BoxContainer
var detail_preview: Control
var detail_title: Label
var more: MenuButton
var content_scroll: ScrollContainer
var count_label: Label
var editing_entry_id := -1

func _ready() -> void:
	theme = PaperTheme.create_menu()
	shade = ColorRect.new()
	shade.color = Color(0.12,0.15,0.14,0.36)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().add_child(shade)
	get_parent().move_child(shade,get_index())
	visibility_changed.connect(func():
		if is_instance_valid(shade): shade.visible = is_visible_in_tree())
	PaperTheme.grain(self)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation",12)
	add_child(shell)
	var header := HBoxContainer.new()
	shell.add_child(header)
	title_label = _label(header,"我的图纸",26)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label = _label(header,"",14)
	_add_button(header,"×",func(): game.toggle_bag()).tooltip_text="关闭图纸 · 6 / B"
	search_field=LineEdit.new();search_field.placeholder_text="搜索作品";search_field.custom_minimum_size.y=40
	search_field.text_changed.connect(func(value:String):query=value;page=0;refresh())
	shell.add_child(search_field)
	var tabs:=HBoxContainer.new();shell.add_child(tabs)
	for item in ["全部","武器","建筑","地形"]:
		var button:=_add_button(tabs,item,func():category=item;page=0;refresh())
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;filters.append(button)
	content_scroll=ScrollContainer.new();content_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(content_scroll)
	body=BoxContainer.new();body.add_theme_constant_override("separation",24)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content_scroll.add_child(body)
	var left:=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(left)
	empty_label=_label(left,"还没有图纸。画一件作品后，就会收藏在这里。",16);empty_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	cards_scroll=ScrollContainer.new();cards_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	cards_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.add_child(cards_scroll)
	grid=GridContainer.new();grid.columns=3;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cards_scroll.add_child(grid)
	right=VBoxContainer.new();right.add_theme_constant_override("separation",6);body.add_child(right)
	detail_preview=preload("res://scripts/blueprint_preview.gd").new();detail_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	detail_preview.custom_minimum_size.y=120;right.add_child(detail_preview)
	detail_title=_label(right,"选一张图纸",22)
	detail_title.max_lines_visible=2
	detail_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	details=_label(right,"",15);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	purpose=_label(right,"生成的作品都收在这里，随时再次使用。",14);purpose.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	purpose.add_theme_color_override("font_color",PaperTheme.MENU_MUTED)
	binding_hint=_label(right,"快捷绑定 · Shift + 数字取用",14);binding_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hotbar=GridContainer.new();hotbar.columns=6;right.add_child(hotbar)
	var edit:=HBoxContainer.new();right.add_child(edit)
	name_field=LineEdit.new();name_field.placeholder_text="作品名称";name_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	name_field.text_submitted.connect(func(value:String):game.rename_blueprint(value));edit.add_child(name_field)
	selection_buttons.append(_add_button(edit,"改名",func():game.rename_blueprint(name_field.text)))
	var secondary:=HBoxContainer.new();right.add_child(secondary)
	selection_buttons.append(_add_button(secondary,"标星",func():game.favorite_blueprint()))
	more=MenuButton.new();more.text="更多";more.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	more.get_popup().add_item("复制图纸",0);more.get_popup().add_item("移出图纸",1)
	more.get_popup().id_pressed.connect(func(id:int):
		if id==0:game.duplicate_blueprint()
		else:game.delete_blueprint())
	secondary.add_child(more);selection_buttons.append(more)
	action_row=BoxContainer.new();action_row.add_theme_constant_override("separation",10);shell.add_child(action_row)
	var paging:=HBoxContainer.new();paging.size_flags_horizontal=Control.SIZE_EXPAND_FILL;action_row.add_child(paging)
	_add_button(paging,"上一页",func():page=maxi(0,page-1);refresh())
	page_label=_label(paging,"",14)
	_add_button(paging,"下一页",func():page+=1;refresh())
	place_button=_add_button(action_row,"先选择一张图纸",func():game.equip_blueprint())
	place_button.custom_minimum_size=Vector2(230,44);PaperTheme.primary(place_button)
	get_viewport().size_changed.connect(_layout)
	_layout();refresh()

func _label(parent:Node,text:String,font_size:int)->Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",font_size)
	if font_size>=22:PaperTheme.heading(label)
	parent.add_child(label);return label

func _add_button(parent:Control,text:String,callback:Callable)->Button:
	var button:=Button.new();button.text=text;button.focus_mode=Control.FOCUS_NONE
	button.custom_minimum_size.y=36;button.pressed.connect(callback);parent.add_child(button);return button

func _layout()->void:
	if body==null:return
	var viewport:=PaperGuiScale.apply(self)
	var narrow:=viewport.x<700
	var short_window:=viewport.y<500
	var style:=PaperTheme.panel();style.set_content_margin_all(14 if narrow or short_window else 24)
	add_theme_stylebox_override("panel",style)
	body.vertical=narrow
	right.custom_minimum_size.x=0 if narrow else 250
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	grid.columns=2 if narrow else 3
	cards_scroll.custom_minimum_size.y=180 if short_window else 260 if narrow else 310
	detail_preview.custom_minimum_size.y=80 if narrow or short_window else 96
	detail_preview.visible=not short_window
	purpose.hide()
	content_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	cards_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	action_row.vertical=narrow
	place_button.custom_minimum_size.x=0 if narrow else 230
	place_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	var desired:=Vector2(minf(1040,viewport.x-24),minf(620,viewport.y-24))
	reset_size();size=desired
	position=Vector2((viewport.x-size.x)*0.5,(viewport.y-size.y)*0.5)*scale.x
	PaperGuiScale.popup(more.get_popup(),scale.x)

func refresh()->void:
	if game==null or grid==null:return
	var entries:=BlueprintBag.filter_entries(game.bag,category,query)
	var pages:int=maxi(1,ceili(float(entries.size())/CARDS_PER_PAGE))
	page=clampi(page,0,pages-1);count_label.text="%d 张"%game.bag.entries.size();page_label.text="%d / %d"%[page+1,pages]
	empty_label.visible=entries.is_empty()
	empty_label.text="还没有图纸。先画一件作品，再按同一数字键生成。" if game.bag.entries.is_empty() else "没有找到作品，试试其他名称或分类。"
	for i in filters.size():PaperTheme.selected(filters[i],["全部","武器","建筑","地形"][i]==category)
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	for index in range(page*CARDS_PER_PAGE,mini(entries.size(),(page+1)*CARDS_PER_PAGE)):
		var entry:Dictionary=entries[index]
		var button:=_add_button(grid,"",func():game.select_blueprint(entry.id))
		button.custom_minimum_size=Vector2(100,140);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		PaperTheme.selected(button,game.selected_blueprint_id==entry.id)
		var preview:=preload("res://scripts/blueprint_preview.gd").new();preview.paths=entry.paths
		preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.offset_left=10;preview.offset_right=-10;preview.offset_top=10;preview.offset_bottom=-36;button.add_child(preview)
		var caption:=Label.new();caption.text=("★ " if entry.favorite else "")+entry.name
		caption.add_theme_font_size_override("font_size",15);caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_left=8;caption.offset_right=-8;caption.offset_top=-30;caption.offset_bottom=-5
		caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(caption);button.tooltip_text=entry.name+" · "+entry.category
	var selected:=BlueprintBag.find_entry(game.bag,game.selected_blueprint_id)
	var has_selection:=not selected.is_empty();place_button.disabled=not has_selection;name_field.editable=has_selection
	for button in selection_buttons:button.disabled=not has_selection
	for child in hotbar.get_children():hotbar.remove_child(child);child.queue_free()
	for slot in range(6):
		var entry:=BlueprintBag.find_entry(game.bag,game.bag.hotbar[slot])
		var button:=_add_button(hotbar,str(slot+1),func():game.bind_hotbar(slot))
		button.add_theme_font_size_override("font_size",14);button.custom_minimum_size=Vector2(29,34)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.disabled=not has_selection
		button.tooltip_text="Shift+%d · %s"%[slot+1,"空格" if entry.is_empty() else entry.name]
		PaperTheme.selected(button,has_selection and game.bag.hotbar[slot]==game.selected_blueprint_id)
	detail_preview.paths=[] if selected.is_empty() else selected.paths;detail_preview.queue_redraw()
	if selected.is_empty():
		editing_entry_id=-1
		detail_title.text="选一张图纸";details.text="选中作品，查看详情与可用操作。";place_button.text="先选择一张图纸";name_field.text=""
	else:
		var weapon:bool=selected.get("role","")=="weapon"
		detail_title.text=selected.name;detail_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		details.text=selected.category+"\n"+("装备后，按 R 使用" if weapon else "取出后点击纸面放置，可重复使用")
		place_button.text="装备武器" if weapon else "再次放置"
		if editing_entry_id != selected.id or not name_field.has_focus():name_field.text=selected.name
		editing_entry_id=selected.id
	_layout()

func _exit_tree()->void:
	if is_instance_valid(shade):shade.queue_free()
