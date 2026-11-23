extends VBoxContainer
## Per-role unsent drafts live in this world. The actors own their transcripts.
const Roles := preload("res://scripts/divine_roles.gd")
const GODS := Roles.NAMES
var host
var role := "companion"
var role_buttons := {}
var drafts:Dictionary:
	get:
		var saved:={}
		for id:String in Roles.ALL:saved[id]=draft_for(id)
		return saved
var feedback := {}
var world_id := ""
var connection: Label
var history := RichTextLabel.new()
var progress: Label
var world_action: Label
var editor := TextEdit.new()
var send_button: Button
var configure_button: Button
var watch_button: Button
var work_button: Button
var work_receipt := {}
var receipt_key := []
var held_row:=HBoxContainer.new()
var held_label:Label
var held_send:Button
var journal_button: Button
var return_button: Button
var traveller_button: Button
var last_transcript := ""
var compact:=false
var revision_row:=HBoxContainer.new()
var revision_id:=""
var placement_row:=HBoxContainer.new()
var placement_buttons:Array[Button]=[]

func _ready() -> void:
	name="DivineChat"
	add_theme_constant_override("separation",7)
	var row:=HFlowContainer.new()
	add_child(row)
	var group:=ButtonGroup.new()
	for id:String in Roles.enabled():
		var choice:Button=host._button(row,GODS[id],open_for.bind(id))
		choice.name={"companion":"ChoosePainter", "priest":"ChoosePriest", "war_god":"ChooseWarGod"}[id]
		choice.icon=preload("res://scripts/role_field_book.gd").character_art(id,true)
		choice.custom_minimum_size.x=100 if id=="companion" else 68
		choice.expand_icon=true
		choice.add_theme_constant_override("icon_max_width",24)
		choice.toggle_mode=true
		choice.button_group=group
		role_buttons[id]=choice
	traveller_button=host._button(row,"砾舟",host.open_role.bind("adventurer-lizhou"))
	traveller_button.icon=preload("res://scripts/role_field_book.gd").character_art("adventurer-lizhou",true)
	traveller_button.custom_minimum_size.x=68
	traveller_button.expand_icon=true
	traveller_button.add_theme_constant_override("icon_max_width",24)
	journal_button=host._button(row,"图纸与手记",host.open_priest_journal)
	host._button(row,"回角色页",func():host.open_role(role))
	connection=host._label(self,"",14,PaperTheme.MENU_MUTED,true)
	history.size_flags_vertical=Control.SIZE_EXPAND_FILL
	history.custom_minimum_size.y=60
	history.bbcode_enabled=false
	history.selection_enabled=true
	history.scroll_following=true
	history.add_theme_color_override("default_color",PaperTheme.INK)
	history.add_theme_font_size_override("normal_font_size",17)
	history.add_theme_constant_override("line_separation",4)
	history.add_theme_stylebox_override("normal",PaperTheme.surface(Color("f6f2e7"),8))
	add_child(history)
	progress=host._label(self,"",15,PaperTheme.MENU_MUTED,true)
	world_action=host._label(self,"",16,PaperTheme.TEAL,true)
	world_action.clip_text=true
	add_child(placement_row)
	for index in 2:
		var b:Button=host._button(placement_row,"",_choose_site.bind(index))
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.clip_text=true
		b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		placement_buttons.append(b)
	placement_row.hide()
	add_child(held_row)
	held_label=host._label(held_row,"",14,PaperTheme.INK)
	held_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	held_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	held_send=host._button(held_row,"补发上一句",_resolve_held.bind(true))
	held_send.tooltip_text="使用此角色所绑定账户，发送上次排队时尚未投递的原话。"
	host._button(held_row,"放弃上一句",_resolve_held.bind(false))
	held_row.hide()
	add_child(revision_row)
	host._button(revision_row,"另存改稿图纸",_resolve_revision.bind(true))
	host._button(revision_row,"放弃这笔改稿",_resolve_revision.bind(false))
	revision_row.hide()
	editor.custom_minimum_size.y=72
	editor.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	editor.tooltip_text="最多 600 字 · Ctrl / ⌘ + Enter 发送"
	editor.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER] and (event.ctrl_pressed or event.meta_pressed):
			editor.accept_event()
			if not send_button.disabled:_send())
	editor.add_theme_font_size_override("font_size",17)
	editor.add_theme_color_override("font_color",PaperTheme.INK)
	editor.add_theme_color_override("caret_color",PaperTheme.INK)
	editor.add_theme_color_override("font_placeholder_color",Color("566563"))
	editor.add_theme_stylebox_override("normal",PaperTheme.surface(Color("fffdf6"),8))
	add_child(editor)
	editor.text_changed.connect(func():
		if editor.text.length()>600:
			var line:=editor.get_caret_line()
			var column:=editor.get_caret_column()
			editor.set_block_signals(true)
			editor.text=editor.text.left(600)
			editor.set_caret_line(mini(line,editor.get_line_count()-1))
			editor.set_caret_column(column)
			editor.set_block_signals(false)
		set_draft(role,editor.text)
		refresh())
	var actions:=HFlowContainer.new()
	add_child(actions)
	send_button=host._button(actions,"发送",_send,true)
	send_button.tooltip_text="调用此角色的模型，使用所绑定账户额度。Ctrl / ⌘ + Enter 发送。"
	configure_button=host._button(actions,"设置 · AI 角色",host._settings)
	watch_button=host._button(actions,"去现场",func():host.watch(role,"",role=="priest"))
	watch_button.add_theme_stylebox_override("normal",PaperTheme.scrap(Color("d9e5d9")))
	work_button=host._button(actions,"看原作",_watch_receipt)
	work_button.name="WorkReceipt"
	work_button.hide()
	return_button=host._button(actions,"回到我",host.close)
	return_button.flat=true

