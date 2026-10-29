extends SceneTree
var failures: Array[String] = []
var count := 0
class Fixture extends Node2D:
	var PIXELS_PER_UNIT := 78.0
	func world_to_screen(p: Vector2) -> Vector2: return Vector2(p.x*PIXELS_PER_UNIT,600-p.y*PIXELS_PER_UNIT)
class Slope extends RefCounted:
	var gradient := 0.25
	func travel_height(x: float) -> float: return -2.8+gradient*(x-3)
class Holder extends Node2D:
	var entities: Array = []
	var terrain
	var game
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	count += 1
	if not ok: failures.append(label); push_error("MEDIEVAL PEOPLE: "+label)
func rig_resources(node: Node, prefix: String = "") -> Dictionary:
	var result := {}
	for child in node.get_children():
		var path := prefix+"/"+str(child.name)
		if child is Sprite2D: result[path] = [child.texture.resource_path if child.texture else "",child.scale]
		if child is Bone2D: result[path] = [child.rest,child.length,child.bone_angle]
		result.merge(rig_resources(child,path))
	return result
func verify_identity(visual, expected: Dictionary, label: String) -> void:
	check(visual != null,label+" uses original rig")
	if visual == null: return
	var actual := rig_resources(visual)
	for path in expected:
		if path.ends_with("Head/Ink"): continue
		check(actual.has(path) and actual[path] == expected[path],label+" original part "+path)
	var head = visual.get_node("Skeleton/Hips/Torso/Head/Ink")
	check(head.open_texture.resource_path == "res://assets/characters/stickman_gpt_v3/parts/head.tres",label+" exact hero head")
	check(visual.get_node("Skeleton") is Skeleton2D and visual.material == null,label+" original skeleton and ink")
	check(is_equal_approx(absf(visual.scale.x),1) and is_equal_approx(visual.scale.y,1),label+" same hero scale")
	for values in actual.values():
		check(not str(values).contains("assets/medieval/villager") and not str(values).contains("assets/medieval/driver"),label+" no legacy human frame")
