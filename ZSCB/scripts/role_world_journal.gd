extends VBoxContainer
## Read a snapshot of this team's witnessed events. New receipts never move a
## card while the player reads it or follows its location.
const PAGE_SIZE := 12
const GuildReceipts := preload("res://scripts/role_guild_receipts.gd")
const NAMES := {"companion":"画家阿靛","priest":"牧师","war_god":"战神","adventurer-lizhou":"冒险者砾舟","guild":"冒险者公会","world":"本队","player":"玩家"}

var book
var tabs := HBoxContainer.new()
var night: Button
var recent: Button
var guild: Button
var ledger_open := false
var receipts: Array = []
var open_ids:Dictionary={}
var updates: Button
var scroll := ScrollContainer.new()
var cards := VBoxContainer.new()
var story: Array = []
var source
var team_world := ""
var overnight := true
var showing := 0
var more: Button
var return_button: Button
var return_offset := 0

func _ready() -> void:
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",5)
	add_child(tabs)
	night=book._button(tabs,"昨夜回顾",open.bind(true))
	recent=book._button(tabs,"近期流水",open.bind(false))
	night.toggle_mode=true
	recent.toggle_mode=true
	guild=book._button(tabs,"公会账本",_open_ledger)
	guild.toggle_mode=true
	var space:=Control.new()
	space.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.add_child(space)
	updates=book._button(tabs,"更新手记",_refresh_requested)
	updates.tooltip_text="读取新记录"
	updates.hide()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.follow_focus=true
	add_child(scroll)
	cards.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation",5)
	scroll.add_child(cards)

func open(night_view:bool=true) -> void:
	var next=book.host.game.medieval_world.chronicle
	if next!=source:
		if source!=null and source.changed.is_connected(_new_record):source.changed.disconnect(_new_record)
		source=next
		source.changed.connect(_new_record)
	team_world=str(book.host.game.team_slot.get("world_id",""))
	ledger_open=false
	guild.set_pressed_no_signal(false)
	overnight=night_view
	book.overnight=night_view
	night.set_pressed_no_signal(overnight)
	recent.set_pressed_no_signal(not overnight)
	open_ids.clear()
	for order:Dictionary in _open_orders(book.host.game.medieval_world):open_ids[order.id]=true
	story=source.overnight(8) if overnight else source.recent(source.CAPACITY)
	if overnight:story=_lead_accounts(story)
	_reset_cards()
	_append_page()
	(night if overnight else recent).grab_focus()
	scroll.scroll_vertical=0
	updates.hide()

func _lead_accounts(selected:Array) -> Array:
	# Lead with a concrete change to life and the latest reached patrol site.
	# The following accounts retain the sequence supplied by the chronicle.
	var life:Dictionary={}
	var patrol:Dictionary={}
	for e:Dictionary in selected:
		if life.is_empty() and e.kind in ["feed","injury","hunt","threat_defeated","birth","meat"]:life=e
		if patrol.is_empty() and e.kind=="patrol_arrived":patrol=e
	var ordered: Array=[]
	if not life.is_empty():ordered.append(life)
	if not patrol.is_empty():ordered.append(patrol)
	for e:Dictionary in selected:
		if e!=life and e!=patrol:ordered.append(e)
	return ordered

func _new_record() -> void:
	updates.show()

func _refresh_requested() -> void:
	if ledger_open:_open_ledger()
	else:open(overnight)

func _open_ledger(contract: String = "") -> void:
	ledger_open=true
	night.set_pressed_no_signal(false)
	recent.set_pressed_no_signal(false)
	guild.set_pressed_no_signal(true)
	updates.hide()
	_reset_cards()
	var world=book.host.game.medieval_world
	var events:Array=source.recent(source.CAPACITY)
	receipts=GuildReceipts.lookup(world,events)
	guild.grab_focus()
	scroll.scroll_vertical=0
	var orders:=_open_orders(world)
	if receipts.is_empty() and orders.is_empty():
		book.host._label(cards,"这支队伍暂时没有可查的委托。",16,PaperTheme.MENU_MUTED,true)
		return
	var accounts:Dictionary={}
	for receipt:Dictionary in receipts:
		var owner:=str(receipt.payee)
		if not accounts.has(owner):accounts[owner]={"count":0,"total":0,"known":true}
		var line:Dictionary=accounts[owner]
		line.count+=1
		if receipt.coins.is_empty():line.known=false
		else:line.total+=int(receipt.coins[1])-int(receipt.coins[0])
	for owner:String in accounts:
		var line:Dictionary=accounts[owner]
		var text:="%s · %d 单已兑付"%[NAMES.get(owner,owner),line.count]
		if line.known:text+="，共入账 %d 金"%line.total
		var summary:Label=book.host._label(cards,text,20,PaperTheme.INK,true)
		summary.tooltip_text="按本队仍可查的合同兑付记录汇总。"
	if not orders.is_empty():
		var logged:Array=world.survival.guild_events(0,GuildReceipts.Contracts.EVENT_CAP).get("events",[])
		for order:Dictionary in orders:_order_card(order,logged,order.id==contract)
	for receipt:Dictionary in receipts:_receipt_card(receipt,receipt.id==contract,accounts.size()>1)

