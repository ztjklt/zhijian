extends VBoxContainer
## A role's live page, shared by the status button and the map.
const PORTRAITS := preload("res://assets/ui/role-book/role-portraits.png")
const Roles := preload("res://scripts/divine_roles.gd")
const TRAVELLER := "adventurer-lizhou"
const TITLES := {"companion":"画家阿靛","priest":"牧师","war_god":"战神","adventurer-lizhou":"冒险者砾舟"}
const VOCATIONS := {"companion":"勘察纸边，执笔接路","priest":"画出生灵，照看村中食物","war_god":"巡视道路，保护村民","adventurer-lizhou":"探索村庄，在公会谋生"}
const WASHES := {"companion":Color("c4d7d7"),"priest":Color("cbd8b8"),"war_god":Color("e1c8b4"),"adventurer-lizhou":Color("d7cfb5")}

var host
var role := "companion"
var page := "person"
var compact := false
var role_buttons := {}
var location_rows:Dictionary={}
var back: Button
var heading: Label
var journal_view
var animals_button:Button
var project_log: Button
var stop_transplant: Button
var project_note: Label
var project_visits := {}
var journal: Button
var history: Button
var archive: Button
var details: Button
var visit: Button
var send: Button
var editor := LineEdit.new()
var role_row := HBoxContainer.new()
var banner := PanelContainer.new()
var portrait := TextureRect.new()
var name_label: Label
var location: Label
var activity: Label
var response: Label
var suggestions:=HFlowContainer.new()
var sample_buttons:=[]
var route_label: Label
var main_scroll := ScrollContainer.new()
var body := VBoxContainer.new()
var person := VBoxContainer.new()
var entries := VBoxContainer.new()
var composer := HBoxContainer.new()
var footer := HBoxContainer.new()
var overnight := false
var context_world := ""

static func character_art(id:String,bust:=false) -> AtlasTexture:
	var index:=Roles.ALL.find(id)
	var image:=AtlasTexture.new()
	image.atlas=PORTRAITS
	image.region=Rect2(index*128+16,4,96,75) if bust else Rect2(index*128,0,128,128)
	image.filter_clip=true
	return image

func _ready() -> void:
	name="RoleFieldBook"
	add_theme_constant_override("separation",7)
	var top:=HBoxContainer.new()
	add_child(top)
	heading=host._label(top,"至高神状态",24,PaperTheme.INK) as Label
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	journal=_button(top,"世界手记",_journal_toggle)
	back=_button(top,"回到我",host.close)
	add_child(role_row)
	role_row.add_theme_constant_override("separation",4)
	for id:String in Roles.enabled()+[TRAVELLER]:
		var b:=_button(role_row,TITLES[id],select_role.bind(id))
		b.toggle_mode=true
		b.icon=character_art(id,true)
		b.expand_icon=true
		b.add_theme_constant_override("icon_max_width",32)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.tooltip_text=VOCATIONS[id]
		role_buttons[id]=b
	main_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	main_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	main_scroll.follow_focus=true
	journal_view=preload("res://scripts/role_world_journal.gd").new()
	journal_view.book=self
	add_child(journal_view)
	journal_view.hide()
	add_child(main_scroll)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	main_scroll.add_child(body)
	body.add_child(person)
	person.add_child(banner)
	var landscape:=TextureRect.new()
	landscape.texture=preload("res://assets/ui/paper-art/hills.png")
	landscape.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	landscape.stretch_mode=TextureRect.STRETCH_SCALE
	landscape.modulate=Color(1,1,1,.43)
	landscape.mouse_filter=Control.MOUSE_FILTER_IGNORE
	banner.add_child(landscape)
	var band:=HBoxContainer.new()
	banner.add_child(band)
	portrait.custom_minimum_size=Vector2(80,78)
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	band.add_child(portrait)
	var bio:=VBoxContainer.new()
	bio.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bio.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	bio.add_theme_constant_override("separation",1)
	band.add_child(bio)
	name_label=host._label(bio,"",24,PaperTheme.INK)
	location=host._label(bio,"",16,PaperTheme.INK,true)
	visit=_button(band,"去现场",_watch,true)
	visit.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	stop_transplant=_button(person,"停止这次移栽",_stop_transplant)
	stop_transplant.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	stop_transplant.hide()
	activity=host._label(person,"",16,PaperTheme.MENU_MUTED,true)
	animals_button=_button(person,"本局生物",_animals)
	animals_button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	project_log=_button(person,"",_projects)
	project_log.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	response=host._label(person,"",15,PaperTheme.MENU_MUTED,true)
	person.add_child(suggestions)
	for i in 2:
		sample_buttons.append(_button(suggestions,"",_use_example.bind(i)))
	body.add_child(entries)
	entries.hide()
	add_child(footer)
	footer.add_theme_constant_override("separation",4)
	history=_button(footer,"交谈记录",_conversation)
	archive=_button(footer,"历史作品",_works)
	details=_button(footer,"行动与连接",_technical)
	route_label=host._label(self,"",14,PaperTheme.MENU_MUTED,true)
	add_child(composer)
	editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	editor.max_length=600
	editor.add_theme_font_size_override("font_size",16)
	composer.add_child(editor)
	editor.text_changed.connect(_draft)
	editor.text_submitted.connect(func(_s):_submit())
	send=_button(composer,"发送",_submit,true)

