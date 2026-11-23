extends "res://scripts/companion_actor.gd"

func _dress_actor() -> void:
	character_visual.pencil.self_modulate.a=0.0
	equipped_weapon=PaperWeaponGrip.practice_sword()
	var helm := Polygon2D.new()
	helm.color=Color("876140")
	helm.antialiased=true
	helm.polygon=PackedVector2Array([Vector2(-13,-5),Vector2(-9,-13),Vector2(7,-13),Vector2(15,-6),Vector2(9,-3),Vector2(-10,-3)])
	helm.z_index=2
	var head=character_visual.get_node_or_null("Skeleton/Hips/Torso/Head")
	if head!=null: head.add_child(helm)
	else: helm.free()
	var sash:=Polygon2D.new()
	sash.color=Color("854840")
	sash.antialiased=true
	sash.polygon=PackedVector2Array([Vector2(-7,-25),Vector2(-2,-26),Vector2(9,-8),Vector2(8,-4),Vector2(3,-5),Vector2(-7,-21)])
	sash.z_index=2
	character_visual.get_node("Skeleton/Hips/Torso").add_child(sash)
