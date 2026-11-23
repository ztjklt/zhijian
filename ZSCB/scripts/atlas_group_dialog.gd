extends ConfirmationDialog
const Atlas := preload("res://scripts/team_atlas.gd")
const Art := preload("res://scripts/team_atlas_art.gd")
const Palette := preload("res://scripts/pen_palette.gd")

func open_page(game,ref:Dictionary,done:Callable) -> void:
	title="取组笔另存"
	dialog_autowrap=true
	dialog_hide_on_ok=false
	ok_button_text="另存图纸"
	var target:=Atlas.read_sheet(game,ref)
	var sources:=Atlas.study_catalog(game)
	if not target.ok or sources.is_empty():queue_free();return
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size=Vector2(350,160)
	add_child(scroll)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var pick:=OptionButton.new()
	pick.fit_to_longest_item=false
	var parts:=OptionButton.new()
	parts.fit_to_longest_item=false
	var row:=HBoxContainer.new()
	box.add_child(row)
	for item in [pick,parts]:
		item.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
		row.add_child(item)
		item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for page in sources:pick.add_item(page.name)
	var choose:=func(i):
		parts.clear()
		for part in sources[i].parts:
			if part.strokes.size()<=8:
				parts.add_item("%s · %d笔"%[part.label,part.strokes.size()])
				parts.set_item_metadata(parts.item_count-1,part.id)
	pick.item_selected.connect(choose)
	choose.call(0)
	var target_ids:=LineEdit.new()
	target_ids.placeholder_text="替换本图原笔号，从1开始，逗号分隔"
	var legend:=[]
	for i in target.recipe.layout.layers.size():legend.append("%d · %s"%[i+1,target.recipe.layout.layers[i]])
	target_ids.tooltip_text="\n".join(legend)
	var targets:=HBoxContainer.new()
	box.add_child(targets)
	targets.add_child(target_ids)
	target_ids.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var add_target:=MenuButton.new()
	add_target.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	add_target.text="选原层"
	targets.add_child(add_target)
	for i in legend.size():add_target.get_popup().add_item(legend[i],i+1)
	add_target.get_popup().id_pressed.connect(func(n):
		var current:=_indices(target_ids.text)
		var i:int=n-1
		if current.has(i):current.erase(i)
		else:current.append(i)
		target_ids.text=",".join(current.map(func(k):return str(k+1)))
	)
	var source_ids:=LineEdit.new()
	source_ids.placeholder_text="取原书笔号，从1开始；留空使用所选部件"
	box.add_child(source_ids)
	var shape:=HBoxContainer.new()
	box.add_child(shape)
	var numbers:=[]
	for info in [["横",0.0],["高",0.0],["宽倍",1.0],["高倍",1.0]]:
		var n:=SpinBox.new()
		n.min_value=.01 if numbers.size()>=2 else -24.0
		n.max_value=24.0
		n.step=.01
		n.value=info[1]
		n.prefix=info[0]
		n.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		shape.add_child(n)
		numbers.append(n)
	var colors:=OptionButton.new()
	colors.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	colors.add_item("原笔色")
	colors.set_item_metadata(0,"source")
	for tint in Palette.LABELS:
		colors.add_item(Palette.LABELS[tint])
		colors.set_item_metadata(colors.item_count-1,tint)
	var mirror:=CheckButton.new()
	mirror.text="左右镜像"
	var options:=HBoxContainer.new()
	box.add_child(options)
	options.add_child(colors)
	options.add_child(mirror)
	var preview:=Button.new()
	preview.text="预览"
	options.add_child(preview)
	var art:=Art.new()
	var frame:=Control.new()
	frame.clip_contents=true
	frame.custom_minimum_size=Vector2(320,56)
	frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(frame)
	frame.add_child(art)
	frame.resized.connect(art.queue_redraw)
	art.set_sheet(target)
	var status:=Label.new()
	status.text="先选原书，再填本图要换的笔号。"
	box.add_child(status)
	var submit:=func(save:bool):
		var src:Dictionary=sources[pick.selected]
		var r:={"study":src.work_id,"team_id":src.ref.team_id,"world_id":src.ref.world_id,"layer":"取件","origin":[numbers[0].value,numbers[1].value],"scale":[numbers[2].value,numbers[3].value],"mirror_x":mirror.button_pressed,"pigment":colors.get_selected_metadata()}
		if source_ids.text.strip_edges()!="":r.strokes=_indices(source_ids.text)
		elif parts.selected>=0:r.part=parts.get_selected_metadata()
		var edits:=[{"indices":_indices(target_ids.text),"reference":r}]
		var res:=Atlas.copy_plan(game,ref,"player",(target.entry.name+" · 取件改稿").left(64),[],{},edits) if save else Atlas.study_variant(game,target,edits)
		if not res.ok:status.text=res.error;return
		if save:
			done.call(res)
			queue_free()
		else:
			var sheet:=target.duplicate(true)
			sheet.recipe.strokes=res.strokes
			sheet.recipe.layout=res.layout
			art.set_sheet(sheet)
			status.text="原图%d笔，改稿%d笔。"%[target.recipe.strokes.size(),res.strokes.size()]
	preview.pressed.connect(submit.bind(false))
	confirmed.connect(submit.bind(true))
	canceled.connect(queue_free)
	close_requested.connect(queue_free)
	popup_centered(Vector2i(mini(540,game.get_viewport_rect().size.x-12),mini(350,game.get_viewport_rect().size.y-8)))

func _indices(text:String) -> Array:
	var ids:=[]
	for word in text.replace("，",",").split(","):
		if not word.strip_edges().is_valid_int():return []
		ids.append(word.strip_edges().to_int()-1)
	return ids
