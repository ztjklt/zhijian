extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func run()->void:
	var world:=MedievalWorld.new()
	root.add_child(world)
	await physics_frame
	# Samples are actual visible walk segments. The conservative edge envelope
	# uses less than the hero's 3.58m double-jump rise and 7m horizontal range.
	var points:Array[Vector2]=[]
	var owners:Array[String]=[]
	var reached:Array[bool]=[]
	for entity in world.entities:
		for edge in entity.world_walk_segments():
			for t in [0.05,0.5,0.95]:
				var point:Vector2=edge[0].lerp(edge[1],t)
				points.append(point);owners.append(entity.entity_id)
				reached.append(point.y-world.terrain.travel_height(point.x)<=3.1)
	for iteration in 16:
		var added:=false
		for index in points.size():
			if reached[index]:continue
			for source in points.size():
				if not reached[source]:continue
				var delta:Vector2=points[index]-points[source]
				if absf(delta.x)<=4.2 and delta.y<=2.9 and delta.y>=-6:
					reached[index]=true;added=true;break
		if not added:break
	var tops:Dictionary={}
	for i in points.size():
		if not tops.has(owners[i]) or points[i].y>points[tops[owners[i]]].y:tops[owners[i]]=i
	for entity in world.entities:
		if entity.kind not in ["oak","pine","house","market","castle_piece","orchard_tree","forge","tavern","windmill","watermill","ruin_arch"]:continue
		if not tops.has(entity.entity_id):continue
		check(reached[tops[entity.entity_id]],"highest visible landing reachable for "+entity.entity_id)
	# Continuous road is still the universal route, even after all roofs are cut.
	for i in 1800:
		var x:=float(i)/10
		check(absf(world.travel_height(x+0.1)-world.travel_height(x))<=0.121,"ground route has no abrupt inaccessible step at "+str(x))
	world.queue_free();await process_frame
	print("MEDIEVAL PRODUCT UPPER ROUTES: ",checks," checks, ",failures.size()," failures; ",points.size()," landing samples")
	quit(0 if failures.is_empty() else 1)
