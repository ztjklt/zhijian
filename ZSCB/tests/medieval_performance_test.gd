extends SceneTree
## Actual medieval map, with a legal complex sword: run in an isolated copy.
var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("MEDIEVAL PERFORMANCE: " + label)

func sample(world, center: Vector2, name: String, expect_hit: bool) -> void:
	var before := PackedVector2Array()
	var current := PackedVector2Array()
	for i in 96:
		before.append(center+Vector2(cos(i*0.31)*1.3,sin(i*0.31)*1.3))
		current.append(center+Vector2(1+cos(i*0.31+0.4)*1.3,sin(i*0.31+0.4)*1.3))
	var start := Time.get_ticks_usec()
	var contact := {}
	for i in 5: contact = world.blade_contact([before],[current],center)
	var average_ms := (Time.get_ticks_usec()-start)/5000.0
	print("MEDIEVAL PERF ",name," 96-point sweep avg_ms=",snappedf(average_ms,0.001))
	check(contact.is_empty() != expect_hit,name+" retains actual contact outcome")
	# Generous deterministic CPU-only budget; the unpruned empty-air regression
	# takes around 187 ms per call on this machine, freezing ordinary swings.
	check(average_ms < 25.0,name+" complex sweep remains below 25 ms")

func run() -> void:
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await physics_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.onboarding.dismiss()
	sample(game.medieval_world,Vector2(74,5.0),"castle_contact",true)
	sample(game.medieval_world,Vector2(1,28),"empty_air",false)
	game.queue_free()
	await process_frame
	print("MEDIEVAL PERFORMANCE TESTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