func _open_orders(world) -> Array:
	if world.survival==null:return []
	var unique:={}
	for actor:String in GuildReceipts.Contracts.ACTORS:
		for order:Dictionary in world.survival.guild_contracts(actor).cards:
			if order.status in ["open","active","ready"]:unique[order.id]=order
	var active:Array=unique.values()
	var priority:={"ready":0,"active":1,"open":2}
	active.sort_custom(func(a,b):
		if a.status!=b.status:return priority[a.status]<priority[b.status]
		return int(str(a.id).trim_prefix("guild-"))>int(str(b.id).trim_prefix("guild-")))
	return active

func _order_next(order:Dictionary) -> String:
	if order.status=="ready":return "回公会柜台领取 %d 金"%int(order.reward)
	if order.status=="open":return "可在公会柜台领单"
	var person:=GuildReceipts.resident_name(str(order.target))
	match order.kind:
		"supply":return "等%s吃完已送的朱果"%person if order.stage=="delivered" else "给%s送一枚朱果"%person
		"guard":return "前去核实%s已脱险"%person if order.protected else "保护%s，等威胁解除"%person
		"escort":return "陪%s走到安全处"%person if order.stage=="escort" else "去接应"+person
		"survey":return "踏过已接通的新岸" if order.stage=="crossing" else "去纸边查看落脚处"
	return str(order.detail)

func _order_card(order:Dictionary,logged:Array,expanded:bool) -> void:
	var box:=PanelContainer.new()
	box.add_theme_stylebox_override("panel",PaperTheme.surface(Color("e6ebdf"),6))
	cards.add_child(box)
	var column:=VBoxContainer.new()
	box.add_child(column)
	var head:=HBoxContainer.new()
	column.add_child(head)
	var copy:=VBoxContainer.new()
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(copy)
	var owner:=str(NAMES.get(order.owner,order.owner))
	var status:="尚未领取" if order.status=="open" else owner+(" · 待领款" if order.status=="ready" else " · 已领待办")
	var title:="第 %s 单 · %s"%[str(order.id).trim_prefix("guild-"),order.title]
	book.host._label(copy,title+"　"+status,15,PaperTheme.INK,true)
	book.host._label(copy,_order_next(order),16,PaperTheme.INK,true)
	var detail:=VBoxContainer.new()
	column.add_child(detail)
	detail.visible=expanded
	var toggle:Button=book._button(head,"查此单",func():detail.visible=not detail.visible)
	toggle.set_meta("contract",order.id)
	if expanded:toggle.grab_focus.call_deferred()
	var location_button:Button=book._button(head,"看地点",_visit_order.bind(order.id))
	location_button.disabled=not _has_location(order)
	location_button.text="看委托地" if order.status=="open" else "看柜台" if order.status=="ready" else "看地点"
	location_button.tooltip_text="查看委托当前所指的位置"
	location_button.set_meta("contract_place",order.id)
	book.host._label(detail,"约定报酬 %d 金，尚未兑付"%int(order.reward),14,PaperTheme.MENU_MUTED,true)
	for event:Dictionary in logged:
		if event.contract_id!=order.id:continue
		var row:=HBoxContainer.new()
		detail.add_child(row)
		var line:=str(event.detail)
		if not str(event.target).is_empty():line=line.replace(event.target,GuildReceipts.resident_name(event.target))
		var fact:Label=book.host._label(row,str(NAMES.get(event.actor,event.actor))+"　"+line,14,PaperTheme.INK,true)
		fact.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if _has_location(event):
			var point:={"id":"guild/%s/%d"%[event.world_id,event.seq],"kind":"guild","title":title,"at":event.at}
			if GuildReceipts.STAGES.has(event.action):point.ledger_stage=event.action
			var jump:Button=book._button(row,"看当时地点",_visit.bind(point))
			jump.set_meta("event_id",point.id)

func _visit_order(id:String) -> void:
	for order:Dictionary in _open_orders(book.host.game.medieval_world):
		if order.id!=id:continue
		if _has_location(order):
			var title:=str(order.title)+" · "+("委托所指地点" if order.status=="open" else _order_next(order))
			_visit({"id":id,"kind":"guild","title":title,"at":order.at})
		return
	_open_ledger(id)

