class_name MedievalWorld
extends Node2D

const Entity := preload("res://scripts/medieval_entity.gd")
const Sweep := preload("res://scripts/blade_sweep.gd")
const CastleLayout := preload("res://scripts/medieval_castle_layout.gd")
const Terrain := preload("res://scripts/medieval_terrain.gd")
const TreeRoots := preload("res://scripts/medieval_tree_roots.gd")
const Visibility := preload("res://scripts/medieval_visibility.gd")
const MAP_ID := "medieval-v1"
const LENGTH := 180.0
const CONTENT_VERSION := 3
const Composition := preload("res://scripts/medieval_composition.gd")
const BLADE_BOUNDS_MARGIN := 0.00001 # Bounds reject work, never exact contacts.
const SECTIONS := [{"name":"丘陵树林","x":3.0},{"name":"台地村庄","x":25.5},{"name":"河岸集市","x":54.0},{"name":"高地城堡","x":77.0},{"name":"飞龙山脊","x":92.0},{"name":"风车麦田","x":113.0},{"name":"磨坊渡口","x":134.0},{"name":"古修道院","x":153.0},{"name":"边境营地","x":172.0}]
var game
var terrain := Terrain.new()
var entities: Array = []
var debris: Array = []
var elapsed := 0.0
var _monitored := {}
var _impact_cooldowns := {}
var _previous_velocities := {}
var _prop_ink_contacts := {}
var bridge_trial

func _enter_tree() -> void:
	# Returning a parked map keeps its bodies, but tree-exit cleanup removed
	# their old exemptions. Restore patrols after all children enter again.
	if not entities.is_empty(): _restore_actor_exemptions.call_deferred()

func _restore_actor_exemptions() -> void:
	if not is_inside_tree(): return
	for entity in entities:
		if is_instance_valid(entity): Entity.WalkSurfaces.configure_actor(entity)

func _ready() -> void:
	terrain.build_physics(self)
	if entities.is_empty(): _populate()
	bridge_trial = preload("res://scripts/mill_bridge_trial.gd").new()
	bridge_trial.world = self
	add_child(bridge_trial)

func _spawn(kind: String, x: float, suffix: int, y: float = -999.0):
	var entity := Entity.new()
	var floor_y := terrain.travel_height(x)
	var stable_id := "castle-piece-"+str(suffix) if kind == "castle_piece" else kind+"-"+str(suffix)
	entity.setup(kind,Vector2(x,floor_y if y == -999.0 else y),stable_id,floor_y)
	# Wide walkers must enter physics already tangent to the slope. Spawning
	# a level deer rectangle inside a steep hill ejects it above follow range.
	if entity.is_ground_animal() and y==-999.0:
		var pose:=terrain.support_pose(x,entity.size.x*.335,.05)
		entity.position.y=pose.position_y
		entity.rotation=pose.rotation
	add_child(entity)
	entities.append(entity)
	return entity

func _populate() -> void:
	for i in [0,2]: _spawn("oak",[4.5,8.2,13.2,17.2][i],i)
	for i in [0,2]: _spawn("pine",[90.6,93.0,98.0][i],i)
	for i in 3: _spawn("house",22.5+i*6,i)
	for i in 3: _spawn("market",43+i*4,i)
	for i in 5:
		_spawn("barrel",[20.0,38.0,41.0,48.8,66.0][i],i)
		_spawn("crate",[21.0,39.0,45.1,53.3,89.0][i],i)
	for i in 5: _spawn("villager",[25.5,31.5,37.0,55.0,64.0][i],i)
	var horse = _spawn("horse",60,0)
	var horse_pose:=terrain.support_pose(horse.position.x,horse.size.x*0.335,0.05)
	horse.position.y=horse_pose.position_y+0.1
	horse.rotation=horse_pose.rotation
	var wagon = _spawn("wagon",57.7,0)
	var wagon_pose:=terrain.wagon_pose(wagon.position.x,wagon.source_rect,wagon.size,wagon.facing)
	wagon.position.y=wagon_pose.position_y
	wagon.rotation=wagon_pose.rotation
	wagon.companion_id = horse.entity_id
	var driver = _spawn("driver",58.15,0,wagon.position.y+0.2)
	driver.companion_id = wagon.entity_id
	driver.freeze = true
	driver.rebuild_geometry()
	for part in CastleLayout.records(): _spawn(part.kind,part.x,part.suffix,part.y)
	for role in CastleLayout.role_positions():
		var person = _spawn(role.kind,role.x,0,role.y-0.045)
		person.patrol_half_width = minf(person.home_x-role.patrol_left,role.patrol_right-person.home_x)-0.25
	_spawn("general",65.7,0)
	_spawn("knight",78.6,0)
	_spawn("dragon",92,0,8.2)
	_populate_expansion()
	for entity in entities:
		Composition.configure_patrol(entity)
		_place_ground_prop(entity)