func set_draft(id:String,words:String) -> void:
	if world_id!=str(host.game.team_slot.get("world_id","")):return
	var actor:Node=host._actor(id)
	if actor!=null:
		actor.set("divine_draft" if id=="companion" else "unsent_draft",words)

func draft_for(id:String) -> String:
	var actor:Node=host._actor(id)
	if actor==null:return ""
	return str(actor.get("divine_draft" if id=="companion" else "unsent_draft"))

func bind_world() -> void:
	var current_id:String=host.game.team_slot.get("world_id","")
	if current_id==world_id:return
	feedback.clear()
	world_id=current_id

func open_for(id: String) -> void:
	if not role_buttons.has(id):return
	bind_world()
	role=id
	role_buttons[id].set_pressed_no_signal(true)
	journal_button.visible = id == "priest"
	editor.set_block_signals(true)
	editor.text=draft_for(role)
	editor.set_block_signals(false)
	editor.placeholder_text=Roles.PROMPTS[id]
	last_transcript=""
	refresh()

func fit_view(available:Vector2)->void:
	var small:=available.y<440
	if small==compact:return
	compact=small
	add_theme_constant_override("separation",3 if compact else 7)
	editor.custom_minimum_size.y=52 if compact else 72
	history.custom_minimum_size.y=32 if compact else 60
	world_action.autowrap_mode=TextServer.AUTOWRAP_OFF if compact else TextServer.AUTOWRAP_WORD_SMART
	world_action.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS if compact else TextServer.OVERRUN_NO_TRIMMING
	refresh()

func _send() -> void:
	var actor:Node=host._actor(role)
	if actor==null or not actor.has_method("submit_divine_chat"):return
	var route:Dictionary=host._route_state(role)
	if not route.ready:
		feedback[role]=route.message
		refresh()
		return
	var raw:=editor.text
	if raw.strip_edges().is_empty():return
	var state:Dictionary=actor.divine_chat_status()
	if state.get("pending",false) or not state.get("can_send",true):
		feedback[role]=str(state.get("hint","请等这轮处理完再发送。"))
		refresh()
		return
	var result:Dictionary=actor.submit_divine_chat(raw)
	if result.get("ok",false):
		set_draft(role,"")
		editor.clear()
		feedback.erase(role)
	else: feedback[role]=str(result.get("message","未能发送，原话已保留。"))
	refresh()

func _resolve_held(send:bool) -> void:
	if world_id!=str(host.game.team_slot.get("world_id","")):return
	var actor:Node=host._actor(role)
	if actor==null or actor.held_chat.is_empty():return
	if send:
		if held_send.disabled:return
		var current:=draft_for(role)
		var result:Dictionary=actor.submit_divine_chat(actor.held_chat[0],true)
		if not result.get("ok",false):
			feedback[role]=result.get("message","尚未发出，原话已保留。")
			refresh()
			return
		set_draft(role,current)
	actor.held_chat.pop_front()
	refresh()

func _resolve_revision(keep:bool) -> void:
	var actor:Node=host._actor(role)
	if role!="priest" or not actor or revision_id.is_empty():return
	var result:Dictionary=actor.resolve_revision_offer(revision_id,keep)
	if result.ok:feedback.erase(role)
	else:feedback[role]=result.message
	refresh()

func _choose_site(index:int) -> void:
	var actor:Node=host._actor(role)
	if role!="priest" or not actor or not actor.has_method("choose_creation_site"):return
	var button:=placement_buttons[index]
	var result:Dictionary=actor.choose_creation_site(str(button.get_meta("option_id","")))
	if result.ok:feedback.erase(role)
	else:feedback[role]=result.message
	refresh()

