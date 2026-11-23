extends RefCounted
## Survival owns every root and grass seat. The priest stores only the current job.
const Ground:=preload("res://scripts/priest_ground.gd")
const Food:=preload("res://scripts/priest_food_web.gd")
const Species:=preload("res://scripts/priest_species.gd")
const SIGHT:=13.0
const WALK_SPEED:=2.0
const EVENT_UNIT:={"grass":"patch_portions","feed":"animal_satiety","hunger":"animal_health","plant_root":"planted_roots"}
var job:Dictionary={}
var route:Dictionary={}

static func valid(value:Variant,works:Dictionary,active:bool) -> bool:
	if not value is Dictionary or active==value.is_empty():return false
	if not active:return true
	if not works.has(value.get("work_id")) or not value.get("chat") is bool:return false
	for key in ["work_id","call_id","source_id","root_id","soil_id"]:
		if not value.get(key) is String or value[key].length()>128:return false
	if value.call_id.is_empty() or value.soil_id.is_empty() or (value.source_id.is_empty() and value.root_id.is_empty()):return false
	return Species.pair(value.get("source_at"),1e6) and Species.pair(value.get("site_at"),1e6)

func restore(value:Dictionary) -> void:
	job=value.duplicate(true)
	route={}

static func _live_grazer(a) -> bool:
	return a!=null and a.phase not in ["dead","drawing"] and a.has_action("graze_grass")

static func _recent(p,id:String) -> Array:
	var recent:=[]
	for i in range(p.ecology_log.rows.size()-1,-1,-1):
		var row:Dictionary=p.ecology_log.rows[i]
		if row.work_id!=id or row.kind not in ["feed","grass","hunger","plant_root"]:continue
		recent.push_front({"seq":row.seq,"kind":row.kind,"source_or_plot":row.target_id,"before":row.before,"after":row.after,"unit":EVENT_UNIT[row.kind]})
		if recent.size()==8:break
	return recent

static func _plots(p,a,at:Vector2) -> Array:
	var plots:=[]
	var foot:=Vector2(a.beast_x,a.beast_y)
	for offset in [-.8,.8,-1.8,1.8,-2.8,2.8,0.0,-3.8,3.8]:
		var x:=snappedf(foot.x+offset,.1)
		var surface:=Ground.trace(p.world,foot,x)
		if surface.is_empty():continue
		var soil:Dictionary=p.world.survival.pasture_root_site(Vector2(x,surface.y))
		if not soil.get("ok",false):continue
		var target:=Vector2(soil.x,soil.y)
		if not Food.pasture_barrier(a,soil).is_empty():continue
		if not p.world.paper_nav_route(at,target).get("ok",false):continue
		plots.append({"id":"plot@%.1f,%.2f"%[target.x,target.y],"at":[target.x,target.y],"soil_id":soil.work_id})
		if plots.size()>=3:break
	return plots

static func _route_seconds(route_info:Dictionary) -> float:
	if not route_info.get("ok",false):return INF
	var seconds:=0.0
	for step in route_info.steps:
		if step.kind=="walk":
			seconds+=Species.vec(step.from).distance_to(Species.vec(step.to))/WALK_SPEED
		else:seconds+=float(step.duration)
	return seconds

static func _meals(p,id:String) -> Dictionary:
	var window:=[]
	var by_plot:={}
	var own:=0
	var delivered:=0
	for i in range(p.ecology_log.rows.size()-1,-1,-1):
		var row:Dictionary=p.ecology_log.rows[i]
		if row.work_id!=id or row.kind not in ["grass","feed"]:continue
		if row.kind=="grass":by_plot[row.target_id]=int(by_plot.get(row.target_id,0))+1
		if window.size()>=8:continue
		if row.kind=="grass":own+=1
		else:delivered+=1
		window.push_front({"seq":row.seq,"kind":row.kind,"plot_or_feeder":row.target_id})
	return {"oldest_first":window,"self_grazed":own,"hand_fed":delivered,"self_by_plot_in_retained_log":by_plot}

static func _earliest_new(p,here:Vector2,sites:Array,sources:Array,held:Array,first_growth:float,accessible:Dictionary) -> Dictionary:
	var best_s:=INF
	var best:={}
	for spot in sites:
		var dest:=Species.vec(spot.at)
		# A held root can start at the priest's foot. A new split needs both real routes.
		var origins:Array=[{"id":held[0],"x":here.x,"y":here.y,"walk_to_split_s":0.0}] if not held.is_empty() else sources
		for source in origins:
			var start:=Vector2(source.x,source.y)
			var carry:=_route_seconds(p.world.paper_nav_route(start,dest))
			var walk:float=float(source.walk_to_split_s)+carry
			if walk>=best_s:continue
			best_s=walk
			best={"site_id":spot.id,"source_or_held_root":source.id,"already_held":not held.is_empty(),
				"donor_already_counted_for_this_animal":accessible.has(source.id),"plant_in_s":snappedf(walk,.01),
				"first_ripe_after_plant_s":first_growth,"first_ripe_from_now_s":snappedf(walk+first_growth,.01)}
	return best

