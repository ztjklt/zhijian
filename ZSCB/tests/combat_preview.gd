extends SceneTree

class RigContext extends RefCounted:
	var equipped_weapon: Dictionary = {}
	var PIXELS_PER_UNIT := 84.0
	var combat = null
	var player = null
	var facing := 1

func _init() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	root.title = "纸上城堡 · 战斗与握持效果"
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	game.onboarding.dismiss()
	for frame in range(45): await physics_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.land_timer = 0
	game.flip_timer = 0
	game.pose = "idle"
	game.camera_x = game.player.position.x + 1.8
	game.set_draw_mode(2)
	var origin: Vector2 = game.player.position + Vector2(2.6, 0.8)
	var samples := [
		[Vector2(0, 0), Vector2(0, 0.45)],
		[Vector2(-0.22, 0.4), Vector2(0.22, 0.4)],
		[Vector2(-0.1, 0.45), Vector2(-0.1, 1.45), Vector2(0, 1.7), Vector2(0.1, 1.45), Vector2(0.1, 0.45), Vector2(-0.1, 0.45)],
	]
	for sample in samples:
		var points: Array = []
		for point in sample: points.append(origin + point)
		game.draft.append({"points": points})
	game.generate()
	var chosen := origin + Vector2(0, 0.22)
	game.pointer_move(game.world_to_screen(chosen))
	await capture("/tmp/paper-castle-grip-selection.png")
	game.pointer_down(game.world_to_screen(chosen))
	game.pointer_up(game.world_to_screen(chosen))
	game.generate()
	await capture("/tmp/paper-castle-grip-equipped.png")
	var weapon: Dictionary = game.equipped_weapon.duplicate(true)
	game.queue_free()
	await process_frame
	root.size = Vector2i(1280, 510)
	var backdrop := ColorRect.new()
	backdrop.color = Color("faf7eb")
	backdrop.size = Vector2(1280, 510)
	root.add_child(backdrop)
	var title := Label.new()
	title.text = "纸上城堡 · 战斗待机与手绘武器握持"
	title.position = Vector2(32, 22)
	title.add_theme_color_override("font_color", Color("303941"))
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)
	var rigs: Array = []
	var contexts: Array = []
	var labels := ["抬手护架", "呼吸蓄力", "选定握点 · 手绘武器", "转身 · 握点跟随"]
	for i in range(4):
		var rig = load("res://scenes/character.tscn").instantiate()
		rig.set_process(false)
		root.add_child(rig)
		rig.position = Vector2(125 + i * 320, 325)
		rig.scale = Vector2(-2.8 if i == 3 else 2.8, 2.8)
		var context := RigContext.new()
		if i >= 2: context.equipped_weapon = weapon
		context.facing = -1 if i == 3 else 1
		rig.game = context
		rig.set_process(false)
		contexts.append(context)
		var animator: AnimationPlayer = rig.get_node("AnimationPlayer")
		animator.play("idle", 0)
		animator.seek(i * 0.6, true)
		animator.advance(0)
		animator.pause()
		rigs.append(rig)
		var caption := Label.new()
		caption.text = labels[i]
		caption.position = Vector2(i * 320, 428)
		caption.size.x = 320
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_color", Color("66746b"))
		caption.add_theme_font_size_override("font_size", 18)
		root.add_child(caption)
	await capture("/tmp/paper-castle-combat-hero.png")
	# Native animation frames, encoded separately for a compact in-chat preview.
	DirAccess.make_dir_recursive_absolute("/tmp/paper-castle-combat-frames")
	for frame in range(29):
		for i in range(rigs.size()):
			var animator: AnimationPlayer = rigs[i].get_node("AnimationPlayer")
			animator.seek(float(frame) / 12.0 + i * 0.3, true)
			animator.advance(0)
		await capture("/tmp/paper-castle-combat-frames/%03d.png" % frame)
	print("COMBAT PREVIEW COMPLETE")
	quit()
