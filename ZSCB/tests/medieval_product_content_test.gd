extends SceneTree
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label);print("FAIL: ",label)
func run() -> void:
	var world:=MedievalWorld.new()
	root.add_child(world)
	await physics_frame
	check(world.LENGTH==180.0,"world expands to 180 metres")
	check(world.SECTIONS.size()==9,"nine distinct exploration districts")
	check(world.entities.size()>=240 and world.entities.size()<=384,"bounded full scene population")
	var kinds:={}
	var foliage:=0
	for entity in world.entities:
		kinds[entity.kind]=true
		if entity.kind in ["grass_meadow","grass_tall","reeds","wildflowers","bush","wheat"]:foliage+=1
	check(kinds.size()>=37,"22 new independent scene kinds")
	check(foliage>=80 and foliage<=95,"authored clustered foliage population")
	check(world.terrain.surface_height(134)<world.terrain.travel_height(134)-1.5,"mill river has real bed under traversable crossing")
	check(world.terrain.surface_height(172)>world.terrain.surface_height(152)+3.0,"abbey and border have distinct elevation")
	var state:Array=world.save_state()
	check(world.validate_state(state),"full default population validates for save")
	check(world.restore_state(state,3,3),"new snapshot restores")
	check(JSON.stringify(state)==JSON.stringify(world.save_state()),"new snapshot roundtrip exact")
	for record in MedievalComposition.records():
		if not record.has("stack_on"):continue
		var upper=world.entity_by_id(record.id)
		var lower=world.entity_by_id(record.stack_on)
		check(upper.position.distance_to(lower.to_global(Vector2(0,lower.size.y)))<0.001 and absf(upper.rotation-lower.rotation)<0.001,"stacked crate uses actual transformed lower top "+record.id)
	var old:Array=state.filter(func(record):return record.kind not in ["castle_piece"] and int(str(record.id).get_slice("-",1))<100)
	var old_house:Dictionary=old.filter(func(record):return record.id=="house-0")[0]
	old_house.health=0;old_house.alive=false;old_house.state="destroyed"
	var old_barrel:Dictionary=old.filter(func(record):return record.id=="barrel-0")[0]
	old_barrel.cuts=[{"x":0.0,"y":0.4,"radius":0.3,"side":0}]
	var legacy_wall:=MedievalEntity.new()
	legacy_wall.setup("wall",Vector2(72,3.4),"wall-0",3.4)
	old.append(legacy_wall.save_record());legacy_wall.free()
	check(world.restore_state(old,2,1),"legacy content can seed expansion")
	check(not world.entity_by_id("house-0").alive and world.entity_by_id("barrel-0").cuts.size()==1,"legacy original deaths and cuts remain")
	check(world.entity_by_id("windmill-100")!=null and world.entity_by_id("villager-106")!=null,"new districts seed with unique stable identities")
	check(world.entities.filter(func(entity):return entity.kind=="castle_piece").is_empty(),"legacy modular castle not overwritten by new atlas castle")
	var planted=world.entity_by_id("grass_meadow-100")
	world.damage_entity(planted,999,planted.position,Vector2.ZERO)
	var migrated:Array=world.save_state()
	check(world.restore_state(migrated,3,3) and JSON.stringify(migrated)==JSON.stringify(world.save_state()),"version3 exact migration roundtrip retains cut foliage")
	check(not world.entity_by_id("grass_meadow-100").alive,"saved dead new foliage never respawns")
	for x in [5.0,14.0,38.0,66.0,94.0,105.5,127.5,143.0,162.0]:
		var pose:Dictionary=world.terrain.prop_pose(x,0.5)
		var minimum:=INF
		for i in 21:
			var contact:Vector2=Vector2(x,pose.position_y)+Vector2(-0.5+float(i)/20.0,0).rotated(pose.rotation)
			minimum=minf(minimum,contact.y-world.terrain.travel_height(contact.x))
		check(minimum>=-0.015 and minimum<0.015,"real full prop bottom rests on terrain at "+str(x))
	check(not world.restore_state(state,2,1),"oversized version1 input cannot overflow migration budget")
	check(JSON.stringify(migrated)==JSON.stringify(world.save_state()),"rejected migration leaves live world intact")
	var maximum_legacy:Array=old.duplicate(true)
	while maximum_legacy.size()<96:
		var record:Dictionary=old_barrel.duplicate(true)
		record.id="legacy-extra-"+str(maximum_legacy.size())
		maximum_legacy.append(record)
	check(world.restore_state(maximum_legacy,2,1) and world.entities.size()<=384 and world.entities.size()>280,"maximum valid legacy content preserves originals and seeds bounded new life")
	print("Population ",state.size()," kinds ",kinds.size()," foliage ",foliage)
	world.queue_free();await process_frame
	print("MEDIEVAL PRODUCT CONTENT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
