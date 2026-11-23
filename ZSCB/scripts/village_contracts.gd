extends RefCounted
## The guild keeps one board per live world. Only witnessed actions change a contract.
const Survey := preload("res://scripts/village_survey.gd")
const Ground := preload("res://scripts/priest_ground.gd")
const NAMES := {"supply":"饥民补给","escort":"牧场护送","survey":"纸边探路","guard":"村庄守护"}
const REWARDS := {"supply":4,"escort":6,"survey":5,"guard":8}
const CAP := 32
const EVENT_CAP := 96
const TERMINAL := ["paid","closed"]
const ACTORS := ["player","adventurer-lizhou"]
var world
var state := initial()
var s:
	get: return world.survival

func _init(owner_world) -> void:
	world=owner_world

static func initial() -> Dictionary:
	return {"v":1,"time":0.0,"next_poll":0.0,"serial":0,"seq":0,"cards":[],"events":[],"surveyed":""}

static func _number(n:Variant, high:float) -> bool:
	return (n is float or n is int) and is_finite(n) and n>=0 and n<=high

static func _whole(n:Variant,high:float) -> bool:
	return _number(n,high) and n==floorf(n)

static func _text(v:Variant,limit:int) -> bool:
	return v is String and v.length()<=limit

static func _point(p:Variant) -> bool:
	return p is Array and p.size()==2 and (p[0] is int or p[0] is float) and (p[1] is int or p[1] is float) and is_finite(p[0]) and is_finite(p[1]) and absf(p[0])<=1e7 and absf(p[1])<=1e7

static func valid(book:Variant) -> bool:
	if not book is Dictionary or book.get("v")!=1 or not _number(book.get("time"),1e12) or not _number(book.get("next_poll"),1e12):return false
	if not _whole(book.get("serial"),1e12) or not _whole(book.get("seq"),1e12) or not _text(book.get("surveyed"),160):return false
	if not book.get("cards") is Array or book.cards.size()>CAP or not book.get("events") is Array or book.events.size()>EVENT_CAP:return false
	var visited=book.get("verified_seams",{})
	if not visited is Dictionary or visited.size()>book.serial:return false
	for seam in visited:
		if not _text(seam,160) or visited[seam]!=true:return false
	var ids:={}
	for c in book.cards:
		if not c is Dictionary or not _whole(c.get("n"),book.serial) or c.n<1 or c.get("id")!="guild-%d"%int(c.n) or ids.has(c.id):return false
		ids[c.id]=true
		if not NAMES.has(c.get("kind")) or c.get("status") not in ["open","active","ready","closed","paid"]:return false
		if c.get("owner") not in ["","player","adventurer-lizhou"] or (c.status in ["active","ready","paid"] and c.owner=="") or (c.status=="open" and c.owner!=""):return false
		for key in ["target","source","stage","detail","prey"]:
			if not _text(c.get(key),220):return false
		if not _point(c.get("at")) or not _point(c.get("safe")) or not _number(c.get("posted"),book.time):return false
		if not c.get("protected") is bool:return false
		if c.has("fruit_ahead") and (c.kind!="supply" or c.status!="active" or c.stage!="delivered" or not _whole(c.fruit_ahead,998)):return false
		if c.has("basis") and not _text(c.basis,160):return false
		if c.has("previous") and (c.kind!="survey" or not _text(c.previous,32) or not c.previous.begins_with("guild-") or c.previous==c.id):return false
		if c.has("trail") and (c.kind!="survey" or c.stage!="crossing" or not _point(c.trail)):return false
	var prior:int=int(book.seq)-book.events.size()
	for e in book.events:
		prior+=1
		if not e is Dictionary or not _whole(e.get("seq"),book.seq) or e.seq!=prior or not _number(e.get("time"),book.time) or not _point(e.get("at")):return false
		for key in ["basis","work_id"]:
			if e.has(key) and not _text(e[key],160):return false
		if e.has("goods"):
			var sale=e.goods
			if not sale is Dictionary or not preload("res://scripts/architecture/stall_goods.gd").valid(sale.get("offer")) or not _whole(sale.get("slot"),23):return false
			for key in ["cash","bag","stock","till"]:
				if not sale.get(key) is Array or sale[key].size()!=2:return false
				for n in sale[key]:
					if not _whole(n,9999):return false
		if e.has("changes"):
			if not e.changes is Dictionary or e.changes.size()!=4:return false
			for key in ["coins_before","coins_after","fruit_before","fruit_after"]:
				if not _whole(e.changes.get(key),9999):return false
		for key in ["kind","action","actor","contract_id","target","detail","world_id","team_id"]:
			if not _text(e.get(key),300):return false
	return true