func _button(parent: Control, label: String, action: Callable, primary:=false) -> Button:
	var button:Button=host._button(parent,label,action,primary)
	button.focus_mode=Control.FOCUS_ALL
	return button

func fit(available: Vector2) -> void:
	compact=available.y<440
	add_theme_constant_override("separation",2 if compact else 8)
	person.add_theme_constant_override("separation",2 if compact else 12)
	portrait.custom_minimum_size=Vector2(55,50) if compact else Vector2(82,78)
	name_label.add_theme_font_size_override("font_size",19 if compact else 27)
	activity.add_theme_font_size_override("font_size",14 if compact else 16)
	for row in [get_child(0),role_row,footer,composer]:
		for item in row.get_children():
			if item is Button: item.custom_minimum_size.y=30 if compact else 39
	response.visible=not compact and not response.text.is_empty()
	suggestions.visible=not compact

func select_role(id: String) -> void:
	if not role_buttons.has(id): return
	var current_world:=str(host.game.team_slot.get("world_id",""))
	if current_world!=context_world:
		context_world=current_world
	role=id
	page="person"
	for key:String in role_buttons:
		role_buttons[key].set_pressed_no_signal(key==id)
	editor.max_length=120 if id==TRAVELLER else 600
	if id==TRAVELLER:host.chat_panel.bind_world()
	else:host.chat_panel.open_for(id)
	editor.text=host.chat_panel.draft_for(id)
	editor.placeholder_text="对%s说…" % TITLES[id]
	portrait.texture=character_art(id)
	var surface:=PaperTheme.surface(WASHES[id].lerp(Color("faf4e7"),.57),8)
	surface.border_color=WASHES[id]
	banner.add_theme_stylebox_override("panel",surface)
	var examples:Array={
		"companion":["你在勘察哪里？","请去东边把地图接长一截。"],
		"priest":["村里的食物够吗？","说说你造过的生物。"],
		"war_god":["你现在守着哪里？","附近有村民遇险吗？"],
		"adventurer-lizhou":["你上次去了哪里？","请帮我问问村里的消息。"]}[id]
	for i in sample_buttons.size():
		sample_buttons[i].text=examples[i]
		sample_buttons[i].tooltip_text="填入草稿，可修改后发送"
	name_label.text=TITLES[id]
	name_label.tooltip_text=VOCATIONS[id]
	history.text="交谈与委托" if id==TRAVELLER else "交谈记录"
	var actor:Node=host._actor(id)
	var projects: Array = actor.atlas_projects() if id=="companion" and actor!=null and actor.has_method("atlas_projects") else []
	animals_button.visible = id=="priest" and host.priest_journal!=null
	project_log.visible = not projects.is_empty()
	project_log.text = "工程手册 · 柜台成交" if projects.any(func(p):return not _trade_receipt(p).is_empty()) else "工程手册"
	_show_page(true)
	refresh()

func _use_example(index:int) -> void:
	var example:Button=sample_buttons[index]
	editor.text=example.text
	_draft(editor.text)
	editor.grab_focus()
	editor.caret_column=editor.text.length()

