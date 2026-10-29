extends SceneTree
var failures: Array[String]=[]
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("TYPE ACK: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var session:=PaperNetSession.new();root.add_child(session)
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	game.set_physics_process(false);game.combat.set_natives(false)
	session.game=game;game.network_session=session;session.ready_to_play=true
	game.set_draw_mode(2)
	var draft: Array=[{"points":[Vector2.ZERO,Vector2(0,1.2)]}]
	game.draft=draft.duplicate(true)
	game.generate();game.select_weapon_grip(Vector2(0,.1));game.generate();game.select_weapon_type("firearm")
	var weapon:=PaperWeaponGrip.make_weapon(draft,Vector2(0,.1));weapon.weapon_type="firearm"
	session.equip_drawing(weapon)
	var number:int=session.pending.keys().front()
	for i in 128:BlueprintBag.add_entry(game.bag,PaperWeaponGrip.practice_sword())
	game.feedback.events.clear()
	session._result({"seq":number,"ok":true,"weapon":weapon})
	check(game.equipped_weapon.get("weapon_type","")=="firearm","server confirmed equipment remains truthful")
	check(game.draft==draft and game.selecting_weapon_type,"full bag at ACK keeps complete drawing and type stage")
	check(not game.feedback.events.any(func(e:Dictionary)->bool:return e.kind=="create"),"failed blueprint save never celebrates FORGED")
	check(game.toolbar.status_text.contains("未保存"),"capacity race explains that blueprint was not saved")
	BlueprintBag.remove_entry(game.bag,game.bag.entries.back().id)
	session.equip_drawing(weapon)
	check(session.pending.is_empty() and session.seq==number,"capacity retry archives locally without sending another equip")
	check(game.draft.is_empty() and not game.selecting_weapon_type,"retry after making room finishes original drawing")
	check(game.bag.entries.back().get("weapon_type","")=="firearm","retry preserves firearm type")
	game.queue_free();session.queue_free();await process_frame
	print("WEAPON TYPE ACK TESTS: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
