extends VBoxContainer
## On the same inventory paper as the guild counter.
var picker:=OptionButton.new()
var body:=Label.new()
var action:=Button.new()
var option:=""
var selected_id:=""
var last_labels:=[]
var bag_panel

func configure(panel) -> void:
	bag_panel=panel
	add_theme_constant_override("separation",10)
	add_child(picker)
	picker.item_selected.connect(func(index):selected_id=str(picker.get_item_metadata(index));bag_panel.refresh())
	body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size",16)
	body.add_theme_color_override("font_color",Color("524c3d"))
	body.custom_minimum_size=Vector2(235,72)
	add_child(body)
	add_child(action)
	action.pressed.connect(func():
		if option!="":bag_panel._act("contract",{"option":option}))
	hide()

func refresh(service) -> void:
	var board:Dictionary=service.guild_contracts(service.PLAYER)
	var labels:=[]
	var rows:Array=board.cards.filter(func(c):return board.at_counter or c.owner==service.PLAYER)
	var phases:={"open":"待领","active":"在办","ready":"待结算","paid":"已领款","closed":"已结束"}
	for c in rows:labels.append([c.id,"%s · %s · %d 金"%[c.title,phases[c.status],c.reward]])
	if labels!=last_labels and not picker.get_popup().visible:
		last_labels=labels
		picker.clear()
		for label in labels:
			picker.add_item(label[1])
			picker.set_item_metadata(picker.item_count-1,label[0])
			if selected_id==label[0]:picker.select(picker.item_count-1)
		selected_id=str(picker.get_selected_metadata()) if picker.item_count>0 else ""
	picker.visible=not rows.is_empty()
	var matches:=rows.filter(func(c):return c.id==selected_id)
	option=""
	action.hide()
	if matches.is_empty():
		body.text="委托板上暂时没有新纸签。" if board.at_counter else "到 31 米公会柜台查看待领委托。"
		return
	var c:Dictionary=matches[0]
	var who:String={"":"尚无人领取","player":"你已领取","adventurer-lizhou":"砾舟已领取"}.get(c.owner,"")
	var step:String=c.detail
	if c.status=="ready":step="履约已确认，回 31 米公会柜台领取 %d 金。"%c.reward
	elif c.status=="paid":step="报酬已经进入接单人的钱袋。"
	elif c.status=="closed":step="现场情况已经改变，这项委托已结束。"
	elif c.stage=="delivered":step="朱果已递到居民手里，等他吃完。"
	elif c.stage=="escort":step="带居民往 %.1f 米的安全处走，保持三米内同行。"%c.at[0]
	elif c.protected:step="战神已击退威胁，走近幸存居民核实。"
	if c.kind=="supply" and c.status in ["open","active"] and c.stage!="delivered":
		var sites:Array=board.orchards.duplicate()
		sites.sort_custom(func(a,b):return absf(a.at[0]-c.at[0])<absf(b.at[0]-c.at[0]))
		for orchard in sites.slice(0,3):
			step+="\n%.1f 米果树有 %d 枚熟果"%[orchard.at[0],orchard.ripe]
			if orchard.next_in_s>=0:step+="，下一枚约 %d 秒"%orchard.next_in_s
		if sites.is_empty():step+="\n暂无活果树"
	body.text="%s　%s\n%s\n现场 %.1f 米　%s"%[c.id,who,step,c.at[0],c.target]
	for o in board.actions:
		if o.contract_id==c.id:
			option=o.id
			action.text=o.label+" · %d 金"%c.reward if o.verb=="settle" else o.label
			action.show()
			break

