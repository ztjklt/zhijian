extends SceneTree

var game
var failures: Array[String] = []
var assertions := 0
var obstacles: Array[StaticBody2D] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		push_error("WALL: "+label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func obstacle(center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = center
	var fixture := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	fixture.shape = shape
	body.add_child(fixture)
	game.add_child(body)
	obstacles.append(body)
	return body

func prepare(position: Vector2) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_down")
	Input.action_release("jump")
	Input.action_release("move_up")
	for body in obstacles: body.queue_free()
	obstacles.clear()
	game.player.reset_movement()
	game.wall_climb.reset(game.player)
	game.player.position = position
	game.player.linear_velocity = Vector2.ZERO
	await frames(15)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	# Keep this physics fixture independent of roaming combat and death/respawn.
	game.combat.set_natives(false)
	await frames(10)
	check(game.get("wall_climb") != null, "player has an automatic wall-climb controller")
	if game.get("wall_climb") == null:
		finish()
		return
	for direction in [1,-1]:
		await prepare(Vector2(-direction*0.65,game.GROUND_Y+0.4))
		obstacle(Vector2(direction*1.5,game.GROUND_Y+1),Vector2(3,2))
		await frames(3)
		Input.action_press("move_right" if direction==1 else "move_left")
		var reached := false
		var climbing_seen := false
		for i in 130:
			await physics_frame
			climbing_seen = climbing_seen or game.wall_climb.active
			if game.player.position.x*direction > 0.35 and game.player.position.y > game.GROUND_Y+2.27:
				reached = true
				break
		check(climbing_seen, "holding direction %d starts a wall climb"%direction)
		if not reached: print("LEDGE DEBUG ",direction," position=",game.player.position," velocity=",game.player.linear_velocity," active=",game.wall_climb.active," ledge=",game.wall_climb._ledge," has=",game.wall_climb._has_ledge)
		check(reached, "direction %d climbs and safely gets over a two-meter ledge"%direction)
	await prepare(Vector2(-0.65,game.GROUND_Y+0.4))
	obstacle(Vector2(0.5,game.GROUND_Y+2.5),Vector2(1,5))
	await frames(3)
	var start_y: float = game.player.position.y
	await frames(20)
	check(game.player.position.y < start_y+0.1, "standing beside a wall without input does not climb")
	Input.action_press("move_right")
	await frames(32)
	check(game.wall_climb.active and game.player.position.y > start_y+0.5, "tall wall climbs continuously instead of teleporting")
	Input.action_release("move_right")
	var release_y: float = game.player.position.y
	await frames(40)
	check(not game.wall_climb.active and game.player.gravity_scale == 1 and game.player.position.y < release_y-0.15, "releasing direction restores gravity and falls")
	Input.action_press("move_right")
	await frames(25)
	Input.action_press("move_down")
	await frames(10)
	check(not game.wall_climb.active and game.player.gravity_scale == 1, "down input overrides automatic climbing")
	Input.action_release("move_down")
	await frames(22)
	game.jumps_used = 2
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	if game.wall_climb.active or game.player.linear_velocity.y <= 6 or game.player.linear_velocity.x >= 0: print("JUMP DEBUG position=",game.player.position," velocity=",game.player.linear_velocity," active=",game.wall_climb.active," side=",game.wall_climb.side," used=",game.jumps_used)
	check(not game.wall_climb.active and game.player.linear_velocity.y > 6 and game.player.linear_velocity.x < 0, "space jumps away from the wall even after aerial jumps are used")
	await prepare(Vector2(-0.65,game.GROUND_Y+0.4))
	obstacle(Vector2(0.5,game.GROUND_Y+2.5),Vector2(1,5))
	await frames(3)
	Input.action_press("move_right")
	await frames(25)
	check(game.wall_climb.active, "W jump fixture is actually climbing before the input")
	Input.action_press("move_up")
	await frames(2)
	Input.action_release("move_up")
	check(not game.wall_climb.active and game.player.linear_velocity.y > 6 and game.player.linear_velocity.x < 0, "W jumps away from automatic wall climbing like space")
	await prepare(Vector2(-0.65,game.GROUND_Y+0.4))
	obstacle(Vector2(0.5,game.GROUND_Y+2),Vector2(1,4))
	obstacle(Vector2(-0.3,game.GROUND_Y+1.6),Vector2(1.6,0.2))
	await frames(3)
	Input.action_press("move_right")
	await frames(100)
	check(game.player.position.y < game.GROUND_Y+1.26, "climbing never phases through a low ceiling")
	await prepare(Vector2(-0.65,game.GROUND_Y+0.4))
	obstacle(Vector2(0.5,game.GROUND_Y+2.5),Vector2(1,5))
	await frames(3)
	Input.action_press("move_right")
	await frames(25)
	game.toggle_bag()
	await frames(3)
	check(not game.wall_climb.active and game.player.gravity_scale == 1, "opening the bag cannot leave the player hanging without gravity")
	game.toggle_bag()
	Input.action_release("move_right")
	finish()

func finish() -> void:
	print("WALL CLIMB: %d checks, %d failures"%[assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)