func _populate_expansion() -> void:
	# Content migration only calls this for newly authored IDs. Existing bodies,
	# including destroyed originals and legacy wall assemblies, remain untouched.
	for record in Composition.records():
		if entities.size()>=384:break
		if entity_by_id(record.id)!=null:continue
		var y:float=record.y
		var x:float=record.x
		var stack_base=entity_by_id(record.get("stack_on",""))
		if stack_base!=null:
			var at:Vector2=stack_base.to_global(Vector2(0,stack_base.size.y))
			x=at.x;y=at.y
		if record.get("natural_ground",false):y=terrain.surface_height(x)
		var entity=_spawn(record.kind,x,record.suffix,y)
		if y!=-999.0:entity.set_meta("authored_root",true)
		if stack_base!=null:entity.rotation=stack_base.rotation
		_place_ground_prop(entity)

	for record in Composition.actor_records():
		if entities.size()>=384:break
		var id:String=record.kind+"-"+str(record.suffix)
		if entity_by_id(id)!=null:continue
		var flight:float=record.get("flight_height",0.0)
		var actor=_spawn(record.kind,record.x,record.suffix,terrain.travel_height(record.x)+flight if flight>0 else -999.0)
		Composition.configure_patrol(actor)
	if entity_by_id("horse-100")==null and entities.size()<384:
		var horse=_spawn("horse",118.5,100)
		Composition.configure_patrol(horse)
		var pose:=terrain.support_pose(horse.position.x,horse.size.x*0.335,0.05)
		horse.position.y=pose.position_y
		horse.rotation=pose.rotation
	if entity_by_id("wagon-100")==null and entities.size()<384:
		var wagon=_spawn("wagon",116.2,100)
		wagon.companion_id="horse-100"
		var pose:=terrain.wagon_pose(wagon.position.x,wagon.source_rect,wagon.size,wagon.facing)
		wagon.position.y=pose.position_y
		wagon.rotation=pose.rotation
	if entity_by_id("driver-100")==null and entities.size()<384 and entity_by_id("wagon-100")!=null:
		var wagon=entity_by_id("wagon-100")
		var driver=_spawn("driver",116.65,100,wagon.position.y+0.2)
		driver.companion_id="wagon-100"
		driver.freeze=true
		driver.rebuild_geometry()

func _place_ground_prop(entity) -> void:
	if entity.kind in ["oak","pine","orchard_tree"]:
		entity.position.y = terrain.surface_height(entity.position.x)
		entity.rotation = 0
		entity.tree_roots = TreeRoots.new(entity,terrain)
		entity.rebuild_geometry()
		return
	if entity.is_actor() or entity.kind in ["castle_piece","wagon"] or entity.has_meta("authored_root"):return
	if entity.kind in ["barrel","crate","haystack","fence","bench","cart_goods"]:
		var contacts:=_ink_bottom_contacts(entity)
		var pose:=terrain.ink_prop_pose(entity.position.x,contacts,entity.size.x*0.5)
		entity.position.y=pose.position_y
		entity.rotation=pose.rotation
	elif entity.kind in Composition.FOLIAGE:
		# Roots follow their small real footprint while the stem remains upright.
		entity.position.y=terrain.travel_height(entity.position.x)


func _ink_bottom_contacts(entity) -> PackedVector2Array:
	if _prop_ink_contacts.has(entity.kind):return _prop_ink_contacts[entity.kind]
	var contacts:=PackedVector2Array()
	if entity.texture==null or entity.source_rect.size.x<=0:return contacts
	var image:Image=entity.texture.get_image()
	var source:Rect2=entity.source_rect
	# Sample the actual alpha envelope once per source image, excluding empty
	# crop corners and raised shafts. Fine samples preserve rounded barrel feet.
	var stride:=maxi(1,int(source.size.x/96))
	for x in range(int(source.position.x),int(source.end.x),stride):
		for y in range(int(source.end.y)-1,int(source.position.y)-1,-1):
			if image.get_pixel(x,y).a<0.12:continue
			contacts.append(Vector2((float(x)-source.position.x)/source.size.x-0.5,1.0-(float(y)-source.position.y)/source.size.y)*entity.size)
			break
	_prop_ink_contacts[entity.kind]=contacts
	return contacts

