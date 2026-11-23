extends RefCounted

const Ground := preload("res://scripts/priest_ground.gd")
const Autonomy := preload("res://scripts/sandbox_autonomy.gd")
const Senses := preload("res://scripts/companion_senses.gd")
const NATIVE_PREFIX := "map:"
const SIGHT := 16.0

static func _route(world, foot:Vector2, x:float, id:String, label:String) -> Dictionary:
	if absf(x-foot.x)<2.0:return {}
	var row:=Ground.trace(world,foot,x)
	var stand:=Vector2(x,float(row.y)) if not row.is_empty() else Vector2(x,world.travel_height(x))
	if not stand.is_finite() or not world.paper_nav_route(foot,stand).get("ok",false):return {}
	for item in world.paper_surfaces(x,stand.y+.08,stand.y+1.25):
		if item.face=="ceiling":return {}
	var cell:Vector2i=world.paper_cell_at(stand)
	var place:String=world.paper_nav_label(id,stand) if world.has_method("paper_nav_label") else label
	return {"id":id,"name":label,"label":place,"at":Senses.pair(stand),"page":[cell.x,cell.y],"distance":snappedf(absf(x-foot.x),.1)}

static func routes(guard, at: Vector2) -> Array:
	var world=guard.world
	var foot:Vector2=guard.foot_position()
	var near:=Ground.nearby(world,at.x,foot.y,.65)
	if not near.is_empty(): foot.y=near.y
	var result:=[]
	# The body can still stand with its centre just beyond a ledge. Navigation
	# resolves the footprint and only returns sites reachable within patrol range.
	for site in world.paper_nav_sites(foot,8,48.0):
		if not Autonomy.pair(site.get("at")):continue
		var target:=Vector2(site.at[0],site.at[1])
		if target.distance_to(foot)<2.0 or target.distance_to(foot)>48.0:continue
		var name:=str(site.get("name","附近纸页"))
		result.append({"id":site.id,"name":name,"label":site.get("label",name),"at":site.at,"page":site.cell,"distance":snappedf(target.distance_to(foot),.1)})
	for index in world.SECTIONS.size():
		var region:Dictionary=world.SECTIONS[index]
		if absf(region.x-at.x)>44.0:continue
		var row:=_route(world,foot,region.x,"section-%d"%index,region.name)
		if not row.is_empty():result.append(row)
	var limits:Rect2=world.paper_motion_bounds()
	for direction in [-1.0,1.0]:
		for delta in [11.0,25.0]:
			var x:=clampf(at.x+direction*delta,limits.position.x+.65,limits.end.x-.65)
			if result.any(func(row):return absf(row.at[0]-x)<2.5):continue
			var label:="西向成形纸面" if direction<0 else "东向成形纸面"
			var cell:Vector2i=world.paper_cell_at(Vector2(x,foot.y))
			var row:=_route(world,foot,x,"road-%d-%.1f"%[cell.x,x],label)
			if not row.is_empty():result.append(row)
	for row in result:
		row.recent=guard.visits.any(func(old): return absf(old.x-row.at[0])<3.0 and absf(old.y-row.at[1])<1.5)
	return result

static func native_target(world, id: String) -> Dictionary:
	if not id.begins_with(NATIVE_PREFIX):return {}
	var body=world.entity_by_id(id.trim_prefix(NATIVE_PREFIX))
	# The existing guild explicitly records dragon defeats as monster bounties.
	if body==null or not body.alive or body.kind!="dragon":return {}
	var center:Vector2=body.position+Vector2(0, .4)
	return {"id":id,"name":"飞龙","at":Senses.pair(center),"health":body.health,"reason":"公会登记的现有讨伐目标","body":body}

static func threat(guard, id: String, sight:float) -> Dictionary:
	var at:Vector2=guard.actor.player.position
	if id.begins_with(NATIVE_PREFIX):
		var item:=native_target(guard.world,id)
		if not item.is_empty() and at.distance_to(Vector2(item.at[0],item.at[1]))<=sight:return item
		return {}
	var priest=guard.world.get_node_or_null("SandboxPriest")
	if priest==null or not priest.has_method("combat_targets"):return {}
	for row in priest.combat_targets(at,sight):
		if row.get("work_id")==id and row.get("hostile")==true and float(row.get("health",0))>0.0:
			return {"id":id,"name":row.get("name","敌对造物"),"at":[row.x,row.y+.23],"reason":row.get("reason","现场主动敌对"),"health":row.health}
	return {}

