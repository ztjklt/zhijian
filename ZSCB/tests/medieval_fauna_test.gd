extends SceneTree
const Entity := preload("res://scripts/medieval_entity.gd")
const Catalog := preload("res://scripts/medieval_catalog.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); print("FAIL: ",label)

class Habitat extends Node2D:
	var game = null
	var entities: Array = []
	var terrain := MedievalTerrain.new()

func run() -> void:
	check(Entity.supported_kind("rabbit") and Entity.supported_kind("deer") and Entity.supported_kind("bat"),"all three new fauna are supported physical actors")
	if not failures.is_empty():
		print("FAUNA: ",checks," checks, ",failures.size()," failures")
		quit(1)
		return
	var habitat := Habitat.new()
	root.add_child(habitat)
	for kind in ["rabbit","deer","bat"]:
		var animal = Entity.new()
		animal.setup(kind,Vector2(5,5),"fauna-test-"+kind,0)
		habitat.entities.append(animal)
		habitat.add_child(animal)
		check(animal.is_actor() and not animal.freeze and animal.collision_layer==64 and animal.collision_mask==9,kind+" uses combat actor layer and real rigid-body physics")
		check(animal.call("is_ground_animal")== (kind!="bat"),kind+" exposes locomotion category")
		check(animal.texture!=null and Entity.source_regions[kind].size()==8,kind+" loads eight generated frames")
		check(animal.get_child_count()>0,kind+" has physical fixtures")
		var prior := Vector2.ZERO
		for frame in 8:
			var draw: Dictionary = animal.raster_actor_frame_draw(frame)
			var scale: Vector2=draw.rect.size/draw.source.size
			check(absf(scale.x-scale.y)<.00001,kind+" all frames preserve source pixel aspect")
			check(draw.rect.has_area() and (kind=="bat" or absf(draw.rect.get_center().x)<.001),kind+" preserves pivot and positive draw dimensions")
			if prior!=Vector2.ZERO: check(scale.is_equal_approx(prior),kind+" never pumps pixel scale between atlas frames")
			prior=scale
		var origin: Vector2 = animal.position
		for tick in 120: animal.step(1.0/60.0)
		check(animal.linear_velocity.length()>.1,kind+" actively patrols without needing rendering")
		check(absf(animal.position.x-origin.x)<.01,kind+" movement is left to rigid-body integration")
		animal.damage(1,animal.position,Vector2(3,4))
		check(animal.state=="hurt" and animal.frame_index()==4 and animal.linear_velocity.x>1,kind+" hurt pose and physical impulse")
		var impulse: Vector2=animal.linear_velocity
		animal.step(.1)
		check(animal.linear_velocity.is_equal_approx(impulse),kind+" hurt timer prevents patrol overriding knockback")
		animal.damage(1000,animal.position,Vector2(2,3))
		check(not animal.alive and animal.state=="fall" and animal.frame_index()==5,kind+" fatal blow selects actual falling frame")
		animal.step(.7)
		check(animal.gravity_scale>0 and animal.state=="dead" and animal.frame_index()==6,kind+" falls under gravity and selects downed art")
		animal.queue_free()
	await process_frame
	habitat.queue_free()
	await process_frame
	print("FAUNA: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
