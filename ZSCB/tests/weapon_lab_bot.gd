extends "res://tests/network_duel_bot.gd"
func run()->void:
	session=PaperNetSession.new();root.add_child(session)
	session.operation_finished.connect(func(result):
		results[int(result.get("seq",0))]=result
		if result.get("op")=="attack":print("LAB ATTACK RECEIPT ",role," ok=",result.get("ok")," started=",result.get("attack_started")))
	if role=="owner":session.connect_room(address,"create","","试打甲","paper")
	else:
		if not await wait_until(func():return marked("invite")):fail("missing invite");return
		session.connect_room(address,"join",FileAccess.get_file_as_string(folder.path_join("invite")),"试打乙","paper")
	if not await wait_until(func():return session.ready_to_play):fail("not ready");return
	if role=="owner":mark("invite",session.code)
	if not await wait_until(func():return session.remotes.size()==1):fail("partner missing");return
	var game=session.game;var lab=game.weapon_lab
	phase="move apart"
	Input.action_press("move_left" if role=="owner" else "move_right")
	await create_timer(.6).timeout
	Input.action_release("move_left" if role=="owner" else "move_right")
	await create_timer(.6).timeout
	var w=PaperWeaponGrip.practice_sword();w.weapon_type="firearm";game.equipped_weapon=w
	if not await wait_until(func():return session.sent_weapon.get("weapon_type")=="firearm"):fail("firearm not confirmed");return
	phase="place and fire"
	game.weapon_lab_action({"action":"start","distance":1.2})
	if not await wait_until(func():return lab.active and lab.current.get("kind")=="firearm"):fail("target not confirmed");return
	game.aim_world=lab.position;game.attack()
	if not await wait_until(func():return lab.current.get("hits",0)==1):fail("actual firearm missed near cursor target");return
	if lab.current.last!=28 or lab.others.size()!=1:fail("bad measured result or missing partner target");return
	game.weapon_lab_action({"action":"keep"})
	if not await wait_until(func():return lab.baseline.get("hits",0)==1):fail("baseline not retained");return
	phase="copy and re-equip"
	var before:Dictionary=game.equipped_weapon.duplicate(true)
	if not game.refine_weapon() or game.equipped_weapon!=before or game.draft.size()!=before.paths.size():fail("copy lost source/equipment");return
	game.generate();game.select_weapon_grip(game.draft[0].points[0]);game.generate();game.select_weapon_type("bow");game.generate()
	if not await wait_until(func():return game.draft.is_empty() and session.sent_weapon.get("weapon_type")=="bow" and not session.equip_wait):fail("normal grip/type/equip flow failed");return
	if not await wait_until(func():return lab.current.get("kind")=="bow" and lab.current.get("hits",-1)==0):fail("new design reused gun scores");return
	print("LAB BOW BEFORE ",role," intent_cooldown=",session.combat_intent.cooldown," charge=",game.combat.bow_charge," ink=",game.ink.amount)
	if not await wait_until(func():return session.combat_intent.cooldown<=0):fail("prior weapon cooldown did not expire");return
	await create_timer(.2).timeout
	game.aim_world=lab.position;game.attack()
	if not await wait_until(func():return lab.current.get("hits",0)==1,8):fail("actual reworked bow missed cursor target");return
	if lab.current.last!=24 or lab.baseline.kind!="firearm" or lab.baseline.last!=28:fail("comparison attribution invalid");return
	print("WEAPON LAB CLIENT ",role," gun28/bow24 measured, original model copied through grip/type/equip, baseline retained")
	mark(role+".lab")
	if not await wait_until(func():return marked("owner.lab") and marked("guest.lab")):fail("partner did not complete");return
	if role=="owner":
		var number:=session.send_op("save")
		if not await wait_until(func():return results.has(number)) or not results[number].ok:fail("save failed");return
		mark("world_id",session.world_id);mark("owner.checked");session.leave()
		if not await wait_until(func():return session.ended):fail("close failed");return
	else:
		mark("guest.checked")
		if not await wait_until(func():return session.ended):fail("owner close missing");return
	quit()
