extends SceneTree
## Exhaustive reference: pruning must not omit ink or change contact ordering.
var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func exhaustive(old: Array, current: Array, polygons: Array, origin: Vector2) -> Dictionary:
	var steps := clampi(ceili(PaperBladeSweep.motion_distance(old,current)/0.035),1,64)
	for sample in range(steps+1):
		var time := float(sample)/steps
		var paths := PaperBladeSweep.at_time(old,current,time)
		var reference := origin if origin.is_finite() else PaperBladeSweep.bounds(paths).get_center()
		var nearest := {}
		var distance := INF
		for polygon in polygons:
			for path in paths:
				for j in range(1,path.size()):
					var a: Vector2 = path[j-1]
					var b: Vector2 = path[j]
					var points := PackedVector2Array()
					if Geometry2D.is_point_in_polygon(a,polygon): points.append(a)
					if Geometry2D.is_point_in_polygon(b,polygon): points.append(b)
					var projected := Geometry2D.get_closest_point_to_segment(reference,a,b)
					if Geometry2D.is_point_in_polygon(projected,polygon): points.append(projected)
					for edge in polygon.size():
						var point = Geometry2D.segment_intersects_segment(a,b,polygon[edge],polygon[(edge+1)%polygon.size()])
						if point != null: points.append(point)
					for point in points:
						var candidate := reference.distance_squared_to(point)
						if candidate < distance:
							distance = candidate
							nearest = {"position":point,"time":time}
		if not nearest.is_empty(): return nearest
	return {}

func compare(world, old: Array, current: Array, origin: Vector2, label: String) -> void:
	var expected := exhaustive(old,current,world.terrain.collision_geometry,origin)
	var actual: Dictionary = world.blade_contact(old,current,origin)
	check(actual.is_empty()==expected.is_empty() and (actual.is_empty() or (is_equal_approx(actual.time,expected.time) and actual.position.distance_to(expected.position)<0.0001)),label)

func run() -> void:
	var world := MedievalWorld.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 241024
	for trial in 32:
		var x := rng.randf_range(0,100)
		var center := Vector2(x,world.terrain.surface_height(x)+rng.randf_range(0.1,2.5))
		var old: Array = []
		var current: Array = []
		for stroke in 2:
			var path := PackedVector2Array()
			var next := PackedVector2Array()
			for i in 5:
				var point := Vector2(rng.randf_range(-2.7,2.7),rng.randf_range(-2.7,2.7))
				path.append(center+point)
				next.append(center+point.rotated(0.5)+Vector2(-0.7,0.1))
			old.append(path)
			current.append(next)
		compare(world,old,current,center if trial%2==0 else Vector2.INF,"full contour / earliest time / nearest grip "+str(trial))
	var tangent: Array = [PackedVector2Array([Vector2(-2,-2.8),Vector2(0,-2.8)])]
	compare(world,tangent,tangent,Vector2(-1,-2.8),"tangent and zero-height segment bounds remain solid")
	var across: Array = [PackedVector2Array([Vector2(55,-1),Vector2(63,-1)])]
	compare(world,[],across,Vector2(55,-1),"missing previous paths use current geometry")
	compare(world,[PackedVector2Array([Vector2.ZERO])],across,Vector2(55,-1),"changed vertex count uses current geometry")
	world.free()
	print("LARGE WEAPON CONTACT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
