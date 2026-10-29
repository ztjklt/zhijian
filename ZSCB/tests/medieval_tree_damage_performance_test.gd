extends SceneTree
## Root fitting must not consume a complete 60 Hz frame on each axe hit.
func _init() -> void: call_deferred("run")

func run() -> void:
	var world := MedievalWorld.new()
	root.add_child(world)
	await physics_frame
	var failures: Array[String] = []
	for kind in ["oak","pine","orchard_tree"]:
		var tree = world._spawn(kind,5,250)
		world._place_ground_prop(tree)
		var start := Time.get_ticks_usec()
		for i in 12:
			var at: Vector2 = tree.to_global(tree.art_to_local(Vector2(0,.4)))
			tree.damage(1,at,Vector2.ZERO)
		var ms := float(Time.get_ticks_usec()-start)/12000.0
		print("TREE HIT ",kind," mean_cpu_ms=",snappedf(ms,.001))
		if ms>12: failures.append(kind)
		world.entities.erase(tree)
		world.remove_child(tree)
		tree.queue_free()
	world.queue_free()
	await process_frame
	print("TREE DAMAGE PERFORMANCE: 3 checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