func _receipt_card(receipt:Dictionary,expanded:bool,show_owner:bool) -> void:
	var box:=PanelContainer.new()
	box.add_theme_stylebox_override("panel",PaperTheme.surface(Color("f1ebdb"),6))
	cards.add_child(box)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",1)
	box.add_child(column)
	var head:=HBoxContainer.new()
	column.add_child(head)
	var copy:=VBoxContainer.new()
	copy.add_theme_constant_override("separation",0)
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(copy)
	var job:=str(receipt.title)
	if not str(receipt.seam).is_empty():job+=" · %.1f 米旧岸"%float(receipt.seam)
	var number:=str(receipt.id).trim_prefix("guild-")
	var source_name:="第 %s 单"%number if number.is_valid_int() else str(receipt.id)
	if show_owner:source_name+=" · "+str(NAMES.get(receipt.payee,receipt.payee))
	if not receipt.resident.is_empty():source_name+="　"+GuildReceipts.resident_name(receipt.resident)
	var name:=str(receipt.road)
	var author:=str(receipt.author)
	if not name.is_empty():
		var road:="《"+name+"》"
		if not author.is_empty():road=str(NAMES.get(author,author))+"画的"+road
		source_name+="　"+road
	book.host._label(copy,source_name,14,PaperTheme.MENU_MUTED,true)
	var change:=""
	if receipt.coins.size()==2:
		change="　+%d 金　（%d → %d）"%[int(receipt.coins[1])-int(receipt.coins[0]),receipt.coins[0],receipt.coins[1]]
	book.host._label(copy,job+change,16 if book.compact else 18,PaperTheme.INK,true)
	var chain:=VBoxContainer.new()
	column.add_child(chain)
	chain.visible=expanded
	var button:Button=book._button(head,"查此单",func():chain.visible=not chain.visible)
	button.tooltip_text="查看本单领单、履约与入账记录"
	button.set_meta("contract",receipt.id)
	if expanded:button.grab_focus.call_deferred()
	var target:=str(receipt.id)
	book.host._label(chain,"合同 "+target,13,PaperTheme.MENU_MUTED)
	for recorded:Dictionary in GuildReceipts.in_recorded_order(receipt):
		var stage:=str(recorded.action)
		var e:Dictionary=recorded.duplicate(false)
		e.ledger_stage=stage
		var row:=HBoxContainer.new()
		chain.add_child(row)
		var text:=str(e.detail)
		if not receipt.resident.is_empty():
			text=text.replace(receipt.resident,GuildReceipts.resident_name(receipt.resident))
		# A battle and a rescue have separate witnesses. The clickable place
		# follows the same witness as the text the player is currently reading.
		var phase_title:=str(GuildReceipts.STAGES[stage])
		if stage=="protected" and receipt.has("defeat"):
			e=receipt.defeat.duplicate(false)
			text=str(e.title).trim_prefix("已击退威胁 · ")
			phase_title="战神击退"
		var spot:=""
		if _has_location(e):
			spot=" · 公会 %.1f 米"%float(e.at[0]) if stage in ["accepted","settled"] else " · %.1f 米"%float(e.at[0])
		var fact:=phase_title+spot+"　"+text
		var info:Label=book.host._label(row,fact,14,PaperTheme.INK,true)
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if _has_location(e):
			var place:Button=book._button(row,"看地点",_visit.bind(e))
			place.set_meta("event_id",e.id)

func _reset_cards() -> void:
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	showing=0
	more=null
	return_button=null

func _append_page() -> void:
	if more!=null:
		cards.remove_child(more)
		more.queue_free()
		more=null
	if story.is_empty():
		book.host._label(cards,"这支队伍还没有可回看的事件。",16,PaperTheme.MENU_MUTED,true)
		return
	var start:=showing
	showing=mini(showing+PAGE_SIZE,story.size())
	var first_new:Button
	for i in range(start,showing):
		var first:=_card(story[i])
		if i==start:first_new=first
	if showing<story.size():
		more=book._button(cards,"继续读前面的记录（还余 %d 条）"%(story.size()-showing),_append_page)
	if start>0 and first_new!=null:first_new.grab_focus()

