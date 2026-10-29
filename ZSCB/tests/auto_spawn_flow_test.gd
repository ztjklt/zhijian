extends SceneTree

var checks := 0
var failures: Array[String] = []
var game

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("AUTO SPAWN FLOW: " + label)

func strokes() -> Array:
	return [{"points": [Vector2(9.5,3.5), Vector2(10.5,3.5), Vector2(10.5,4.5), Vector2(9.5,4.5), Vector2(9.5,3.5)]}]

func verify_created(label: String) -> void:
	check(game.objects.size() == 1, label + " creates exactly one body despite enclosing obstruction")
	if game.objects.is_empty(): return
	var body: RigidBody2D = game.object_nodes[0]
	check(body.get_meta("spawn_adjusted", false), label + " records automatic relocation")
	var offset: Vector2 = body.get_meta("spawn_offset", Vector2.ZERO)
	check(offset.length() > 12, label + " accepts nearest exit beyond the old search and input range")
	check(body.position.distance_to(Vector2(game.objects[0].x,game.objects[0].y)) < 0.001, label + " saves the actual translated body position")
	check(game.draft.is_empty(), label + " consumes draft only after successful generation")
	check(game._spawn_notice(body,"完成").contains("最近安全空位"), label + " explains automatic relocation")

func clear_created() -> void:
	for body in game.object_nodes: body.queue_free()
	game.object_nodes.clear()
	game.objects.clear()
	await physics_frame
	await physics_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.combat.set_natives(false)
	game.player.freeze = true
	game.player.position = Vector2(9,4)
	var block := StaticBody2D.new()
	block.position = Vector2(10,4)
	block.collision_layer = 8
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(30,30)
	shape.shape = rectangle
	block.add_child(shape)
	game.add_child(block)
	await physics_frame
	await physics_frame
	game.set_draw_mode(1)
	game.generator = "own"
	game.draft = strokes()
	game.generate()
	verify_created("free drawing")
	var blueprint_id: int = game.selected_blueprint_id
	await clear_created()
	game.placing_blueprint_id = blueprint_id
	game.place_blueprint(10,4)
	verify_created("blueprint reuse")
	check(game.placing_blueprint_id == -1,"successful distant automatic placement ends blueprint placement")
	await clear_created()
	var frozen := DrawingRules.building(strokes(),"freehand")
	frozen.dynamic = false
	var frozen_entry := BlueprintBag.add_entry(game.bag,frozen)
	game.placing_blueprint_id = frozen_entry.entry.id
	game.place_blueprint(10,4)
	verify_created("legacy frozen blueprint reuse")
	if not game.object_nodes.is_empty():
		check(game.object_nodes[0].freeze,"automatic clearance preserves a legacy blueprint's fixed behavior")
	await clear_created()
	game.set_draw_mode(3)
	game.draft = strokes()
	game.release_building()
	verify_created("building")
	await clear_created()
	game.set_draw_mode(1)
	game.generator = "library"
	game.draft = strokes()
	game.generate()
	game.confirm_candidate()
	verify_created("library candidate")
	await clear_created()
	game.set_draw_mode(5)
	game.draft = strokes()
	game.confirm_sculpt()
	verify_created("sculpt")
	await clear_created()
	block.queue_free()
	await physics_frame
	await physics_frame
	game.player.position = Vector2(0,game.GROUND_Y+.31)
	var original := Vector2(0,game.GROUND_Y+1)
	var tall := {"kind":"freehand","dynamic":true,"x":original.x,"y":original.y,
		"paths":[{"points":[Vector2(-.5,-20),Vector2(.5,-20),Vector2(.5,20),Vector2(-.5,20),Vector2(-.5,-20)]}]}
	var tall_body: RigidBody2D = game._drop_candidate(tall)
	check(tall_body!=null,"manual range uses requested pose before automatic soil clearance of a tall drawing")
	if tall_body!=null:
		check(tall_body.get_meta("spawn_offset",Vector2.ZERO).distance_to(tall_body.position-original)<.001,"automatic offset is measured from original drawn pose, including soil adjustment")
		tall_body.free()
	game.queue_free()
	await process_frame
	await verify_authority()
	print("AUTO SPAWN FLOW: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func verify_authority() -> void:
	var room := PaperNetRoom.new()
	room.configure("AUTO","paper","owner-auto",PaperWorldStore.new("user://auto_spawn_room"),"auto")
	root.add_child(room)
	var owner: Dictionary = room.join("","画家")
	room.ready(owner.player_id)
	var actor = room.actors[owner.player_id]
	actor.player.freeze = true
	actor.set_physics_process(false)
	var target := Vector2(actor.player.position.x, 0)
	var block := StaticBody2D.new()
	block.position = target
	block.collision_layer = 8
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(30,30)
	shape.shape = rectangle
	block.add_child(shape)
	room.world.add_child(block)
	await physics_frame
	await physics_frame
	var result: Dictionary = room.command(owner.player_id,{"op":"spawn","seq":1,"object":{
		"kind":"freehand","dynamic":true,"x":target.x,"y":target.y,
		"paths":[{"points":[Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5),Vector2(-.5,-.5)],"collision":true}]}})
	check(result.ok,"authority accepts blocked creation and finds a distant safe exit")
	if result.ok:
		var actual := Vector2(result.object.x,result.object.y)
		check(actual.distance_to(target)>12,"authority does not reject the automatically adjusted position at original range boundary")
		check(room.world.objects.size()==1 and room.world.object_nodes[0].position.distance_to(actual)<.001,"authority broadcasts and stores the actual translated pose")
		var repeat: Dictionary = room.command(owner.player_id,{"op":"spawn","seq":1,"object":{}})
		check(repeat.ok and repeat.id==result.id and room.world.objects.size()==1,"repeated network confirmation does not duplicate relocated creation")
	room.queue_free()
	await process_frame
