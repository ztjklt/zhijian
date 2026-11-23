extends Node2D
## A quilted indigo vest in the original stick figure's torso coordinates.
const OUTLINE := Color("313838")
const CLOTH := Color("597978")
const SEAM := Color("9cae99")
const BINDING := Color("404e50")
const TOGGLE := Color("d9b883")

static func mount(rig: Node2D) -> Node2D:
	var torso: Node2D = rig.get_node("Skeleton/Hips/Torso")
	var coat := new()
	coat.name = "QuiltedCoat"
	torso.add_child(coat)
	torso.move_child(coat,torso.get_node("Ink").get_index()+1)
	coat.hide()
	return coat

func _draw() -> void:
	var shape := PackedVector2Array([Vector2(-3.5,-24),Vector2(-7,-22),Vector2(-6,-17),
		Vector2(-5,-14),Vector2(-6.5,-2),Vector2(-2,.5),Vector2(1,-1),
		Vector2(4,.2),Vector2(7,-1.6),Vector2(5.5,-14),Vector2(6,-18),
		Vector2(7,-21),Vector2(3.2,-24),Vector2(.5,-21)])
	draw_colored_polygon(shape,CLOTH)
	shape.append(shape[0])
	draw_polyline(shape,OUTLINE,1.35,true)
	for y in [-14,-8]:
		draw_polyline(PackedVector2Array([Vector2(-4.6,y),Vector2(-1,y+2),
			Vector2(2,y),Vector2(5,y+1)]),SEAM,.85,true)
	draw_polyline(PackedVector2Array([Vector2(-3.4,-23.4),Vector2(2.4,-18),
		Vector2(1.6,-2.4)]),BINDING,2.1,true)
	for y in [-17,-12]: draw_line(Vector2(-.2,y),Vector2(3.3,y+.4),TOGGLE,1.4,true)