static func native_approach(guard, center:Vector2) -> Dictionary:
	var world=guard.world
	var feet:Vector2=guard.foot_position()
	var candidates:= []
	var nearest_gap:=INF
	if guard.actor.on_ground and absf(feet.x-center.x)<=1.35 and absf(feet.y+.29-center.y)<=1.05:
		return {"ok":true,"stand":Senses.pair(feet)}
	for offset in [0.0,-.55,.55,-1.05,1.05]:
		var x:=center.x+float(offset)
		for floor_row in world.paper_surfaces(x,center.y-12.0,center.y+.8):
			if floor_row.face!="floor":continue
			var stand:=Vector2(x,floor_row.y)
			var gap:=absf(center.y-(stand.y+.29))
			nearest_gap=minf(nearest_gap,gap)
			if gap<=1.05:
				candidates.append(stand)
	candidates.sort_custom(func(a,b):return feet.distance_squared_to(a)<feet.distance_squared_to(b))
	for stand in candidates:
		var path:Dictionary=world.paper_nav_route(feet,stand)
		if not path.get("ok",false):continue
		var goal:=Vector2(path.goal[0],path.goal[1])
		if absf(goal.x-center.x)>1.35 or absf(goal.y+.29-center.y)>1.05:continue
		return {"ok":true,"stand":Senses.pair(goal)}
	var result:={"ok":false,"reason":"实地上暂无能进入近战范围的可达脚点"}
	if is_finite(nearest_gap):
		result.vertical_gap=snappedf(nearest_gap,.01)
		if nearest_gap>1.05:result.reason="飞行目标与最近脚面身体高度仍差 %.2f 米，超过近战高差 1.05 米"%nearest_gap
	return result

static func view(guard, chat: Dictionary) -> Dictionary:
	var world=guard.world
	var at:Vector2=guard.actor.player.position
	var danger:=[]
	var seen_routes:=routes(guard,at)
	for entity in world.entities:
		if entity.kind!="dragon" or at.distance_to(entity.position)>SIGHT:continue
		var item:=threat(guard,NATIVE_PREFIX+entity.entity_id,SIGHT)
		if not item.is_empty():
			item.erase("body")
			var center:=Vector2(item.at[0],item.at[1])
			item.approach=native_approach(guard,center)
			if guard.intercept_on_hold(item.id) and item.approach.ok:
				item.approach={"ok":false,"reason":"上一次接近未进入近战范围，短时改为守望"}
			if not item.approach.ok and not seen_routes.is_empty():
				var alternatives:=seen_routes.duplicate()
				alternatives.sort_custom(func(a,b):
					if a.recent!=b.recent:return not a.recent
					return Vector2(a.at[0],a.at[1]).distance_squared_to(center)<Vector2(b.at[0],b.at[1]).distance_squared_to(center))
				item.observe_from=alternatives[0].id
			danger.append(item)
	var peaceful:=[]
	var priest=world.get_node_or_null("SandboxPriest")
	if priest!=null and priest.has_method("combat_targets"):
		for row in priest.combat_targets(at,SIGHT):
			if row.get("hostile")==true:
				var item:=threat(guard,row.work_id,SIGHT)
				if not item.is_empty():danger.append(item)
			else:peaceful.append({"id":row.work_id,"name":row.name,"at":[row.x,row.y]})
	var villagers:=[]
	if world.survival!=null:
		var facts:Dictionary=world.survival.decision_facts("war_god",at,13.0)
		villagers=facts.get("villagers",[])
	return {"role":"war_god","identity":"战神","scope":Autonomy.scope(guard.game),"at":Senses.pair(at),
		"health":guard.actor.combat.health,"routes":seen_routes,"threats":danger,"villagers":villagers,
		"peaceful_life":peaceful,"visits":guard.visits.duplicate(true),"recent":guard.memory.duplicate(true),
		"last_confirmed_player_hit":guard.last_player_hit.duplicate(true),"chat":chat}
