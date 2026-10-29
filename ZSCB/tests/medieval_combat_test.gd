extends SceneTree

class Entity extends RefCounted:
	var health := 100.0
	var alive := true
	var geometry: Array = []
	var impulse := Vector2.ZERO
	var hits := 0
	func _init(x: float): geometry = [PackedVector2Array([Vector2(x, 1), Vector2(x, 3)])]
	func is_actor() -> bool: return true

class World extends RefCounted:
	var entities: Array = []
	func segment_contact(a: Vector2, b: Vector2) -> Dictionary:
		var nearest := {}
		for entity in entities:
			if not entity.alive: continue
			for path in entity.geometry:
				var point = Geometry2D.segment_intersects_segment(a, b, path[0], path[1])
				if point == null: continue
				var time: float = a.distance_to(point) / maxf(a.distance_to(b), 0.00001)
				if time < nearest.get("time", INF): nearest = {"entity": entity, "position": point, "time": time}
		return nearest
	func blade_contact(old: Array, current: Array, _origin := Vector2.INF) -> Dictionary:
		var nearest := {}
		for entity in entities:
			if not entity.alive: continue
			var hit := PaperBladeSweep.blade_contact(old, current, entity.geometry, entity.geometry)
			if not hit.is_empty() and hit.time < nearest.get("time", INF): nearest = {"entity": entity, "position": hit.position, "time": hit.time}
		return nearest
	func damage_entity(entity, amount: float, _point: Vector2, impulse: Vector2) -> void:
		if not entity.alive: return
		entity.hits += 1
		entity.health = maxf(0, entity.health - amount)
		entity.alive = entity.health > 0
		entity.impulse = impulse

class Feedback extends RefCounted:
	var events: Array = []
	func emit_event(kind: String, at: Vector2) -> void: events.append({"kind": kind, "position": at})

class Terrain extends RefCounted:
	var collision_geometry: Array = [PackedVector2Array([Vector2(0.5, 1), Vector2(0.5, 3)])]

class Fixture extends RefCounted:
	var medieval_world = World.new()
	var knowledge_world = null
	var objects: Array = []
	var object_nodes: Array = []
	var feedback = Feedback.new()
	var player := Node2D.new()
	var character_visual: Node2D
	var equipped_weapon: Dictionary = {}
	var selected := -1
	var crouching := false
	const GROUND_Y := 0.0
	func object_point(obj: Dictionary, point: Vector2) -> Vector2: return Vector2(obj.x, obj.y) + point
	func screen_to_world(point: Vector2) -> Vector2: return point
	func terrain_hit(a: Vector2, b: Vector2) -> Dictionary:
		for path in knowledge_world.collision_geometry:
			var point = Geometry2D.segment_intersects_segment(a, b, path[0], path[1])
			if point != null: return {"position": point}
		return {}
	func cancel_pointer() -> void: pass
	func message(_text: String) -> void: pass

var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("MEDIEVAL COMBAT: " + label)
func arm(battle) -> void:
	battle.swing = 0.25
	battle.recoil = 0
	battle.hit_ids.clear()
	battle.swing_direction = Vector2.RIGHT
	battle.swing_weapon = {"grip": Vector2.ZERO, "paths": [{"points": [Vector2.ZERO, Vector2.RIGHT]}]}
	battle.previous_player_paths = [PackedVector2Array([Vector2(0, 1.4), Vector2(0, 2.6)])]
	battle.player_paths = [PackedVector2Array([Vector2(4, 1.4), Vector2(4, 2.6)])]
func arrow(battle) -> void:
	battle.projectiles.clear()
	battle.shoot_arrow(Vector2(0, 2), Vector2.RIGHT, "player")
