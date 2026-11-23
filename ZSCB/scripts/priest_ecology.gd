extends RefCounted
## Observations come from living map entities, the shared orchard and saved animals.
const Form := preload("res://scripts/ink_life_form.gd")
const Ground := preload("res://scripts/priest_ground.gd")
const Species := preload("res://scripts/priest_species.gd")
const CAPACITY := Species.MAX_LIVE
const PATCH_WIDTH := 10.0
const POCKET_PITCH := .25
const BRUSH_REACH := 1.47
const NATIVE_ANIMALS := ["rabbit","deer","horse","bat","dragon"]

## Choose actual pasture clumps and ground beside tree trunks for a local inspection.
static func patrol_sites(priest, here: Vector2, last_id: String) -> Array:
	var facts: Dictionary = priest.world.survival.decision_facts("priest", here, 16.0)
	var grasses := []
	for grass in facts.pastures:
		grasses.append({"id":grass.id, "at":[grass.x,grass.y], "label":"%.1f 米处的草地" % grass.x,
			"evidence":"出发时看到草地有 %d/%d 份牧草" % [grass.portions,grass.capacity]})
	var trees := []
	for tree in facts.trees:
		if not tree.alive:continue
		var trunk := Vector2(tree.at[0], tree.at[1])
		var floor_row := Ground.nearby(priest.world, trunk.x, trunk.y, .65)
		if floor_row.is_empty():continue
		var x := trunk.x - 1.05 if here.x <= trunk.x else trunk.x + 1.05
		var stand := Ground.trace(priest.world, Vector2(trunk.x,floor_row.y), x)
		if stand.is_empty():continue
		var name := str({"oak":"橡树", "pine":"松树", "orchard_tree":"果树"}.get(tree.kind,"林木"))
		trees.append({"id":tree.id, "at":[x,stand.y], "label":"%.1f 米处的%s旁" % [x,name],
			"evidence":"出发时看到%s生命 %d/%d" % [name,tree.health,tree.max_health]})
	var by_distance := func(a,b):return here.distance_squared_to(Vector2(a.at[0],a.at[1])) < here.distance_squared_to(Vector2(b.at[0],b.at[1]))
	grasses.sort_custom(by_distance)
	trees.sort_custom(by_distance)
	var last_was_grass := grasses.any(func(site):return site.id==last_id)
	var sites := trees+grasses if last_was_grass else grasses+trees
	return sites.filter(func(site):return site.id!=last_id)

static func observe(priest) -> Dictionary:
	var patches := []
	var center := roundi((priest.priest_x+1.48)/PATCH_WIDTH)
	var limits:=Ground.bounds(priest.world)
	for index in range(center-2,center+3):
		var x := -1.48+index*PATCH_WIDTH
		if x<limits.x+.8 or x>limits.y-.8: continue
		var area:=patch(priest,index)
		if not area.is_empty(): patches.append(area)
	# A ledge can fit wholly between two of the original ten-metre sample columns.
	add_nearby_pocket(priest,patches)
	var animals := []
	var population:={"living":0,"remains":0,"drawing":0,"by_blueprint":{}}
	for animal in priest.works:
		var state: String = "remains" if animal.phase=="dead" else "drawing" if animal.phase=="drawing" else "living"
		var family: String = animal.blueprint_id if animal.blueprint_id!="" else animal.work_id
		if not population.by_blueprint.has(family):population.by_blueprint[family]={"name":animal.design.name,"living":0,"remains":0,"drawing":0}
		population.by_blueprint[family][state]+=1
		population[state]+=1
		animals.append({"work_id":animal.work_id,"name":animal.design.name,"habitat_id":animal.habitat_id,
			"feeding":animal.design.get("actions",animal.design.get("feeding","gnaw")),"favorite":animal.design.get("favorite",""),"phase":animal.phase,
			"x":snappedf(animal.beast_x,.1),"y":snappedf(animal.beast_y,.1),"blueprint_id":animal.blueprint_id,"health":animal.health,"satiety":snappedf(animal.satiety,.1),"ground_fruit_full_at":preload("res://scripts/priest_ground_fruit.gd").FULL,"hunger_seconds":animal.hunger_seconds,"delivered_meals":animal.delivered_meals,"blocked_by":animal.blocked_by,"pasture_target":animal.grass_target.get("id",""),"portions":animal.portions,"edible":animal.design.get("edible",false),"fruit_meals":animal.fruit_meals,"ground_fruit_target":animal.fruit_target.get("id",""),"grass_meals":animal.grass_meals,"flights":animal.takeoffs,"landings":animal.landings,"hits":animal.hits,"kills":animal.kills,"bites_by_tree":animal.eaten.duplicate(),"bites_per_tree_limit":animal.MEALS_PER_TREE})
	var sites:Array=priest.world.paper_nav_sites(Vector2(priest.priest_x,priest.priest_y),16) if priest.world.has_method("paper_nav_sites") else []
	for alternative in priest.travel_alternatives:
		if not sites.any(func(s):return s.id==alternative.id):sites.append(alternative.duplicate(true))
	return {"pasture_care":priest.pasture_care.observe(priest),"carried_grass":priest.feed_run.carried,"population":population,"recent_effects":priest.ecology_log.rows.slice(-12).duplicate(true),"last_route_alternatives":priest.travel_alternatives.duplicate(true),"navigation_sites":sites,"travel":priest.travel_target.duplicate(true),"priest_protocol":Species.SCHEMA,"identity":{"name":"牧师","role":"priest","team_id":priest._scope().team_id},"memory":priest.memory.duplicate(true),"commitments":priest.commitments.duplicate(true),"blueprints":priest.blueprints.duplicate(true),"task":"ecology","habitats":patches,"creatures":animals,"live_limit":CAPACITY,
		"native_diet_record":"原生野兽统计在 native_counts；拆件生命按各自的行为与食性行动，牲畜与捕食兽都属于实际个体。","prior_goal":priest.goal,"last_result":priest.progress,"protected_tree":priest.protected_tree}

