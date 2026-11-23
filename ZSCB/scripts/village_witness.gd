extends RefCounted
## What a nearby resident can say about witnessed events in this one save.
const Senses := preload("res://scripts/companion_senses.gd")
const Accounts := preload("res://scripts/role_guild_receipts.gd")
const Contracts := preload("res://scripts/village_contracts.gd")
const REACH := 2.6

static func receipt(answer:Dictionary) -> Dictionary:
	var result:={"npc_id":answer.npc_id,"reply":answer.message,"witness":answer.witness}
	for key in ["event_id","subject_id","resident_id"]:
		if answer.has(key):result[key]=answer[key]
	return result

static func asks_news(question:String) -> bool:
	for route in ["怎么走","如何走","在哪个方向","怎么去","通向哪里"]:
		if question.contains(route):return false
	for word in ["近况","发生","出什么事","出了什么事","遇到","遇上","听闻","听说","怎么了","有什么事","出了事","村里怎样","村里的消息","村里的事","谁有事","什么消息","这几天","最近怎么样","可还好","还好吗","受伤","受袭","救过","得救","获救","谁救","救了你","吃过果","谁递","谁送","吃饱","缺粮","缺食","挨饿","送果","送来","饱食","受了伤","方才","刚才","刚刚"]:
		if question.contains(word):return true
	return false

static func _foot_surface(world,at:Vector2) -> Dictionary:
	var floor:Dictionary={}
	for surface in world.paper_surfaces(at.x,at.y-.52,at.y+.05):
		if surface.face=="floor" and (floor.is_empty() or surface.y>floor.y):floor=surface
	return floor

static func _floor_at_middle(floors:Array, support:Dictionary) -> float:
	var best:=INF
	for surface in floors:
		if surface.face=="floor" and surface.work_id==support.work_id and absf(surface.y-support.y)<absf(best-support.y):
			best=surface.y
	return best

static func _within(world, at:Vector2, person) -> bool:
	if person==null or not person.alive or not person.is_person():return false
	var there:Vector2=person.position
	if not at.is_finite() or at.distance_to(there)>REACH:return false
	if at.distance_squared_to(there)<0.0025:return true
	var a:=_foot_surface(world,at)
	var b:=_foot_surface(world,there)
	if not a.is_empty() and not b.is_empty() and (a.work_id!=b.work_id or absf(a.y-b.y)>.5):
		# The world can have two walkable surfaces at one x even when the
		# physics server has not streamed the distant collision bodies.
		var floors:Array=world.paper_surfaces((at.x+there.x)*.5,minf(a.y,b.y)-REACH,maxf(a.y,b.y)+REACH)
		var left:=_floor_at_middle(floors,a)
		var right:=_floor_at_middle(floors,b)
		if is_finite(left) and is_finite(right) and absf(left-right)>.45:return false
	# A resting villager can store its ground point; cast above both feet.
	# A floor or ceiling separating two
	# close bodies counts from either side, including a one-way paper floor.
	var space:PhysicsDirectSpaceState2D=world.get_world_2d().direct_space_state
	for ends in [[at,there],[there,at]]:
		var ray:=PhysicsRayQueryParameters2D.create(ends[0]+Vector2(0,.32),ends[1]+Vector2(0,.32),1)
		var hit:=space.intersect_ray(ray)
		if hit.is_empty():continue
		if not hit.collider.get_meta("map_drop_allowed",false):return false
		# A low overhang can cross a line between the characters' shoulders
		# although both really stand on the same lower floor.
		if a.is_empty() or b.is_empty() or a.work_id!=b.work_id:return false
		if absf(a.y-b.y)>.25+1.1*absf(at.x-there.x):return false
	return true

static func label(person) -> String:
	if person.kind=="villager":return Accounts.resident_name(person.entity_id)
	return Senses.ROLE_NAMES.get(person.kind,"居民")

static func nearby(world,at:Vector2) -> Array:
	var people:Array=[]
	for person in world.entities:
		if _within(world,at,person):
			people.append({"id":person.entity_id,"label":label(person),"at":person.position})
	people.sort_custom(func(a,b):
		var da:=at.distance_squared_to(a.at)
		var db:=at.distance_squared_to(b.at)
		return a.id<b.id if da==db else da<db)
	return people

static func _name(who:String) -> String:
	return {"adventurer-lizhou":"砾舟","player":"玩家","war_god":"战神","priest":"牧师","companion":"阿靛"}.get(who,"有人")

static func _place(world,event:Dictionary) -> String:
	if event.get("at",[]).size()!=2:return "村里"
	var point:=Vector2(event.at[0],event.at[1])
	var place:=str(world.paper_nav_label("",point)).get_slice("（",0).strip_edges().trim_suffix(" · 地表")
	if place.begins_with("纸上落脚点"):
		if point.x < -5.0:return "村西%.0f米处"%absf(point.x)
		return str(world.paper_nav_label("road",point)).get_slice(" · ",0)
	return place.replace(" · ","的")

