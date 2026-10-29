extends SceneTree
var failures: Array=[]
func _init() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func run() -> void:
	var game=load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	await process_frame
	var world=game.knowledge_world
	game.combat.set_natives(false)
	var has_blocks:=false
	for property in world.get_property_list():
		if property.name=="semantic_blocks":has_blocks=true
	check(has_blocks,"map exposes complete semantic textbook groups")
	if not has_blocks:quit(1);return
	var expected: Dictionary={
		"autumn":{"title":"天净沙·秋思","author":"马致远","lines":["枯藤老树昏鸦，","小桥流水人家，","古道西风瘦马。","夕阳西下，","断肠人在天涯。"]},
		"spring":{"title":"春望","author":"杜甫","lines":["国破山河在，城春草木深。","感时花溅泪，恨别鸟惊心。","烽火连三月，家书抵万金。","白头搔更短，浑欲不胜簪。"]}}
	for id in expected:
		var found: Dictionary={}
		for block in world.semantic_blocks:
			if block.id==id:found=block;break
		check(not found.is_empty(),"full poem exists: "+id)
		if found.is_empty():continue
		check(found.title==expected[id].title and found.author==expected[id].author and found.lines==expected[id].lines,"accurate complete text and attribution: "+id)
		var actual: Array=[]
		var previous_y: float=INF
		var aligned:=true
		for row in world.text_rows:
			if row.group_id!=id or row.role!="body":continue
			actual.append(row.text)
			aligned=aligned and is_equal_approx(row.p.x,found.bounds.position.x) and row.p.y<previous_y and found.bounds.encloses(Rect2(row.p,Vector2(row.w,row.h)))
			previous_y=row.p.y
		check(actual==expected[id].lines and aligned,"all poem lines rendered once, ordered, aligned and contained: "+id)
	var grouped:=true
	for entry in world.placements:
		var owner: Dictionary={}
		for block in world.semantic_blocks:
			if block.id==entry.group_id:owner=block;break
		grouped=grouped and not owner.is_empty()
		if not owner.is_empty():grouped=grouped and owner.bounds.encloses(Rect2(entry.p,Vector2(entry.w,entry.h)))
	check(grouped and world.placements.size()>12,"formulas and diagrams stay inside their knowledge group")
	var expected_owners: Dictionary={"math-pythagoras":"pythagoras","math-root":"pythagoras","shape-triangle":"pythagoras","math-equation":"equations","math-delta":"equations","shape-spring":"force","physics-force":"force","physics-energy":"force","graph-parabola":"quadratic","graph-sine":"periodic","chem-water":"reactions"}
	var corresponding:=true
	for entry in world.placements:
		if expected_owners.has(entry.id):corresponding=corresponding and entry.group_id==expected_owners[entry.id]
	check(corresponding,"related formulas and their corresponding diagrams share a topic")
	var horizontal:=true
	for tier in world.terrain_rects:
		var a: float=world.surface_height(tier.position.x+.2)
		var b: float=world.surface_height(tier.end.x-.2)
		horizontal=horizontal and is_equal_approx(a,b) and is_equal_approx(a,tier.end.y)
	check(horizontal and world.terrain_rects.size()>=6,"chapter terrain consists of aligned flat text tiers")
	await physics_frame
	var physical:=true
	for tier in world.terrain_rects:
		var x: float=tier.get_center().x
		game.knowledge_world.checkpoint=Vector2(x,tier.end.y+1)
		game.knowledge_world.respawn()
		world._update_chunks()
		await physics_frame
		var ray:=PhysicsRayQueryParameters2D.create(Vector2(x,tier.end.y+.08),Vector2(x,tier.end.y-.08),1)
		var hit: Dictionary=game.get_world_2d().direct_space_state.intersect_ray(ray)
		physical=physical and not hit.is_empty()
		if not hit.is_empty():physical=physical and absf(hit.position.y-tier.end.y)<.015
	check(physical,"actual solid collision matches the visible first text row cap")
	print("SEMANTIC LAYOUT: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