## Check the actual short, ground-following path used for a local survey and its easel.
static func dry_walk(priest, start:Vector2, end:Vector2) -> bool:
	var world=priest.world
	var prev:=start
	var steps:=maxi(1,ceili(absf(end.x-start.x)/.24))
	for i in range(1,steps+1):
		var x:=lerpf(start.x,end.x,float(i)/steps)
		var row:=Ground.trace(world,prev,x)
		if row.is_empty():return false
		var at:=Vector2(x,row.y)
		if world.paper_space and is_finite(world.paper_space.water_surface(at+Vector2(0,.01))):return false
		var left:=prev if prev.x<at.x else at
		var right:=at if prev.x<at.x else prev
		var a:=left+Vector2(-.10,.18)
		var b:=right+Vector2(.10,.18)
		var shape:=PackedVector2Array([a,b,b+Vector2(0,.94),a+Vector2(0,.94)])
		if world.spawn_shape_blocker(shape)!="":return false
		var area:=Rect2(a,Vector2.ZERO).expand(b).expand(shape[2]).expand(shape[3])
		for obj in priest.game.objects:
			if (obj.get("pen")=="draw_object" or obj.has("built_plan")) and area.intersects(priest.game.object_bounds(obj)):return false
		prev=at
	return absf(prev.y-end.y)<.05

static func pocket_clear(priest, foot:Vector2) -> bool:
	var world=priest.world
	var observer:=Vector2(priest.priest_x,priest.priest_y)
	if not Ground.room(priest,foot.x,foot.y):return false
	var hand:=Ground.trace(world,foot,foot.x-BRUSH_REACH)
	if hand.is_empty():return false
	var easel:=Vector2(foot.x-BRUSH_REACH,hand.y)
	return dry_walk(priest,observer,foot) and dry_walk(priest,foot,easel) and dry_walk(priest,observer,easel)

static func pocket_at(priest, column:int, expected_id:String="") -> Dictionary:
	var x:=column*POCKET_PITCH
	if absf(x-priest.priest_x)>PATCH_WIDTH*.5+.01:return {}
	var surface:=Ground.trace(priest.world,Vector2(priest.priest_x,priest.priest_y),x)
	if surface.is_empty():return {}
	var key:="pocket-%d/%d/%s"%[column,roundi(surface.y*100),str(surface.work_id).sha256_text().left(16)]
	if expected_id!="" and key!=expected_id:return {}
	if not pocket_clear(priest,Vector2(x,surface.y)):return {}
	var area:=describe_patch(priest,roundi((x+1.48)/PATCH_WIDTH),x,surface,key,true)
	if expected_id=="" and not area.space:return {}
	area.label=priest.world.paper_nav_label(str(surface.work_id),Vector2(x,surface.y))
	return area

static func by_id(priest, id:String) -> Dictionary:
	if id.begins_with("pocket-"):
		var col:=id.trim_prefix("pocket-").get_slice("/",0)
		if col.is_valid_int():return pocket_at(priest,int(col),id)
	elif id.begins_with("grove-"):
		var index:=id.trim_prefix("grove-").get_slice("/",0)
		if index.is_valid_int():
			var site:=patch(priest,int(index))
			if site.get("id","")==id:return site
	return {}