func _pair(p:Vector2) -> Array:
	return [snappedf(p.x,.001),snappedf(p.y,.001)]

func _at(p:Array) -> Vector2:
	return Vector2(p[0],p[1])

func _slot() -> Dictionary:
	return world.game.team_slot if world.game!=null and "team_slot" in world.game else {}

func events(after:int=0,limit:int=20) -> Dictionary:
	var rows:=[]
	for e in state.events:
		if e.seq>after and rows.size()<clampi(limit,0,EVENT_CAP):rows.append(e.duplicate(true))
	return {"world_id":_slot().get("world_id","medieval-v1"),"seq":state.seq,"first_seq":state.seq-state.events.size()+1,"events":rows}

func _emit(c:Dictionary,action:String,actor:String,detail:String,at:Vector2,changes:Dictionary={}) -> void:
	state.seq+=1
	var slot:=_slot()
	var e:={"seq":state.seq,"time":state.time,"contract_id":c.get("id",""),"kind":c.kind,
		"action":action,"actor":actor,"target":c.target,"detail":detail.left(280),"at":_pair(at),
		"world_id":slot.get("world_id","medieval-v1"),"team_id":slot.get("team_id","legacy")}
	if c.kind=="survey":
		e.basis=c.get("basis","")
		e.work_id=c.get("source","")
		if c.has("previous"):e.previous=c.previous
	if not changes.is_empty():e.changes=changes.duplicate(true)
	if c.has("goods"):e.goods=c.goods.duplicate(true)
	state.events.append(e)
	if state.events.size()>EVENT_CAP:state.events.pop_front()
	if "chronicle" in world and world.chronicle!=null:
		world.chronicle.record("guild/%s/%d"%[e.world_id,int(e.seq)],"guild_"+action,actor,str(c.get("title",NAMES.get(c.kind,"摊位成交"))),e.detail,at,c.get("id",c.target))

func market_title(station:String) -> String:
	if station=="market-2":return "河岸第三摊"
	if world.paper_space!=null and world.paper_space.entries.has(station):
		var rec:Dictionary=world.paper_space.entries[station].record
		return str(rec.get("name",rec.get("label","果摊"))).left(80)
	for obj in world.game.objects:
		if obj.get("structure_id")==station:
			var meta:Dictionary=obj.get("built_plan",{})
			var title:String=str(obj.get("name",""))
			if not meta.is_empty():
				var plans:=preload("res://scripts/architecture/building_plans.gd")
				var original:Dictionary=plans._source(world.game,meta.owner,int(meta.id))
				title=str(original.get("name",title))
			return title.left(80) if not title.is_empty() else "果摊"
	return "果摊"

func market_trade(id:String,station:String,at:Vector2,coins:int,fruit:int,title:String) -> void:
	var changes:={"coins_before":coins-s.FRUIT_PRICE,"coins_after":coins,"fruit_before":fruit+1,"fruit_after":fruit}
	_emit({"kind":"market","target":station,"title":title+" · 成交"},"stall_trade",id,"%s · 交朱果一枚，金币 %d→%d"%[title,changes.coins_before,coins],at,changes)

func goods_trade(id:String,station:String,at:Vector2,detail:String,offer:Dictionary,slot:int,cash:Array,bag:Array,stock:Array,till:Array) -> void:
	var audit:={"offer":offer.duplicate(true),"slot":slot,"cash":cash,"bag":bag,"stock":stock,"till":till}
	_emit({"kind":"market","target":station,"title":market_title(station)+" · 成交","goods":audit},"stall_trade",id,detail,at)

func card(key:String) -> Dictionary:
	for c in state.cards:
		if c.id==key:return c
	return {}

func _pending(kind:String,target:String="") -> bool:
	for c in state.cards:
		if c.kind==kind and c.status not in TERMINAL and (target=="" or c.target==target):return true
	return false