func _show_sites(options:Array,pending:bool) -> void:
	placement_row.visible=not options.is_empty()
	for i in placement_buttons.size():
		var b:=placement_buttons[i]
		b.visible=i<options.size()
		if not b.visible:continue
		var option:Dictionary=options[i]
		b.text="在此落笔 · "+str(option.label)
		b.tooltip_text=b.text+"（使用本次笔稿，无需再次调用模型）"
		b.set_meta("option_id",option.id)
		b.disabled=pending

func _latest_work(actor:Node, state:Dictionary) -> Dictionary:
	var messages:Array=state.get("messages",[])
	if messages.is_empty() or messages.back().get("speaker")!="status":return {}
	var brief:=""
	for i in range(messages.size()-2,-1,-1):
		if messages[i].get("speaker")=="player":
			brief=messages[i].text
			break
	if brief.is_empty():return {}
	var result:Dictionary=actor.last_result
	var command:Dictionary=actor.last_command
	var detail:=str(result.get("detail",""))
	var live:bool=result.get("tool")=="revise_scene_component" and not detail.is_empty() \
		and not str(result.get("call_id","")).is_empty() and result.call_id==command.get("call_id") \
		and str(messages.back().text).ends_with(detail)
	var target:=""
	if live:
		target=str(result.get("work_id","")) if result.ok else str(command.get("args",{}).get("work_id",""))
		if target.is_empty():return {}
	var found:={}
	for obj:Dictionary in host.game.objects:
		if obj.get("author_id")!="companion" or not obj.has("built_plan") or str(obj.get("work_id","")).is_empty():continue
		if live:
			if obj.work_id!=target:continue
			if result.ok and result.get("structure_id")!=obj.get("structure_id"):continue
		else:
			# Old saves carry the full commission and call on the installed drawing.
			var ink:Dictionary=obj.built_plan.get("layout",{}).get("authorship",{})
			if ink.get("tool")!="revise_scene_component" or ink.get("brief")!=brief or str(ink.get("call_id","")).is_empty():continue
			if not found.is_empty():return {}
		found={"id":obj.work_id,"name":obj.name,"verdict":"original"}
		if live:
			if not result.ok:found.verdict="refused"
			elif int(result.get("plan_id",-1))==int(obj.built_plan.get("id",-2)):found.verdict="changed"
			found.count=result.get("changed_strokes",[]).size()
			break
	return found

func _watch_receipt() -> void:
	if role!="companion" or world_id!=str(host.game.team_slot.get("world_id","")):return
	for obj:Dictionary in host.game.objects:
		if obj.get("work_id")!=work_receipt.get("id") or obj.get("author_id")!="companion" or not obj.has("built_plan"):continue
		var bounds:Rect2=host.game.object_bounds(obj)
		var at:=bounds.get_center()
		host.watch_point(at,str(obj.name),"阿靛的原作",host.open_chat.bind(role),bounds,"回到阿靛交谈")
		return
	work_receipt.clear()
	work_button.hide()
	host.game.message("这件原作已离开现场。")

func _work_feedback(actor:Node, state:Dictionary, messages:Array) -> void:
	watch_button.text="看阿靛" if role=="companion" else "去现场"
	if role!="companion" or actor==null:
		work_button.hide()
		return
	if state.get("pending",false):
		work_button.hide()
		match state.get("chat_phase"):
			"sent","thinking":world_action.text="阿靛正在看你的委托"
			"executing":world_action.text=str(state.get("progress",world_action.text))
		return
	var key:=[world_id,actor.last_result.get("request_id",""),messages,host.game.objects.size()]
	if key!=receipt_key:
		receipt_key=key
		work_receipt=_latest_work(actor,state)
	if work_receipt.is_empty():
		work_button.hide()
		return
	var words:=str(work_receipt.name)
	match work_receipt.verdict:
		"changed":words+=" · 已改 %d 笔"%work_receipt.count
		"refused":
			words+=" · 退稿，原画保留，可补一句"
			world_action.add_theme_color_override("font_color",Color("854e3d"))
		_:words+=" · 原作在场"
	world_action.text=words
	world_action.tooltip_text=words
	work_button.text="看改后原作" if work_receipt.verdict=="changed" else "看原作"
	work_button.tooltip_text=words
	work_button.show()