func _show_page(is_person:bool) -> void:
	var reading:=page=="events"
	var locating:=page=="locations"
	journal_view.visible=reading
	main_scroll.visible=not reading
	role_row.visible=not reading and not locating and page!="projects"
	heading.text="队友方位" if locating else "世界手记" if reading else ("阿靛的工程手册" if page=="projects" else "至高神状态")
	journal.text="回到地图" if locating else "回到角色" if reading else "世界手记"
	person.visible=is_person
	entries.visible=not is_person
	footer.visible=is_person
	composer.visible=is_person
	route_label.visible=is_person
	main_scroll.scroll_vertical=0

func _draft(words:String) -> void:
	host.chat_panel.set_draft(role,words)
	refresh()

func _conversation() -> void:
	if role==TRAVELLER:
		host.close()
		host.game.map_controls.open_adventurer()
	else:host.open_chat(role)

func _watch() -> void:
	host.watch(role,"",role=="priest")

func _stop_transplant() -> void:
	if role!="priest" or page!="person":
		return
	var priest:Node=host._actor(role)
	if priest!=null and priest.has_method("cancel_pasture_work"):
		var result:Dictionary=priest.cancel_pasture_work()
		host.game.message(str(result.get("message","")))
	refresh()

func _submit() -> void:
	if send.disabled:return
	if not host._route_state(role).get("ready",false):
		host.open_role_settings(role)
		return
	if role!=TRAVELLER:
		host.open_chat(role)
		host.chat_panel._send()
	else:
		var actor:Node=host._actor(role)
		if actor!=null and actor.invite("chat",editor.text):
			host.chat_panel.set_draft(role,"")
			editor.clear()
		refresh()

func _technical() -> void:
	host.open_role_controls(role)

func _line(words:String) -> void:
	host._label(entries,words,16,PaperTheme.INK,true)

func _clear_entries() -> void:
	for old in entries.get_children():
		entries.remove_child(old)
		old.queue_free()

func _works() -> void:
	if host.open_team_atlas(role):return
	if role=="priest":
		host.open_priest_journal()
		return
	page="works"
	_show_page(false)
	_clear_entries()
	_line(TITLES[role]+"的作品")
	var rows:Array=host.game.medieval_world.paper_strokes_snapshot() if role=="companion" else []
	if role=="companion":rows.append_array(host.game.medieval_world.east_segments_snapshot())
	var count:=0
	for record:Dictionary in rows:
		if str(record.get("author_id",""))!=role:continue
		_line(str(record.get("name","无题")))
		var at=record.get("anchor",{}).get("at",[])
		if at is Array and at.size()==2:
			_button(entries,"看落笔处",host.watch_point.bind(Vector2(at[0],at[1]),str(record.get("name","作品"))))
		count+=1
	if count==0:_line("这支队伍还没有这位角色的作品记录。")
	_button(entries,"回到角色",select_role.bind(role)).grab_focus()

func _journal_toggle() -> void:
	if page=="locations":return_to_map()
	elif page=="events":host.open_role(role)
	else:show_events()

func show_locations(focus_role:String) -> void:
	page="locations"
	_show_page(false)
	_clear_entries()
	location_rows.clear()
	for id:String in role_buttons:
		var row:=HBoxContainer.new()
		entries.add_child(row)
		var art:=TextureRect.new()
		art.texture=character_art(id,true)
		art.custom_minimum_size=Vector2(42,44)
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
		var copy:=VBoxContainer.new()
		copy.add_theme_constant_override("separation",0)
		copy.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		var name_place:Label=host._label(copy,"",16,PaperTheme.INK)
		var action:Label=host._label(copy,"",14,PaperTheme.MENU_MUTED)
		for label in [name_place,action]:label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var watch:=_button(row,"看本人",_watch_from_locations.bind(id))
		watch.tooltip_text="跟着"+str(TITLES[id])+"的镜头"
		location_rows[id]={"place":name_place,"activity":action,"watch":watch}
	_update_locations()
	host._layout()
	if location_rows.has(focus_role):location_rows[focus_role].watch.grab_focus()