func _post(kind:String,target:String,where:Vector2,why:String,source:String="",prey:String="",previous:String="") -> Dictionary:
	if not where.is_finite() or _pending(kind,target):return {}
	if state.cards.size()>=CAP:
		var i:int=state.cards.find_custom(func(c):return c.status in TERMINAL and c.id!=previous)
		if i<0:return {}
		state.cards.remove_at(i)
	state.serial+=1
	var c:={"id":"guild-%d"%int(state.serial),"n":state.serial,"kind":kind,"status":"open","owner":"","target":target,
		"source":source,"prey":prey,"posted":state.time,"at":_pair(where),"safe":_pair(where),"stage":"","protected":false,"detail":why}
	if kind=="survey":
		c.basis=Survey.basis(world,where)
		if previous!="":
			c.previous=previous
			c.stage="crossing"
	state.cards.append(c)
	_emit(c,"posted","guild",why+" · 报酬 %d 金"%REWARDS[kind],where)
	return c

func _person(c:Dictionary):
	var p=s.people.get(c.target)
	return p if is_instance_valid(p) and p.alive and p.kind=="villager" else null

func _counter() -> Vector2:
	return Vector2(s.Guild.COUNTER_X,world.travel_height(s.Guild.COUNTER_X)+.4)

func location(c:Dictionary) -> Vector2:
	if c.status=="ready":return _counter()
	if c.stage=="escort":return _at(c.safe)
	if c.stage=="crossing":return Survey.stand(world,c)
	var p=_person(c)
	return p.position+Vector2(0,.45) if p!=null else _at(c.at)

func _transition(c:Dictionary,status:String,action:String,why:String,at:Vector2) -> void:
	c.status=status
	if status!="active":c.erase("fruit_ahead")
	_emit(c,action,c.owner if c.owner!="" else "guild",why,at)

func _survey_gap() -> void:
	if _pending("survey") or world.paper_space==null:return
	var paper:Dictionary=world.observe_east_edge()
	if paper.get("busy",false) or not _point(paper.get("edge")):return
	var edge:=_at(paper.edge)
	if not Ground.nearby(world,edge.x+1.8,edge.y,1.3).is_empty():return
	var seam:="east@%.2f,%.2f"%[edge.x,edge.y]
	if not _verified(seam):_post("survey",seam,edge,"东侧 %.1f 米纸边外 1.8 米未见相连落脚面，请到边前查路"%edge.x)

func _verified(seam:String) -> bool:
	return state.surveyed==seam or state.get("verified_seams",{}).has(seam)

func _mark_verified(c:Dictionary) -> void:
	if not state.has("verified_seams"):state.verified_seams={}
	state.verified_seams[c.target]=true
	state.surveyed=c.target

func restore(book:Dictionary) -> void:
	state=book.duplicate(true) if not book.is_empty() else initial()
	if not state.has("verified_seams"):state.verified_seams={}
	if state.surveyed!="":state.verified_seams[state.surveyed]=true
	for c in state.cards:
		if c.kind=="survey" and c.status in ["ready","paid"]:state.verified_seams[c.target]=true

func _refresh_survey(c:Dictionary) -> void:
	var edge:=_at(c.at)
	if not c.has("basis"):c.basis=Survey.basis(world,edge)
	if c.status=="closed" and (c.owner=="" or _verified(c.target)):return
	if c.stage=="crossing" and c.status in ["open","active"]:return
	if Ground.nearby(world,edge.x+1.8,edge.y,1.3).is_empty():return
	var link:=Survey.adjoining(world,edge)
	if link.is_empty() or c.basis=="" or Survey.basis(world,edge)!=c.basis:return
	if _verified(c.target):
		_transition(c,"closed","closed","这道接缝已有勘察回执",edge)
		return
	if c.owner!="":c.status="active"
	c.stage="crossing"
	c.source=link.id
	c.detail=_crossing_detail(edge,link)
	_emit(c,"route_joined",c.owner if c.owner!="" else "guild",c.detail,edge)

func _crossing_detail(edge:Vector2,link:Dictionary) -> String:
	return "原 %.1f 米断路已由《%s》接通。请从西侧旧岸走过这道接缝，再回柜台。"%[edge.x,link.name]

