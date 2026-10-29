extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL LAB NETWORK: ",label)
func run()->void:
	var room:=PaperNetRoom.new();room.configure("LAB01","paper","owner",PaperWorldStore.new("user://lab-network"),"lab");root.add_child(room);room.set_physics_process(false)
	var owner:Dictionary=room.join("","甲");var guest:Dictionary=room.join("","乙")
	room.ready(owner.player_id);room.ready(guest.player_id)
	var actor=room.actors[owner.player_id];var friend=room.actors[guest.player_id]
	friend.player.position=Vector2(-9,-2.515);PhysicsServer2D.body_set_state(friend.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,friend.player.transform)
	var command={"op":"weapon_lab","action":"start","distance":1.2,"seq":1}
	var started:Dictionary=room.command(owner.player_id,command)
	check(started.ok,"ready player can request an authoritative practice target")
	if not started.ok:room.queue_free();quit(1);return
	var lab=actor.weapon_lab;var generation:int=lab.generation
	room.command(owner.player_id,command)
	check(lab.generation==generation,"duplicate request cannot restart a test generation")
	check(room.command(guest.player_id,command).ok,"friend owns its separate target")
	var w=PaperWeaponGrip.practice_sword();w.weapon_type="firearm";actor.equipped_weapon=w
	room.command(owner.player_id,{"op":"attack","direction":Vector2.RIGHT,"seq":2});room._step_shared_arrows(.1)
	check(lab.current.hits==1 and lab.current.last==28 and friend.weapon_lab.current.hits==0,"shared projectile arbitration attributes the real hit only to shooter")
	check(not room.command(owner.player_id,{"op":"weapon_lab","action":"hit","score":999,"seq":3}).ok,"client cannot upload hits or scores")
	var point:Vector2=lab.position
	check(not room.command(owner.player_id,{"op":"weapon_lab","action":"start","position":Vector2(100,100),"distance":1.2,"seq":4}).ok and lab.position==point,"client cannot inject a target position")
	check(room.command(owner.player_id,{"op":"weapon_lab","action":"keep","seq":5}).ok and lab.baseline.hits==1,"authority preserves a measured baseline")
	var session:=PaperNetSession.new();root.add_child(session);session.player_id=owner.player_id;session.epoch=room.epoch;session.apply_snapshot(room.snapshot())
	var replica=session.game.weapon_lab
	check(replica.active and replica.current.hits==1 and replica.others.size()==1,"late join/resync contains both visible targets and own measured result")
	replica.hit({"generation":replica.generation,"key":replica.current.key},40,replica.position,Vector2.ZERO)
	check(replica.current.hits==1 and not replica.start(5).ok,"replica cannot score or relocate its target")
	actor.dead_time=3
	check(not room.command(owner.player_id,{"op":"weapon_lab","action":"start","distance":1.2,"seq":6}).ok,"dead players cannot operate a test station")
	actor.dead_time=0
	check(not room.command(owner.player_id,{"op":"weapon_lab","action":"start","distance":NAN,"seq":7}).ok,"nonfinite distance is rejected")
	actor.equipped_weapon=actor.equipped_weapon.duplicate(true);actor.equipped_weapon.weapon_type="bow"
	check(room.command(owner.player_id,{"op":"weapon_lab","action":"inspect","seq":8}).ok and lab.current.kind=="bow" and lab.current.hits==0,"opening comparison inspects the actual equipped design without starting a target")
	check(not room.snapshot().world.has("weapon_lab") and room._save().ok,"test scores never enter persistent shared world")
	check(room._import_world(actor,{"objects":[],"world":room.world.world_save_state()}).ok and not lab.active and lab.baseline.hits==1,"world replacement clears temporary target but retains session comparison")
	room.command(owner.player_id,{"op":"weapon_lab","action":"start","distance":1.2,"seq":9})
	room.disconnect_player(owner.player_id)
	check(not lab.active,"disconnect removes the temporary target and invalidates old shots")
	session.game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("WEAPON LAB NETWORK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