static func _animal_facts(p,a,here:Vector2,sources:Array,held:Array,first_growth:float) -> Dictionary:
	var feet:=Vector2(a.beast_x,a.beast_y)
	var meals:=_meals(p,a.work_id)
	var fields:=[]
	var accessible:={}
	var ripe:=0
	var production:=0.0
	var next_growth:=INF
	var next_plot:=""
	for patch in p.world.survival.pasture_near(feet,a.design.sight):
		var blocked:=Food.pasture_barrier(a,patch)
		var rate:float=60.0/float(patch.interval_s)
		var self_meals:int=meals.self_by_plot_in_retained_log.get(patch.id,0)
		fields.append({"id":patch.id,"portions":patch.portions,"capacity":patch.capacity,"next_in_s":patch.regrow_s,
			"interval_s":patch.interval_s,"plot_portions_per_min":snappedf(rate,.001),"blocked_by":blocked,"can_self_graze":blocked.is_empty(),
			"self_meals_from_plot_in_retained_log":self_meals,"self_accessible_portions_per_min":snappedf(rate,.001) if blocked.is_empty() else 0.0})
		if not blocked.is_empty():continue
		accessible[patch.id]=true
		ripe+=int(patch.portions)
		production+=rate
		if patch.portions<patch.capacity and patch.regrow_s<next_growth:
			next_growth=patch.regrow_s
			next_plot=patch.id
	var used_rate:float=a.last_metabolism_rate
	var rate_source:="last_body_step"
	if used_rate<0:
		rate_source="restored_phase_estimate"
		used_rate=Food.SATIETY_LOSS
		if a.phase=="flee":used_rate=Food.FLEE_LOSS
		elif a.phase in ["takeoff","fly","land"]:used_rate=0.0
	var demand:=60.0*used_rate/Food.GRASS_GAIN
	var sites:=_plots(p,a,here)
	var balance:={"self_ripe_portions_now":ripe,"self_growable_portions_per_min":snappedf(production,.001),
		"capacity_basis":"仅该只当前可见且身体能走到的草株；隔栏草源可供牧师割或分根，其产量不计入自食。",
		"satiety_per_portion":Food.GRASS_GAIN,"current_satiety_use_per_s":used_rate,"metabolism_basis":rate_source,
		"seconds_supported_by_one_full_portion":snappedf(Food.GRASS_GAIN/used_rate,.01) if used_rate>0 else null,
		"portions_needed_per_min_at_this_rate":snappedf(demand,.001),"supply_minus_demand_per_min":snappedf(production-demand,.001),
		"existing_next_growth":{"plot_id":next_plot,"in_s":snappedf(next_growth,.01)} if is_finite(next_growth) else {},
		"new_if_started_now_estimate":_earliest_new(p,here,sites,sources,held,first_growth,accessible),"last_meals":meals}
	return {"work_id":a.work_id,"name":a.design.name,"at":[feet.x,feet.y],"health":a.health,"satiety":a.satiety,
		"previous_bite_feet":a.grazing.places.duplicate(true),"returning_to":a.grazing.aim.duplicate(true),
		"self_grazed":a.grass_meals,"hand_fed":a.delivered_meals,"reachable_portions_per_minute":snappedf(production,.001),
		"grass_balance":balance,"fields":fields,"hunger_clock":a.starvation_facts(),"recent":_recent(p,a.work_id),"sites":sites}

static func observe(p) -> Dictionary:
	var service=p.world.survival
	if not service or not service.has_method("pasture_root_site"):return {}
	var here:=Vector2(p.priest_x,p.priest_y)
	var sources:=[]
	for patch in service.pasture_near(here,SIGHT):
		if not patch.get("can_divide",false):continue
		var seconds:=_route_seconds(p.world.paper_nav_route(here,Vector2(patch.x,patch.y)))
		if not is_finite(seconds):continue
		patch.walk_to_split_s=seconds
		sources.append(patch)
	var held:Array=service.pasture_roots("priest")
	var first_growth:float=service.Pasture.interval(1)
	var animals:=[]
	for a in p.works:
		if _live_grazer(a) and here.distance_to(Vector2(a.beast_x,a.beast_y))<=SIGHT:
			animals.append(_animal_facts(p,a,here,sources,held,first_growth))
	return {"roots_in_hand":held,"sources":sources,"animals":animals,
		"satiety_per_grass":Food.GRASS_GAIN,"base_drain_per_second":Food.SATIETY_LOSS}

func _decline(p,message:String,chat:bool) -> void:
	p.progress=message
	p.chat_notice=message
	if chat:p._chat_line("status",message)

