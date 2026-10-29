extends "res://tests/large_weapon_contact_test.gd"
func run()->void:
	var world:=MedievalWorld.new()
	check(world.has_method("_swept_segment_may_touch"),"moving segments have a conservative polygon rejection before temporal sampling")
	if not world.has_method("_swept_segment_may_touch"):world.free();print("MEDIEVAL SWEEP BOUNDS: ",checks," checks, ",failures.size()," failures");quit(1);return
	var triangle:=PackedVector2Array([Vector2(0,0),Vector2(2,0),Vector2(2,2)])
	var above:=PackedVector2Array([Vector2(.2,1.3),Vector2(.3,1.4),Vector2(.3,1.5),Vector2(.4,1.6)])
	check(PaperBladeSweep.bounds([above]).intersects(PaperBladeSweep.bounds([triangle]),true),"disjoint fixture overlaps the polygon's broad box")
	check(not world._swept_segment_may_touch(above,triangle),"separated swept ink is rejected even inside the broad box")
	for points in [PackedVector2Array([Vector2(0,0),Vector2(1,1),Vector2(0,0),Vector2(1,1)]),PackedVector2Array([Vector2(2,2),Vector2(2,2),Vector2(2,2),Vector2(2,2)])]:
		check(world._swept_segment_may_touch(points,triangle),"tangent/degenerate swept material is never pruned")
	# Starts left of the target, then crosses it: >4 samples and no t=0 hit
	# guarantee blade_contact reaches its delayed conservative-pruning branch.
	var delayed_polygon:=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	var delayed_old:Array=[PackedVector2Array([Vector2(-1,.2),Vector2(-1,.8)])]
	var delayed_current:Array=[PackedVector2Array([Vector2(.5,.2),Vector2(.5,.8)])]
	world.terrain.collision_geometry=[delayed_polygon]
	var delayed:=exhaustive(delayed_old,delayed_current,[delayed_polygon],Vector2.ZERO)
	check(not delayed.is_empty() and delayed.time>0 and ceili(PaperBladeSweep.motion_distance(delayed_old,delayed_current)/.035)>4,"delayed contact fixture reaches temporal pruning with a nondegenerate hull")
	compare(world,delayed_old,delayed_current,Vector2.ZERO,"temporal pruning preserves earliest delayed contact")
	var rng:=RandomNumberGenerator.new();rng.seed=300600
	for trial in 64:
		var offset:=Vector2(rng.randf_range(-5,180),rng.randf_range(-10,26))
		var polygon:=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(.1,.1),Vector2(-1,1)])
		for i in polygon.size():polygon[i]+=offset
		world.terrain.collision_geometry=[polygon]
		var old:Array=[];var current:Array=[]
		for path_index in 2:
			var path:=PackedVector2Array();var moved:=PackedVector2Array()
			for i in 4:
				var point:=offset+Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
				path.append(point);moved.append(point+Vector2(rng.randf_range(-.6,.6),rng.randf_range(-.6,.6)))
			old.append(path);current.append(moved)
		compare(world,old,current,offset if trial%2 else Vector2.INF,"unchanged exhaustive concave/time/grip result "+str(trial))
	# Long strokes straddle several batch boundaries and first touch only
	# after sample zero. Both sloped and concave solids use oblique rejection.
	for trial in 16:
		var offset:=Vector2(rng.randf_range(-5,180),rng.randf_range(-10,26))
		var polygon:=PackedVector2Array([Vector2(0,2),Vector2(3,.2),Vector2(3,-3),Vector2(0,-3)])
		if trial%2:polygon=PackedVector2Array([Vector2(0,2),Vector2(1,.5),Vector2(2,1.2),Vector2(3,.2),Vector2(3,-3),Vector2(0,-3)])
		for i in polygon.size():polygon[i]+=offset
		world.terrain.collision_geometry=[polygon,polygon.duplicate()]
		var old:Array=[];var current:Array=[]
		for stroke in 2:
			var before:=PackedVector2Array();var after:=PackedVector2Array()
			for vertex in 34:
				var angle:=TAU*vertex/33.0
				var point:=Vector2(cos(angle),sin(angle)*.8)+Vector2(stroke*.01,0)
				before.append(offset+point+Vector2(1.5,4))
				after.append(offset+point.rotated(.3)+Vector2(1.8,-.5))
			old.append(before);current.append(after)
		var expected:=exhaustive(old,current,world.terrain.collision_geometry,offset+Vector2(-2,2))
		check(not expected.is_empty() and expected.time>0,"multi-batch oblique fixture has actual delayed contact "+str(trial))
		compare(world,old,current,offset+Vector2(-2,2),"multi-batch sloped/concave nearest order "+str(trial))
		if trial==0:
			compare(world,[],current,offset,"multi-batch missing old paths retain current geometry")
			old[0].remove_at(0)
			compare(world,old,current,offset,"multi-batch changed path length retains current geometry")
	world.free();print("MEDIEVAL SWEEP BOUNDS: ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
