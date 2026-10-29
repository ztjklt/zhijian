@tool
extends Node2D

@export_enum("torso", "head", "arm", "forearm", "thigh", "shin", "hand", "shoe", "scarf", "pencil") var part := "arm"
@export var back := false
const INK := Color("30333b")
const PAPER := Color("fffaf0")

func _ready() -> void:
	set_process(part == "head" and not Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _stroke(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(a, b, color, width, true)
	draw_circle(a, width * 0.5, color)
	draw_circle(b, width * 0.5, color)

func _shape(points: PackedVector2Array, fill: Color, width: float = 1.8) -> void:
	draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, INK, width, true)

func _draw() -> void:
	var ink := Color("63646a") if back else INK
	match part:
		"torso":
			_stroke(Vector2(0, -20), Vector2(0, -1), 7.0, INK)
			_stroke(Vector2(-3, 0), Vector2(3, 0), 5.5, INK)
		"head":
			_shape(PackedVector2Array([Vector2(-12,-5),Vector2(-11,-12),Vector2(-5,-17),Vector2(4,-17),Vector2(11,-13),Vector2(14,-6),Vector2(12,2),Vector2(7,8),Vector2(-2,9),Vector2(-10,4)]), PAPER, 2.4)
			# A folded paper cap and warm cheek give the small silhouette a clear identity.
			_shape(PackedVector2Array([Vector2(-12,-12),Vector2(-1,-23),Vector2(13,-13)]), Color("e7e0cc"), 1.6)
			draw_line(Vector2(-1,-23),Vector2(1,-13),Color("a8a28f"),1.0,true)
			var blink := fmod(Time.get_ticks_msec() * 0.001, 4.1) > 3.95
			for x in [1.0, 8.0]:
				if blink:
					draw_line(Vector2(x-1,-4),Vector2(x+1,-4),INK,1.3,true)
				else:
					draw_circle(Vector2(x,-4),1.5,INK)
			draw_circle(Vector2(9,0),2.2,Color(0.79,0.40,0.29,0.25))
			draw_arc(Vector2(4,-1),4.0,0.3,1.7,10,INK,1.1,true)
		"arm", "forearm":
			_stroke(Vector2.ZERO,Vector2(0,12 if part == "arm" else 11),4.0 if back else 4.5,ink)
		"thigh", "shin":
			_stroke(Vector2.ZERO,Vector2(0,12 if part == "thigh" else 10),5.2 if part == "thigh" else 4.1,ink)
		"hand":
			draw_circle(Vector2.ZERO,3.1,ink)
			draw_circle(Vector2(2,-1),1.8,ink)
		"shoe":
			_shape(PackedVector2Array([Vector2(-3,-2),Vector2(2,-2),Vector2(7,1),Vector2(7,3),Vector2(-4,3)]),ink,1.0)
			draw_line(Vector2(-3,2),Vector2(6,2),Color("a4a19b"),0.8,true)
		"scarf":
			_shape(PackedVector2Array([Vector2(-2,0),Vector2(-17,5),Vector2(-13,9),Vector2(-17,13),Vector2(0,5)]),Color("b9754f"),1.0)
			_stroke(Vector2(-4,-1),Vector2(4,-1),4.3,Color("cd9366"))
		"pencil":
			_stroke(Vector2(0,5),Vector2(0,-10),3.2,Color("c7924a"))
			_shape(PackedVector2Array([Vector2(-1.8,-10),Vector2(1.8,-10),Vector2(0,-16)]),Color("e4cba5"),0.7)