func _update_locations() -> void:
	var here:Vector2=host.game.player.position-Vector2(0,.29)
	for id:String in location_rows:
		var row:Dictionary=location_rows[id]
		var actor:Node=host._actor(id)
		var point:Vector2=host.person_point(id)
		if actor==null or not point.is_finite():
			row.place.text=TITLES[id]
			row.activity.text="尚未入场"
			row.watch.disabled=true
			continue
		var foot:=point if id=="priest" else point-Vector2(0,.29)
		var dx := foot.x - here.x
		var dy := foot.y - here.y
		var direction := "就在身边"
		if absf(dx) >= .25:
			direction = "%s %.1f 米" % ["向西" if dx < 0 else "向东", absf(dx)]
		elif absf(dy) > .75:
			direction = "正上方" if dy > 0 else "正下方"
		if absf(dy) > .75:
			direction += " · %s %.1f 米" % ["高" if dy > 0 else "低", absf(dy)]
		var state:Dictionary=host._autonomy_state(actor)
		var words:=str(state.get("summary",""))
		if id=="priest":words=host._priest_person_summary(actor,state)
		row.place.text="%s　%s · %s"%[TITLES[id],place_label(foot),direction]
		row.place.tooltip_text = "%s（%.1f，%.1f 米）" % [row.place.text, foot.x, foot.y]
		row.activity.text = player_activity_for(id,state,words)
		if id == "priest" and words.begins_with("站定 · 脚点"):
			row.activity.text = "站定"
		elif words.begins_with("候命 · "):
			row.activity.text = "候命 · 自主已暂停" if state.get("autonomy_paused",false) else "候命 · 等候模型连接"
		row.activity.tooltip_text=row.activity.text
		row.watch.disabled=false

func _watch_from_locations(id:String) -> void:
	if context_world!=str(host.game.team_slot.get("world_id","")):return
	if not host.person_point(id).is_finite():return
	host.watch(id,"",id=="priest")
	host.site_return=host.game.map_controls.open_role_locations.bind(id)
	host.journal_return.text="回队友方位"
	host.journal_return.show()
	host.journal_return.grab_focus()
	host._layout()

func return_to_map() -> void:
	host.close()
	host.game.toolbar.navigation_open=true
	host.game.map_controls.focus_locations_on_return = true

func show_events(night:=true) -> void:
	page="events"
	overnight=night
	_show_page(false)
	journal_view.open(night)
	host._layout()

func _trade_receipt(project: Dictionary, events := []) -> Dictionary:
	# A later player sale may follow another visitor's first receipt on this counter.
	var targets: Array = project.get("trade_targets",[])
	var scopes: Array = [project.get("scope",{})] + project.get("trade_origin_scopes",[])
	for i in range(events.size()-1,-1,-1):
		var row: Dictionary = events[i]
		if row.get("action")!="stall_trade" or row.get("actor")!="player" or row.get("target") not in targets:continue
		if scopes.any(func(s):return row.get("team_id")==s.get("team_id") and row.get("world_id")==s.get("world_id")):return row
	var receipt: Dictionary = project.get("trade_receipt",{})
	if not receipt.is_empty():return receipt
	for row: Dictionary in project.get("outcomes",[]):
		if row.get("phase")=="trade" and row.get("ok",false):return row.get("trade",{})
	return {}

func _shop(project: Dictionary, stalls: Array, receipt: Dictionary) -> Dictionary:
	var targets: Array = project.get("trade_targets",[])
	for stall: Dictionary in stalls:
		if stall.station not in targets:continue
		if receipt.is_empty():return stall
		if receipt.get("target")!=stall.station:continue
		var slot: int=int(receipt.get("goods",{}).get("slot",-1))
		if slot<0 or stall.site=="market-counter.%s.%d"%[stall.station,slot]:return stall
	return {}

func _animals() -> void:
	host.open_priest_journal()
	host.priest_journal.select_page(host.priest_journal.Page.ANIMALS)