func _offer_archived_crossing() -> void:
	# Offer one unclaimed archived crossing at a time in a long-running world.
	if state.cards.any(func(c):return c.kind=="survey" and c.status=="open" and c.stage=="crossing"):return
	# A past closing is an observed event. A new slip can cite it without reopening it.
	for c in state.cards:
		if c.kind!="survey" or c.owner!="" or c.status!="closed" or c.stage!="":continue
		if _verified(c.target) or _pending("survey",c.target):continue
		var seam:=_at(c.at)
		var previous_bank:=Survey.basis(world,seam)
		if previous_bank=="" or c.get("basis",previous_bank)!=previous_bank:continue
		var joined:=Survey.adjoining(world,seam)
		if joined.is_empty():continue
		_post("survey",c.target,seam,"承接 "+c.id+"。"+_crossing_detail(seam,joined),joined.id,"",c.id)
		return

func _offer_food() -> void:
	if _pending("supply"):return
	var chosen
	var lowest:=101
	for p in s.people.values():
		if not p.alive or p.kind!="villager":continue
		var b:Dictionary=s.actors[p.entity_id]
		if b.satiety<=s.FORAGE_AT and b.satiety<lowest and b.fruit==0 and b.livelihood.meat==0 and b.meal<=0:
			lowest=int(b.satiety)
			chosen=p
	if chosen!=null:_post("supply",chosen.entity_id,chosen.position,"%s 饱食 %d，随身无食。送一枚朱果并等对方吃完"%[chosen.entity_id,lowest])

func tick(delta:float) -> void:
	state.time+=delta
	for c in state.cards:
		if c.status!="active" or c.stage!="crossing":continue
		if _verified(c.target):
			c.erase("trail")
			_transition(c,"closed","closed","这道接缝已有勘察回执",_at(c.at))
		elif Survey.crossed(s,c):
			c.stage="crossed"
			c.erase("trail")
			_mark_verified(c)
			_transition(c,"ready","crossed","接单人已从旧岸踏过 %.1f 米接缝，回柜台领取 %d 金"%[c.at[0],REWARDS.survey],s._position(c.owner))
	if state.time<state.next_poll:return
	state.next_poll=state.time+3.0
	for c in state.cards:
		if c.kind=="survey":
			if c.status in ["open","active"] or (c.status=="closed" and c.owner!=""):_refresh_survey(c)
			continue
		if c.status not in ["open","active"]:continue
		var p=_person(c)
		if p==null:_transition(c,"closed","closed","委托所指居民已倒下",_at(c.at))
		elif c.kind=="supply" and c.stage!="delivered" and s.actors[c.target].satiety>s.FORAGE_AT:
			_transition(c,"closed","closed","居民饥饿已缓解，本单尚无接单人送达的朱果",p.position)
		elif c.kind=="guard" and not c.protected:
			var priest=world.get_node_or_null("SandboxPriest")
			var beast=priest.work_by_id(c.source) if priest!=null else null
			if beast!=null and beast.phase=="dead":_transition(c,"closed","closed","威胁已在本次护民履约前解除",p.position)
	# A team imported mid-flight already carries the living creature's source ID and the resident's wound.
	for p in s.people.values():
		if p.kind!="villager" or not p.alive:continue
		var life:Dictionary=s.actors[p.entity_id].livelihood
		if life.escape_s<=0 or life.get("source_id","")=="" or _pending("guard",p.entity_id):continue
		var priest=world.get_node_or_null("SandboxPriest")
		var beast=priest.work_by_id(life.source_id) if priest!=null else null
		if beast!=null and beast.phase not in ["dead","drawing"]:
			_post("guard",p.entity_id,p.position,"%s 正在避险，生命 %d/%d，威胁来自%s"%[p.entity_id,p.health,p.max_health,beast.design.name],beast.work_id)
	_offer_food()
	_offer_archived_crossing()
	_survey_gap()

func threat(result:Dictionary) -> void:
	if not result.get("ok",false) or not result.get("alive",false) or result.get("source_id","")=="":return
	var priest=world.get_node_or_null("SandboxPriest")
	if priest==null or priest.work_by_id(result.source_id)==null:return
	var key:String=result.id
	if not _pending("guard",key):_post("guard",key,_at(result.at),"%s 遭受造物威胁，生命 %d→%d。战神退敌后须到场核实幸存者"%[key,result.health_before,result.health_after],result.source_id)

