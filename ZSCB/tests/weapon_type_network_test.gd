extends SceneTree
var failures: Array[String] = []
var count := 0
func check(ok: bool, label: String) -> void:
	count+=1
	if not ok: failures.append(label); push_error("TYPE NETWORK: "+label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var room=PaperNetRoom.new()
	room.configure("TYPES1","paper","types-owner",PaperWorldStore.new("user://types-room"),"types")
	root.add_child(room)
	var a: Dictionary=room.join("","甲"); var b: Dictionary=room.join("","乙")
	room.ready(a.player_id); room.ready(b.player_id)
	for i in 10: await physics_frame
	room.set_physics_process(false)
	var actor=room.actors[a.player_id]; var target=room.actors[b.player_id]
	var seq:=1
	for kind in ["sword","hammer","spear","bow","firearm"]:
		actor.ink.amount=300
		actor.combat.reset()
		var weapon:=PaperWeaponGrip.practice_sword(); weapon.weapon_type=kind
		var result: Dictionary=room.command(a.player_id,{"seq":seq,"op":"equip","weapon":weapon}); seq+=1
		check(result.ok and actor.equipped_weapon.get("weapon_type","")==kind,"authority equips "+kind)
		check(actor.state().weapon.get("weapon_type","")==kind,"replication includes "+kind)
		result=room.command(a.player_id,{"seq":seq,"op":"attack","direction":Vector2.RIGHT}); seq+=1
		check(result.ok,"authority attacks using "+kind)
		if kind=="bow": check(actor.combat.bow_charge>0 and actor.combat.swing==0,"authority custom bow charges")
		elif kind=="firearm": check(actor.combat.projectiles.size()==1 and actor.combat.projectiles[0].kind=="bullet","authority firearm creates bullet")
		elif kind=="hammer": check(actor.combat.motion_index==3 and actor.combat.swing>.6,"authority heavy strike timing")
		elif kind=="spear": check(actor.combat.motion_index==2,"authority spear thrust")
	# Real authority projectile arbitration: no hand-authored damage command.
	actor.player.position=Vector2(0,0); target.player.position=Vector2(2,0)
	actor.combat.projectiles=[]; target.combat.projectiles=[]
	target.combat.invulnerable=0; target.combat.health=100
	actor.combat.shoot_bullet(Vector2(0,.2),Vector2.RIGHT,"player")
	room._step_shared_arrows(.1)
	check(target.combat.health==72 and actor.combat.health==100,"bullet damages friend exactly once and cannot hit shooter")
	actor.combat.reset(); actor.equipped_weapon.weapon_type="bow"
	actor.combat.attack(Vector2.RIGHT)
	room.command(a.player_id,{"seq":seq,"op":"input","combat_blocked":true,"right":true}); seq+=1
	check(actor.combat.bow_charge==0,"type/grip modal input cancels authority custom bow")
	var bad: Dictionary=actor.equipped_weapon.duplicate(true); bad.weapon_type="laser"
	check(not room.command(a.player_id,{"seq":seq,"op":"equip","weapon":bad}).ok,"authority rejects unsupported type")
	room.queue_free(); await process_frame
	print("WEAPON TYPE NETWORK TESTS: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