func _projects() -> void:
	page="projects"
	_show_page(false)
	_clear_entries()
	project_visits.clear()
	project_note=host._label(entries,"",15,PaperTheme.MENU_MUTED,true)
	project_note.hide()
	var actor:Node=host._actor("companion")
	var projects: Array=actor.atlas_projects()
	var markets: Script = preload("res://scripts/architecture/market_sites.gd")
	var survival=host.game.medieval_world.survival
	var stalls: Array=markets.call("known_stalls",host.game,host.game.player.position) if survival!=null and markets.has_method("known_stalls") else []
	var ledger: Array = survival.guild_events(0,200).get("events",[]) if survival!=null else []
	var current:=projects.filter(func(p):return p.get("stage")=="working")
	if not current.is_empty():
		_line("阿靛正在做《%s》。继续另一项会先暂停这项。"%current.back().title)
	var title_counts := {}
	var cards := []
	for project:Dictionary in projects:
		var receipt := _trade_receipt(project,ledger)
		var title: String=project.title
		title_counts[title]=int(title_counts.get(title,0))+1
		cards.append({"project":project,"receipt":receipt,"number":title_counts[title],"order":cards.size()})
	cards.sort_custom(func(a,b):
		var a_player:bool=a.receipt.get("actor")=="player"
		var b_player:bool=b.receipt.get("actor")=="player"
		if a_player!=b_player:return a_player
		var a_paid:=int(a.receipt.get("seq",-1))
		var b_paid:=int(b.receipt.get("seq",-1))
		return a.order>b.order if a_paid==b_paid else a_paid>b_paid)
	for card in cards:
		var project:Dictionary=card.project
		var title: String=project.title
		var tag: String=" · 同名第%d份"%int(card.number) if title_counts[title]>1 else ""
		_project_card(project,title+tag,card.receipt,_shop(project,stalls,card.receipt))
	_button(entries,"回到角色",host.open_role.bind(role))

func _project_card(project:Dictionary, title:String, receipt:Dictionary, shop:Dictionary) -> void:
	var frame:=PanelContainer.new()
	frame.add_theme_stylebox_override("panel",PaperTheme.surface(Color("f5f0e1") if receipt.is_empty() else Color("e5eee4"),5))
	entries.add_child(frame)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",3)
	frame.add_child(box)
	var header:Label=host._label(box,title,17,PaperTheme.INK,true)
	header.tooltip_text=str(project.get("brief",""))
	var phases:Array=project.get("phases",[])
	var cursor:=clampi(int(project.get("cursor",0)),0,phases.size())
	var verified: bool=project.get("outcomes",[]).any(func(o):return o.get("phase")=="verify" and o.get("ok",false))
	var progress: String="%s %d/%d"%[{"paused":"暂停","working":"施工中","awaiting_trade":"待成交","complete":"完工"}.get(project.stage,"进度"),cursor,phases.size()]
	var facts:=PackedStringArray()
	if not shop.is_empty():facts.append("柜台已开")
	elif project.get("trade",false) and project.get("trade_targets",[]).is_empty():facts.append("尚未建柜")
	if phases.any(func(p):return p.get("kind")=="verify"):facts.append("阿靛已试走" if verified else "阿靛待试走")
	facts.append(progress)
	host._label(box,"　·　".join(facts),14,PaperTheme.MENU_MUTED,true)
	if not receipt.is_empty():
		var who: String="你已成交" if receipt.get("actor")=="player" else "柜台成交"
		host._label(box,who+"　"+str(receipt.get("detail","")),16,PaperTheme.TEAL,true)
	if cursor<phases.size():
		var step:Dictionary=phases[cursor]
		var next:=str(step.get("aim",""))
		if step.get("kind")=="verify" and not receipt.is_empty():
			next="阿靛沿旧路走到新柜，核对来客的落脚处。"
			if project.get("water_access",false):next+="再从岸口涉水。"
			if project.get("boat",false):next+="复核下层航道的净空和水面。"
		host._label(box,"下一步　"+next,15,PaperTheme.INK,true)
	var actions:=HFlowContainer.new()
	box.add_child(actions)
	if not shop.is_empty():
		var visit_shop:=_button(actions,"看这家店",_visit_shop.bind(str(project.project_id)),true)
		visit_shop.tooltip_text=str(shop.name)
		project_visits[str(project.project_id)]=visit_shop
	var sections:Array=project.get("channel_plan",{}).get("sections",[])
	if not sections.is_empty():
		_button(actions,"分段施工 · %d 段"%sections.size(),_open_sections.bind(str(project.project_id),context_world))
	if project.stage=="paused":
		var action:=_button(actions,"继续此工程",_resume_project.bind(str(project.project_id)))
		action.tooltip_text="沿用已完成的工序。后续若向模型发单，将使用画家的连接。"
	var brief:=str(project.get("brief","")).strip_edges()
	var clarification:=str(project.get("clarification","")).strip_edges()
	if not brief.is_empty():
		var quoted:Label=host._label(box,brief+("\n最近补充　"+clarification if not clarification.is_empty() else ""),15,PaperTheme.INK,true)
		quoted.hide()
		var disclose:=_button(actions,"委托原话",func():quoted.visible=not quoted.visible)
		disclose.toggle_mode=true

