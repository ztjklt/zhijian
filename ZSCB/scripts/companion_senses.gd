extends RefCounted

static func pair(point: Vector2) -> Array:
	return [snappedf(point.x, 0.01), snappedf(point.y, 0.01)]

static func floor_at(game, x: float, from_y: float, depth: float) -> Dictionary:
	var from := Vector2(x, from_y)
	var query := PhysicsRayQueryParameters2D.create(from, from - Vector2(0, depth), 9)
	var hit: Dictionary = game.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.45: return {}
	return hit

static func clear_circle(game, at: Vector2, radius: float, mask: int) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform.origin = at
	query.collision_mask = mask
	return game.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

static func spawn_near(game, prefer_right := false) -> Vector2:
	var human: Vector2 = game.player.position
	var world = game.medieval_world
	for offset: float in [-1.65, 1.65, -1.1, 1.1, -2.3, 2.3]:
		var x := human.x - offset if prefer_right else human.x + offset
		if x < -3.7 or x > world.east_walk_limit() - 0.25: continue
		var hit := floor_at(game, x, human.y + 1.55, 3.7)
		if not hit.is_empty():
			var at := Vector2(x, hit.position.y + 0.48)
			if clear_circle(game, at, 0.31, 11): return at
	# The human may be on an isolated roof or in midair. Players do not
	# collide with one another; use their already occupied free space.
	return human

static func observe(game, actor, result: Dictionary, autonomous := false) -> Dictionary:
	var at: Vector2 = actor.player.position
	var human: Vector2 = game.player.position
	var world = game.medieval_world
	var nearby := []
	for entity in world.entities:
		if entity.alive and entity.position.distance_to(at) < 5.0 and nearby.size() < 12:
			nearby.append({"kind":entity.kind, "at":pair(entity.position)})
	var built := []
	var signed_works := 0
	for node in game.object_nodes:
		if node.position.distance_to(at) > 6.0: continue
		if node.data.get("artist", "") in ["阿靛","painter"]: signed_works += 1
		if built.size() < 12:
			built.append({"name":node.data.get("name", node.data.kind), "at":pair(node.position), "artist":node.data.get("artist", "")})
	var sites := []
	var screen: Rect2 = game.get_viewport_rect().grow(-22.0)
	for step: float in [-2.4, -1.35, 1.35, 2.4]:
		var x := at.x + step
		var px := x + signf(step) * 1.0
		if minf(x, px) < -3.7 or maxf(x, px) > world.east_walk_limit() - 0.75: continue
		var stand := floor_at(game, x, at.y + 2.1, 5.2)
		var paper := floor_at(game, px, at.y + 2.7, 6.4)
		if stand.is_empty() or paper.is_empty(): continue
		var feet: Vector2 = stand.position
		var origin: Vector2 = paper.position + Vector2(0, 0.11)
		if not autonomous and not screen.has_point(game.world_to_screen(origin + Vector2(0,0.45))): continue
		if not autonomous and not screen.has_point(game.world_to_screen(feet + Vector2(0,0.8))): continue
		if absf(feet.y + 0.3 - at.y) > 2.0 or absf(origin.y - feet.y) > 1.05: continue
		if not autonomous and (feet.distance_to(human) < 0.72 or origin.distance_to(human) < 0.95): continue
		if not clear_circle(game, feet + Vector2(0,0.48), 0.29, 9): continue
		if not clear_circle(game, origin + Vector2(0,0.45), 0.30, 11): continue
		sites.append({"id":"s%d" % sites.size(), "stand":pair(feet), "paper":pair(origin),
			"slope":snappedf(-paper.normal.x / paper.normal.y, 0.01)})
	return {"self":pair(at), "human":pair(human) if not autonomous or at.distance_to(human)<=5.0 else null, "sites":sites, "nearby":nearby, "built":built,
		"can_draw":signed_works < 2 and game.objects.size() < game.MAX_OBJECTS, "last_result":result.duplicate(true)}


const ROLE_NAMES := {"villager":"村民", "driver":"车夫", "general":"将军", "knight":"骑士", "king":"国王", "queen":"王后"}

static func people(world, at: Vector2) -> Array:
	var people_seen := []
	for entity in world.entities:
		if entity.alive and entity.is_person() and entity.position.distance_to(at) <= 6.0:
			people_seen.append({"id":entity.entity_id, "name":ROLE_NAMES.get(entity.kind, "居民"),
				"role":entity.kind, "at":pair(entity.position)})
	people_seen.sort_custom(func(a,b): return Vector2(a.at[0],a.at[1]).distance_squared_to(at) < Vector2(b.at[0],b.at[1]).distance_squared_to(at))
	return people_seen.slice(0, 5)

static func answer(world, person) -> String:
	var edge: float = world.terrain.profile[-1].x
	var metres := roundi(edge - person.position.x)
	if person.kind in ["knight", "general"]:
		return "我在这里巡逻。向东约%d米就到纸边，记得给人留条缓坡。" % metres
	if person.kind == "driver":
		return "车轮怕急坡。你去东边画路，给我的车留段平地吧。"
	var rise: float = world.travel_height(person.position.x + 2.0) - world.travel_height(person.position.x)
	if rise > 0.3: return "往东要上坡。你去接路的话，坡顶缓一点才好走。"
	if rise < -0.3: return "脚下往东是下坡。顺着走，到了纸边帮我们接一条路吧。"
	return "这一段平地好走。纸边还在东面约%d米，我想看看你会接出什么路。" % metres