static func add_nearby_pocket(priest, known:Array) -> void:
	if priest.surveyed_site.begins_with("pocket-"):
		var surveyed:=by_id(priest,priest.surveyed_site)
		if not surveyed.is_empty():
			known.append(surveyed)
			if surveyed.space:return
	var at:=Vector2(priest.priest_x,priest.priest_y)
	for site in known:
		var foot:=Vector2(site.x,site.ground_y)
		if site.space and site.water_depth==0 and at.distance_to(foot)<=PATCH_WIDTH*.5 and dry_walk(priest,at,foot):return
	var center:=roundi(at.x/POCKET_PITCH)
	for i in range(1+2*roundi(PATCH_WIDTH*.5/POCKET_PITCH)):
		var column:=center+ceili(i*.5)*(1 if i%2==0 else -1)
		var site:=pocket_at(priest,column)
		if not site.is_empty():
			known.append(site)
			return

static func patch(priest, index: int) -> Dictionary:
	var world = priest.world
	var x := -1.48+index*PATCH_WIDTH
	var origin:=Vector2(priest.priest_x,priest.priest_y)
	var surface:=Ground.trace(world,origin,x)
	if surface.is_empty(): return {}
	var layer:=str(surface.work_id)
	var key:="grove-%d" % index if layer.begins_with("legacy:") else "grove-%d/%s" % [index,layer.sha256_text().left(16)]
	return describe_patch(priest,index,x,surface,key,false)

static func describe_patch(priest,index:int,x:float,surface:Dictionary,key:String,exact:bool) -> Dictionary:
	var world=priest.world
	var layer:=str(surface.work_id)
	var trees := []
	var native_counts := {}
	var healthy := 0
	var wounds := 0
	var fruit := 0
	var grasses:=[]
	var grass_units:=0
	if world.survival and world.survival.has_method("pasture_near"):
		for grass in world.survival.pasture_near(Vector2(x,surface.y),8.0):
			if exact:
				var ground_at:=Ground.trace(world,Vector2(x,surface.y),grass.x)
				if ground_at.is_empty() or absf(ground_at.y-grass.y)>.12:continue
			grasses.append(grass)
			grass_units+=int(grass.portions)
	var ground_fruit:=[]
	if world.survival and world.survival.has_method("ground_fruit_near"):
		for item in world.survival.ground_fruit_near(Vector2(x,surface.y),8):
			var layer_at:=Ground.trace(world,Vector2(x,surface.y),item.x)
			if not layer_at.is_empty() and absf(float(layer_at.y)-(float(item.y)-.085))<.12:ground_fruit.append(item)
	var residents := 0
	var livestock := 0
	var predators := 0
	for animal in priest.works:
		if animal.phase=="dead":continue
		var dist:=Vector2(animal.beast_x,animal.beast_y).distance_to(Vector2(x,surface.y))
		if dist<13.0:
			if animal.has_action("hunt_livestock"):predators+=1
			if animal.design.get("edible",false):livestock+=1
		if not animal.has_action("hunt_livestock") and (animal.habitat_id==key or dist<PATCH_WIDTH*.5):residents+=1
	for entity in world.entities:
		if not is_instance_valid(entity) or absf(entity.position.x-x)>7.0: continue
		if entity.kind in NATIVE_ANIMALS and entity.alive and entity.position.distance_to(Vector2(x,surface.y))<12.0:
			native_counts[entity.kind] = int(native_counts.get(entity.kind,0))+1
		if not Form.FOOD.has(entity.kind): continue
		var tree_floor:=Ground.trace(world,Vector2(x,surface.y),entity.position.x)
		if tree_floor.is_empty() or absf(entity.position.y-tree_floor.y)>.55: continue
		var hp := maxi(0,roundi(entity.health)) if entity.alive else 0
		var damage := maxi(0,roundi(entity.max_health)-hp)
		var ripe := 0
		if world.survival != null and entity == world.survival.tree: ripe = world.survival.fruit_count()
		fruit += ripe
		wounds += damage
		if hp >= entity.max_health*.70 and entity.entity_id != priest.protected_tree: healthy += 1
		trees.append({"id":entity.entity_id,"kind":entity.kind,"hp":hp,"max_hp":roundi(entity.max_health),
			"lost_hp":damage,"cuts":entity.cuts.size(),"ripe_fruit":ripe})
	var clear := false
	var birth_x := x
	var birth_y:float=surface.y
	if exact:
		clear=not priest.works.any(func(a):return a.phase!="dead" and Vector2(a.beast_x,a.beast_y).distance_to(Vector2(x,surface.y))<1.15)
	var offsets:=[] if exact else [0.0,-1.5,1.5,-3.0,3.0]
	for offset in offsets:
		var spot := x+float(offset)
		if priest.works.any(func(a):return a.phase!="dead" and absf(a.beast_x-spot)<1.15 and absf(a.beast_y-surface.y)<1.2):continue
		var floor_at:=Ground.trace(world,Vector2(x,surface.y),spot)
		if not floor_at.is_empty() and Ground.room(priest,spot,floor_at.y) and not Ground.trace(world,Vector2(spot,floor_at.y),spot-1.47).is_empty():
			birth_y=floor_at.y
			birth_x = spot
			clear = true
			break
	var point:=Vector2(birth_x,birth_y)
	var page:=Ground.cell(world,point)
	var water:float=world.paper_space.water_surface(point+Vector2(0,.12)) if world.paper_space!=null else -INF
	var ceilings: Array = world.paper_surfaces(birth_x,birth_y+.15,birth_y+8.0).filter(func(row):return row.face=="ceiling")
	return {"id":key,"index":index,"page":[page.x,page.y],"surface":layer,"x":snappedf(birth_x,.01),"ground_y":birth_y,
		"space":clear,"ground_fruit":ground_fruit,"fruit_units":ground_fruit.size(),"grasses":grasses,"grass_units":grass_units,"livestock":livestock,"predators":predators,"room_for_species":clear and not is_finite(water) and priest.live_count()<CAPACITY and priest.works.size()<Species.MAX_WORKS,"water_depth":snappedf(maxf(0.0,water-birth_y),.1),"overhead_ceiling":not ceilings.is_empty(),"trees":trees,"healthy_food_trees":healthy,"tree_damage":wounds,"ripe_fruit":fruit,
		"native_counts":native_counts,"resident_bark_eaters":residents,
		"can_birth":clear and not is_finite(water) and healthy>0 and residents==0 and priest.live_count()<CAPACITY}