func surface_height(x: float) -> float:
	return terrain.surface_height(x)

func travel_height(x: float) -> float:
	return terrain.travel_height(x)

func step(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	delta = minf(delta,0.1)
	elapsed += delta
	terrain.step(delta)
	for entity in entities:
		# Static scenery has no locomotion or water state. Only its short damage
		# flash needs a timer; bodies and damage geometry remain fully present.
		if not entity.is_actor():
			if entity.hurt_timer>0:entity.step(delta)
			continue
		entity.ground_y=terrain.travel_height(entity.position.x)
		entity.step(delta)
		_follow_slope(entity,delta)
		terrain.apply_water_body(entity,delta)
		if entity.alive and (entity.is_person() or entity.is_ground_animal()) and entity.hurt_timer <= 0 and entity.patrol_turn_cooldown <= 0 and not (entity.kind == "driver" and entity.companion_id != "") and _patrol_blocked(entity):
			entity.facing *= -1
			entity.linear_velocity.x *= -1
			entity.patrol_turn_cooldown = 0.6
	for entity in entities:
		if entity.kind != "wagon" or not entity.alive or entity.companion_id == "": continue
		var horse = entity_by_id(entity.companion_id)
		if horse != null and horse.alive and horse.hurt_timer <= 0:
			entity.position.x = horse.position.x - horse.facing * 2.3
			if entity.facing!=horse.facing:
				entity.facing=horse.facing
				entity.rebuild_geometry()
			var pose:=terrain.wagon_pose(entity.position.x,entity.source_rect,entity.size,entity.facing)
			entity.position.y=pose.position_y
			entity.rotation=pose.rotation
	for entity in entities:
		if entity.kind != "driver" or not entity.alive or entity.companion_id == "": continue
		var wagon = entity_by_id(entity.companion_id)
		if wagon == null or not wagon.alive:
			entity.detach_carriage()
		else:
			entity.position = wagon.to_global(Vector2(wagon.facing * 0.45, 0.2))
			entity.rotation=wagon.rotation
			entity.facing = wagon.facing
	for item in debris:
		item.life -= delta
		item.position += item.velocity * delta
		item.velocity.y -= 12*delta
	debris = debris.filter(func(item): return item.life > 0)
	if game != null:
		for object in game.object_nodes:
			if is_instance_valid(object) and object is RigidBody2D: terrain.apply_water_body(object,delta)
	_monitor_ink()
	if bridge_trial != null: bridge_trial.step(delta)

func _patrol_blocked(actor) -> bool:
	# Autonomous people share the same through-façade route as the player.
	# Only real ground discontinuities or authored dynamic ink can block a walk.
	var direction:float=float(actor.facing)
	var next_x:float=actor.position.x+direction*0.4
	if next_x<0.4 or next_x>LENGTH-0.4:return true
	if absf(terrain.travel_height(next_x)-terrain.travel_height(actor.position.x))>0.65:return true
	if game==null:return false
	var a:Vector2=actor.position+Vector2(0,0.52)+Vector2(direction*(actor.size.x*0.335+0.03),0)
	var b:Vector2=a+Vector2(direction*0.34,0)
	var query:=PhysicsRayQueryParameters2D.create(a,b,9)
	query.exclude=[actor.get_rid()]
	var hit:=get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider is BuildObject

func _follow_slope(entity,delta: float) -> void:
	if not entity.alive or not (entity.is_person() or entity.is_ground_animal()) or entity.hurt_timer>0 or (entity.kind=="driver" and entity.companion_id!=""): return
	# Grounded walkers get a tangent velocity. Airborne and hurt bodies keep the
	# engine's gravity/impulses instead of snapping back onto a hidden flat plane.
	var half:float=entity.size.x*0.335
	var pose:Dictionary=terrain.support_pose(entity.position.x,half,0.05) if entity.is_ground_animal() else {}
	var support:float=pose.position_y if entity.is_ground_animal() else terrain.support_height(entity.position.x,half)-0.045
	if absf(entity.position.y-support)>0.22 or entity.linear_velocity.y>1.0: return
	var next_x:float=entity.position.x+entity.linear_velocity.x*delta
	var next:float=terrain.support_pose(next_x,half,0.05).position_y if entity.is_ground_animal() else terrain.support_height(next_x,half)-0.045
	entity.linear_velocity.y=(next-support)/delta
	if entity.is_ground_animal(): entity.rotation=pose.rotation
	# A tiny predictive foot clearance crosses adjoining terrain trapezoids at
	# a slope change. The old 5mm skin let a rectangular foot catch their seam.
	# Hurt/airborne actors returned above and retain all impulses and gravity.
	var skin:=0.035 if entity.is_person() else 0.005
	if entity.position.y<support+0.04:
		entity.position.y=support+skin
		# Synchronize the physical transform now: the engine otherwise restores
		# the previous rigid-body state before the queued Node2D change arrives.
		PhysicsServer2D.body_set_state(entity.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,entity.global_transform)
		entity.sleeping=false

func _spawn_shape_clear(shape: PackedVector2Array) -> bool:
	for polygon in terrain.collision_geometry:
		if not Geometry2D.intersect_polygons(shape,polygon).is_empty():return false
	for entity in entities:
		if not entity.alive:continue
		# The surface, not the decorative façade, is the physical spawn blocker.
		if entity.has_method("world_walk_segments"):
			for edge in entity.world_walk_segments():
				var a:Vector2=edge[0];var b:Vector2=edge[1]
				if Geometry2D.is_point_in_polygon(a,shape) or Geometry2D.is_point_in_polygon(b,shape):return false
				for index in shape.size():
					if Geometry2D.segment_intersects_segment(a,b,shape[index],shape[(index+1)%shape.size()])!=null:return false
		elif entity.collision_layer & 1:
			for polygon in entity.world_polygons():
				if not Geometry2D.intersect_polygons(shape,polygon).is_empty():return false
	return true

func safe_legacy_player_position(at: Vector2) -> Vector2:
	var shape:=PackedVector2Array([at+Vector2(-0.25,-0.48),at+Vector2(0.25,-0.48),at+Vector2(0.25,0.56),at+Vector2(-0.25,0.56)])
	return at if _spawn_shape_clear(shape) else safe_spawn_position(at.x)

func safe_spawn_position(desired_x: float) -> Vector2:
	for i in 81:
		var offset := 0.0 if i == 0 else float((i+1)/2)*0.5*(1 if i%2 == 1 else -1)
		var x:=clampf(desired_x+offset,0.5,LENGTH-0.5)
		var candidate := Vector2(x,terrain.support_height(x,0.27)+0.56)
		var shape := PackedVector2Array([candidate+Vector2(-0.25,-0.48),candidate+Vector2(0.25,-0.48),candidate+Vector2(0.25,0.56),candidate+Vector2(-0.25,0.56)])
		if _spawn_shape_clear(shape):return candidate
	return Vector2(1,terrain.support_height(1,0.27)+0.56)

func entity_by_id(stable_id: String):
	for entity in entities:
		if entity.entity_id == stable_id: return entity
	return null

func draw_world(canvas: Node2D) -> void:
	terrain.draw_world(canvas,game)
	for entity in entities:
		if Visibility.entity_visible(game,entity,1.5):entity.draw_entity(canvas,game)
	if bridge_trial != null: bridge_trial.draw_world(canvas,game)
	for item in debris:
		var a: Vector2 = game.world_to_screen(item.position)
		canvas.draw_line(a,a+item.direction*minf(8,game.PIXELS_PER_UNIT*0.08),Color(0.04,0.035,0.03,minf(1,item.life)),1.3,true)

func _polygon_segment(a: Vector2,b: Vector2,polygon: PackedVector2Array) -> Dictionary:
	if Geometry2D.is_point_in_polygon(a,polygon): return {"position":a,"time":0.0}
	var best: Dictionary = {}
	for i in polygon.size():
		var point = Geometry2D.segment_intersects_segment(a,b,polygon[i],polygon[(i+1)%polygon.size()])
		if point == null: continue
		var time: float = a.distance_to(point)/maxf(a.distance_to(b),0.00001)
		if best.is_empty() or time < best.time: best = {"position":point,"time":time}
	return best

func segment_contact(a: Vector2,b: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	for polygon in terrain.collision_geometry:
		var contact:=_polygon_segment(a,b,polygon)
		if not contact.is_empty() and contact.time<nearest.get("time",INF):
			contact.index=-1
			nearest=contact
	for entity in entities:
		if not entity.alive: continue
		for polygon in entity.world_polygons():
			var contact := _polygon_segment(a,b,polygon)
			if not contact.is_empty() and (nearest.is_empty() or contact.time < nearest.time):
				contact.entity = entity
				contact.index = -2
				nearest = contact
	return nearest

func blade_contact(old: Array,current: Array,origin: Vector2 = Vector2.INF) -> Dictionary:
	if current.is_empty(): return {}
	# These conservative boxes only reject impossible contacts. Cache current
	# world polygons once, before temporal sampling, instead of transforming every
	# distant entity again for every segment of every sample in an empty-air swing.
	var area := Sweep.swept_bounds(old,current).grow(BLADE_BOUNDS_MARGIN)
	var candidates: Array = []
	for entity in entities:
		if not entity.alive: continue
		for polygon in entity.world_polygons():
			if polygon.size() < 3: continue
			var box := Sweep.bounds([polygon]).grow(BLADE_BOUNDS_MARGIN)
			if not area.intersects(box,true): continue
			var edges: Array = []
			for edge in polygon.size():
				var a: Vector2 = polygon[edge]
				var b: Vector2 = polygon[(edge+1)%polygon.size()]
				edges.append({"a":a,"b":b,"bounds":Rect2(a,Vector2.ZERO).expand(b)})
			candidates.append({"entity":entity,"polygon":polygon,"bounds":box,"edges":edges})
	for polygon in terrain.collision_geometry:
		var box:=Sweep.bounds([polygon]).grow(BLADE_BOUNDS_MARGIN)
		if not area.intersects(box,true): continue
		var edges:Array=[]
		for edge in polygon.size():
			var a:Vector2=polygon[edge];var b:Vector2=polygon[(edge+1)%polygon.size()]
			edges.append({"a":a,"b":b,"bounds":Rect2(a,Vector2.ZERO).expand(b)})
		candidates.append({"entity":null,"polygon":polygon,"bounds":box,"edges":edges})
	if candidates.is_empty(): return {}
	# Retain every segment that can touch this solid anywhere in the frame.
	# Large hollow weapons often surround a target's box while almost all their
	# actual ink misses it. Do this conservative rejection once, before sampling,
	# instead of revisiting every irrelevant segment at every instant.
	var steps := clampi(ceili(Sweep.motion_distance(old,current)/Sweep.SAMPLE_SPACING),1,Sweep.MAX_SAMPLES)
	for target in candidates:
		var segments: Array[PackedVector2Array] = []
		for path_index in current.size():
			var path: PackedVector2Array = current[path_index]
			var before: PackedVector2Array = old[path_index] if old.size()==current.size() and old[path_index].size()==path.size() else path
			for j in range(1,path.size()):
				var box := Rect2(path[j-1],Vector2.ZERO).expand(path[j]).expand(before[j-1]).expand(before[j])
				if not box.intersects(target.bounds,true): continue
				var segment := PackedVector2Array([before[j-1],before[j],path[j-1],path[j]])
				segments.append(segment)
		target.segments = segments
	candidates = candidates.filter(func(target: Dictionary) -> bool: return not target.segments.is_empty())
	if candidates.is_empty(): return {}
	for i in range(steps+1):
		# Most touching swings finish at the initial sample. Only pay for the
		# stronger moving-ink rejection when several later samples remain.
		if i==1 and steps>4:
			for target in candidates:
				var retained: Array[PackedVector2Array] = []
				for segment in target.segments:
					if _swept_segment_may_touch(segment,target.polygon): retained.append(segment)
				target.segments=retained
			candidates=candidates.filter(func(target:Dictionary)->bool:return not target.segments.is_empty())
			if candidates.is_empty(): return {}
		var time := float(i)/steps
		# The held grip only orders contacts that the actual sword already makes.
		# It never creates an owner-to-target attack ray or fills a sword's gaps.
		var reference := origin if origin.is_finite() else Sweep.bounds(Sweep.at_time(old,current,time)).get_center()
		var nearest := {}
		var distance := INF
		for target in candidates:
			var polygon: PackedVector2Array = target.polygon
			for segment in target.segments:
				var a: Vector2 = segment[0].lerp(segment[2],time)
				var b: Vector2 = segment[1].lerp(segment[3],time)
				var segment_box := Rect2(a,Vector2.ZERO).expand(b)
				if not segment_box.intersects(target.bounds,true): continue
				# Keep the exact ordered predicates, but accumulate the best point
				# directly instead of allocating a buffer for each sampled segment.
				var contact_point := Vector2.ZERO
				var contact_distance := distance
				var candidate_distance: float
				if Geometry2D.is_point_in_polygon(a,polygon):
					candidate_distance = reference.distance_squared_to(a)
					if candidate_distance < contact_distance: contact_distance=candidate_distance;contact_point=a
				if Geometry2D.is_point_in_polygon(b,polygon):
					candidate_distance = reference.distance_squared_to(b)
					if candidate_distance < contact_distance: contact_distance=candidate_distance;contact_point=b
				var projected := Geometry2D.get_closest_point_to_segment(reference,a,b)
				if Geometry2D.is_point_in_polygon(projected,polygon):
					candidate_distance = reference.distance_squared_to(projected)
					if candidate_distance < contact_distance: contact_distance=candidate_distance;contact_point=projected
				for edge in target.edges:
					if not segment_box.intersects(edge.bounds,true): continue
					var point = Geometry2D.segment_intersects_segment(a,b,edge.a,edge.b)
					if point != null:
						candidate_distance = reference.distance_squared_to(point)
						if candidate_distance < contact_distance: contact_distance=candidate_distance;contact_point=point
				if contact_distance < distance:
					distance = contact_distance
					nearest = {"position":contact_point,"time":time,"index":-1 if target.entity==null else -2}
					if target.entity!=null: nearest.entity=target.entity
		if not nearest.is_empty(): return nearest
	return {}


func _swept_segment_may_touch(segment: PackedVector2Array, polygon: PackedVector2Array) -> bool:
	# Every interpolated point lies inside the convex hull of these four ends.
	# A separating projection can only reject; retained material still uses all
	# original temporal samples and exact point/edge predicates below.
	var hull := Geometry2D.convex_hull(segment)
	if hull.size()<3: return true
	var reference: Vector2 = hull[0]
	for i in hull.size():
		var edge: Vector2 = hull[(i+1)%hull.size()]-hull[i]
		if edge.length_squared()<0.0000000001: continue
		var axis := Vector2(-edge.y,edge.x)
		var ink_min := 0.0
		var ink_max := 0.0
		for point in hull:
			var value := axis.dot(point-reference)
			ink_min=minf(ink_min,value);ink_max=maxf(ink_max,value)
		var solid_min := INF
		var solid_max := -INF
		for point in polygon:
			var value := axis.dot(point-reference)
			solid_min=minf(solid_min,value);solid_max=maxf(solid_max,value)
		# A small broad-phase rounding allowance preserves boundary-only contact.
		var margin := BLADE_BOUNDS_MARGIN*4*axis.length()
		if ink_min>solid_max+margin or solid_min>ink_max+margin: return false
	return true

func damage_entity(entity,amount: float,point: Vector2,impulse: Vector2,weapon_type: String = "") -> void:
	if entity == null or not entities.has(entity) or not entity.alive: return
	if not point.is_finite() or not impulse.is_finite() or not is_finite(amount) or amount <= 0: return
	var before_health: float = entity.health
	entity.damage(amount,point,impulse)
	var feedback = game.get("feedback") if game != null else null
	if feedback != null:
		if weapon_type!="":PaperCombatAudio.impact(feedback,"hit" if entity.alive else "break",point,weapon_type)
		else:feedback.emit_event("hit" if entity.alive else "break",point)
		if not entity.alive:PaperCombatAudio.cry(feedback,entity.kind,point)
	var combat = game.get("combat") if game != null else null
	if combat != null and combat.has_method("add_damage_text"): combat.add_damage_text(point,before_health-entity.health)
	for i in 7:
		if debris.size() >= 160: debris.pop_front()
		var angle := float(i)*2.399+elapsed
		debris.append({"position":point,"velocity":Vector2(cos(angle)*2.5,sin(angle)*2+3)+impulse*0.12,"direction":Vector2(cos(angle),sin(angle)),"life":0.6+i*0.06})

func _monitor_ink() -> void:
	if game == null: return
	for object in game.object_nodes:
		if not is_instance_valid(object) or not object is BuildObject: continue
		var key: int = object.get_instance_id()
		if not _monitored.has(key):
			object.contact_monitor = true
			object.max_contacts_reported = 16
			object.body_entered.connect(_on_ink_contact.bind(object))
			_monitored[key] = weakref(object)
		_previous_velocities[key] = object.linear_velocity
	for key in _monitored.keys():
		if _monitored[key].get_ref() == null:
			_monitored.erase(key)
			_previous_velocities.erase(key)
	for key in _impact_cooldowns.keys():
		if elapsed - _impact_cooldowns[key] > 3: _impact_cooldowns.erase(key)

func _on_ink_contact(body: Node,object: RigidBody2D) -> void:
	if body!=null and body.has_meta("medieval_owner"):body=body.get_meta("medieval_owner")
	if not body is MedievalEntity or not body.alive or not object is BuildObject or object.freeze: return
	var velocity: Vector2 = _previous_velocities.get(object.get_instance_id(),object.linear_velocity)
	if object.linear_velocity.length() > velocity.length(): velocity = object.linear_velocity
	var relative: Vector2 = velocity-body.linear_velocity
	if relative.length() < 2.5: return
	var key := str(object.get_instance_id())+":"+str(body.get_instance_id())
	if elapsed-_impact_cooldowns.get(key,-100.0) < 0.65: return
	_impact_cooldowns[key] = elapsed
	var point: Vector2 = body.position+Vector2(0,body.size.y*0.5)
	var collision := segment_contact(object.position,point)
	if collision.get("entity") == body: point = collision.position
	var damage := clampf(relative.length()*sqrt(maxf(0.1,object.mass))*4,6,65)
	damage_entity(body,damage,point,relative.normalized()*minf(12,damage*0.18)+Vector2(0,1.5))

func save_state() -> Array:
	var result: Array = []
	for entity in entities:
		var record:Dictionary=entity.save_record()
		record.angle=entity.rotation
		result.append(record)
	return result

static func _number(record: Dictionary,key: String,minimum: float,maximum: float) -> bool:
	var value = record.get(key)
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func validate_state(records: Variant) -> bool:
	if not records is Array: return false
	if records.size() > 384: return false
	var ids := {}
	for entry in records:
		if not entry is Dictionary: return false
		var record: Dictionary = entry
		var id = record.get("id")
		var kind = record.get("kind")
		if not id is String or id.length() < 1 or id.length() > 64 or ids.has(id) or not kind is String or not Entity.supported_kind(kind): return false
		ids[id] = true
		if not _number(record,"x",-5,185) or not _number(record,"y",-16,30) or not _number(record,"home_x",0,180): return false
		if record.has("angle") and not _number(record,"angle",-PI,PI): return false
		if not _number(record,"health",0,Entity.initial_health(kind)) or not _number(record,"vx",-30,30) or not _number(record,"vy",-50,50): return false
		if not record.get("alive") is bool or bool(record.alive) != (float(record.health)>0): return false
		if not _number(record,"facing",-1,1) or absf(float(record.facing)) != 1 or record.get("state") not in ["idle","walk","fly","hurt","fall","dead","destroyed"]: return false
		if not record.get("companion","") is String or record.get("companion","").length() > 64: return false
		var cuts = record.get("cuts")
		if not cuts is Array or cuts.size() > 12: return false
		var size := Entity.dimensions(kind)
		if kind == "castle_piece":
			var descriptor: Dictionary = CastleLayout.descriptor(id)
			if descriptor.is_empty(): return false
			size = descriptor.size
		for cut in cuts:
			if not cut is Dictionary or not _number(cut,"x",-size.x*0.5-0.000001,size.x*0.5+0.000001) or not _number(cut,"y",-0.000001,size.y+0.000001) or not _number(cut,"radius",0.3,0.8) or not _number(cut,"side",0,3) or float(cut.side) != floorf(float(cut.side)): return false
	return true

static func validate_snapshot(world:Dictionary)->bool:
	if not preload("res://scripts/mill_bridge_trial.gd").valid_state(world.get("bridge_trial",{})): return false
	for key in ["terrain_version","content_version"]:
		var value=world.get(key,1)
		if not (value is int or value is float):return false
		if not is_finite(float(value)) or value<1 or value>3 or float(value)!=floorf(float(value)):return false
	var records=world.get("entities")
	return validate_state(records) and (int(world.get("content_version",1))!=1 or records.size()<=96)

func _migrated_home(record: Dictionary) -> float:
	var locations:Dictionary={"oak":[4.5,8.2,13.2,17.2],"pine":[90.6,93.0,98.0],"house":[22.5,28.5,34.5],"market":[43.0,47.0,51.0],"barrel":[20.0,38.0,41.0,48.8,66.0],"crate":[21.0,39.0,45.1,53.3,89.0],"villager":[25.5,31.5,37.0,55.0,64.0],"horse":[60.0],"wagon":[57.7],"driver":[58.15],"wall":[72.02,75.02,82.02,72.02,75.02,82.02],"tower":[69.4,84.64],"gate":[78.52],"dragon":[92.0]}
	var suffix:String=record.id.get_slice("-",1)
	if not suffix.is_valid_int(): return record.home_x
	var index:=suffix.to_int()
	var homes:Array=locations.get(record.kind,[])
	if record.id!=record.kind+"-"+str(index) or index<0 or index>=homes.size(): return record.home_x
	return homes[index]

func restore_state(records: Array,source_terrain_version: int=Terrain.VERSION,source_content_version: int=CONTENT_VERSION,trial_state: Variant={}) -> bool:
	# Share this preflight with disk/network validation before any live state
	# is cleared or an imported snapshot is persisted.
	if not validate_snapshot({"entities":records,"terrain_version":source_terrain_version,"content_version":source_content_version,"bridge_trial":trial_state}):return false
	for entity in entities:
		remove_child(entity)
		entity.queue_free()
	entities.clear()
	debris.clear()
	_impact_cooldowns.clear()
	var authored:Dictionary={}
	for entry in Composition.records():authored[entry.id]=entry
	for record in records:
		# Retire only untouched authored decor. A felled tree or cut plant is
		# still part of the user's world and its stable record is preserved.
		if source_content_version<3 and Composition.retired_id(record.id) and record.alive and record.cuts.is_empty() and is_equal_approx(float(record.health),Entity.initial_health(record.kind)):
			continue
		var entity := Entity.new()
		var restored_x:float=record.x
		var restored_home:float=record.home_x
		if source_terrain_version==1:
			restored_home=_migrated_home(record)
			restored_x=clampf(restored_x+restored_home-float(record.home_x),0.5,LENGTH-0.5)
		var height:=terrain.travel_height(restored_x)
		var restored_y:float=record.y
		if source_terrain_version<Terrain.VERSION: restored_y=terrain.upgrade_position(Vector2(restored_x,restored_y),source_terrain_version).y
		entity.setup(record.kind,Vector2(restored_x,restored_y),record.id,height)
		entity.home_x = restored_home
		Composition.configure_patrol(entity)
		entity.home_x = restored_home
		entity.rotation=record.get("angle",0.0)
		entity.health = record.health
		entity.alive = record.alive
		entity.state = record.state
		entity.facing = record.facing
		entity.cuts = record.cuts.duplicate(true)
		entity.companion_id = record.get("companion","")
		if entity.kind == "driver":
			if entity.companion_id == "": entity.detach_carriage()
			else: entity.freeze = true
		entity.linear_velocity = Vector2(record.vx,record.vy)
		if authored.has(record.id):
			var placement:Dictionary=authored[record.id]
			if placement.y!=-999.0 or placement.has("stack_on") or placement.get("natural_ground",false):entity.set_meta("authored_root",true)
		entity.rebuild_geometry()
		add_child(entity)
		entities.append(entity)
		if source_terrain_version<Terrain.VERSION or entity.kind in ["oak","pine","orchard_tree"]: _place_ground_prop(entity)
	if source_terrain_version<Terrain.VERSION:
		for placement in authored.values():
			if not placement.has("stack_on"):continue
			var upper=entity_by_id(placement.id);var lower=entity_by_id(placement.stack_on)
			if upper!=null and lower!=null:
				upper.position=lower.to_global(Vector2(0,lower.size.y))
				upper.rotation=lower.rotation
	if source_content_version<CONTENT_VERSION:_populate_expansion()
	if bridge_trial != null: bridge_trial.restore(trial_state)
	return true
