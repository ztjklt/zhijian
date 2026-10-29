extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error("AUDIO PLAYBACK: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	AudioServer.set_bus_mute(0,true)
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.combat.set_natives(false);game.onboarding.dismiss()
	var fx=game.feedback;fx.set_process(false)
	check(DisplayServer.get_name()!="headless","actual audio player path is exercised")
	for key in PaperCombatAudio.KEYS:
		for voice in fx.voices:voice.stop()
		fx._play_cue(key,game.player.position)
		check(fx.voices.any(func(v):return v.playing and fx.sound_banks[key].has(v.stream)),"real player starts "+key)
		var first:int=fx.last_sound.get(key,-1)
		fx._play_cue(key,game.player.position)
		check(fx.last_sound.get(key,-1)!=first,"consecutive variants differ for "+key)
	for voice in fx.voices:voice.stop()
	fx._play_cue("death_horse",game.player.position+Vector2(25,0))
	check(not fx.voices.any(func(v):return v.playing),"remote death outside audible radius is silent")
	fx._play_cue("death_human_low",game.player.position)
	fx._play_cue("create",game.player.position)
	for i in 40:fx._play_cue("stroke",game.player.position)
	check(fx.voices.size()==10 and fx.voices.any(func(v):return v.playing and fx.sound_banks.death_human_low.has(v.stream)) and fx.voices.any(func(v):return v.playing and v.stream==fx.sounds.create),"bounded accents cannot steal death or creation tails")
	for voice in fx.voices:voice.stop()
	# A request refused by ten protected voices must not count as a played take.
	fx._play_cue("sword_hit",game.player.position)
	var played_take:int=fx.last_sound.sword_hit
	for voice in fx.voices:
		voice.stream=fx.sounds.create;voice.set_meta("priority",3);voice.play()
	fx._play_cue("sword_hit",game.player.position)
	check(fx.last_sound.sword_hit==played_take,"refused sound cannot advance the actual-played variant history")
	for voice in fx.voices:voice.stop()
	fx.audio_enabled=false;fx._play_cue("firearm_shoot",game.player.position)
	check(not fx.voices.any(func(v):return v.playing),"audio disable is respected")
	game.queue_free();await process_frame
	print("AUDIO PLAYBACK: 18 banks, no-repeat, 24m distance, 10 voice priority, mute; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