static func _accounts(world) -> Array:
	var by_id:Dictionary={}
	for fact:Dictionary in world.survival.guild_events(0,Contracts.EVENT_CAP).events:
		if str(fact.get("target","")).is_empty():continue
		var id:="guild/%s/%d"%[fact.world_id,int(fact.seq)]
		by_id[id]={"id":id,"action":fact.action,"contract":fact.contract_id,"kind":fact.kind,"person":fact.target,"actor":fact.actor,"at":fact.at,"detail":fact.detail}
	var ordered:Array=[]
	for event:Dictionary in world.chronicle.recent(world.chronicle.CAPACITY):
		if by_id.has(event.id):
			ordered.append(by_id[event.id])
			by_id.erase(event.id)
		elif event.kind=="injury":
			# The priest's public wound receipt starts with the exact victim ID.
			var victim:=str(event.detail).get_slice(" 生命 ",0)
			if victim==event.detail or victim.is_empty():continue
			ordered.append({"id":event.id,"action":"injury","contract":"","kind":"injury","person":victim,"actor":str(event.title).trim_suffix(" · 居民受伤"),"at":event.at,"detail":event.detail})
		elif str(event.kind).begins_with("guild_"):
			var c:Dictionary=world.survival.contracts.card(event.subject_id)
			if c.get("kind") not in ["supply","guard","escort"]:continue
			ordered.append({"id":event.id,"action":str(event.kind).trim_prefix("guild_"),"contract":event.subject_id,"kind":c.kind,"person":c.target,"actor":event.role,"at":event.at,"detail":event.detail})
	# Older saves can keep a guild receipt after the public chronicle rolled off.
	var ledger_only:=by_id.values()
	ledger_only.reverse()
	ordered.append_array(ledger_only)
	return ordered

static func _words(world, e:Dictionary, own:bool) -> String:
	var who:="我" if own else Accounts.resident_name(e.person)
	var where:=_place(world,e)
	var giver:=_name(e.actor)
	match e.action:
		"fed":return "%s在%s吃到了%s送来的朱果。"%[who,where,giver]
		"delivered":return "%s在%s把一枚朱果递给了%s。"%[giver,where,who]
		"protected":
			var creature:=str(e.detail).get_slice(" 已被",0)
			if creature==e.detail or creature.is_empty():creature="那头野兽"
			if e.actor=="war_god":return "%s在%s躲过一劫。战神击退了%s。"%[who,where,creature]
			return "%s在%s脱了险。"%[who,where]
		"injury":return "%s在%s被%s伤过。"%[who,where,e.actor]
		"verified":
			if e.kind=="guard":return "%s来%s看过%s，确认%s已经平安了。"%[giver,where,who,who]
		"escorted":return "%s陪%s到了%s。"%[giver,who,where]
		"posted":
			var c:Dictionary=world.survival.contracts.card(e.contract)
			if c.get("status") not in ["open","active"]:return ""
			if e.kind=="supply" and c.get("stage")!="delivered":return "公会在%s替%s挂了张求朱果的单子，还等人送来。"%[where,who]
			if e.kind=="guard" and not c.get("protected",false):return "公会在%s替%s发过求援，还没收到脱险的回音。"%[where,who]
	return ""

static func ask(world,at:Vector2,npc_id:String,question:String="问近况") -> Dictionary:
	var person=world.entity_by_id(npc_id)
	if not _within(world,at,person):
		return {"ok":false,"npc_id":npc_id,"message":"已经隔得太远或隔了一层地面，走到这人身边再问。"}
	var response:={"ok":true,"npc_id":npc_id,"label":label(person),"witness":"unknown","message":"我这儿没遇上能讲准的事。"}
	if world.survival==null or world.chronicle==null:return response
	var rows:=_accounts(world)
	var latest_visit:Dictionary={}
	var heard:=question.contains("村里谁") or question.contains("村里有谁") or question.contains("听说") or question.contains("听闻")
	for own in [true,false]:
		if not own and not heard:break
		for e:Dictionary in rows:
			if (e.person==npc_id)!=own:continue
			if e.action=="verified" and e.kind=="guard" and own and latest_visit.is_empty():
				latest_visit=e
			if e.action not in ["fed","delivered","protected","injury","escorted","posted"]:continue
			if not own and e.kind not in ["guard","supply","escort"]:continue
			var words:=_words(world,e,own)
			if words.is_empty():continue
			response.merge({"message":words if own else "我听公会说，"+words.trim_prefix("公会"),"witness":"self" if own else "heard","event_id":e.id,"subject_id":e.contract if e.contract!="" else e.person,"resident_id":e.person},true)
			return response
		if own and not latest_visit.is_empty():
			response.merge({"message":_words(world,latest_visit,true),"witness":"self","event_id":latest_visit.id,"subject_id":latest_visit.contract,"resident_id":npc_id},true)
			return response
	return response
