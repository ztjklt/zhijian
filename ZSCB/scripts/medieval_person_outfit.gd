extends Node2D
## Role accessories share the original skeleton; all hat bases meet head alpha.
var part := "hat"
var role := "villager"
var eyes_closed := false
const INK := Color(0.065,0.055,0.045,0.98)
const PAPER := Color(0.94,0.925,0.87,1)
func contact_point() -> Vector2: return Vector2.ZERO
func line(points: Array, width: float = 1.0) -> void:
	draw_polyline(PackedVector2Array(points),INK,width,true)
func closed_shape(points: Array, fill: Color = PAPER) -> void:
	var polygon := PackedVector2Array(points)
	draw_colored_polygon(polygon,fill)
	polygon.append(polygon[0])
	draw_polyline(polygon,INK,1,true)
func _draw() -> void:
	if part == "eyes":
		for x in [1.7,5.8]:
			if eyes_closed:
				draw_arc(Vector2(x,1.8),0.9,0.15,PI-0.15,10,Color(0.97,0.96,0.91),0.55,true)
			else:
				draw_set_transform(Vector2(x,1.9),0,Vector2(0.85,1.35))
				draw_circle(Vector2.ZERO,1,Color(0.98,0.97,0.93),true,-1,true)
				draw_circle(Vector2(0.2,0.12),0.35,INK,true,-1,true)
			draw_set_transform(Vector2.ZERO)
	elif part == "hat":
		match role:
			"villager":
				closed_shape([Vector2(-7,0.4),Vector2(-5,-4),Vector2(4,-4.6),Vector2(7,0.4)])
				line([Vector2(-10,0.4),Vector2(10,0.4)],1.3)
			"driver":
				closed_shape([Vector2(-7,0.4),Vector2(-6,-6),Vector2(5,-6),Vector2(7,0.4)])
				line([Vector2(-10,0.4),Vector2(11,0.4)],1.3)
				line([Vector2(-6,-1.6),Vector2(6,-1.6)])
			"king", "queen":
				var tall := 8.0 if role == "queen" else 6.0
				closed_shape([Vector2(-7,1),Vector2(-8,-tall),Vector2(-4,-3),Vector2(0,-tall-1),Vector2(4,-3),Vector2(8,-tall),Vector2(7,1)])
				line([Vector2(-7,-1),Vector2(7,-1)])
				for x in [-4,0,4]: draw_circle(Vector2(x,-0.2),0.65,INK,true,-1,true)
			"knight", "general":
				closed_shape([Vector2(-8,3),Vector2(-8,-2),Vector2(-5,-6),Vector2(2,-7),Vector2(7,-4),Vector2(8,1),Vector2(3,1),Vector2(-3,1),Vector2(-4,8),Vector2(-8,8)])
				line([Vector2(-3,-5),Vector2(-2,0),Vector2(9,0)],1.2)
				if role == "general":
					closed_shape([Vector2(-3,-6),Vector2(-7,-14),Vector2(-2,-12),Vector2(2,-7)],INK)
	else:
		match role:
			"villager", "driver":
				for side in [-1,1]:
					var x := float(side)
					line([Vector2(x*2,-22),Vector2(x*6,-17),Vector2(x*5,-3),Vector2(x*1,-5)],1.1)
				line([Vector2(-5,-5),Vector2(5,-5)],1.1)
			"general", "knight":
				closed_shape([Vector2(-4,-23),Vector2(-8,-19),Vector2(-6,-5),Vector2(0,-2),Vector2(6,-5),Vector2(8,-19),Vector2(4,-23)])
				line([Vector2(-5,-16),Vector2(5,-16)])
				line([Vector2(-4,-8),Vector2(4,-8)])
				line([Vector2(0,-20),Vector2(0,-5)])
				if role == "general":
					line([Vector2(-7,-20),Vector2(-11,-17),Vector2(-9,5),Vector2(-4,1)],1.2)
					closed_shape([Vector2(2,-18),Vector2(3,-20),Vector2(4,-18),Vector2(6,-17),Vector2(4,-16),Vector2(3,-14),Vector2(2,-16),Vector2(0,-17)],INK)
			"king", "queen":
				closed_shape([Vector2(-4,-23),Vector2(-8,-19),Vector2(-7,-7),Vector2(-10,3),Vector2(0,6),Vector2(10,3),Vector2(7,-7),Vector2(8,-19),Vector2(4,-23)])
				line([Vector2(-4,-22),Vector2(-1,-16),Vector2(3,-22)])
				line([Vector2(-6,-5),Vector2(6,-5)])
				if role == "king":
					line([Vector2(-8,-18),Vector2(-11,-14),Vector2(-12,8),Vector2(-7,4)],1.2)
				else:
					for x in [-5,0,5]: line([Vector2(x,-3),Vector2(x*1.4,3)])
