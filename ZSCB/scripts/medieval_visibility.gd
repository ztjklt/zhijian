class_name MedievalVisibility
extends RefCounted
## Conservative presentation bounds; body simulation and damage never use this.
static func entity_visible(game, entity, margin_m: float = 1.5) -> bool:
	if game == null or not is_instance_valid(entity): return true
	var anchor: Vector2 = game.world_to_screen(entity.position)
	# A full diagonal also covers rotated props, wings and local root fitting.
	var padding: float = (entity.size.length() + margin_m) * game.PIXELS_PER_UNIT
	return Rect2(Vector2.ZERO, game.get_viewport_rect().size).grow(padding).has_point(anchor)