func refresh() -> void:
	if send_button==null:return
	var actor:Node=host._actor(role)
	var supported:=actor!=null and actor.has_method("divine_chat_status") and actor.has_method("submit_divine_chat")
	var state:Dictionary=actor.divine_chat_status() if supported else {}
	var options:Array=state.get("placement_options",[]) if role=="priest" else []
	_show_sites(options,state.get("placement_busy",false))
	var choice:Dictionary=state.get("revision_choice",{})
	revision_id=str(choice.get("call_id",""))
	revision_row.visible=role=="priest" and not revision_id.is_empty()
	revision_row.get_child(0).visible=not choice.get("waiting",false)
	revision_row.get_child(1).text="停止追随并放弃改笔" if choice.get("waiting",false) else "放弃这笔改稿"
	var route:Dictionary=host._route_state(role)
	connection.text="发送会使用此角色绑定的模型和账户额度。" if route.ready else str(route.message)
	configure_button.visible=not route.ready and not route.has("retry_after_ms")
	configure_button.text="补本次 Key" if route.code=="needs_key" else "设置 · AI 角色" if route.ready else "去设置 AI 角色连接"
	var lines:=PackedStringArray()
	var messages:Array=state.get("messages",[])
	var newest_question := -1
	for i in range(messages.size()-1,-1,-1):
		if messages[i] is Dictionary and messages[i].get("speaker") == "player":
			newest_question = i
			break
	var last_spoken := ""
	for i in messages.size():
		var message=messages[i]
		if not message is Dictionary:continue
		var speaker:String=message.get("speaker","")
		var words:=str(message.get("text",""))
		if words.is_empty():continue
		var who:String="你" if speaker=="player" else GODS[role] if speaker=="god" else "现场回执"
		if i == newest_question:who = "你 · 这次的话"
		if i < newest_question and speaker == "status":who = "此前的现场回执"
		last_spoken = words if speaker in ["god","status"] else ""
		lines.append(who+"\n"+words)
	var transcript:="\n\n".join(lines) if not lines.is_empty() else "你与%s的对话会显示在这里。"%GODS[role]
	var visible_progress:=PackedStringArray()
	var latest:=str(state.get("progress",""))
	var phase_label: String={"queued":"已排队，尚未请求服务商","sent":"已发给服务商，等待回复","thinking":"已发给服务商，等待回复","executing":"正在现场执行"}.get(state.get("chat_phase",""),"")
	if not phase_label.is_empty() and state.get("pending",false):visible_progress.append(phase_label)
	if not latest.is_empty() and latest != phase_label and latest != last_spoken:visible_progress.append(latest)
	if state.get("pending",false) and latest.is_empty():visible_progress.append("正在等待%s回应。"%GODS[role])
	if not supported:visible_progress.append("角色尚未入场。")
	var local:=str(feedback.get(role,""))
	if local!="" and local!=latest:visible_progress.append(local)
	progress.text="\n".join(visible_progress)
	progress.visible=not compact and not visible_progress.is_empty()
	connection.visible=not compact
	var live:Dictionary=actor.divine_status() if actor!=null else {}
	var activity:=str(live.get("summary","角色尚未入场"))
	var subject:Vector2=host.person_point(role)
	var feet:=subject if role=="priest" else subject-Vector2(0,.29)
	var book=host.field_book
	if book!=null and subject.is_finite():
		var action_text:String=book.player_activity_for(role,live,activity)
		world_action.text=book.place_label(feet)+" · "+action_text
	else:world_action.text="本局现场　"+host.action_summary(live,activity)
	world_action.tooltip_text=world_action.text
	if compact:
		var info:="\n".join(visible_progress)
		transcript=connection.text+("\n"+info if info!="" else "")+"\n\n"+transcript
	if transcript!=last_transcript:
		history.text=transcript
		last_transcript=transcript
	progress.tooltip_text=progress.text
	var refused:bool=latest.contains("退稿") or latest.contains("未落笔") or latest.contains("未建成") or latest.contains("拒绝") or latest.contains("未能")
	progress.add_theme_color_override("font_color",Color("854e3d") if refused else PaperTheme.MENU_MUTED)
	if compact and refused:
		world_action.text=latest
		world_action.tooltip_text=latest
	world_action.add_theme_color_override("font_color",Color("854e3d") if refused else PaperTheme.TEAL)
	_work_feedback(actor,state,state.get("messages",[]))
	var can_send:bool=supported and route.ready and not state.get("pending",false) and state.get("can_send",true)
	held_row.visible=supported and not actor.held_chat.is_empty()
	if held_row.visible:
		held_label.text="上次待发　"+str(actor.held_chat[0])
		held_label.tooltip_text=held_label.text
		held_send.disabled=not can_send
	send_button.disabled=not can_send or editor.text.strip_edges().is_empty()
	watch_button.disabled=actor==null or not actor.observation_target().is_finite()