func pasture_attack(attacker:String,prey:String,at:Vector2) -> void:
	var priest=world.get_node_or_null("SandboxPriest")
	if priest==null or not at.is_finite():return
	var beast=priest.work_by_id(attacker)
	var animal=priest.work_by_id(prey)
	if beast==null or animal==null or not animal.design.get("edible",false) or animal.health>=36 or beast.last_target!=prey:return
	if _pending("escort"):return
	var resident
	var closest:=13.0
	for p in s.people.values():
		if p.kind!="villager" or not p.alive:continue
		var d:float=p.position.distance_to(at)
		if d<closest:
			closest=d
			resident=p
	if resident==null:return
	var away:=1.0 if resident.position.x>=at.x else -1.0
	var start:Vector2=resident.position
	var surface:=Ground.nearby(world,start.x,start.y,.65)
	if surface.is_empty():return
	var safe_x:=start.x+away*4.0
	var ground:=Ground.trace(world,Vector2(start.x,surface.y),safe_x)
	if ground.is_empty():return
	var c:=_post("escort",resident.entity_id,start,"牧场牲畜遭袭，护送 %s 离开袭击处约四米"%resident.entity_id,attacker,prey)
	if not c.is_empty():c.safe=_pair(Vector2(safe_x,ground.y))

func protected(work_id:String,source:String) -> void:
	if source!="war_god":return
	var priest=world.get_node_or_null("SandboxPriest")
	var beast=priest.work_by_id(work_id) if priest!=null else null
	if beast==null or beast.phase!="dead" or beast.health>0:return
	for c in state.cards:
		if c.kind=="guard" and c.status in ["open","active"] and c.source==work_id and not c.protected and _person(c)!=null:
			c.protected=true
			c.detail="%s 已被战神击倒。走到 %s 身边，确认他已脱险，再回柜台领款。"%[beast.design.name,c.target]
			_emit(c,"protected",source,c.detail,_person(c).position)

func fruit_given(giver:String, recipient:String, already_in_bag:int) -> String:
	for c in state.cards:
		if c.kind!="supply" or c.status!="active" or c.stage!="" or c.owner!=giver or c.target!=recipient:
			continue
		var person=_person(c)
		if person==null or s.actors[recipient].satiety>s.FORAGE_AT:return ""
		# Fruit leaves the stack in arrival order. Keep the position of this one real portion.
		c.fruit_ahead=already_in_bag
		c.stage="delivered"
		var message:="已将朱果递给"+recipient+"，等居民实际吃完"
		_emit(c,"delivered",giver,message,s._position(giver))
		return message
	return ""

func fruit_spent(id:String, eaten:bool, before:int, after:int) -> void:
	for c in state.cards:
		if c.kind!="supply" or c.status!="active" or c.stage!="delivered" or c.target!=id:continue
		# Older explicit deliveries required an empty recipient bag, so their fruit was first.
		if c.get("fruit_ahead",0)>0:
			c.fruit_ahead-=1
		elif eaten and after>before:
			_transition(c,"ready","fed","%s 吃完所送朱果，饱食 %d→%d，回公会领 %d 金"%[id,before,after,REWARDS.supply],s._position(id))
		else:
			c.erase("fruit_ahead")
			c.stage=""
			_emit(c,"diverted",id,"委托朱果已另作他用，仍需交一枚给"+id,s._position(id))
		return

func escort_motion(p,delta:float) -> bool:
	for c in state.cards:
		if c.stage!="escort" or c.status!="active" or c.target!=p.entity_id:continue
		var guide:Vector2=s._position(c.owner)
		var safe:=_at(c.safe)
		if not guide.is_finite() or guide.distance_to(p.position+Vector2(0,.45))>3.3:
			p.linear_velocity.x=0.0
			return true
		if absf(p.position.x-safe.x)<.85 and absf(p.position.y-safe.y)<.75 and absf(guide.x-safe.x)<1.5:
			_transition(c,"ready","escorted","居民亲自走到安全点，生命 %d，回柜台结算"%p.health,p.position)
			return false
		var dx:float=guide.x-p.position.x
		p.linear_velocity.x=clampf(dx*1.7,-1.35,1.35) if absf(dx)>.42 else 0.0
		if absf(p.linear_velocity.x)>.01:p.facing=1 if dx>0 else -1
		return true
	return false