func begin(p,c:Dictionary,facts:Dictionary,chat:bool) -> void:
	if not job.is_empty() or p.activity not in ["idle","wait"]:
		_decline(p,"牧师还有未完的工序，这次尚未动身分根。",chat)
		return
	if not _live_grazer(p.work_by_id(c.work_id)):
		_decline(p,"要照看的原只已经不在场，或已不能采草。",chat)
		return
	var choices:Array=facts.get("animals",[]).filter(func(a):return a.work_id==c.work_id)
	if choices.is_empty():
		_decline(p,"这次巡视没有看见指定的原只。",chat)
		return
	var sites:Array=choices[0].sites.filter(func(s):return s.id==c.site_id)
	if sites.is_empty():
		_decline(p,"本次没有勘到这处可让原只吃草的土地。",chat)
		return
	var source:=[0.0,0.0]
	if c.root_id.is_empty():
		var donors:Array=facts.sources.filter(func(row):return row.id==c.source_id)
		if donors.is_empty():
			_decline(p,"本次没有勘到这丛可以分根的成熟牧草。",chat)
			return
		source=[donors[0].x,donors[0].y]
	elif not c.root_id in p.world.survival.pasture_roots("priest"):
		_decline(p,"指定的活根已不在牧师手中。",chat)
		return
	job={"work_id":c.work_id,"call_id":c.call_id,"chat":chat,"source_id":c.source_id,"source_at":source,"root_id":c.root_id,
		"site_at":sites[0].at.duplicate(),"soil_id":sites[0].soil_id}
	route={}
	p.activity="plant"
	p.goal=c.goal
	p.model_reason=c.reason
	p.last_eco_call=c.call_id
	p.progress="动身分取活根" if c.root_id.is_empty() else "携带原有活根前往栽点"
	p.chat_notice=p.progress
	if chat:p._chat_line("god",c.reply,c,c.work_id)
	p._keep_notes(c)

func finish(p,result:String) -> void:
	if job.is_empty():return
	var root_id:String=job.root_id
	if root_id!="" and root_id in p.world.survival.pasture_roots("priest"):result+=" 已分出的活根仍在牧师手中。"
	p.progress=result
	p.chat_notice=result
	p.record_outcome("移栽牧草",p.model_reason,result,job.work_id,job.call_id)
	if job.chat:p._chat_line("status",result)
	job={}
	route={}
	p.activity="idle"

func step(p,dt:float) -> void:
	var a=p.work_by_id(job.work_id)
	if not _live_grazer(a):
		finish(p,"原草食个体已经不在场，结束这次移栽。")
		return
	var service=p.world.survival
	var carrying:bool=not job.root_id.is_empty()
	if carrying and not job.root_id in service.pasture_roots("priest"):
		finish(p,"这簇活根已不在牧师手中。")
		return
	var dest:Vector2=Species.vec(job.site_at if carrying else job.source_at)
	var here:=Vector2(p.priest_x,p.priest_y)
	if route.is_empty():route=p.world.paper_nav_route(here,dest)
	if not route.get("ok",false):
		finish(p,"脚下没有通往本次栽点或草场的路。")
		return
	var move:Dictionary=p.world.paper_nav_step(route,here,dt,WALK_SPEED)
	if not move.get("ok",false):
		finish(p,"栽护途中脚面改变，结束本次工作。")
		return
	var foot:Vector2=move.at
	p.priest_x=foot.x
	p.priest_y=foot.y
	p.progress=("携根走向栽点" if carrying else "走向草场分根")+" · 脚点（%.1f，%.1f）"%[foot.x,foot.y]
	if not move.arrived:return
	# The target must still be real soil, accessible to this specific animal.
	var site:Vector2=Species.vec(job.site_at)
	var soil:Dictionary=service.pasture_root_site(site)
	if not soil.get("ok",false) or soil.work_id!=job.soil_id or Vector2(soil.x,soil.y).distance_to(site)>.12 or not Food.pasture_barrier(a,soil).is_empty():
		finish(p,"原栽点的土面、空位或这只兽的取食通路已改变。")
		return
	if not carrying:
		var split:Dictionary=service.dig_pasture_root("priest",job.source_id)
		if not split.get("ok",false):
			finish(p,"抵达后未能分根："+str(split.get("error","草场已变")))
			return
		job.root_id=split.root_id
		route={}
		p.progress="已分得一簇活根，准备携往原兽一侧"
		p.ecology_log.record(p,a,"dig_root",split.root_id,0,1,"牧师在 %s 分得一簇可移栽的活根。"%job.source_id,foot)
		return
	var planted:Dictionary=service.plant_pasture_root("priest",job.root_id,site)
	if not planted.get("ok",false):
		finish(p,"埋根未成功："+str(planted.get("error","草场已变")))
		return
	p.ecology_log.record(p,a,"plant_root",planted.pasture_id,0,1,"牧师为%s栽下一簇真根，等待此株首次长出牧草。"%a.design.name,site)
	finish(p,"已为%s在（%.1f，%.1f）栽下活根，等待生长后复查原只是否自己吃到。"%[a.design.name,site.x,site.y])
