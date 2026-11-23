extends RefCounted
## Team-local journal for multi-turn commissions. Geometry and trades stay with their owners.

const TYPES := ["landscape","water","vegetation","building","verify"]
const ChannelPlan := preload("res://scripts/painter_channel_plan.gd")
const WaterBody := preload("res://scripts/painter_scene_water_body.gd")
const MAX_ATTEMPTS := 3
var entries: Array[Dictionary] = []
var history: Array[Dictionary] = []
var active_id := ""

func active() -> Dictionary:
	for entry in entries:
		if entry.project_id==active_id:return entry
	return {}

func add(args: Dictionary, brief: String, scope: Dictionary, site: Dictionary) -> Dictionary:
	var phases = args.get("phases")
	if not phases is Array or phases.size()<2 or phases.size()>6:
		return {}
	var ordered := []
	for phase in phases:
		if not phase is Dictionary or phase.get("kind") not in TYPES or not phase.get("aim") is String or phase.aim.strip_edges().is_empty():
			return {}
		var step:Dictionary={"kind":phase.kind,"aim":phase.aim.strip_edges().left(100)}
		if phase.get("form") in ["tree","small_detail","distant","scenery"] or (phase.get("form")=="foundation" and phase.kind=="landscape"):
			step.form=phase.form
		ordered.append(step)
	if ordered.back().kind!="verify" or not args.get("title") is String:return {}
	var sequence:Array=[]
	for step in ordered:
		if not sequence.is_empty() and _same_tree_crown(sequence.back(),step):
			sequence.back().aim=(str(sequence.back().aim)+"；"+str(step.aim)).left(100)
		else:sequence.append(step)
	ordered=sequence
	var previous:=active()
	if not previous.is_empty() and previous.stage=="working":previous.stage="paused"
	for index in range(entries.size()-1,-1,-1):
		if entries[index].stage=="complete":
			history.append(entries.pop_at(index))
	active_id="scene-"+Crypto.new().generate_random_bytes(12).hex_encode()
	var entry:Dictionary={"project_id":active_id,"scope":scope.duplicate(true),"brief":brief.left(600),"title":args.title.left(48),
		"stage":"working","phases":ordered,"cursor":0,"attempts":0,"site":site.duplicate(true),"surveyed":false,
		"outcomes":[],"work_ids":[],"plan_ids":[],"trade":args.get("trade")==true,"trade_targets":[],
		"subject":str(args.get("subject","")).left(100),"boat":args.get("boat")==true,"water_access":args.get("water_access")==true,"reworks":0,"moves":0,
		"origin":str(args.get("origin","player"))}
	if args.get("composition") is Dictionary:entry.composition=args.composition.duplicate(true)
	if args.get("water_body") is Dictionary and WaterBody.valid(args.water_body):entry.water_body=args.water_body.duplicate(true)
	entries.append(entry)
	return entry

static func _same_tree_crown(tree:Dictionary, next:Dictionary) -> bool:
	if tree.kind!="vegetation" or tree.get("form")!="tree" or next.kind!="vegetation":return false
	var aim:String=next.aim
	var is_crown:bool=["柳冠","树冠","冠团","冠叶"].any(func(word):return aim.contains(word))
	return is_crown and not ["另一","另外","新增","草","苔","花丛","灌木","一株"].any(func(word):return aim.contains(word))

func step() -> Dictionary:
	var entry:=active()
	if entry.is_empty() or int(entry.cursor)>=entry.phases.size():return {}
	return entry.phases[int(entry.cursor)]

func revise(remaining:Variant, clarification:String) -> bool:
	var entry:=active()
	if entry.is_empty() or not entry.stage in ["working","paused"] or not remaining is Array or remaining.is_empty():
		return false
	if int(entry.cursor)+remaining.size()>8:return false
	var steps:=[]
	for phase in remaining:
		if not phase is Dictionary or not phase.get("kind") in TYPES or not phase.get("aim") is String or phase.aim.strip_edges().is_empty():
			return false
		var step:Dictionary={"kind":phase.kind,"aim":phase.aim.left(100)}
		if phase.get("form") in ["tree","small_detail","distant","scenery"] or (phase.get("form")=="foundation" and phase.kind=="landscape"):
			step.form=phase.form
		steps.append(step)
	if steps.back().kind!="verify":return false
	if entry.get("trade",false) and entry.get("trade_targets",[]).is_empty() and not steps.any(func(s):return s.kind=="building"):return false
	entry.phases=entry.phases.slice(0,int(entry.cursor))+steps
	entry.clarification=clarification
	entry.stage="working"
	entry.attempts=0
	entry.moves=0
	entry.distant_from=entry.outcomes.size()
	for field in ["plant","detail_study","return_to","pending_build","shore_build","foundation_site"]:entry.erase(field)
	return true

