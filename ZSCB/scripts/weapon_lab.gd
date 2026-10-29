extends RefCounted
## Optional session-only meter. Only authority combat may supply a hit.
const DISTANCES := [1.2,2.5,5.0]
var game
var active:=false
var position:=Vector2.ZERO
var generation:=0
var samples:Dictionary={}
var current:Dictionary={}
var baseline:Dictionary={}
var last_hit:Dictionary={}
var others:Dictionary={}
var cached:Dictionary={}
var refresh_clock:=0.0
var brief:=""
func _init(owner_game=null)->void:game=owner_game
func remote()->bool:return game.network_session!=null
func effective_weapon()->Dictionary:
	return {"weapon_type":"bow","paths":[],"trial":true} if game.combat!=null and game.combat.bow_equipped else game.equipped_weapon
func select(weapon:Dictionary)->void:
	if remote():return
	var data:Dictionary={}
	for field in ["paths","grip","weapon_type","cooldown","model_fill","trial"]:
		if weapon.has(field):data[field]=weapon[field]
	var key:String
	if cached==data and not current.is_empty() and samples.has(current.key):return
	cached=data.duplicate(true)
	key=JSON.stringify(SaveStore._json_value(data)).sha256_text()
	if not samples.has(key):
		while samples.size()>=8:samples.erase(samples.keys().front())
		var reach:=0.0;var grip:Vector2=weapon.get("grip",Vector2.ZERO)
		for path in weapon.get("paths",[]):
			for p in path.points:reach=maxf(reach,p.distance_to(grip))
		var kind:=PaperWeaponTypes.kind(weapon)
		var cooldown:=.78 if kind=="bow" else .75 if kind=="firearm" else PaperWeaponTypes.attack_cooldown(weapon)
		samples[key]={"key":key,"kind":kind,"reach":reach,"cooldown":cooldown,"trial":weapon.get("trial",false),"hits":0,"total":0.0,"last":0.0,"maximum":0.0,"farthest":0.0}
	current=samples[key]
	_update_brief()
func start(distance:float)->Dictionary:
	if remote():return {"ok":false,"error":"试靶由服务器布置"}
	if distance not in DISTANCES:return {"ok":false,"error":"请选择1.2、2.5或5米试靶"}
	var point:Vector2=game.player.position+Vector2(game.facing*distance,.2)
	if game.knowledge_world!=null and (point.x<game.knowledge_world.LEFT or point.x>game.knowledge_world.RIGHT):return {"ok":false,"error":"试靶需要位于当前地图内"}
	if game.medieval_world!=null and (point.x<0 or point.x>game.medieval_world.LENGTH):return {"ok":false,"error":"试靶需要位于当前地图内"}
	var query:=PhysicsShapeQueryParameters2D.new();var shape:=CircleShape2D.new();shape.radius=.3
	query.shape=shape;query.transform=Transform2D(0,point);query.collision_mask=1|8|2|64|128;query.exclude=[game.player.get_rid()]
	if not game.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():return {"ok":false,"error":"这里有地形或部件，请在空处换方向布靶"}
	position=point;generation+=1;active=true
	select(effective_weapon())
	return {"ok":true,"error":""}
func stop()->void:
	if remote():return
	active=false;generation+=1;_update_brief()
func reset()->void:
	if remote():return
	generation+=1;samples.clear();current={};last_hit={};select(effective_weapon())
func keep()->Dictionary:
	if remote():return {"ok":false,"error":"试打记录由服务器确认"}
	if current.is_empty() or current.hits==0:return {"ok":false,"error":"请先用当前方案实际命中试靶"}
	baseline=current.duplicate(true)
	return {"ok":true,"error":""}
func ticket()->Dictionary:
	if remote() or not active:return {}
	select(effective_weapon())
	return {"generation":generation,"key":current.key}
func accepts(stamp:Dictionary)->bool:
	return not remote() and active and stamp.get("generation",-1)==generation and samples.has(stamp.get("key",""))
func hit(stamp:Dictionary,amount:float,contact:Vector2,origin:Vector2)->void:
	if not accepts(stamp):return
	if not is_finite(amount) or amount<5 or amount>40 or not contact.is_finite() or not origin.is_finite():return
	var sample:Dictionary=samples[stamp.key]
	sample.hits+=1;sample.total+=amount;sample.last=amount;sample.maximum=maxf(sample.maximum,amount)
	sample.farthest=maxf(sample.farthest,origin.distance_to(contact))
	last_hit={"kind":sample.kind,"amount":amount,"distance":origin.distance_to(contact)}
	_update_brief()
func step(delta:float)->void:
	if remote() or (not active and current.is_empty()):return
	refresh_clock-=delta
	if refresh_clock<=0:refresh_clock=.2;select(effective_weapon())
func _update_brief()->void:
	brief="试靶 · %s · %d击 · 最近%.0f / 最高%.0f · 作品→武器试打"%[PaperWeaponTypes.LABELS.get(current.get("kind","sword"),"武器"),current.get("hits",0),current.get("last",0),current.get("maximum",0)] if active else ""
func snapshot()->Dictionary:
	return {"active":active,"position":position,"generation":generation,"current":current.duplicate(true),"baseline":baseline.duplicate(true),"last_hit":last_hit.duplicate(true)}
func receive(data:Dictionary)->void:
	if not remote() or not data.get("position",Vector2.ZERO) is Vector2 or not data.get("position",Vector2.ZERO).is_finite():return
	active=bool(data.get("active",false));position=data.get("position",Vector2.ZERO);generation=int(data.get("generation",0))
	current=data.get("current",{}).duplicate(true);baseline=data.get("baseline",{}).duplicate(true);last_hit=data.get("last_hit",{}).duplicate(true);_update_brief()
func draw_target(canvas:Node2D,data:Dictionary,friend:bool=false)->void:
	if not data.get("active",false):return
	var p:Vector2=game.world_to_screen(data.position);var radius:float=.26*game.PIXELS_PER_UNIT
	var ink:=Color("808b84") if friend else Color("376f65")
	canvas.draw_circle(p,radius,Color("faf7eb"));canvas.draw_arc(p,radius,0,TAU,32,ink,2,true)
	canvas.draw_arc(p,radius*.5,0,TAU,24,ink,1.5,true);canvas.draw_circle(p,2,ink)
	canvas.draw_string(ThemeDB.fallback_font,p+Vector2(-radius,-radius-10),"朋友试靶" if friend else "武器试靶",HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
func draw_world(canvas:Node2D)->void:
	draw_target(canvas,snapshot())
	for data in others.values():draw_target(canvas,data,true)
