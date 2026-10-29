extends SceneTree
## A freed surface RID must leave both temporary hero and permanent NPC ignores.
class FixtureWorld extends MedievalWorld:
	func _ready()->void: pass # Keep real re-entry handling, omit the full map.
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func surface_rids(house)->Array[RID]:
	var result:Array[RID]=[]
	for child in house.get_children():
		if child is StaticBody2D and child.has_meta("medieval_owner"):result.append(child.get_rid())
	return result
func exception_ids(actor)->Array[RID]:
	# The server's raw RID getter is not bound to GDScript in Godot4.6.3.
	# Its public body wrapper returns null for orphan RIDs and emits the exact
	# engine error this regression catches; retain null as an invalid RID.
	var result:Array[RID]=[]
	for body in actor.get_collision_exceptions():
		result.append(body.get_rid() if is_instance_valid(body) else RID())
	return result
func retained(actor,old:Array[RID])->Array[RID]:
	var result:Array[RID]=[]
	var current:=exception_ids(actor)
	for rid in current:
		if not rid.is_valid() or old.has(rid):result.append(rid)
	return result
func settle()->void:
	await process_frame
	await physics_frame
	await process_frame
func probes(player,label:String)->void:
	var supports:Array=player.support_bodies()
	check(not supports.is_empty(),label+" support rays still find real ground")
	var climb:=PaperWallClimb.new()
	check(not climb.step(player,1,1.0/60),label+" climb query remains callable without a wall")
func run()->void:
	var world:=FixtureWorld.new();root.add_child(world)
	var floor:=StaticBody2D.new();var fixture:=CollisionShape2D.new();var shape:=RectangleShape2D.new()
	shape.size=Vector2(20,.2);fixture.shape=shape;fixture.position=Vector2(0,-.1);floor.add_child(fixture);world.add_child(floor)
	var house:=MedievalEntity.new();house.setup("house",Vector2.ZERO,"lifecycle-house",0);world.add_child(house);world.entities.append(house)
	var npc:=MedievalEntity.new();npc.setup("villager",Vector2(-4,.04),"lifecycle-villager",0);world.add_child(npc);world.entities.append(npc)
	var player:=StickmanPlayer.new();player.position=Vector2(-2,.31);world.add_child(player)
	await physics_frame
	for i in 35:
		player.linear_velocity.x=1.5
		await physics_frame
	player.linear_velocity=Vector2.ZERO
	player.freeze=true
	var old:=surface_rids(house)
	print("BEFORE rebuild player=",exception_ids(player)," npc=",exception_ids(npc)," surfaces=",old)
	check(player.position.x>-1.3 and player.position.y<.5,"hero physically enters beneath the house")
	check(not retained(player,old).is_empty(),"underpass registers actual temporary surface exceptions")
	check(retained(npc,old).size()==old.size() and not old.is_empty(),"patrol registers permanent exceptions for every owned roof")
	house.rebuild_geometry()
	await settle()
	print("AFTER rebuild stale player=",retained(player,old)," stale npc=",retained(npc,old))
	check(retained(player,old).is_empty(),"rebuild removes every retired player exception RID")
	check(retained(npc,old).is_empty(),"rebuild removes every retired patrol exception RID")
	var replacement:=surface_rids(house)
	check(not replacement.is_empty() and retained(npc,replacement).size()==replacement.size(),"patrol ignores replacement surfaces after rebuild")
	check(not retained(player,replacement).is_empty(),"underpass reacquires replacement surface exceptions")
	probes(player,"after rebuild")
	var parked:=Node2D.new();root.add_child(parked)
	world.reparent(parked)
	await settle()
	check(retained(npc,replacement).size()==replacement.size(),"parked map restores every patrol exemption")
	check(not retained(player,replacement).is_empty(),"parked map restores temporary underpass exemptions")
	world.reparent(root)
	await settle()
	check(retained(npc,replacement).size()==replacement.size(),"returning map retains every patrol exemption")
	check(not retained(player,replacement).is_empty(),"returning map retains temporary underpass exemptions")
	world.entities.erase(house);world.remove_child(house);house.queue_free()
	await settle()
	print("AFTER removal player=",exception_ids(player)," npc=",exception_ids(npc))
	check(retained(player,replacement).is_empty(),"remove/free removes every remaining player surface RID")
	check(retained(npc,replacement).is_empty(),"remove/free removes every remaining patrol surface RID")
	check(exception_ids(player).is_empty(),"player exception list contains no orphan RID")
	check(exception_ids(npc).is_empty(),"patrol exception list contains no orphan RID")
	probes(player,"after removal")
	world.queue_free();await process_frame
	print("SURFACE LIFECYCLE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
