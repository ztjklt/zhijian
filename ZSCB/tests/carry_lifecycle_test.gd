extends "res://tests/carry_drop_test.gd"

func assert_held(label: String) -> void:
	var index: int = game.carried_index()
	var body: RigidBody2D = game.object_nodes[index] if index >= 0 else null
	check(body != null and body.freeze and body.collision_layer == 0 and body.collision_mask == 0, label)

func run() -> void:
	await fresh(Vector2(0,2))
	var key: String = game.carried_id
	game.set_draw_mode(1)
	check(game.carried_id == key, "switching to drawing does not implicitly drop the object")
	assert_held("tool changes preserve carried collision suppression")
	# Continue from a real pickup even on the old failing tool branch.
	if game.carried_id == "": game.selected = 0; game.toggle_carry()
	game.toggle_bag()
	check(game.carried_id == key and game.bag_open, "opening blueprints preserves carrying")
	game.toggle_bag()
	game.experience.open()
	check(game.carried_id == key, "non-destructive personal panel preserves carrying")
	game.experience.close()
	await dispose()

	await fresh(Vector2(0,2))
	game.drop_carried()
	game.set_draw_mode(3)
	draw_block(Vector2(-2,2))
	game.set_draw_mode(4)
	game.selected = 0
	game.toggle_carry()
	key = game.carried_id
	var click: Vector2 = game.world_to_screen(Vector2(game.objects[1].x,game.objects[1].y))
	game.pointer_down(click); game.pointer_up(click)
	check(game.selected == 1, "another piece is selected through real pointer input")
	game.delete_selected()
	game._update_world_chunks()
	check(game.objects.size() == 1 and game.carried_id == key, "deleting a different piece retains carried identity")
	assert_held("rebuilt carried object still has disabled collision")
	game.selected = game.carried_index()
	game.delete_selected()
	check(game.carried_id == "" and game.carried_previous.is_empty(), "deleting the held piece clears transient carry state immediately")
	await dispose()

	await fresh(Vector2(0,2))
	game.drop_carried()
	game.objects[0].id = "different-wire-id"
	game.selected = 0
	game.toggle_carry()
	check(game.carried_id == "different-wire-id", "existing wire identity wins over a distinct structure key")
	game._rebuild_objects()
	game._update_object_activity()
	assert_held("same-key rebuild reapplies carry suppression")
	await finish()