func run() -> void:
	root.size=Vector2i(1440,900)
	var original = load("res://scenes/character.tscn").instantiate()
	var expected := rig_resources(original)
	original.free()
	var fixture := Fixture.new()
	root.add_child(fixture)
	var holder := Holder.new()
	holder.game = fixture
	fixture.add_child(holder)
	for kind in ["villager","driver","general","knight","queen","king"]:
		var entity := MedievalEntity.new()
		entity.setup(kind,Vector2(3,-2.8),kind+"-test",-2.8)
		if kind == "driver": entity.companion_id = "wagon-test"; entity.freeze = true
		entity.freeze = true # Rig/IK fixture has no floor; real actor physics is checked separately.
		holder.add_child(entity)
		await process_frame
		check(entity.texture == null and entity.reaction_texture == null,kind+" does not load retired art")
		check(not MedievalEntity.source_regions.has(kind),kind+" never crops legacy people frames")
		var visual = entity.get("person_visual")
		verify_identity(visual,expected,kind)
		if visual == null: entity.queue_free(); continue
		visual._process(0)
		check(visual.get_parent() == holder,kind+" screen rig outside metre transform")
		check(visual.position.is_equal_approx(fixture.world_to_screen(entity.position+Vector2(0,0.54))),kind+" hero center anchor")
		check(entity.size.y <= 1.15,kind+" original hero physics scale")
		check(entity.is_person() and entity.is_actor(),kind+" actor movement and damage")
		var hat = visual.get_node("Skeleton/Hips/Torso/Head/IdentityHat")
		check(hat.has_method("contact_point"),kind+" measured head contact")
		if hat.has_method("contact_point"):
			var head = visual.get_node("Skeleton/Hips/Torso/Head/Ink")
			var opaque: Rect2i = head.texture.get_image().get_used_rect()
			var expected_top: float = head.position.y+(opaque.position.y-head.texture.get_height()*0.5)*head.scale.y
			check(absf(hat.position.y-expected_top) < 0.7,kind+" brim touches actual Sprite alpha including offset")
		check(visual.get_node_or_null("Skeleton/Hips/Torso/Head/GentleEyes") != null,kind+" gentle local eyes")
		check(visual.get_node_or_null("Skeleton/Hips/Torso/Head/IdentityHat") != null,kind+" bone-bound hat")
		check(visual.get_node_or_null("CombatPose") == null,kind+" unarmed rig")
		if kind == "driver": check(absf(visual.get_node("Skeleton/Hips/FrontLeg").rotation) > 1, "seated driver bends original legs")
		if kind == "villager":
			entity.linear_velocity = Vector2(0.4,0)
			entity.state = "walk"
			visual._process(0.1)
			check(visual.current_pose == "walk", "villager reuses hero walk animation")
			entity.linear_velocity = Vector2.ZERO
			entity.state = "idle"
			visual._process(0.1)
			check(visual.current_pose == "idle", "stationary villager reuses hero idle animation")
		if kind == "driver": entity.detach_carriage(); entity.freeze = true
		holder.terrain = Slope.new()
		entity.linear_velocity = Vector2(0.4,0)
		for grade in [-0.25,0.25]:
			holder.terrain.gradient = grade
			for direction in [-1,1]:
				entity.facing = direction
				for cycle in 4:
					visual._process(0.1)
					for leg in ["FrontLeg","BackLeg"]:
						var foot = visual.get_node("Skeleton/Hips/"+leg+"/Shin/Foot")
						var contact: Vector2 = foot.to_global(Vector2(2.4,4.25))
						var world_x: float = contact.x/fixture.PIXELS_PER_UNIT
						var world_y: float = (600-contact.y)/fixture.PIXELS_PER_UNIT
						check(absf(world_y-holder.terrain.travel_height(world_x)) < 0.035,kind+" both original feet touch uphill/downhill in either direction")
					check(visual.rotation*grade < -0.007,kind+" grounded body leans with slope")
		holder.terrain = null
		entity.facing = 1
		if kind in ["king","queen"]:
			var walk := MedievalEntity.new()
			walk.setup("wall",Vector2(3,8.07-MedievalEntity.dimensions("wall").y),"castle-walk",0)
			holder.add_child(walk)
			holder.entities.append(walk)
			var high_roof := MedievalEntity.new()
			high_roof.setup("wall",Vector2(3,15.0-MedievalEntity.dimensions("wall").y),"castle-roof",0)
			holder.add_child(high_roof)
			holder.entities.append(high_roof)
			holder.terrain = Slope.new()
			entity.position.y = 8.07
			for cycle in 4:
				visual._process(0.1)
				for leg in ["FrontLeg","BackLeg"]:
					var foot = visual.get_node("Skeleton/Hips/"+leg+"/Shin/Foot")
					var contact: Vector2 = foot.to_global(Vector2(2.4,4.25))
					check(absf((600-contact.y)/fixture.PIXELS_PER_UNIT-8.07) < 0.035,kind+" feet rest on actual elevated castle walk, never distant roof")
			entity.position.y = 9.0
			visual._process(0.1)
			check(not is_equal_approx(visual.get_node("Skeleton/Hips").position.y,15),kind+" unsupported pose never reaches to distant platform")
			entity.position.y = 8.07
			entity.linear_velocity.y = 2
			visual._process(0.1)
			check(not is_equal_approx(visual.get_node("Skeleton/Hips").position.y,15),kind+" jumping pose does not receive foot IK")
			holder.entities.clear()
			walk.queue_free()
			high_roof.queue_free()
			holder.terrain = null
		entity.damage(5,entity.position,Vector2(-4,3))
		visual._process(0)
		check(entity.state == "hurt" and entity.linear_velocity.y > 0,kind+" physical knockup")
		check(kind != "driver" or entity.companion_id == "", "hurt driver detaches")
		var original_visual_id: int = visual.get_instance_id()
		entity.step(0.3)
		visual._process(0.1)
		check(entity.person_visual.get_instance_id() == original_visual_id,kind+" keeps exact rig while airborne")
		entity.damage(100,entity.position,Vector2(2,2))
		entity.step(0.7)
		visual._process(0)
		verify_identity(visual,expected,kind+" dead")
		check(entity.state == "dead" and absf(visual.rotation) > 1.4 and visual.modulate.a == 1,kind+" stable prone rig")
		var old_visual = weakref(visual)
		entity.queue_free()
		await process_frame
		await process_frame
		check(old_visual.get_ref() == null,kind+" cleans sibling visual")
	fixture.queue_free()
	await process_frame
	print("MEDIEVAL PEOPLE: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