func _open_sections(project_id:String,world_id:String,section_id:="",scroll:=0,project_scroll:=-1) -> void:
	if str(host.game.team_slot.get("world_id",""))!=world_id:return
	var actor:Node=host._actor("companion")
	if actor==null:return
	for project:Dictionary in actor.scene_projects.list():
		if project.project_id!=project_id or project.get("channel_plan",{}).get("sections",[]).is_empty():continue
		if project_scroll<0:project_scroll=main_scroll.scroll_vertical
		page="sections"
		_show_page(false)
		_clear_entries()
		heading.text="水道分段施工"
		role_row.hide()
		var sheet=preload("res://scripts/role_channel_sheet.gd").new()
		entries.add_child(sheet)
		sheet.open(self,project,world_id,section_id,scroll,project_scroll)
		return
	_projects()

func _visit_shop(project_id:String) -> void:
	var game=host.game
	var actor:Node=host._actor("companion")
	var market:Script=preload("res://scripts/architecture/market_sites.gd")
	if game.medieval_world.survival==null or not market.has_method("known_stalls"):return
	var sites:Array=market.call("known_stalls",game,game.player.position)
	for project: Dictionary in actor.atlas_projects():
		if project.project_id!=project_id:continue
		var ledger: Array = game.medieval_world.survival.guild_events(0,200).get("events",[])
		var shop:=_shop(project,sites,_trade_receipt(project,ledger))
		if shop.is_empty():
			_projects()
			project_note.text="柜位刚有变化，请查看当前工程。"
			project_note.show()
			return
		var at:=Vector2(shop.at[0],shop.at[1])
		var subject:=Rect2()
		for obj:Dictionary in game.objects:
			if obj.get("structure_id")==shop.station:
				subject=game.object_bounds(obj)
				break
		host.watch_point(at,shop.name,place_label(at),_return_project.bind(project_id,context_world,main_scroll.scroll_vertical),subject)
		return

func _return_project(project_id:String,world_id:String,scroll:int) -> void:
	if str(host.game.team_slot.get("world_id",""))!=world_id:
		host.close()
		return
	host.open_role("companion")
	_projects()
	var button:Button=project_visits.get(project_id)
	if is_instance_valid(button):button.grab_focus()
	main_scroll.set_deferred("scroll_vertical",scroll)

func _resume_project(id:String) -> void:
	var actor:Node=host._actor("companion")
	if actor!=null and actor.resume_scene_project(id):
		host.open_role("companion")
	else:
		project_note.text="画家正在执行手上的行动。等他停步后可再继续，原工程进度已保留。"
		project_note.show()
		main_scroll.ensure_control_visible(project_note)

func place_label(at: Vector2) -> String:
	if not at.is_finite():return "尚未入场"
	var label:String=host.game.medieval_world.paper_nav_label("",at)
	return label.get_slice("（",0).trim_suffix(" · 地表")

func player_activity_for(id: String, state: Dictionary, words:String) -> String:
	if id=="companion" and words.ends_with("工程暂停"):return words
	if state.get("decision_source")=="本地行动":
		if state.get("phase")=="walking" or words.contains("沿实地行走") or words.contains("前往"):
			return {"companion":"正在勘察地形","priest":"正在巡看林地","war_god":"正在巡防村路"}.get(id,words)
		return {"companion":"停步察看地形","priest":"驻足查看草木","war_god":"停步巡望"}.get(id,words)
	if words.begins_with("站定 · 已到"):return "已到目的地"
	return words