func distant_ids() -> Array:
	var entry:=active()
	if entry.is_empty() or step().get("form")!="distant":return []
	var ids:=[]
	for row in entry.outcomes.slice(int(entry.get("distant_from",0))):
		if row.get("tool")=="paint_distant_sheet" and row.get("ok",false):
			ids.append_array(row.get("work_ids",[]))
	return ids

func observe() -> Dictionary:
	var entry:=active()
	if entry.is_empty():return {}
	return {"project_id":entry.project_id,"title":entry.title,"brief":entry.brief,"stage":entry.stage,"current":step(),
		"phases":entry.phases,"composition":entry.get("composition",{}),"cursor":entry.cursor,
		"water_body":entry.get("water_body",{}),"distant_ids":distant_ids(),"site":entry.site,"attempts":entry.attempts,"channel_plan":entry.get("channel_plan",{}),
		"outcomes":entry.outcomes.slice(-5),"work_ids":entry.work_ids,"plan_ids":entry.plan_ids,"trade":entry.trade,
		"subject":entry.get("subject",""),"boat":entry.get("boat",false),"water_access":entry.get("water_access",false),
		"clarification":entry.get("clarification",""),"reworks":entry.get("reworks",0),
		"moves":entry.get("moves",0),"origin":entry.get("origin","player")}

func outcome(result:Dictionary, completed:bool) -> void:
	var entry:=active()
	if entry.is_empty() or entry.stage!="working":return
	var row:Dictionary={"phase":step().get("kind",""),"tool":str(result.get("tool","")),"ok":result.get("ok")==true,
		"detail":str(result.get("detail","")).left(240),"call_id":str(result.get("call_id","")).left(100)}
	for field in ["end","work_id","plan_id","id","plant_review","water_foot","support_work_id","visited_doors","channel_section"]:
		if result.has(field):row[field]=result[field]
	var ids:Array=result.get("work_ids",[])
	if result.get("work_id") is String and not result.work_id.is_empty():ids=ids+[result.work_id]
	if not ids.is_empty():row.work_ids=ids
	entry.outcomes.append(row)
	for id in ids:
		if id is String and not id in entry.work_ids:entry.work_ids.append(id)
	if result.has("plan_id") and not result.plan_id in entry.plan_ids:entry.plan_ids.append(result.plan_id)
	if result.get("service_work")==true and result.has("id") and not result.id in entry.trade_targets:
		entry.trade_targets.append(result.id)
	if completed:
		entry.distant_from=entry.outcomes.size()
		var verified_tree:bool=step().kind=="vegetation" and result.get("plant_review",{}).get("kind")=="tree"
		entry.cursor+=1
		var return_to:int=int(entry.get("return_to",-1))
		if return_to>=entry.cursor and return_to<entry.phases.size():
			entry.cursor=return_to
			entry.erase("return_to")
		if verified_tree and entry.cursor<entry.phases.size() and _same_tree_crown({"kind":"vegetation","form":"tree"},step()):
			row.covers_crown_stage=step().aim
			entry.cursor+=1
		entry.attempts=0
		entry.moves=0
		entry.erase("plant")
		entry.erase("detail_study")
		if entry.cursor>=entry.phases.size():entry.stage="awaiting_trade" if entry.get("trade",false) else "complete"
	elif result.get("partial",false):
		entry.attempts=0
	elif result.get("tool")=="scene_reposition" and result.get("ok",false):
		entry.moves=int(entry.get("moves",0))+1
	else:
		entry.attempts+=1
		if entry.attempts>=MAX_ATTEMPTS:entry.stage="paused"

