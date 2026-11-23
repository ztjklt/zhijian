extends VBoxContainer
## Read-only views of a project and its real terrain. No change of active project or player position.
const Survey=preload("res://scripts/paper_channel_survey.gd")
const Way=preload("res://scripts/paper_waterway.gd")
const Market=preload("res://scripts/architecture/market_sites.gd")
const Pen=preload("res://scripts/paper_world_pen.gd")

var book
var host
var project:Dictionary
var world_id:String
var team_id:String
var project_scroll:int
var section_id:=""
var buttons:={}
var sheet_scroll:=0
var section_note:=""
var route_note:=""
var report:={}
var elapsed:=0.0

func open(field_book,record:Dictionary,owner:String,focused:String,scroll:int,from_scroll:int) -> void:
	book=field_book
	host=book.host
	project=record
	world_id=owner
	team_id=str(host.game.team_slot.get("team_id",""))
	project_scroll=from_scroll
	var rows:Array=record.channel_plan.sections
	var header:=HBoxContainer.new()
	add_child(header)
	var title:Label=host._label(header,str(record.title),17,PaperTheme.INK,true)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	book._button(header,"回到这项工程",book._return_project.bind(record.project_id,owner,project_scroll))
	var order:Array=range(rows.size())
	# Show current work first, while keeping the numbers of the original draft.
	order.sort_custom(func(a,b):
		var ink_a:bool=not rows[a].work_ids.is_empty()
		var ink_b:bool=not rows[b].work_ids.is_empty()
		if ink_a!=ink_b:return ink_a
		return a>b if ink_a else a<b)
	for index:int in order:
		var row:Dictionary=rows[index]
		var kind:="注水稿" if row.kind=="water" else "开槽稿"
		var button:Button=book._button(self,"第 %d 段　%s　·　%s"%[index+1,row.name,kind],_visit.bind(row.id))
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text=str(row.id)
		buttons[row.id]=button
	if buttons.has(focused):
		buttons[focused].grab_focus()
		book.main_scroll.set_deferred("scroll_vertical",scroll)
	elif not order.is_empty():buttons[rows[order[0]].id].grab_focus()
	set_process(false)

func _current() -> bool:
	return is_instance_valid(host) and str(host.game.team_slot.get("world_id",""))==world_id and str(host.game.team_slot.get("team_id",""))==team_id

func _visit(id:String) -> void:
	if not _current():return
	section_id=id
	sheet_scroll=book.main_scroll.scroll_vertical
	var row:=_read()
	if row.is_empty():return
	host.watch_point(report.at,report.title,"",_restore,report.bounds,"回到这一段")
	_show_reading()
	elapsed=0.0
	set_process(true)

func _restore() -> void:
	if not _current():
		if is_instance_valid(host):host.close()
		return
	var id=project.project_id
	host.open_role("companion")
	book._open_sections(id,world_id,section_id,sheet_scroll,project_scroll)

func _process(delta:float) -> void:
	if not _current() or not host.is_visible_in_tree() or not host.pinned_point.is_finite() or host.site_return!=_restore:
		set_process(false)
		return
	elapsed+=delta
	if elapsed<1.5:return
	elapsed=0
	if not _read().is_empty():_show_reading()

func _show_reading() -> void:
	var text:=section_note+"\n"+route_note
	if host.action.text==report.title and host.route.text==text and host.pinned_point==report.at and host.site_subject==report.bounds:return
	host.pinned_point=report.at
	host.site_subject=report.bounds
	host.action.text=report.title
	host.route.text=text
	host._layout()

func _read() -> Dictionary:
	var latest:Dictionary={}
	var actor:Node=host._actor("companion")
	if not is_instance_valid(actor):return {}
	for item:Dictionary in actor.scene_projects.list():
		if item.project_id==project.project_id:
			latest=item
			break
	var rows:Array=latest.get("channel_plan",{}).get("sections",[])
	for index:int in rows.size():
		var row:Dictionary=rows[index]
		if row.id!=section_id:continue
		project=latest
		_measure(row,index)
		return row
	section_note="这段施工稿已更新，请回工程手册查看。"
	route_note=""
	host.route.text=section_note
	return {}

