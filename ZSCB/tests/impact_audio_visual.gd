extends SceneTree

func _init() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	var feedback = game.feedback
	if not "sound_banks" in feedback:
		push_error("Impact audio needs multiple real samples per cue")
		quit(1)
		return
	for kind in ["hit", "hurt", "break"]:
		var previous = null
		var heard := {}
		for index in range(18):
			feedback.emit_event(kind, game.player.position)
			var active: Array = feedback.voices.filter(func(voice): return voice.playing and feedback.sound_banks[kind].has(voice.stream))
			assert(active.size() == 1, "one active voice per impact type")
			assert(active[0].stream != previous, "consecutive impacts must use different recordings")
			assert(active[0].pitch_scale >= 0.94 and active[0].pitch_scale <= 1.06)
			previous = active[0].stream
			heard[previous.resource_path] = true
		assert(heard.size() >= 2, "repeated hits audibly vary")
		assert(feedback.sound_banks[kind].size() == 3, "three playable samples per impact type")
		print("IMPACT AUDIO PASS ", kind, ": 18 triggers, no consecutive repeated recording, one bounded voice")
	feedback.emit_event("create", game.player.position)
	assert(feedback.voices.any(func(voice): return voice.playing and voice.stream == feedback.sounds.create and voice.pitch_scale == 1.0), "creation chord retains original tuning")
	assert(feedback.voices.size() == 6 and feedback.events.size() <= feedback.MAX_EVENTS)
	game.queue_free()
	await process_frame
	print("IMPACT AUDIO VISUAL PASS: real playback variation and bounded voices")
	quit()
