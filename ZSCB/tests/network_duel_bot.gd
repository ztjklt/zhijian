extends SceneTree
var session: PaperNetSession
var role := ""
var folder := ""
var address := ""
var map_id := "paper"
var results: Dictionary = {}
var phase := "connecting"
var diagnostic_clock := 0.0
func _process(delta:float)->bool:
	diagnostic_clock+=delta
	if diagnostic_clock>=2 and session!=null and session.game!=null:
		diagnostic_clock=0
		var peer=session.remotes.values().front() if not session.remotes.is_empty() else null
		print("DUEL STATE ",role," phase=",phase," ready=",session.ready_to_play," focus=",session.focus_active," local_weapon=",not session.game.equipped_weapon.is_empty()," sent_weapon=",not session.sent_weapon.is_empty()," equip_wait=",session.equip_wait," peer_weapon=",peer!=null and not peer.equipped_weapon.is_empty()," self=",session.game.player.position," peer=",peer.player.position if peer!=null else Vector2.ZERO," hp=",session.game.combat.health," peer_hp=",peer.combat.health if peer!=null else -1," bow=",session.game.combat.is_bow()," charge=",session.game.combat.bow_charge," recoil=",session.game.combat.recoil," intent_cd=",session.combat_intent.cooldown," arrows=",session.game.combat.projectiles.size())
	return false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):role=arg.trim_prefix("--role=")
		elif arg.begins_with("--coord="):folder=arg.trim_prefix("--coord=")
		elif arg.begins_with("--map="):map_id=arg.trim_prefix("--map=")
		elif arg.begins_with("--address="):address=arg.trim_prefix("--address=")
	call_deferred("run")
func wait_until(condition:Callable,seconds:float=12)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return false
func mark(name:String,value:String="ok")->void:
	var file:=FileAccess.open(folder.path_join(name),FileAccess.WRITE);file.store_string(value);file.close()
func marked(name:String)->bool:return FileAccess.file_exists(folder.path_join(name))
func fail(label:String)->void:
	Input.action_release("move_right")
	mark(role+".failed",label);print("DUEL BOT FAIL ",role,": ",label," status=",session.status);quit(1)
func approach()->bool:
	var deadline:=Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline:
		var remote=session.remotes.values().front()
		var gap:float=remote.player.position.x-session.game.player.position.x
		if absf(gap)>=.5 and absf(gap)<=.8:return true
		var follow:bool=absf(gap)>.8
		var direction:String="move_right" if (gap>0)==follow else "move_left"
		Input.action_press(direction)
		await create_timer(minf(.08,maxf(.06,absf(absf(gap)-.65)/4.6))).timeout
		Input.action_release(direction)
		await create_timer(maxf(.7,session.round_trip_ms/1000.0*2.0+.25)).timeout
	return false
func aim_at_friend()->void:
	var remote=session.remotes.values().front()
	session.game.aim_world=remote.player.position+Vector2(0,.20)
func hit_friend()->void:
	var remote=session.remotes.values().front()
	session.game.aim_world=remote.player.position+Vector2(0,.15)
	session.game.attack()