## Give the painter its own studio history separately from the public events
## it may have read about. A title or a planned phase is never a finished work.
func studio_memory(chronicle) -> Dictionary:
	var samples: Array = []
	var counts := {}
	var seen := {}
	# The two ledgers have separate insertion order. Include both finished
	# places and unfinished plans even after a very long night.
	for group in [entries,history]:
		for project in group.slice(-6):
			var finished: Array = []
			for result in project.get("outcomes",[]):
				if not result.get("ok",false):
					continue
				var ids: Array = result.get("work_ids",[])
				if ids.is_empty() and result.has("work_id"):
					ids = [result.work_id]
				for work_id in ids:
					if str(work_id).is_empty():
						continue
					var phase: String = str(result.get("phase",""))
					if phase not in finished: finished.append(phase)
					if not seen.has(work_id):
						seen[work_id] = true
						counts[phase] = int(counts.get(phase,0))+1
			var sample := {"title":project.title,"state":project.stage,"actual_work_types":finished,
				"at":project.site.get("stand",[])}
			var cursor := int(project.get("cursor",0))
			if project.stage=="paused" and cursor>=0 and cursor<project.phases.size():
				sample.unfinished = project.phases[cursor].get("aim","")
				for i in range(project.outcomes.size()-1,-1,-1):
					if not project.outcomes[i].get("ok",false):
						sample.last_obstacle = str(project.outcomes[i].get("detail","")).left(120)
						break
			samples.append(sample)
	var public_events: Array = []
	for event in chronicle.highlights(10):
		if event.role!="companion" and public_events.size()<4:
			public_events.append({"role":event.role,"event":event.title,"detail":event.detail,"at":event.at})
	return {"recent_projects":samples,"sample_work_counts_by_phase":counts,"world_news":public_events}

func list() -> Array:
	return (history+entries).duplicate(true)

func snapshot() -> Dictionary:
	return {"v":2,"active_id":active_id,"entries":entries.duplicate(true),"history":history.duplicate(true)}

func restore(data: Variant, scope: Dictionary) -> void:
	if not data is Dictionary or (data.get("v")!=1 and data.get("v")!=2) or not data.get("entries") is Array:return
	entries.clear()
	history.clear()
	active_id=str(data.get("active_id",""))
	var archived:Variant=data.get("history",[]) if data.get("v")==2 else []
	if not archived is Array:archived=[]
	for entry in archived+data.entries:
		if not entry is Dictionary or not entry.get("project_id") is String or not entry.get("phases") is Array or entry.phases.is_empty():continue
		if not entry.phases.all(func(p):return p is Dictionary and p.get("kind") in TYPES and p.get("aim") is String):continue
		if entry.get("stage") not in ["working","paused","awaiting_trade","complete"]:continue
		if not entry.get("site") is Dictionary or not entry.get("scope") is Dictionary:continue
		var copy:Dictionary=entry.duplicate(true)
		if copy.has("channel_plan"):
			copy.channel_plan=ChannelPlan.restore_plan(copy.channel_plan)
		if copy.scope.get("team_id")!=scope.get("team_id") and copy.stage=="working":copy.stage="paused"
		var origins=copy.get("trade_origin_scopes",[])
		if origins is Array:
			copy.trade_origin_scopes=origins.filter(func(row):
				return row is Dictionary and row.get("world_id") is String and row.get("team_id") is String)
		else:copy.erase("trade_origin_scopes")
		if not copy.get("trade_receipt",{}) is Dictionary:copy.erase("trade_receipt")
		if not copy.get("trade_receipts",{}) is Dictionary:copy.erase("trade_receipts")
		if copy.scope.get("world_id")!=scope.get("world_id") or copy.scope.get("team_id")!=scope.get("team_id"):
			var old_scope:={"world_id":copy.scope.get("world_id",""),"team_id":copy.scope.get("team_id","")}
			var trade_scopes:Array=copy.get("trade_origin_scopes",[])
			if not old_scope in trade_scopes:trade_scopes.append(old_scope)
			copy.trade_origin_scopes=trade_scopes
			if copy.get("trade_receipt",{}).is_empty():copy.trade_sequence=0
		copy.scope=scope.duplicate(true)
		copy.cursor=clampi(int(copy.get("cursor",0)),0,copy.phases.size())
		copy.attempts=clampi(int(copy.get("attempts",0)),0,MAX_ATTEMPTS)
		for field in ["outcomes","work_ids","plan_ids","trade_targets"]:
			if not copy.get(field) is Array:copy[field]=[]
		if copy.stage=="complete" and copy.project_id!=active_id:history.append(copy)
		else:entries.append(copy)
