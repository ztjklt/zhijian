extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func run()->void:
	var world:=MedievalWorld.new();root.add_child(world);await physics_frame
	var trees:=0;var foliage:=0;var people:=0;var kinds:={}
	for entity in world.entities:
		kinds[entity.kind]=kinds.get(entity.kind,0)+1
		if entity.kind in ["oak","pine","orchard_tree"]:trees+=1
		if entity.kind in MedievalComposition.FOLIAGE:foliage+=1
		if entity.is_person():people+=1
	print("LIVING COUNTS: entities=",world.entities.size()," trees=",trees," foliage=",foliage," people=",people," kinds=",kinds)
	check(trees==6,"six intentionally spaced trees")
	check(foliage>=80 and foliage<=95,"foliage reduced about half")
	check(people>=30,"twelve more original-rig walkers")
	check(kinds.get("rabbit",0)==6 and kinds.get("deer",0)==4,"ten ground wildlife")
	check(kinds.get("bat",0)==4 and kinds.get("dragon",0)==3,"seven flying creatures")
	check(world.entities.size()<310,"less total scene clutter despite more life")
	check(world.terrain.surface_height(0)>8 and world.terrain.surface_height(180)>8,"both ends form high mountains")
	for interval in [[20.0,37.0],[40.0,54.0],[68.0,88.0],[108.0,128.0],[147.0,160.0],[164.0,179.0]]:
		check(absf(world.terrain.surface_height(interval[0])-world.terrain.surface_height(interval[1]))<.01,"building terrace remains level "+str(interval))
	check(world.terrain.has_method("upgrade_position"),"versioned position migration exists")
	if world.terrain.has_method("upgrade_position"):
		var legacy_at:=Vector2(8.2,1.2)
		var upgraded_at:Vector2=world.terrain.upgrade_position(legacy_at,2)
		check(absf((upgraded_at.y-world.travel_height(legacy_at.x))-(legacy_at.y-.04))<.001,"migration retains old elevation above exact version2 soil")
		check(world.terrain.upgrade_position(upgraded_at,3)==upgraded_at,"version3 positions never migrate twice")
	var walkers:={}
	for id in ["villager-107","villager-108","rabbit-0","rabbit-4","deer-0","deer-3","bat-0","dragon-2"]:
		var actor=world.entity_by_id(id)
		if actor!=null:walkers[id]=actor.position
	for tick in 150:
		world.step(1.0/60)
		await physics_frame
	for id in walkers:
		var actor=world.entity_by_id(id)
		print("ACTOR ",id," at ",actor.position," road ",world.travel_height(actor.position.x)," rotation ",actor.rotation," velocity ",actor.linear_velocity," support ",world.terrain.support_pose(actor.position.x,actor.size.x*.335,.05))
		check(actor.position.distance_to(walkers[id])>.4,"actual physics moves new actor "+id)
		if actor.is_person() or actor.is_ground_animal():check(absf(actor.position.y-world.travel_height(actor.position.x))<.3,"new ground actor follows mountain route "+id)
		else:check(actor.state=="fly" and actor.gravity_scale==0 and actor.position.y>world.travel_height(actor.position.x)+1.0,"flying creature remains airborne under real physics "+id)
	var state:Array=world.save_state()
	check(world.validate_state(state),"new default state validates")
	check(world.restore_state(state,3,3),"version3 state restores")
	check(JSON.stringify(state)==JSON.stringify(world.save_state()),"version3 state roundtrip exact")
	var old:Array=[]
	for item in [["oak",1,8.2],["pine",1,93.0],["orchard_tree",102,101.5]]:
		var body:=MedievalEntity.new();body.setup(item[0],Vector2(item[2],0),item[0]+"-"+str(item[1]),0)
		var record:Dictionary=body.save_record();body.free()
		if item[0]=="oak":record.health=0;record.alive=false;record.state="destroyed"
		if item[0]=="orchard_tree":record.health-=10;record.cuts=[{"x":0.0,"y":.5,"radius":.3,"side":0}]
		old.append(record)
	check(world.restore_state(old,2,2),"version2 decor migrates")
	check(world.entity_by_id("pine-1")==null,"pristine retired tree removed")
	check(world.entity_by_id("oak-1")!=null and not world.entity_by_id("oak-1").alive,"felled retired tree remains felled")
	check(world.entity_by_id("orchard_tree-102")!=null and world.entity_by_id("orchard_tree-102").cuts.size()==1,"retired damaged tree retains cuts")
	var migrated:Array=world.save_state()
	check(world.restore_state(migrated,3,3) and JSON.stringify(migrated)==JSON.stringify(world.save_state()),"migrated content roundtrip does not respawn retired trees")
	var full:Array=[]
	for i in 384:
		var record:Dictionary=old[0].duplicate(true);record.id="preserved-"+str(i);record.kind="barrel";full.append(record)
	check(world.restore_state(full,2,2) and world.entities.size()==384,"full damaged save retains all records within cap")
	world.queue_free();await process_frame
	print("LIVING WORLD: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