func refresh() -> void:
	if page=="locations":
		_update_locations()
		return
	if page!="person":return
	var actor:Node=host._actor(role)
	var at:Vector2=host.person_point(role)
	var state:Dictionary=host._autonomy_state(actor)
	var words:=str(state.get("summary","角色尚未入场"))
	stop_transplant.visible=role=="priest" and state.get("can_cancel_pasture",false) and actor!=null and actor.has_method("cancel_pasture_work")
	if role=="priest" and actor!=null:words=host._priest_person_summary(actor,state)
	var foot:=at if role=="priest" else at-Vector2(0,.29)
	location.text=place_label(foot)+" · "+player_activity_for(role,state,words)
	if role=="companion" and words.ends_with("工程暂停"):
		var next_step:=str(state.get("reason","")).strip_edges()
		activity.text="恢复后 · "+next_step if not next_step.is_empty() else "可到工程手册查看待办"
	else:activity.text="职责 · "+str(VOCATIONS[role])
	activity.visible=true
	visit.disabled=not at.is_finite()
	var route:Dictionary=host._route_state(role)
	var ready:=bool(route.get("ready",false))
	var status:Dictionary=actor.divine_chat_status() if actor and actor.has_method("divine_chat_status") else {}
	var latest:=str(status.get("progress","")).strip_edges()
	response.text=latest
	response.visible=not compact and not latest.is_empty()
	var busy:bool=status.get("pending",false)
	var blocked:=role==TRAVELLER and at.is_finite() and at.distance_to(host.game.player.position)>11
	if ready:
		route_label.text="砾舟离你较远，可用「交谈与委托」到他身边。" if blocked else "上一句话正在处理，可先写下一句。" if busy else "发送会使用此角色绑定的模型和账户额度。"
		send.text="发送"
		send.disabled=editor.text.strip_edges().is_empty() or busy or blocked or actor==null or not status.get("can_send",true)
	else:
		var code:=str(route.get("code",""))
		route_label.text="尚未连接模型，仍可看现场。草稿会为此角色保留。" if str(route.get("id","")).is_empty() else str(route.get("message","连接暂不可用。"))
		if route.has("retry_after_ms"):
			send.text="等候重试"
			send.disabled=true
		else:
			send.text="补本次 Key" if code=="needs_key" else "设置连接"
			send.disabled=false

func show_controls(id:String) -> void:
	page="controls"
	_show_page(false)
	_clear_entries()
	_line(TITLES[id]+"的行动与连接")
	var at:Vector2=host.person_point(id)
	if at.is_finite():_line("实际位置　"+host.game.medieval_world.paper_nav_label("",at if id=="priest" else at-Vector2(0,.29)))
	var actor:Node=host._actor(id)
	var state:Dictionary=host._autonomy_state(actor)
	for pair in [["goal","目标"],["reason","缘由"],["progress","进展"],["pause_reason","暂停原因"]]:
		var words:String=host._intent_text(state.get(pair[0],""))
		if not words.is_empty():_line(pair[1]+"　"+words)
	_line(host._connection_text(id))
	var controls:=HFlowContainer.new()
	entries.add_child(controls)
	if actor!=null and actor.has_method("set_autonomy_paused"):
		_button(controls,"恢复自主" if state.get("autonomy_paused",false) else "暂停自主",func():
			host._toggle_autonomy(id)
			show_controls(id))
	if actor!=null and actor.has_method("set_action_budget"):
		var picker:=OptionButton.new()
		picker.tooltip_text="自主行动的模型回合额度"
		for limit in [0,1,3,8,16,32]:
			picker.add_item("持续自主" if limit==0 else "最多 %d 回合"%limit,limit)
		var limit:=int(state.get("budget",0))
		if picker.get_item_index(limit)<0:picker.add_item("最多 %d 回合"%limit,limit)
		picker.select(picker.get_item_index(limit))
		controls.add_child(picker)
		picker.item_selected.connect(func(index):actor.set_action_budget(picker.get_item_id(index)))
	_button(controls,"模型设置",host.open_role_settings.bind(id))
	_button(controls,"全部角色操作",host.open_all_controls)
	_button(controls,"回到角色",select_role.bind(id))