static func evidence(site: Dictionary) -> String:
	return "纸页 (%d, %d) · %s · 可食树 %d · 树伤 %d · 熟果 %d · 食皮兽 %d · %s" % [
		site.page[0],site.page[1],"水边" if site.water_depth>0 else "洞内" if site.overhead_ceiling else "露天",site.healthy_food_trees,site.tree_damage,site.ripe_fruit,site.resident_bark_eaters,
		"有落脚地" if site.space else "落脚地拥挤"]

## Re-sample on arrival. Remembered places identify old meals, not a live grass inventory.
static func survey_report(p,site:Dictionary) -> Dictionary:
	var observer:=Vector2(p.priest_x,p.priest_y)
	var sight:float=p.pasture_care.SIGHT
	var subject=null
	var distance:=INF
	for a in p.works:
		if a.phase=="drawing" or not a.has_action("graze_grass"):continue
		var gap:=observer.distance_to(Vector2(a.beast_x,a.beast_y))
		if gap<=sight and gap<distance:
			subject=a
			distance=gap
	var ground:=evidence(site) if not site.is_empty() else "到场时原勘点的脚面已改变"
	if subject==null:return {"text":"到场 %.1f 米，巡视范围 %.0f 米内未见草食个体。%s"%[observer.x,sight,ground],"id":""}
	var foot:=Vector2(subject.beast_x,subject.beast_y)
	var text:="到场见%s（%.1f，%.1f），生命 %d，饱食 %.1f，自采 %d 份。"%[subject.design.name,foot.x,foot.y,subject.health,subject.satiety,subject.grass_meals]
	if subject.phase=="dead":text+="原只已死亡。"
	else:
		var ripe:=0
		if p.world.survival:
			for patch in p.world.survival.pasture_near(foot,subject.design.sight):
				if subject.FoodWeb.pasture_barrier(subject,patch).is_empty():ripe+=int(patch.portions)
		text+="此处它能采的成熟草 %d 份。"%ripe
		if not subject.grazing.places.is_empty():
			var last:Dictionary=subject.grazing.places[0]
			text+="距上次自采脚点 %.1f 米（%s）。"%[foot.distance_to(Vector2(last.at[0],last.at[1])),last.id]
	return {"text":(text+ground).left(240),"id":subject.work_id}