func _card(e:Dictionary) -> Button:
	var actor:=str(e.role)
	var who:=str(NAMES.get(actor,"本队"))
	var tint:Color=book.WASHES.get(actor,Color("d8d2bf"))
	var box:=PanelContainer.new()
	var panel:=PaperTheme.surface(Color("faf5e8").lerp(tint,.23),6)
	panel.border_color=tint.darkened(.19)
	panel.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel",panel)
	cards.add_child(box)
	var stack:=VBoxContainer.new()
	stack.add_theme_constant_override("separation",1)
	box.add_child(stack)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	stack.add_child(row)
	if book.TITLES.has(actor):
		var art:=TextureRect.new()
		art.texture=book.character_art(actor,true)
		art.custom_minimum_size=Vector2(35,35)
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
	var copy:=VBoxContainer.new()
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation",0)
	row.add_child(copy)
	var location:="巡防" if e.kind=="patrol_arrived" else _location(e)
	book.host._label(copy,who+("　·　"+location if not location.is_empty() else ""),13,PaperTheme.MENU_MUTED,true)
	book.host._label(copy,_headline(e),16 if book.compact else 18,PaperTheme.INK,true)
	var details:=VBoxContainer.new()
	var info:Button=book._button(row,"详情",func():details.visible=not details.visible)
	info.flat=true
	info.tooltip_text="原记录、发生时间与相关编号"
	var jump:Button
	if str(e.kind)=="guild_settled" or (e.kind=="guild" and str(e.detail).contains("结算，金币 ")):
		jump=book._button(row,"查此单",_open_ledger.bind(str(e.subject_id)))
	elif _has_location(e):
		jump=book._button(row,"看现场",func():_visit(e))
		jump.tooltip_text="查看事件发生时的地点"
		jump.set_meta("event_id",e.id)
	stack.add_child(details)
	details.hide()
	details.add_theme_constant_override("separation",3)
	var words:=str(e.detail)
	if e.kind=="feed":
		words=preload("res://scripts/priest_ecology_log.gd").feed_display_text(words)
	if not words.is_empty():book.host._label(details,words,15,PaperTheme.INK,true)
	var reference:=str(e.get("subject_id",""))
	var stamp:=int(e.get("when_unix",0))
	if stamp>0:
		var date:=Time.get_datetime_dict_from_unix_time(stamp+Time.get_time_zone_from_system().bias*60)
		book.host._label(details,"%02d/%02d　%02d:%02d"%[date.month,date.day,date.hour,date.minute],13,PaperTheme.MENU_MUTED)
	if not reference.is_empty():book.host._label(details,"编号　"+reference,12,PaperTheme.MENU_MUTED,true)
	if str(e.kind).begins_with("guild") and open_ids.has(e.get("subject_id","")):
		book._button(details,"查此单",_open_ledger.bind(str(e.subject_id)))
	if book.TITLES.has(actor):
		var now:Button=book._button(details,"看"+who+"现在的位置",func():_visit(e,true))
		now.set_meta("event_id",e.id)
	return jump if jump!=null else info

func _has_location(e:Dictionary) -> bool:
	return e.get("at") is Array and e.at.size()==2

func _location(e:Dictionary) -> String:
	if e.get("ledger_stage","") in ["accepted","settled"]:return "冒险者公会柜台"
	if e.get("ledger_stage","") in ["route_joined","crossed"]:return "东侧探路接缝"
	if e.kind=="patrol_arrived" and str(e.title).begins_with("战神巡到"):
		return str(e.title).trim_prefix("战神巡到")
	if not _has_location(e):return ""
	return book.place_label(Vector2(e.at[0],e.at[1]))

func _headline(e:Dictionary) -> String:
	var title:=str(e.title)
	match e.kind:
		"feed":
			var animal:=title.get_slice(" · ",0)
			if str(e.detail).contains("牧草") and str(e.detail).contains("饱食 "):
				return "%s吃到牧草，饱食 %s"%[animal,str(e.detail).get_slice("饱食 ",1).trim_suffix("。").replace(".0 "," ").trim_suffix(".0")]
		"patrol_arrived":return "已巡抵"+_location(e)
		"guild","guild_posted","guild_closed","guild_settled":
			if str(e.detail).contains("结算，金币 "):return str(e.detail).replace(" 结算，金币 ","入账，钱袋 ")
			if str(e.detail).begins_with("原缺口已有"):return title+" · "+str(e.detail)
	return title

func _visit(e:Dictionary,actor_now:=false) -> void:
	return_button=get_viewport().gui_get_focus_owner() as Button
	return_offset=scroll.scroll_vertical
	if actor_now:book.host.watch(str(e.role),"",e.role=="priest")
	else:
		var label:=str(e.title)
		if e.has("ledger_stage"):label+=" · "+str(GuildReceipts.STAGES[e.ledger_stage])
		book.host.watch_point(Vector2(e.at[0],e.at[1]),label,_location(e))
	book.host.journal_return.show()
	book.host.journal_return.grab_focus()

func restore_card() -> void:
	if str(book.host.game.team_slot.get("world_id",""))!=team_world:
		book.host.close()
		return
	book.host.watching=""
	book.host.pinned_point=Vector2.INF
	book.host.game.observed_camera=Vector2.INF
	book.host.game.get_node("UILayer").show()
	book.host.strip.hide()
	book.host.shade.show()
	book.host.board.show()
	book.host._layout()
	if is_instance_valid(return_button):return_button.grab_focus()
	scroll.set_deferred("scroll_vertical",return_offset)