func run() -> void:
	var game := Fixture.new()
	game.player.position = Vector2(-20, 2)
	var battle := PaperCombat.new(game)
	var entity := Entity.new(2)
	game.medieval_world.entities = [entity]
	var wall := battle.first_structure(Vector2(0, 2), Vector2(4, 2))
	check(wall.get("entity") == entity and wall.get("index", 0) == -2, "arrows identify medieval targets without using authored object indices")
	arm(battle)
	wall = battle._blade_structure(battle.previous_player_paths, battle.player_paths)
	check(wall.get("entity") == entity and wall.get("time", INF) < 1, "actual blade middle sweep finds a medieval target between frames")
	battle._resolve_blades()
	var after_hit: float = entity.health
	battle._resolve_blades()
	check(after_hit < 100 and entity.health == after_hit and entity.hits == 1, "one sword swing damages the entity once")
	check(entity.impulse.x > 0, "sword impact supplies directional knockback")
	check(entity.impulse.y > 0, "the actual combat damage call supplies upward knockup")
	battle.swing = 0
	arrow(battle)
	battle._step_projectiles(0.25)
	check(entity.health < after_hit and battle.projectiles.is_empty(), "an arrow wounds the entity and is consumed")
	check(entity.impulse.x > 0, "arrow impact supplies directional knockback")
	var authored := {"role": "building", "kind": "wall", "x": 1.0, "y": 2.0, "health": 120.0, "paths": [{"collision": true, "points": [Vector2(0, -1), Vector2(0, 1)]}]}
	game.objects = [authored]
	var body := Node2D.new()
	game.object_nodes = [body]
	var before: float = entity.health
	arm(battle)
	battle._resolve_blades()
	check(entity.health == before and authored.health < 120, "prior authored wall blocks sword damage")
	arrow(battle)
	battle._step_projectiles(0.25)
	check(entity.health == before and authored.health < 100, "prior authored wall blocks arrow damage")
	game.objects.clear()
	game.object_nodes.clear()
	body.free()
	game.knowledge_world = Terrain.new()
	wall = battle.first_structure(Vector2(0, 2), Vector2(4, 2))
	check(wall.get("index", 0) == -1, "nearer immutable terrain takes precedence over medieval targets")
	arm(battle)
	battle._resolve_blades()
	check(entity.health == before, "immutable terrain blocks medieval sword damage")
	arrow(battle)
	battle._step_projectiles(0.25)
	check(entity.health == before and battle.projectiles.is_empty(), "immutable terrain blocks medieval arrow damage")
	game.knowledge_world = null
	var front := Entity.new(0.8)
	game.medieval_world.entities = [entity, front]
	arm(battle)
	battle._resolve_blades()
	check(front.health < 100 and entity.health == before, "nearest medieval target blocks the same sword from damaging a victim behind it")
	battle.swing = 0
	arrow(battle)
	battle.shoot_arrow(Vector2(4, 2), Vector2.LEFT, "native")
	game.feedback.events.clear()
	battle._step_projectiles(0.25)
	check(not game.feedback.events.any(func(e: Dictionary) -> bool: return e.kind == "clash"), "prior medieval impact cancels later arrow-arrow clashes")
	front.alive = false
	entity.alive = false
	check(battle.first_structure(Vector2(0, 2), Vector2(4, 2)).is_empty(), "dead entities no longer block arrows")
	arm(battle)
	check(battle._blade_structure(battle.previous_player_paths, battle.player_paths).is_empty(), "dead entities no longer block swords")
	var hits: int = entity.hits
	battle._resolve_blades()
	check(entity.hits == hits, "sword after death cannot damage corpse")
	game.medieval_world = null
	check(battle.first_structure(Vector2(0, 2), Vector2(4, 2)).is_empty(), "old map works with a null medieval world")
	game.player.free()
	real_world_regressions()
	print("MEDIEVAL COMBAT TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func real_world_regressions() -> void:
	var game := Fixture.new()
	var world = MedievalWorld.new()
	world.game = game
	game.medieval_world = world
	var crate := MedievalEntity.new()
	crate.setup("crate",Vector2(1,20),"test-crate",0)
	var villager := MedievalEntity.new()
	villager.setup("villager",Vector2(2,20),"test-villager",0)
	world.add_child(crate)
	world.add_child(villager)
	world.entities = [villager,crate] # Entity traversal also opposes physical order.
	var origin := Vector2(0,20.5)
	var variants: Array = [
		[PackedVector2Array([Vector2(2.6,20.5),origin])],
		[PackedVector2Array([origin,Vector2(2.6,20.5)])],
		[PackedVector2Array([Vector2(2.6,20.5),Vector2(1.5,20.5)]),PackedVector2Array([Vector2(1.5,20.5),origin])],
		[PackedVector2Array([origin,Vector2(1.5,20.5)]),PackedVector2Array([Vector2(1.5,20.5),Vector2(2.6,20.5)])]]
	for i in variants.size():
		var contact: Dictionary = world.blade_contact(variants[i],variants[i],origin)
		check(contact.get("entity") == crate,"real medieval target is grip-nearest independent of vertices/strokes " + str(i))
	var later: Array = [PackedVector2Array([Vector2(3,20.1),Vector2(3,20.7)])]
	var earlier: Array = [PackedVector2Array([Vector2(0,20.1),Vector2(0,20.7)])]
	check(world.blade_contact(later,earlier,origin).get("entity") == villager,"earlier sword motion contact takes precedence over spatial proximity")
	var detached: Array = [PackedVector2Array([Vector2(1.6,20.5),Vector2(2.6,20.5)])]
	check(world.blade_contact(detached,detached,origin).get("entity") == villager,"grip ordering never invents a sword segment through a model gap")
	# The character center is deliberately on the opposite side. Only the displayed
	# held grip provides the correct spatial ordering for this long drawn blade.
	game.player.position = Vector2(4,20.5)
	var rig := Node2D.new()
	game.character_visual = rig
	var node := rig
	for part in ["Skeleton","Hips","Torso","FrontArm","Forearm","Hand","WeaponGrip","HeldWeapon"]:
		var child := Node2D.new()
		child.name = part
		node.add_child(child)
		node = child
	node.position = origin
	var battle := PaperCombat.new(game)
	for i in variants.size():
		crate.health = crate.max_health
		villager.health = villager.max_health
		villager.alive = true
		crate.cuts.clear()
		crate.rebuild_geometry()
		arm(battle)
		battle.player_paths = variants[i]
		battle.previous_player_paths = variants[i]
		battle._resolve_blades()
		check(crate.health < crate.max_health and villager.health == villager.max_health,"real combat grip blocks villagers behind a crate for path ordering " + str(i))
	crate.health = crate.max_health
	crate.cuts.clear()
	crate.rebuild_geometry()
	var authored := {"role":"building","kind":"wall","x":0.4,"y":20.0,"paths":[{"points":[Vector2(0,0.1),Vector2(0,0.9)]}]}
	game.objects = [authored]
	check(battle._blade_structure(variants[0],variants[0],origin).get("index",-9) == 0,"same-time authored wall before medieval entity blocks a reversed blade")
	authored.x = 1.6
	check(battle._blade_structure(variants[0],variants[0],origin).get("entity") == crate,"same-time medieval entity before authored wall wins by actual grip distance")
	game.objects.clear()
	world.entities = [villager]
	villager.health = villager.max_health
	villager.alive = true
	arm(battle)
	battle.player_paths = variants[0]
	battle.previous_player_paths = variants[0]
	battle._resolve_blades()
	check(villager.health < villager.max_health and villager.linear_velocity.y > 0,"actual sword strike knocks a real villager upward")
	villager.health = 1
	arm(battle)
	battle.player_paths = variants[0]
	battle.previous_player_paths = variants[0]
	battle._resolve_blades()
	check(not villager.alive and villager.state == "fall" and villager.linear_velocity.y > 0,"a lethal real sword strike retains knockup and enters fall")
	rig.free()
	game.player.free()
	world.free()