func _measure(row:Dictionary,index:int) -> void:
	var game=host.game
	var a:=Pen.point(row.from)
	var b:=Pen.point(row.to)
	var at:Vector2=(a+b)*.5
	# Use the same section proof as the painter, with commit disabled.
	if game.medieval_world==null or game.medieval_world.paper_space==null or not ResourceLoader.exists("res://scripts/painter_channel_plan.gd"):
		section_note="本次未取得这段的现场测量。"
		route_note=""
		report={"title":"第 %d 段 · %s"%[index+1,row.name],"at":at,"bounds":Rect2(a,Vector2.ZERO).expand(b).grow(.2)}
		return
	var plan:Script=load("res://scripts/painter_channel_plan.gd")
	var measured:Dictionary=plan.measure(game.medieval_world,project,section_id,false)
	var gauge=row.get("level",measured.get("best_measured_level"))
	if gauge==null:gauge=at.y
	at.y=float(gauge)
	var span:=Vector2(minf(a.x,b.x),maxf(a.x,b.x))
	var wet:=_wet_at(game.medieval_world,span,float(gauge))
	var passage:=_counter_route(game,at) if project.get("boat",false) else {}
	var under:float=passage.get("clear_width_m",0.0)
	var through:bool=passage.get("through",false)
	var kind:="注水" if row.kind=="water" else "开槽"
	var clear:float=measured.get("clear_span_m",0.0)
	var stage:="待落笔" if row.work_ids.is_empty() else ("已达段稿" if measured.get("ok",false) else "未达段稿")
	var linked:Array=row.get("linked_water_work_ids",[])
	if not linked.is_empty() and clear==0 and wet==0:stage="关联 %d 笔 · 段内未达"%linked.size()
	var height:=("%.3f"%float(gauge)).trim_suffix("0")
	var water:="高程 %s 米无实水"%height if wet<=0 else "高程 %s 米 · 实水 %.2f 米"%[height,wet]
	section_note="%s %.2f／%.2f 米 · %s　｜　%s"%[kind,clear,measured.get("planned_span_m",span.y-span.x),stage,water]
	if not project.get("boat",false):route_note="本工程未设柜下通船工序"
	elif passage.is_empty():route_note="未量到本工程原柜的使用位"
	else:route_note="柜下净宽 %.2f／%.2f 米 · %s"%[under,Way.WIDTH,"两端已通" if through else "两端未见贯通"]
	report={"at":at,"bounds":Rect2(a,Vector2.ZERO).expand(b).expand(at).grow(.2),"title":"第 %d 段 · %s"%[index+1,row.name],"section_id":section_id,"clear":clear,"wet":wet,"gauge":gauge,"under":under,"through":through,"ok":measured.get("ok",false),"work_count":row.work_ids.size(),"linked_water_count":linked.size()}

# Use the same live water polygons and level tolerance as the original vessel survey.
func _wet_at(world,span:Vector2,level:float) -> float:
	var area:=Rect2(span.x,level-Way.DRAFT,span.y-span.x,Way.DRAFT)
	# Include higher pools whose polygons cover this particular gauge.
	for entry:Dictionary in world.paper_space.nearby(area.grow(Way.EPS)):
		if entry.record.mode=="water":area=area.expand(Vector2(span.x,entry.box.end.y))
	var waters:=Survey._waters(world,area.grow(Way.EPS))
	for y:float in waters:
		if absf(y-level)<=Way.EPS:
			var parts:Array=Survey._band(waters[y].parts,level-Way.DRAFT+Way.EPS,level-Way.EPS,span)
			return Survey._widest(parts)
	return 0.0

func _counter_route(game,from:Vector2) -> Dictionary:
	var stand:=Vector2.INF
	for obj:Dictionary in game.objects:
		if obj.get("hp",1)<=0 or not obj.get("structure_id","") in project.get("trade_targets",[]) or not obj.get("work_id","") in project.work_ids:continue
		for spot:Dictionary in Market._built_spots(game,obj):
			var point:Vector2=spot.at
			if point.distance_squared_to(from)<stand.distance_squared_to(from):stand=point
	if not stand.is_finite():return {}
	var passage:=Way.at_building(game,project,stand)
	if not passage.has("frontage"):return {}
	var current_width:=0.0
	passage.through=false
	var probe:={"feet":[stand.x,stand.y],"hand":[stand.x,stand.y],"grounded":false,"radius":0.0}
	for native:Dictionary in passage.levels:
		if native.spans.is_empty():continue
		var survey:=Survey.observe(game,project,probe,Way.WIDTH,native.water_level)
		if survey.get("building",{}).get("work_id","")!=passage.building_work_id:continue
		for layer:Dictionary in survey.sections:
			if absf(float(native.water_level)-float(layer.level))>Way.EPS:continue
			current_width=maxf(current_width,_shared_width(layer.under_building_wet,native.spans))
			for opening:Dictionary in layer.through_both_open_sides:
				if _shared_width(opening.under,native.spans)+Way.EPS>=Way.WIDTH:passage.through=true
	passage.clear_width_m=current_width
	return passage

func _shared_width(wet:Array,owned:Array) -> float:
	var best:=0.0
	for a:Array in wet:
		for b:Array in owned:
			best=maxf(best,minf(a[1],b[1])-maxf(a[0],b[0]))
	return best
