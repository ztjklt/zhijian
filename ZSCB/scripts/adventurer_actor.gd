extends "res://scripts/companion_actor.gd"
## A traveler's equipment moves with the same animated torso as the human player.

func _dress_actor() -> void:
	var torso: Node2D = character_visual.get_node("Skeleton/Hips/Torso")
	character_visual.pencil.self_modulate.a = 0.0
	var pack := _patch(torso, "Rucksack", Color("534c3b"), [
		Vector2(-8,-25), Vector2(-14,-24), Vector2(-18,-18), Vector2(-18,-7),
		Vector2(-15,-3), Vector2(-7,-2), Vector2(-4,-7), Vector2(-4,-19)])
	_patch(pack, "Canvas", Color("988462"), [Vector2(-8,-23),Vector2(-14,-22),
		Vector2(-16,-17),Vector2(-16,-8),Vector2(-14,-5),Vector2(-7,-4),Vector2(-6,-14)])
	_patch(pack, "Flap", Color("6e745c"), [Vector2(-16,-20),Vector2(-8,-22),
		Vector2(-5,-18),Vector2(-7,-14),Vector2(-16,-14)])
	_patch(pack, "Buckle", Color("d2b681"), [Vector2(-12,-16),Vector2(-10,-16),
		Vector2(-10,-12),Vector2(-12,-12)])
	_patch(torso, "ShoulderStrap", Color("806d4e"), [Vector2(2,-24),Vector2(5,-23),
		Vector2(-3,-5),Vector2(-6,-6)])
	_patch(torso, "TravelScarf", Color("566956"), [Vector2(-6,-26),Vector2(5,-25),
		Vector2(5,-21),Vector2(1,-20),Vector2(-2,-14),Vector2(-10,-9),
		Vector2(-8,-17),Vector2(-11,-19),Vector2(-5,-22)])
	_patch(torso, "ScarfFold", Color("84907a"), [Vector2(-6,-25),Vector2(4,-24),
		Vector2(3,-22),Vector2(-7,-22)])

func _patch(parent: Node2D, part: String, color: Color, vertices: Array) -> Polygon2D:
	var piece := Polygon2D.new()
	piece.name = part
	piece.color = color
	piece.polygon = PackedVector2Array(vertices)
	piece.z_index = 2 if parent == character_visual.get_node("Skeleton/Hips/Torso") else 0
	piece.antialiased = true
	parent.add_child(piece)
	return piece