func run()->void:
	session=PaperNetSession.new();root.add_child(session)
	session.operation_finished.connect(func(result):
		results[int(result.get("seq",0))]=result
		if result.get("op","") in ["attack","bow","equip"]:
			print("DUEL RECEIPT ",role," phase=",phase," at=",Time.get_ticks_msec()," seq=",result.get("seq",-1)," op=",result.get("op","")," ok=",result.get("ok",false)," started=",result.get("attack_started","n/a")," error=",result.get("error","")))
	if role=="owner":session.connect_room(address,"create","","甲",map_id)
	else:
		if not await wait_until(func():return marked("invite")):fail("missing invite");return
		session.connect_room(address,"join",FileAccess.get_file_as_string(folder.path_join("invite")),"乙",map_id)
	if not await wait_until(func():return session.ready_to_play):fail("not ready");return
	if role=="owner":mark("invite",session.code)
	if not await wait_until(func():return session.remotes.size()==1):fail("missing friend");return
	var game:PaperCastleMain=session.game
	phase="equipment"
	game.equipped_weapon=PaperWeaponGrip.practice_sword()
	if not await wait_until(func():return not session.sent_weapon.is_empty() and not session.remotes.values().front().equipped_weapon.is_empty()):fail("equipment not shared");return
	session._send({"type":"ping","stamp":Time.get_ticks_msec()})
	if not await wait_until(func():return session.round_trip_ms>=0):fail("ping calibration missing");return
	phase="wait first hit"
	if role=="guest":
		if not await wait_until(func():return game.combat.health<100):fail("sword did not hit guest");return
		print("DUEL guest received sword damage hp=",game.combat.health)
		if not await wait_until(func():return marked("first_hit")):fail("owner did not mark hit");return
		await create_timer(.8).timeout
		if not await approach():fail("guest cannot approach for retaliation");return
		hit_friend()
		if not await wait_until(func():return marked("return_hit")):fail("return strike missed owner");return
		game.active_stroke={"points":[game.player.position+Vector2(0,2),game.player.position+Vector2(1,2)]}
		if not await wait_until(func():return session.local_dead_time>0,30):fail("lethal damage not observed");return
		var died:=Time.get_ticks_msec()
		if game.character_visual.visible or game.active_stroke!=null or game.draft.size()!=1:fail("death visual or retained draft invalid");return
		mark("death_seen")
		if not await wait_until(func():return session.local_dead_time<=0 and game.combat.health==100,6):fail("not respawned");return
		var delay:=Time.get_ticks_msec()-died
		if delay<2600 or delay>4000 or session.local_protection<1.5:fail("respawn timing/protection invalid: "+str(delay));return
		if game.equipped_weapon.is_empty() or game.draft.size()!=1:fail("respawn lost equipment/draft");return
		print("DUEL guest respawned after ",delay,"ms with protection=",session.local_protection)
		mark("respawn_seen")
		if not await wait_until(func():return game.combat.health<100):fail("bow missed guest");return
		print("DUEL guest received bow damage hp=",game.combat.health)
		mark("bow_hit")
		if not await wait_until(func():return marked("cancelled_bow")):fail("blocked bow check missing");return
		var health:float=game.combat.health
		await create_timer(.7).timeout
		if game.combat.health!=health:fail("blocked charge fired after bag opened");return
		var old_game=game;var old_id:=session.player_id
		session.socket.close(1001,"duel reconnect test")
		if not await wait_until(func():return not session.ready_to_play,3):fail("disconnect not detected");return
		if not await wait_until(func():return session.ready_to_play,8):fail("credential reconnect failed");return
		if session.game!=old_game or session.player_id!=old_id or game.draft.size()!=1 or game.equipped_weapon.is_empty():fail("reconnect lost local/authority state");return
		print("DUEL guest credential reconnect retained identity, draft and sword")
		mark("guest.checked")
		if not await wait_until(func():return session.ended,15):fail("owner close not received");return
		quit()
	else:
		phase="approach friend"
		if not await approach():fail("movement did not approach friend");return
		phase="first attack"
		hit_friend()
		if not await wait_until(func():return session.remotes.values().front().combat.health<100):fail("sword missed friend");return
		print("DUEL owner sword hit confirmed")
		mark("first_hit")
		if not await wait_until(func():return game.combat.health<100):fail("guest sword missed owner");return
		print("DUEL owner received return strike hp=",game.combat.health)
		mark("return_hit")
		for attack in 6:
			await create_timer(.9).timeout
			if not await approach():fail("owner cannot follow knocked-back friend");return
			hit_friend()
			if await wait_until(func():return marked("death_seen"),maxf(.4,session.round_trip_ms/1000.0+.2)):break
		if not marked("death_seen"):fail("sword sequence never killed friend");return
		if not await wait_until(func():return marked("respawn_seen"),6):fail("friend did not respawn");return
		await create_timer(2.1).timeout
		game.combat.toggle_bow()
		if not await wait_until(func():return game.combat.bow_equipped):fail("bow toggle not confirmed");return
		var remote=session.remotes.values().front()
		aim_at_friend()
		game.attack()
		if game.combat.bow_charge<=0:fail("Q then R before echo has no immediate bow pose");return
		print("DUEL owner Q then R displays immediate bow charge")
		if not await wait_until(func():return marked("bow_hit"),5):fail("actual bow failed to hurt friend");return
		await create_timer(.9).timeout
		aim_at_friend()
		game.attack()
		if not await wait_until(func():return game.combat.bow_charge>0):fail("second bow never charged");return
		# Cancel well into the locally visible windup, rather than in its first frame.
		# This still has to arrive before authority release under the delayed stream.
		await create_timer(.28).timeout
		if game.combat.bow_charge<=0:fail("bow pose expired before the cancellation window");return
		print("DUEL owner cancels visible charge remaining=",game.combat.bow_charge)
		game.toggle_bag()
		mark("cancelled_bow")
		await create_timer(.7).timeout
		game.toggle_bag()
		if not await wait_until(func():return marked("guest.checked"),12):fail("guest reconnect verification failed");return
		if not await wait_until(func():return session.remotes.values().front().connected):fail("owner did not observe friend reconnect");return
		phase="firearm to bow"
		# A real firearm shot followed by Q->R must inherit its .75s cooldown.
		var firearm:=PaperWeaponGrip.practice_sword();firearm.weapon_type="firearm"
		game.equipped_weapon=firearm
		if not await wait_until(func():return session.sent_weapon.get("weapon_type","")=="firearm" and not game.combat.bow_equipped):fail("firearm transition was not confirmed");return
		game.aim_world=game.player.position+(game.player.position-remote.player.position).normalized()*4
		game.attack();var firearm_seq:int=session.seq
		await create_timer(.1).timeout
		game.combat.toggle_bow();aim_at_friend();game.attack();var cooling_seq:int=session.seq
		if game.combat.bow_charge>0:fail("cooling firearm produced a false bow charge");return
		await create_timer(.66).timeout
		var health_before:float=remote.combat.health
		aim_at_friend()
		print("DUEL NEXT BOW at=",Time.get_ticks_msec()," self=",game.player.position," target=",remote.player.position," aim=",game.aim_world," hp=",health_before)
		game.attack();var bow_seq:int=session.seq
		if game.combat.bow_charge<=0:fail("bow pose missing after firearm cooldown");return
		if not await wait_until(func():return results.has(firearm_seq) and results.has(cooling_seq) and results.has(bow_seq),5):fail("firearm/bow receipts missing");return
		if not results[firearm_seq].get("attack_started",false) or results[cooling_seq].get("attack_started",true) or not results[bow_seq].get("attack_started",false):fail("authority firearm/bow cooldown decisions differ from actual requests");return
		if not await wait_until(func():return remote.combat.health<health_before,5):fail("bow after firearm cooldown never hit");return
		print("DUEL firearm -> bow inherited cooldown and next actual arrow confirmed")
		await create_timer(.2).timeout
		if DisplayServer.get_name()!="headless":
			var captures:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
			if captures!="":
				DirAccess.make_dir_recursive_absolute(captures)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(captures.path_join("duel-"+map_id+".png"))
		var number:=session.send_op("save")
		if not await wait_until(func():return results.has(number)) or not results[number].ok:fail("save not confirmed");return
		mark("world_id",session.world_id);mark("owner.checked")
		session.leave()
		if not await wait_until(func():return session.ended,5):fail("leave not confirmed");return
		quit()
