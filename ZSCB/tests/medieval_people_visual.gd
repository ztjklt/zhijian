extends SceneTree
class Fixture extends Node2D:
	var PIXELS_PER_UNIT := 78.0
	func world_to_screen(p: Vector2) -> Vector2: return Vector2(p.x*PIXELS_PER_UNIT,650-p.y*PIXELS_PER_UNIT)
class Slope extends RefCounted:
	func travel_height(x: float) -> float: return 0.25*x
class GroundLine extends Node2D:
	var points := PackedVector2Array()
	func _draw() -> void: draw_polyline(points,Color(0.12,0.1,0.08),3,true)
class Holder extends Node2D:
	var terrain
	var game
var roles := ["villager","driver","general","knight","queen","king"]
var models: Array = []
var labels: Array = []
func _init() -> void: call_deferred("run")
func title(text: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color(0.12,0.1,0.08))
	root.add_child(label)
	labels.append(label)
func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	DisplayServer.window_set_size(Vector2i(1580,850))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1580,850)
	await process_frame
	RenderingServer.set_default_clear_color(Color(0.96,0.945,0.9))
	var fixture := Fixture.new()
	root.add_child(fixture)
	var holder := Holder.new()
	holder.game = fixture
	fixture.add_child(holder)
	for i in roles.size():
		var actor := MedievalEntity.new()
		actor.setup(roles[i],Vector2(2+i,0),"lineup-"+roles[i],0)
		actor.freeze = true
		holder.add_child(actor)
		models.append(actor)
	await process_frame
	title("Original stickman role models | same head, limbs and skeleton",Vector2(35,24),26)
	for i in models.size():
		var visual = models[i].person_visual
		visual.set_process(false)
		visual._process(0)
		visual.position = Vector2(125+i*235,365)
		visual.scale = Vector2.ONE*4.0
		title(roles[i].capitalize(),Vector2(55+i*235,580),22)
	await capture("/tmp/medieval-roles-lineup.png")
	for label in labels: label.hide()
	title("Head closeups | hats anchored to visible head alpha",Vector2(35,24),26)
	for i in models.size():
		var visual = models[i].person_visual
		visual.scale = Vector2.ONE*7
		visual.position = Vector2(125+i*235,680)
		title(roles[i].capitalize(),Vector2(55+i*235,610),22)
	await capture("/tmp/medieval-roles-heads.png")
	for label in labels: label.hide()
	title("Same rig through walk, hurt, knockup, seated and prone",Vector2(35,24),26)
	var states := ["walk","hurt","fall","seated","dead","dead"]
	for i in models.size():
		var actor = models[i]
		var visual = actor.person_visual
		if i == 0: actor.linear_velocity.x = 0.4; actor.state = "walk"
		if i == 1 or i == 2: actor.damage(4,actor.position,Vector2(3,4))
		if i == 3: actor.kind = "driver"; actor.companion_id = "bench"
		if i > 3: actor.damage(100,actor.position,Vector2(3,2)); actor.step(0.7)
		visual._process(0.15)
		visual.position = Vector2(125+i*235,365)
		visual.scale = Vector2.ONE*3.8
		if i > 3: visual.position.y = 445
		title(roles[i].capitalize()+" / "+states[i],Vector2(30+i*235,580),20)
	await capture("/tmp/medieval-roles-states.png")
	for label in labels: label.hide()
	title("Grounded original legs: both soles follow the same rising terrain",Vector2(35,24),26)
	fixture.PIXELS_PER_UNIT = 240.0
	holder.terrain = Slope.new()
	var ground := GroundLine.new()
	for x in [0.0,6.5]: ground.points.append(fixture.world_to_screen(Vector2(x,holder.terrain.travel_height(x))))
	root.add_child(ground)
	for i in models.size():
		var actor = models[i]
		actor.alive = true
		actor.health = actor.max_health
		actor.hurt_timer = 0
		actor.state = "walk"
		actor.companion_id = ""
		actor.position = Vector2(0.55+i*0.98,holder.terrain.travel_height(0.55+i*0.98))
		actor.linear_velocity = Vector2(0.4,0)
		actor.person_visual._process(0.1+float(i)*0.05)
		title(roles[i].capitalize(),Vector2(25+i*235,740),20)
	await capture("/tmp/medieval-roles-slope.png")
	ground.queue_free()
	holder.queue_free()
	fixture.queue_free()
	await process_frame
	for label in labels: label.hide()
	var castle = load("res://scenes/medieval.tscn").instantiate()
	castle.onboarding.persist = false
	root.add_child(castle)
	castle.onboarding.dismiss()
	for i in 40: await physics_frame
	castle.player.freeze = true
	castle.set_physics_process(false)
	castle.PIXELS_PER_UNIT = 92.0
	castle.camera_x = 78.0
	castle.camera_y = 8.7
	castle.flip_timer = 0
	for actor in castle.medieval_world.entities:
		if actor.is_person(): actor.freeze = true
	castle.canvas_node.queue_redraw()
	await capture("/tmp/medieval-royals-wallwalk.png")
	castle.queue_free()
	await process_frame
	print("MEDIEVAL PEOPLE VISUAL: 5 screenshots captured")
	quit()
