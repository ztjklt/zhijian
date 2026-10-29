extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("TEST: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(ResourceLoader.exists("res://scripts/onboarding.gd"), "first-play guidance exists")
	if ResourceLoader.exists("res://scripts/onboarding.gd"):
		var guide = load("res://scripts/onboarding.gd").new(false)
		check(guide.stage == 0 and guide.visible, "first session starts at drawing")
		guide.note_play(0.0)
		check(guide.stage == 0, "playing without a build does not complete the guide")
		guide.note_drawn()
		check(guide.stage == 1, "valid drawing advances to building")
		guide.note_built()
		check(guide.stage == 2, "successful building advances to play")
		guide.note_play(2.0)
		guide.note_movement(2.2)
		check(guide.stage == 3, "entering play still requires actual movement")
		guide.note_movement(3.0)
		check(guide.stage == 4, "moving through the world completes first play")
		guide.dismiss()
		guide.restart(false)
		check(guide.stage == 0 and guide.visible, "guidance can be replayed after dismissal")
		guide.restart(true)
		check(guide.stage == 2, "existing builds can start guidance at play")
	# Shape matching and prefab generation.
	var platform_strokes := [{"points": [Vector2(-2, 0), Vector2(2, 0)]}]
	var ranked := ShapeMatcher.rank(platform_strokes)
	check(ranked.error == "", "valid stroke should rank")
	check(ranked.ranked[0].id == "platform", "horizontal stroke should match platform")
	check(ShapeMatcher.make_prefab("ladder", {"width": 0.8, "height": 2.2}).size() == 7, "ladder prefab has rails and five rungs")

	# Blueprint lifecycle, filtering, favorite ordering, hotbar and reusable placement.
	var bag := BlueprintBag.new_bag()
	var wall := {"source": "library", "kind": "wall", "paths": ShapeMatcher.make_prefab("wall", {"width": 2.0, "height": 1.0})}
	var first := BlueprintBag.add_entry(bag, wall)
	var second := BlueprintBag.duplicate_entry(bag, first.entry.id)
	check(first.error == "" and second.error == "", "blueprints can be added and copied")
	second.entry.name = "最爱的墙"
	second.entry.favorite = true
	check(BlueprintBag.filter_entries(bag, "建筑", "最爱")[0].id == second.entry.id, "search/category finds renamed blueprint")
	check(BlueprintBag.bind_hotbar(bag, 5, second.entry.id), "sixth hotbar slot binds")
	var placed_a := BlueprintBag.make_object(second.entry, 1.0, 2.0)
	var placed_b := BlueprintBag.make_object(second.entry, 3.0, 4.0)
	check(placed_a.blueprint_id == placed_b.blueprint_id and bag.entries.size() == 2, "placement reuses blueprint without consuming it")
	check(BlueprintBag.remove_entry(bag, second.entry.id) and bag.hotbar[5] == 0, "deleting blueprint clears hotbar binding")

	var build_scene: PackedScene = load("res://scenes/build_object.tscn")
	var gate_body: RigidBody2D = build_scene.instantiate()
	gate_body.setup({"kind": "gate", "x": 0.0, "y": 0.0, "paths": ShapeMatcher.make_prefab("gate", {"width": 2.6, "height": 2.2}), "dynamic": true})
	check(gate_body.collision_layer == 8 and gate_body.collision_mask & 9 == 9, "gate and ladder bodies collide with ground and their own build-object layer")
	gate_body.free()

	# Save/load round trip and malformed save rejection.
	var save_result := SaveStore.save_game("draft", [placed_a], bag, 8.5, -4.0)
	check(save_result.ok, "save succeeds")
	var load_result := SaveStore.load_game()
	check(load_result.error == "", "saved game loads")
	check(load_result.data.objects.size() == 1 and load_result.data.bag.entries.size() == 1, "save preserves objects and blueprint bag")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))

	var legacy_file := FileAccess.open(SaveStore.SAVE_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"version": 1, "paper": "draft", "objects": []}))
	legacy_file.close()
	var legacy_result := SaveStore.load_game()
	check(legacy_result.error == "", "accepted v1 save loads")
	check(legacy_result.data.has("bag") and legacy_result.data.bag == BlueprintBag.new_bag(), "v1 save migrates a default blueprint bag")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))

	var malformed_file := FileAccess.open(SaveStore.SAVE_PATH, FileAccess.WRITE)
	malformed_file.store_string(JSON.stringify({"version": 1, "paper": "draft", "objects": [{"x": "not-a-number", "y": 0, "paths": []}]}))
	malformed_file.close()
	var malformed_result := SaveStore.load_game()
	check(malformed_result.error == "存档中的部件无效", "malformed numeric object field is rejected cleanly")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))

	# Main scene integration: resources, starter bag, canvas/UI/player and undo/redo.
	var scene: PackedScene = load("res://scenes/main.tscn")
	check(scene != null, "main scene loads")
	if scene:
		var game = scene.instantiate()
		root.add_child(game)
		await process_frame
		check(game.canvas_node != null and game.toolbar != null and game.backpack_panel != null and game.player != null, "main scene creates canvas, UI and player")
		check(game.has_node("CharacterVisual"), "player has a separate editable character rig")
		if game.has_node("CharacterVisual"):
			var visual = game.get_node("CharacterVisual")
			check(visual.get_node("Skeleton") is Skeleton2D, "character uses a real Godot skeleton")
			var head_art = visual.get_node("Skeleton/Hips/Torso/Head/Ink")
			check(head_art is Sprite2D, "generated character uses image components rather than primitive drawings")
			if head_art is Sprite2D:
				check(head_art.texture is AtlasTexture and head_art.texture.get_width() > 0, "generated head component imports as a usable texture")
			if head_art.has_method("set_blinking"):
				var face_size: Vector2 = head_art.texture.get_size() * head_art.scale
				head_art.set_blinking(true)
				check((head_art.texture.get_size() * head_art.scale).is_equal_approx(face_size), "blink keeps generated head dimensions stable")
				head_art.set_blinking(false)
			else:
				check(false, "blink keeps generated head dimensions stable")
			check(not visual.get_node("Skeleton/Hips/Torso/Head").get_autocalculate_length_and_angle(), "leaf bones have explicit lengths")
			var animation: AnimationPlayer = visual.get_node("AnimationPlayer")
			for clip in ["idle", "walk", "jump", "fall", "land", "climb", "draw"]:
				check(animation.has_animation(clip), "character has " + clip + " animation")
			check(visual.has_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip") and visual.has_node("Skeleton/Hips/Torso/BackArm/Forearm/Hand/WeaponGrip"), "both hands expose a bone-following weapon grip")
			animation.play("jump", 0)
			animation.advance(0.15)
			check(visual.get_node("Skeleton/Hips/Torso/FrontArm").rotation < -1.5, "jump animation actually raises the arm bone")
			animation.play("walk", 0)
			animation.advance(0)
			check(visual.get_node("Skeleton/Hips/Torso/FrontArm").rotation > 0.4, "walking uses a different animated arm pose")
			animation.play("idle", 0)
			# Guard readiness and foot contact must hold throughout the breathing loop.
			for beat in [0.0, 0.6, 1.2, 1.8, 2.39]:
				animation.seek(beat, true)
				animation.advance(0)
				var head: Vector2 = visual.to_local(head_art.global_position)
				var front_hand: Vector2 = visual.to_local(visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand").global_position)
				var rear_hand: Vector2 = visual.to_local(visual.get_node("Skeleton/Hips/Torso/BackArm/Forearm/Hand").global_position)
				check(front_hand.y < head.y + 12.0 and rear_hand.y < head.y + 12.0, "both fists stay raised in combat idle at " + str(beat))
				var front_ankle: Vector2 = visual.to_local(visual.get_node("Skeleton/Hips/FrontLeg/Shin/Foot").global_position)
				var rear_ankle: Vector2 = visual.to_local(visual.get_node("Skeleton/Hips/BackLeg/Shin/Foot").global_position)
				check(front_ankle.x - rear_ankle.x > 18.0, "combat feet are staggered at " + str(beat))
				check(absf(visual.get_node("Skeleton/Hips/FrontLeg/Shin").rotation) > 0.3 and absf(visual.get_node("Skeleton/Hips/BackLeg/Shin").rotation) > 0.3, "both combat knees remain flexed at " + str(beat))
				var front_sole: Sprite2D = visual.get_node("Skeleton/Hips/FrontLeg/Shin/Foot/Ink")
				var rear_sole: Sprite2D = visual.get_node("Skeleton/Hips/BackLeg/Shin/Foot/GuardInk")
				var front_bottom: Vector2 = visual.to_local(front_sole.to_global(front_sole.get_rect().end))
				var rear_bottom: Vector2 = visual.to_local(rear_sole.to_global(rear_sole.get_rect().end))
				check(absf(front_bottom.y - 23.14) < 0.8 and absf(rear_bottom.y - 23.21) < 0.8, "both soles stay planted while breathing at " + str(beat))

			animation.play("walk", 0)
			animation.advance(0)
			check(not visual.get_node("Skeleton/Hips/BackLeg/Shin/Foot/GuardInk").visible and visual.get_node("Skeleton/Hips/BackLeg/Shin/Foot/Ink").visible, "leaving guard restores normal walking foot artwork")
			check(is_zero_approx(visual.get_node("Skeleton/Hips/BackLeg/Shin/Foot").rotation), "leaving guard resets the foot rotation")
			animation.play("idle", 0)
		check(game.camera == null, "manual world-to-screen transform is the only camera architecture")
		game.camera_x = 0.0 # Explicit baseline: play mode may already have followed the player.
		game.camera_x = 0.0 # Realtime play already follows the character after the first frame.
		var probe_world := Vector2(3.0, 1.0)
		var probe_before: Vector2 = game.world_to_screen(probe_world)
		game.camera_x = 1.0
		var probe_after: Vector2 = game.world_to_screen(probe_world)
		check(is_equal_approx(probe_after.x - probe_before.x, -game.PIXELS_PER_UNIT), "camera pan is applied exactly once")
		check(game.screen_to_world(probe_after).is_equal_approx(probe_world), "screen/world transforms round trip after camera pan")
		game.camera_x = 0.0
		var foot_shape: CollisionShape2D = game.player.foot_sensor.get_child(0)
		check(foot_shape.position.y < 0.0, "foot sensor sits below the player in the upward-positive world")
		check(game.bag.entries.size() == 6 and game.bag.hotbar.size() == 6, "starter blueprints and six-slot hotbar exist")
		game.bag_open = true
		game.backpack_panel.visible = true
		game.backpack_panel.name_field.grab_focus()
		Input.action_press("toggle_bag")
		await physics_frame
		await physics_frame
		Input.action_release("toggle_bag")
		check(game.bag_open, "typing a B in a blueprint field does not close the bag")
		game.backpack_panel.name_field.release_focus()
		game.bag_open = false
		game.backpack_panel.visible = false
		game.onboarding.restart(false)
		check(game.player.collision_mask & 9 == 9, "player collides with ground and special gate/ladder build objects")
		game.land_timer = 0.0
		game.on_ground = false
		game.ground_contacts = 0
		game.player.linear_velocity = Vector2(0, -2.0)
		game.player._foot_entered(game.ground_chunks.values()[0])
		check(game.land_timer > 0.0, "downward landing triggers the procedural squash pose")

		# Drawing stays available while the stickman is moving in play mode.
		game.mode = "play"
		game.tool = "move"
		var draw_start: Vector2 = game.world_to_screen(Vector2(-1.0, 1.0))
		var draw_end: Vector2 = game.world_to_screen(Vector2(1.0, 1.0))
		game.pointer_down(draw_start)
		game.pointer_move(draw_end)
		game.pointer_up(draw_end)
		check(game.draft.size() == 1, "play mode accepts drawing even while the movement controller is active")
		check(game.onboarding.stage == 1, "guide observes a successful real drawing")
		game.solidify(draw_end)
		check(game.onboarding.stage == 2, "guide observes a successful real build")
		await physics_frame
		await physics_frame
		check(game.onboarding.stage == 3, "building in play mode advances to movement guidance")
		game.toolbar._show_help()
		await physics_frame
		await physics_frame
		check(game.onboarding.stage == 3, "replaying guidance in play mode matches the actual controls")
		check(game.draft.is_empty() and game.objects.size() == 1, "play-mode drawing can solidify without returning to build mode")
		var play_object: Dictionary = game.objects[0]
		var play_bounds := ShapeMatcher.bounds(play_object.paths)
		check(float(play_object.y) + float(play_bounds.min_y) >= game.GROUND_Y, "newly drawn object cannot spawn below the paper baseline")
		var play_body: RigidBody2D = game.object_nodes[0]
		for frame in range(90):
			await physics_frame
		var settled_bottom: float = play_body.position.y + float(play_bounds.min_y)
		check(settled_bottom >= game.GROUND_Y - 0.03, "drawn object settles on rather than through the paper baseline")
		game.objects.clear()
		game._rebuild_objects()
		game.selected = -1
		game.mode = "build"

		# Paper style and world state survive a real save/load cycle.
		game.paper = "textbook"
		check(game.save_game(), "main scene save succeeds")
		game.paper = "draft"
		game.load_game()
		check(game.paper == "textbook", "selected paper style survives save/load")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))

		# Original freehand strokes solidify into a reusable physical blueprint.
		var bag_before: int = game.bag.entries.size()
		game.draft = [
			{"points": [Vector2(-0.4, 0.0), Vector2(-0.4, 1.6)]},
			{"points": [Vector2(0.4, 0.0), Vector2(0.4, 1.6)]},
			{"points": [Vector2(-0.4, 0.5), Vector2(0.4, 0.5)]},
			{"points": [Vector2(-0.4, 1.0), Vector2(0.4, 1.0)]},
		]
		game.generator = "own"
		game.generate()
		check(game.objects.size() == 1 and game.objects[0].kind == "ladder", "freehand ladder solidifies as a physical ladder")
		check(game.bag.entries.size() == bag_before + 1, "solidified drawing is stored as a reusable blueprint")

		game.placing_blueprint_id = game.bag.entries[0].id
		game.place_blueprint(0.0, 1.5)
		var falling_body: RigidBody2D = game.object_nodes[0]
		var start_y: float = falling_body.position.y
		for frame in range(12):
			await physics_frame
		check(falling_body.position.y < start_y, "paper objects fall toward the paper ground")
		check(game.on_ground, "player foot sensor detects the ground in the upward-positive world")
		var before: Dictionary = game.snapshot()
		var object_count_before: int = game.objects.size()
		game.objects.append(placed_b)
		game.record(before)
		game.undo()
		check(game.objects.size() == object_count_before, "undo restores prior object state")
		game.redo()
		check(game.objects.size() == object_count_before + 1, "redo restores object state")

		# Up/space jump and slope traversal are part of the playable movement contract.
		game.mode = "play"
		game.on_ground = true
		game.ground_contacts = 1
		game.player.linear_velocity = Vector2.ZERO
		Input.action_press("move_up")
		await physics_frame
		Input.action_release("move_up")
		check(game.player.linear_velocity.y > 0.0, "up input jumps when grounded and not climbing")

		var slope := StaticBody2D.new()
		var slope_shape := CollisionShape2D.new()
		var slope_box := RectangleShape2D.new()
		slope_box.size = Vector2(2.15, 0.08)
		slope_shape.shape = slope_box
		slope_shape.rotation = atan2(0.8, 2.0)
		slope.add_child(slope_shape)
		slope.position = Vector2(-4.5, game.GROUND_Y + 0.4)
		slope.collision_layer = 1
		game.add_child(slope)
		game.player.position = Vector2(-5.35, game.GROUND_Y + 0.54)
		game.player.linear_velocity = Vector2.ZERO
		game.on_ground = true
		game.ground_contacts = 1
		await physics_frame
		var slope_start_y: float = game.player.position.y
		var slope_peak_y: float = slope_start_y
		Input.action_press("move_right")
		for frame in range(70):
			await physics_frame
			slope_peak_y = maxf(slope_peak_y, game.player.position.y)
		Input.action_release("move_right")
		check(game.player.position.x > -4.0 and slope_peak_y > slope_start_y + 0.2, "stickman walks up and over a physical slope")
		var old_size: Vector2i = root.size
		var old_scale: Vector2i = root.content_scale_size
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(960, 540)
		await process_frame
		await process_frame
		game.toolbar._layout()
		game.backpack_panel._layout()
		check(game.toolbar.header.get_global_rect().end.x <= 960.1, "header fits a 960-wide viewport")
		check(game.backpack_panel.get_global_rect().end.y <= 540.1, "bag fits a 540-high viewport with scrolling")
		var ground_screen: Vector2 = game.world_to_screen(Vector2(0, game.GROUND_Y))
		check(ground_screen.y + 24 < game.toolbar.bottom.position.y, "action dock leaves the ground visible")
		root.size = old_size
		root.content_scale_size = old_scale
		slope.queue_free()
		game.queue_free()

	if failures.is_empty():
		print("TESTS PASSED: ", assertions, " checks — drawing, guide, rig, layout, blueprints, save/load, physics, undo/redo")
		quit(0)
	else:
		print("TESTS FAILED: ", failures.size())
		quit(1)
