extends RefCounted
## Join the chronicle and bounded guild ledger by witnessed event ID. A paid
## contract contributes once, even when both logs retain its settlement.
const Contracts := preload("res://scripts/village_contracts.gd")
const STAGES := {
	"posted":"公会发单", "protected":"幸存者脱险", "accepted":"领单", "route_joined":"新路接通", "crossed":"踏过旧界",
	"delivered":"交付", "fed":"送食完成", "verified":"现场核实", "escorted":"护送到达", "settled":"柜台兑付"
}

static func _old_stage(e:Dictionary) -> String:
	if e.kind!="guild":return str(e.kind).trim_prefix("guild_")
	var text:=str(e.detail)
	if text.begins_with("已领取"):return "accepted"
	if text.contains("结算，金币 "):return "settled"
	if text.begins_with("接单人已从旧岸踏过"):return "crossed"
	if text.contains("米断路已由《"):return "route_joined"
	return ""

static func _coins(text:String) -> Array:
	var start:=text.rfind("金币 ")
	if start<0:return []
	var pair:=text.substr(start+"金币 ".length()).strip_edges().split("→")
	if pair.size()!=2 or not pair[0].is_valid_int() or not pair[1].is_valid_int():return []
	var before:=int(pair[0])
	var after:=int(pair[1])
	return [before,after] if after>=before else []

static func lookup(world,events:Array) -> Array:
	var rows:Dictionary={}
	for e:Dictionary in events:
		if e.kind!="guild" and not str(e.kind).begins_with("guild_"):continue
		if str(e.subject_id).is_empty():continue
		var stage:=_old_stage(e)
		if stage not in STAGES:continue
		var row:=e.duplicate(false)
		row.action=stage
		rows[e.id]=row
	if world.survival!=null:
		var raw:Array=world.survival.guild_events(0,Contracts.EVENT_CAP).events
		for fact:Dictionary in raw:
			if fact.action not in STAGES or str(fact.contract_id).is_empty():continue
			var key:="guild/%s/%d"%[fact.world_id,int(fact.seq)]
			var row:Dictionary=rows.get(key,{
				"id":key,"kind":"guild_"+str(fact.action),"role":fact.actor,"subject_id":fact.contract_id,
				"title":Contracts.NAMES.get(fact.kind,"公会委托"),"at":fact.at,"detail":fact.detail,"when_unix":0})
			row.action=fact.action
			row.contract_kind=fact.kind
			row.target_person=str(fact.target) if fact.kind in ["guard","supply","escort"] else ""
			row.road_id=fact.get("work_id","") if fact.kind=="survey" else ""
			row.old_seam=fact.target
			rows[key]=row
	var grouped:Dictionary={}
	for e:Dictionary in rows.values():
		var id:=str(e.subject_id)
		if not grouped.has(id):grouped[id]={"id":id,"stages":{},"title":e.title,"coins":[],"road_id":"","road":"","author":"","seam":""}
		var entry:Dictionary=grouped[id]
		var stage:=str(e.action)
		var old:Dictionary=entry.stages.get(stage,{})
		if not old.is_empty() and int(old.id.get_slice("/",2))>int(e.id.get_slice("/",2)):continue
		entry.stages[stage]=e
		if not str(e.get("road_id","")).is_empty():entry.road_id=e.road_id
		if str(e.get("old_seam","")).begins_with("east@"):
			entry.seam=str(e.old_seam).trim_prefix("east@").get_slice(",",0)
		if stage=="route_joined":
			var detail:=str(e.detail)
			if detail.contains("《") and detail.contains("》"):entry.road=detail.get_slice("《",1).get_slice("》",0)
			if entry.seam.is_empty() and e.at.size()==2:entry.seam="%.1f"%float(e.at[0])
		if stage=="settled":
			entry.coins=_coins(e.detail)
			entry.payee=e.role
			entry.sequence=int(str(e.id).get_slice("/",2))
	var paid:Array=grouped.values().filter(func(c):return c.stages.has("settled"))
	paid.sort_custom(func(a,b):return a.sequence<b.sequence)
	if paid.is_empty():return paid
	var sheets:Dictionary={}
	for sheet:Dictionary in world.east_segments_snapshot():
		if sheet.has("work_id"):sheets[sheet.work_id]=sheet
	# The guild records where the resident became safe. The war god records where
	# the fight ended. Those locations may be on different parts of the road.
	var defeats := {}
	for event: Dictionary in events:
		if event.kind=="threat_defeated" and event.role=="war_god" and not event.subject_id.is_empty():
			defeats[event.subject_id]=event
	for entry:Dictionary in paid:
		var settled: Dictionary = entry.stages.settled
		var card: Dictionary = world.survival.contracts.card(entry.id) if world.survival!=null else {}
		entry.contract_kind=card.get("kind",settled.get("contract_kind",""))
		entry.resident=str(card.get("target",settled.get("target_person",""))) if entry.contract_kind in ["supply","guard","escort"] else ""
		# The survey reader already opens directly on the four points of a walk.
		if entry.contract_kind not in ["supply","guard","escort"]:
			entry.stages.erase("posted")
		if entry.contract_kind=="guard" and entry.stages.has("protected") and defeats.has(card.get("source","")):
			entry.defeat=defeats[card.source].duplicate(false)
		var sheet:Dictionary=sheets.get(entry.road_id,{})
		if not sheet.is_empty():
			entry.road=sheet.name
			entry.author=sheet.get("author_id","")
	return paid


## A threat may be stopped before an adventurer accepts the follow-up.
## The guild's own sequence preserves either order across a cold resume.
static func in_recorded_order(receipt:Dictionary) -> Array:
	var ordered:Array=receipt.stages.values()
	ordered.sort_custom(func(a,b):
		return int(str(a.id).get_slice("/",2))<int(str(b.id).get_slice("/",2)))
	return ordered

static func resident_name(id:String) -> String:
	if id.begins_with("villager-") and id.trim_prefix("villager-").is_valid_int():
		return "村民"+id.trim_prefix("villager-")
	return id
