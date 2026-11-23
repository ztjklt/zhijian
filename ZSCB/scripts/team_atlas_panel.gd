extends PanelContainer
signal return_requested

const Atlas := preload("res://scripts/team_atlas.gd")
const Art := preload("res://scripts/team_atlas_art.gd")
const Sheet := preload("res://scripts/distant_sheet.gd")
const Palette := preload("res://scripts/pen_palette.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const PROJECT_STAGES := {"working":"施工中","paused":"已暂停","awaiting_trade":"待实际成交","complete":"已完成"}
var game
var world_id := ""
var filter := OptionButton.new()
var search := LineEdit.new()
var pages := ItemList.new()
var heading := Label.new()
var caption := Label.new()
var frame := Control.new()
var art := Art.new()
var actions := HFlowContainer.new()
var controls := VBoxContainer.new()
var name_edit := LineEdit.new()
var stroke := OptionButton.new()
var pigment := OptionButton.new()
var brush := OptionButton.new()
var return_action := Callable()
var rows := []
var sheet := {}
var active := {}
var editing := false
const Goods=preload("res://scripts/architecture/stall_goods.gd")

static func open_for(host, filters := {}, on_return := Callable()) -> Control:
	if host.medieval_world==null: return null
	var parent = host.weapon_lab_panel.get_parent()
	var panel = parent.get_node_or_null("TeamAtlas")
	if panel==null:
		panel=load("res://scripts/team_atlas_panel.gd").new()
		panel.name="TeamAtlas"
		panel.game=host
		parent.add_child(panel)
	panel.open(filters,on_return)
	return panel

func _button(row: Control, text: String, fn: Callable) -> Button:
	var button := Button.new()
	button.text=text
	button.custom_minimum_size.y=32
	button.pressed.connect(fn)
	row.add_child(button)
	return button

func _ready() -> void:
	theme=PaperTheme.create()
	add_theme_stylebox_override("panel",PaperTheme.panel())
	mouse_filter=Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col:=VBoxContainer.new()
	add_child(col)
	var top:=HBoxContainer.new()
	col.add_child(top)
	var title:=Label.new()
	title.text="本队图鉴"
	title.add_theme_font_size_override("font_size",20)
	top.add_child(title)
	for entry in [["本队作品",""],["玩家","player"],["画家","companion"],["牧师","priest"],["战神","war_god"],["冒险者砾舟","adventurer-lizhou"],["参考笔谱","reference"]]:
		filter.add_item(entry[0])
		filter.set_item_metadata(filter.item_count-1,entry[1])
	top.add_child(filter)
	search.placeholder_text="找作品或作者"
	search.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(search)
	_button(top,"返回",_return_to_caller)
	var body:=HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	col.add_child(body)
	pages.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	pages.size_flags_stretch_ratio=.43
	pages.allow_reselect=true
	pages.add_theme_stylebox_override("panel",PaperTheme.surface(Color("e9e5d4"),6))
	for state in ["selected","selected_focus"]:
		pages.add_theme_stylebox_override(state,PaperTheme.surface(Color("d0dccf"),4))
	for state in ["font_color", "font_selected_color", "font_hovered_color", "font_hovered_selected_color"]:
		pages.add_theme_color_override(state, PaperTheme.INK)
	body.add_child(pages)
	var page:=VBoxContainer.new()
	page.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(page)
	heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size",19)
	page.add_child(heading)
	frame.clip_contents=true
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size.y=38
	page.add_child(frame)
	frame.add_child(art)
	frame.resized.connect(art.queue_redraw)
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size",14)
	page.add_child(caption)
	page.add_child(controls)
	name_edit.placeholder_text="新图纸名称"
	name_edit.max_length=64
	controls.add_child(name_edit)
	var picks:=HBoxContainer.new()
	controls.add_child(picks)
	for field: OptionButton in [stroke,brush,pigment]:
		field.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
		field.fit_to_longest_item=false
		field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		picks.add_child(field)
	for key in Brush.BRUSHES:
		brush.add_item(Brush.BRUSHES[key])
		brush.set_item_metadata(brush.item_count-1,key)
	for key in Palette.LABELS:
		pigment.add_item(Palette.LABELS[key])
		pigment.set_item_metadata(pigment.item_count-1,key)
	page.add_child(actions)
	filter.item_selected.connect(func(_i): _list())
	search.text_changed.connect(func(_value): _list())
	pages.item_selected.connect(_select)
	stroke.item_selected.connect(_choose_stroke)
	pigment.item_selected.connect(func(_i):_ink_preview())
	brush.item_selected.connect(func(_i):_ink_preview())
	visibility_changed.connect(func():set_process(visible))
	hide()

func open(filters: Dictionary, on_return := Callable()) -> void:
	_clear_return()
	return_action=on_return
	if return_action.is_valid():return_requested.connect(return_action)
	world_id=game.team_slot.get("world_id","")
	if game.divine_panel!=null and game.divine_panel.visible:game.divine_panel.close()
	game.get_node("UILayer").show()
	_select_author(str(filters.get("author_id","")))
	search.text=filters.get("text","")
	show()
	move_to_front()
	_list(str(filters.get("work_id","")))
	pages.grab_focus()

func _select_author(id: String) -> void:
	filter.select(0)
	for i in filter.item_count:
		if filter.get_item_metadata(i)==id:
			filter.select(i)
			return

func _process(_delta:float) -> void:
	if game.medieval_world==null or game.team_slot.get("world_id","")!=world_id: _close()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if editing:_select(pages.get_selected_items()[0])
		else:_return_to_caller()
		get_viewport().set_input_as_handled()

func _clear_return() -> void:
	if return_action.is_valid() and return_requested.is_connected(return_action):return_requested.disconnect(return_action)
	return_action=Callable()

func _return_to_caller() -> void:
	hide()
	return_requested.emit()
	_close()

func _close() -> void:
	_clear_return()
	hide()
	active={}
	sheet={}
	rows.clear()
	art.set_sheet({})
	editing=false

func _list(want := "") -> void:
	rows=Atlas.query(game,{"author_id":filter.get_selected_metadata(),"text":search.text})
	pages.clear()
	var title_counts := {}
	for row: Dictionary in rows:
		title_counts[row.name] = int(title_counts.get(row.name, 0)) + 1
	var index:=0
	for row: Dictionary in rows:
		var label: String = row.name
		if title_counts[row.name] > 1:
			var kind: String = {"建筑图纸": "图纸", "建筑实物": "已建"}.get(row.kind, row.kind)
			label = "%s · %s" % [kind, row.name]
		pages.add_item(label)
		pages.set_item_tooltip(pages.item_count-1,"%s · %s · %s" % [row.name,Atlas.AUTHORS.get(row.author_id,row.author_id),row.kind])
		if row.work_id==want:index=pages.item_count-1
	if not rows.is_empty():pages.select(index)
	_select(index if not rows.is_empty() else -1)

func _clear_actions() -> void:
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()

func _select(index: int) -> void:
	_clear_actions()
	editing=false
	controls.hide()
	active={} if index<0 else rows[index]
	sheet={} if index<0 else Atlas.read_sheet(game,active)
	if not sheet.get("ok",false):
		var author: String=filter.get_selected_metadata()
		heading.text="%s还没有作品" % Atlas.AUTHORS[author] if search.text.is_empty() and Atlas.AUTHORS.has(author) and author!="reference" else "没有符合条件的图页"
		caption.text=sheet.get("error","本队已有的创作会在这里出现。")
		if filter.get_selected_metadata()!="reference": _button(actions,"翻参考笔谱",func(): _select_author("reference");search.clear();_list())
		art.set_sheet({})
		return
	var entry:Dictionary=sheet.entry
	var recipe:Dictionary=sheet.recipe
	heading.text=entry.name
	var facts:=PackedStringArray([str(Atlas.AUTHORS.get(entry.author_id,entry.author_id)),entry.kind])
	if entry.format!="project" and recipe.has("strokes"): facts.append("%d 笔" % recipe.strokes.size())
	if recipe.has("record") and recipe.record.has("source_stroke"):
		for parent: Dictionary in sheet.related:
			if parent.work_id==entry.source_work_id:
				facts.append("取自《%s》第%d笔" % [parent.name,int(recipe.record.source_stroke)+1])
				break
	if not recipe.get("layout",{}).is_empty():facts.append("● 支点　○ 使用位")
	if recipe.has("design"):
		if recipe.design.has("parts"):facts.append("%d 个部件" % recipe.design.parts.size())
		else:facts.append("原始轮廓稿")
	if entry.format=="project":
		var phases: Array=recipe.get("phases",[])
		var cursor: int=clampi(int(recipe.get("cursor",0)),0,phases.size())
		facts.append("%s · %d/%d 道工序" % [PROJECT_STAGES.get(recipe.stage,"待确认"),cursor,phases.size()])
		if cursor<phases.size():facts.append(str(phases[cursor].get("aim","")).left(48))
		elif not recipe.outcomes.is_empty():facts.append(str(recipe.outcomes.back().get("detail","")).left(48))
	if entry.format=="distant" and recipe.revision > 0:
		var washes: int = recipe.moves.filter(func(m): return m.get("kind") == "wash").size()
		if washes > 0: facts.append("换洗 %d 次" % washes)
		if recipe.revision > washes: facts.append("已改位 %d 次" % (recipe.revision-washes))
	if entry.format=="individual":facts.append("遗骸" if recipe.phase=="dead" else "现场个体")
	caption.text="  ·  ".join(facts)
	caption.tooltip_text=str(recipe.get("brief",entry.work_id))
	if entry.format=="distant" and recipe.revision > 0:
		var last: Dictionary = recipe.moves.back()
		if last.get("kind") == "wash":
			var numbers := PackedStringArray()
			for change in last.changes:
				numbers.append("第 %d 笔%s" % [int(change.index)+1, "递淡" if change.brush=="mist" else "平洗"])
			caption.tooltip_text += "\n第 %d 版　%s，耗 %d 墨" % [last.revision,"、".join(numbers),last.ink_cost]
		else:
			caption.tooltip_text += "\n第 %d 次改位　左下 (%.2f, %.2f) → (%.2f, %.2f) 米\n画幅 %.2f × %.2f → %.2f × %.2f 米" % [
			last.revision, last.from_origin[0], last.from_origin[1], last.origin[0], last.origin[1],
			last.from_size[0], last.from_size[1], last.size[0], last.size[1]]
	art.set_sheet(sheet)
	if entry.format in ["reference","plan"] or (entry.format=="drawing" and recipe.get("pen")=="draw_scenery"):
		_button(actions,"抄入我的图纸包",_copy.bind(false))
		_button(actions,"改一笔另存",_edit)
		if not recipe.get("layout",{}).is_empty():
			_button(actions,"取组笔另存",_edit_group)
		if not recipe.get("layout",{}).get("stations",[]).is_empty(): _button(actions,"给柜位定价",_price_counter)
	if entry.format in ["reference","plan","distant"] or (entry.format=="drawing" and recipe.get("pen")=="draw_scenery"):
		_button(actions,"用作远景纸",_place_distant)
	if entry.format == "distant" and recipe.moves.any(func(m): return m.get("kind") == "wash"):
		_button(actions,"看换洗前原稿",_original_washes)
	if entry.format=="distant" and entry.author_id=="player":
		if recipe.strokes.any(func(line): return line.brush in ["wash","mist"]):
			_button(actions,"改原笔洗法",_edit_distant_wash)
		_button(actions,"调整原作画幅",_place_distant.bind(true))
	if entry.format in ["plan","drawing"] and entry.author_id=="player":
		_button(actions,"拿图选址",_place)
	if sheet.has("focus"):
		_button(actions,"看作品现场",_watch_work)
	if entry.format=="paper" and not recipe.record.has("projection"):
		_button(actions,"临到脚边地形草稿",_paper)
	if entry.format=="project" and recipe.get("stage")=="paused":
		_button(actions,"续作（允许后续调用模型）",_resume_project)
	if entry.format=="species":
		_button(actions,"复用物种图纸",_species)
	if entry.format=="individual":
		_button(actions,"去看这只生物",_watch)
	if not sheet.related.is_empty():
		var links:=MenuButton.new()
		links.text="关联图页（%d）" % sheet.related.size()
		links.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
		actions.add_child(links)
		for related: Dictionary in sheet.related:
			links.get_popup().add_item("%s · %s" % [related.name, "母图" if related.work_id==entry.source_work_id else related.kind])
		var destinations:Array=sheet.related
		links.get_popup().index_pressed.connect(func(i):_follow(destinations[i]))

func _follow(ref: Dictionary) -> void:
	_select_author("reference" if ref.format=="reference" else "")
	search.clear()
	_list(ref.work_id)

func _edit() -> void:
	editing=true
	name_edit.text=(active.name+" · 改稿").left(64)
	stroke.clear()
	for i in sheet.recipe.strokes.size():
		stroke.add_item("%d · %s" % [i+1,sheet.recipe.strokes[i].layer])
	controls.show()
	_clear_actions()
	_button(actions,"存入我的图纸包",_copy.bind(true))
	_button(actions,"取消",_select.bind(pages.get_selected_items()[0]))
	_choose_stroke(0)

func _edit_group() -> void:
	var dialog:=preload("res://scripts/atlas_group_dialog.gd").new()
	add_child(dialog)
	var ref:=active.duplicate()
	dialog.open_page(game,ref,func(result):
		if not result.ok:return
		game.toolbar.update_buttons()
		_select_author("player")
		search.clear()
		_list(result.work_id)
	)

func _choose_stroke(i: int) -> void:
	var line: Dictionary=sheet.recipe.strokes[i]
	for pair in [[brush,line.brush],[pigment,line.pigment]]:
		for n in pair[0].item_count:
			if pair[0].get_item_metadata(n)==pair[1]:pair[0].select(n);break
	_ink_preview()

func _ink_preview() -> void:
	if not editing or stroke.selected<0:return
	var draft:=sheet.duplicate(true)
	var line: Dictionary=draft.recipe.strokes[stroke.selected]
	line.brush=brush.get_selected_metadata()
	line.pigment=pigment.get_selected_metadata()
	art.set_sheet(draft,stroke.selected)
	caption.text="第 %d 笔 · %s · %s" % [stroke.selected+1,brush.get_item_text(brush.selected),pigment.get_item_text(pigment.selected)]

func _copy(change: bool) -> void:
	var patches: Array = [{"stroke":stroke.selected,"brush":brush.get_selected_metadata(),"pigment":pigment.get_selected_metadata()}] if change else []
	var title: String=name_edit.text if change else (active.name+" · 临本").left(64)
	var result:=Atlas.copy_plan(game,active,"player",title,patches)
	if not result.ok:
		caption.text=str(result.error)
		return
	game.toolbar.update_buttons()
	_select_author("player")
	search.clear()
	_list(result.work_id)

func _price_counter() -> void:
	editing=true
	_clear_actions()
	caption.text="选来客站位、货物与本柜的收售方向。单价以金计。"
	var station:=OptionButton.new()
	var item:=OptionButton.new()
	var direction:=OptionButton.new()
	var price:=SpinBox.new()
	for control:Control in [station,item,direction,price]:actions.add_child(control)
	for row in sheet.recipe.layout.stations:
		station.add_item("%s (%.1f 米)"%[row.get("use","柜位"),row.x])
	for key in Goods.items():
		item.add_item(Goods.items()[key].name)
		item.set_item_metadata(item.item_count-1,key)
	direction.add_item("柜台收购")
	direction.add_item("柜台出售")
	price.min_value=1
	price.max_value=99
	price.step=1
	price.suffix="金"
	var show_terms:=func(i:int):
		var existing:Dictionary=sheet.recipe.layout.stations[i].get("offer",Goods.LEGACY)
		for n in item.item_count:
			if item.get_item_metadata(n)==existing.item:item.select(n)
		direction.select(1 if existing.direction==Goods.SELL else 0)
		price.value=existing.unit_price
	station.item_selected.connect(show_terms)
	show_terms.call(0)
	item.item_selected.connect(func(i):price.value=Goods.items()[item.get_item_metadata(i)].price)
	_button(actions,"另存报价图纸",func():
		var sells:=direction.selected==1
		var q:={"direction":Goods.SELL if sells else Goods.BUY,"source":"stall_stock" if sells else "customer_bag","item":item.get_selected_metadata(),"unit_price":int(price.value)}
		var name_with_price:=(str(active.name)+" · "+Goods.label(q)).left(64)
		var result:=Atlas.copy_plan(game,active,"player",name_with_price,[],{"slot":station.selected,"offer":q})
		if not result.ok:caption.text=result.error;return
		game.toolbar.update_buttons()
		_select_author("player")
		search.clear()
		_list(result.work_id))
	_button(actions,"取消",_select.bind(pages.get_selected_items()[0]))

func _place() -> void:
	if not Atlas.read_sheet(game,active).ok:return
	var id:=int(sheet.recipe.bag_id)
	_close()
	game.select_blueprint(id)
	game.equip_blueprint()

func _paper() -> void:
	var at: Vector2=game.player.position
	var world=game.medieval_world
	var supports:Array=world.paper_surfaces(at.x,at.y-1.0,at.y+.05)
	for i in range(supports.size()-1,-1,-1):
		if supports[i].face=="floor":at.y=supports[i].y;break
	var result := Atlas.stage_player_paper(game,active,at)
	if not result.ok:
		caption.text=result.error
		return
	_close()
	game.message("已放入地形草稿，确认落笔时检查支点并扣墨。")

func _original_washes() -> void:
	var original := sheet.duplicate(true)
	original.recipe.strokes = original.recipe.original_strokes
	if not original.recipe.moves.is_empty():
		original.recipe.origin = original.recipe.moves[0].from_origin
		original.recipe.size = original.recipe.moves[0].from_size
	art.set_sheet(original)
	editing = true
	_clear_actions()
	caption.text = "首稿 · %d 笔" % original.recipe.strokes.size()
	_button(actions, "回当前稿", _select.bind(pages.get_selected_items()[0]))

func _edit_distant_wash() -> void:
	editing = true
	_clear_actions()
	var menu := MenuButton.new()
	menu.text = "选择原笔"
	menu.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	actions.add_child(menu)
	var popup := menu.get_popup()
	popup.hide_on_checkable_item_selection = false
	for i in sheet.recipe.strokes.size():
		var line: Dictionary = sheet.recipe.strokes[i]
		if line.brush in ["wash","mist"]:
			popup.add_check_item("第 %d 笔 · %s · %s" % [i+1,Palette.LABELS.get(line.pigment,line.pigment),"递淡" if line.brush=="mist" else "平洗"], i)
	var style := OptionButton.new()
	style.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	style.add_item("山脚递淡")
	style.add_item("普通平洗")
	actions.add_child(style)
	var spec := {"team_id":active.team_id,"world_id":active.world_id,"work_id":active.work_id,
		"expected_revision":sheet.recipe.revision,"request_id":"wash-"+Crypto.new().generate_random_bytes(12).hex_encode(),"edits":[]}
	var confirm := _button(actions,"确认改洗",func():
		var result := Sheet.revise_washes(game,"player",spec)
		if not result.ok:
			caption.text = result.error
			return
		game.toolbar.update_buttons()
		_list(result.work_id)
		caption.text += " · 本次耗 %d 墨" % result.ink_spent)
	_button(actions,"取消",_select.bind(pages.get_selected_items()[0]))
	var preview := func():
		var draft := sheet.duplicate(true)
		var target := "mist" if style.selected == 0 else "wash"
		spec.edits = []
		for j in popup.item_count:
			if popup.is_item_checked(j):
				var number := popup.get_item_id(j)
				spec.edits.append({"index":number,"brush":target})
				draft.recipe.strokes[number].brush = target
		art.set_sheet(draft)
		confirm.disabled = true
		if spec.edits.is_empty():
			caption.text = "先选原笔，可同时勾选几笔。"
			return
		var quote := Sheet.revise_washes(game,"player",spec,false)
		confirm.disabled = not quote.ok
		caption.text = "预览 · 改 %d 笔，共 %d 墨" % [quote.receipt.changes.size(),quote.ink_cost] if quote.ok else quote.error
	popup.id_pressed.connect(func(id):
		var j := popup.get_item_index(id)
		popup.set_item_checked(j,not popup.is_item_checked(j))
		preview.call())
	style.item_selected.connect(func(_i):preview.call())
	preview.call()

func _place_distant(reframe := false) -> void:
	var view:=preload("res://scripts/distant_sheet_panel.gd").new()
	view.name="DistantSheetPlacement"
	view.game=game
	view.sheet=sheet.duplicate(true)
	view.reframe = reframe
	get_parent().add_child(view)
	view.closed.connect(func(placed): 
		if not is_instance_valid(game) or game.team_slot.get("world_id")!=world_id:return
		if placed:_close()
		else:show();pages.grab_focus())
	hide()

func _resume_project() -> void:
	var result:=Atlas.read_sheet(game,active)
	if not result.ok:return
	var painter=game.medieval_world.get_node_or_null("SandboxCompanion")
	if painter!=null and painter.has_method("resume_scene_project") and painter.resume_scene_project(active.work_id):
		_list(active.work_id)
	else:caption.text="画家当前无法续作，请稍后再试。"

func _species() -> void:
	if not Atlas.read_sheet(game,active).ok:return
	var id:String=active.work_id
	var title:String=active.name
	_close()
	game.open_divine_status()
	game.divine_panel.open_chat("priest")
	var editor:TextEdit=game.divine_panel.chat_panel.editor
	editor.set_caret_line(editor.get_line_count()-1)
	editor.set_caret_column(editor.get_line(editor.get_caret_line()).length())
	editor.insert_text_at_caret(("" if editor.text.is_empty() else "\n")+"请照「%s」这份物种图纸（%s）再画一只。"%[title,id])
	editor.grab_focus()

func _watch_work() -> void:
	var current:=Atlas.read_sheet(game,active)
	if not current.get("ok",false) or not current.has("focus"):return
	var at:=Vector2(current.focus[0],current.focus[1])
	var label:=str(current.entry.name)
	_close()
	game.open_divine_status()
	game.divine_panel.watch_point(at,label)

func _watch() -> void:
	if not Atlas.read_sheet(game,active).ok:return
	var id:String=active.work_id
	_close()
	game.open_divine_status()
	game.divine_panel.watch("priest",id)
