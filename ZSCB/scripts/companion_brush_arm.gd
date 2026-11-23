extends Node
## Aim the existing two arm bones; the brush and validation use their actual grip.
var actor
var upper: Bone2D
var lower: Bone2D

func _ready() -> void:
	process_priority = 12
	upper = actor.character_visual.get_node("Skeleton/Hips/Torso/FrontArm")
	lower = upper.get_node("Forearm")

func _process(_delta: float) -> void:
	if not actor.brush_target.is_finite(): return
	var visual = actor.character_visual
	var aim: Vector2 = visual.global_position + (actor.sandbox.world_to_screen(actor.brush_target) - actor.sandbox.world_to_screen(actor.player.position))
	var offset: Vector2 = upper.get_parent().to_local(aim) - upper.position
	if offset.length_squared()<0.01: return
	var upper_length := lower.position.length()
	var lower_length := (lower.get_node("Hand") as Node2D).position.length()
	var span := clampf(offset.length()*0.45, 11.0, upper_length+lower_length-1.5)
	var turn := acos(clampf((upper_length*upper_length+span*span-lower_length*lower_length)/(2.0*upper_length*span), -1.0, 1.0))
	var shoulder := offset.angle()+turn
	var wrist := offset.normalized()*span
	var elbow := Vector2.from_angle(shoulder)*upper_length
	upper.rotation = shoulder - PI*0.5
	lower.rotation = (wrist-elbow).angle() - shoulder