func options(actor:String) -> Array:
	var result:=[]
	if actor not in ACTORS:return result
	var at:Vector2=s._position(actor)
	if not at.is_finite():return result
	var counter:bool=s.Guild.near(s,actor,s.Guild.COUNTER_X)
	for c in state.cards:
		var verb:=""
		if c.status=="open" and counter:verb="accept"
		elif c.owner==actor:
			if c.status=="ready" and counter:verb="settle"
			elif c.status=="active" and at.distance_to(location(c))<=s.REACH:
				match c.kind:
					"supply":
						if c.stage=="" and s.inventory(actor).fruit>0 and _person(c)!=null and s.actors[c.target].satiety<=s.FORAGE_AT and s.actors[c.target].fruit==0 and s.actors[c.target].meal<=0:verb="deliver"
					"guard":
						if c.protected and _person(c)!=null and s.actors[c.target].livelihood.escape_s<=0:verb="verify"
					"survey":
						var walker=world.game if actor==s.PLAYER else s.agent_rig(actor)
						if c.stage=="" and not _verified(c.target) and walker!=null and walker.on_ground and not Ground.nearby(world,at.x,at.y,.9).is_empty():verb="survey"
					"escort":
						if c.stage=="":verb="escort"
		if verb!="":
			var label:String={"accept":"领取","settle":"结算","deliver":"交朱果","verify":"核实幸存者","survey":"勘查纸边","escort":"接应居民"}[verb]
			result.append({"id":verb+"."+c.id,"verb":verb,"contract_id":c.id,"label":label+" · "+NAMES[c.kind],"reward":REWARDS[c.kind]})
	return result

func board(actor:String) -> Dictionary:
	var rows:=[]
	var at:Vector2=s._position(actor)
	for c in state.cards:
		if c.status=="open" or c.owner==actor or (c.status=="active" and s.Guild.near(s,actor,s.Guild.COUNTER_X)):
			var place:=location(c)
			rows.append({"id":c.id,"kind":c.kind,"title":NAMES[c.kind],"status":c.status,"owner":c.owner,"target":c.target,"source":c.source,"prey":c.prey,"basis":c.get("basis",""),"origin":c.at.duplicate(),
				"stage":c.stage,"protected":c.protected,"at":_pair(place),"detail":c.detail,"reward":REWARDS[c.kind]})
	return {"cards":rows,"actions":options(actor),"orchard":s.orchard_facts(),"orchards":s.orchard_sites(),"at_counter":at.is_finite() and s.Guild.near(s,actor,s.Guild.COUNTER_X)}

func execute(actor:String,option:String) -> Dictionary:
	var matches:=options(actor).filter(func(o):return o.id==option)
	if matches.size()!=1:return {"error":"委托、站位或背包已有变化"}
	var op:Dictionary=matches[0]
	var c:=card(op.contract_id)
	var at:Vector2=s._position(actor)
	var msg:=""
	match op.verb:
		"accept":
			c.owner=actor
			msg="已领取"+NAMES[c.kind]
			_transition(c,"active","accepted",msg,at)
		"settle":
			var bag:Dictionary=s.inventory(actor)
			var reward:int=REWARDS[c.kind]
			if bag.economy.coins+reward>9999:return {"error":"钱袋已满，稍后仍可领款"}
			var before:int=bag.economy.coins
			bag.economy.coins+=reward
			s.actors[actor]=bag
			msg="%s 结算，金币 %d→%d"%[NAMES[c.kind],before,bag.economy.coins]
			_transition(c,"paid","settled",msg,at)
		"deliver":
			var given:Dictionary=s.act(actor,"give",{"to":c.target})
			if not given.get("ok",false):return given
			msg=given.message
		"verify":
			msg="实地核对幸存居民，生命 %d"%_person(c).health
			_transition(c,"ready","verified",msg,at)
		"survey":
			var seam:=_at(c.at)
			if not Ground.nearby(world,seam.x+1.8,seam.y,1.3).is_empty():
				_refresh_survey(c)
				return {"error":c.detail if c.stage=="crossing" else "前方有新落脚面，待接缝成形后可从旧岸踏过"}
			_mark_verified(c)
			msg="已在 %.1f 米核实断路并记下落脚点"%seam.x
			_transition(c,"ready","surveyed",msg,at)
		"escort":
			c.stage="escort"
			msg="居民已认出向导，保持在三米内带往 %.1f 米"%float(c.safe[0])
			_emit(c,"met",actor,msg,at)
	return {"ok":true,"message":msg,"contract_id":c.id,"status":c.status,"reward":REWARDS[c.kind]}

