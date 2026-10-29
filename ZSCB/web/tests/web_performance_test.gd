extends SceneTree
var checks:=0
var failures:Array[String]=[]
class ScannedWorld extends MedievalWorld:
	var scanned:=0
	func entity_by_id(id:String):
		for entity in entities:
			scanned+=1
			if entity.entity_id==id:return entity
		return null
class FixtureEntity extends Node2D:
	var entity_id:=""
	var health:=100.0
	var alive:=true
	var state:="idle"
	var facing:=1
	var cuts:Array=[]
	func rebuild_geometry()->void:pass
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var metrics=load("res://web_metrics.gd")
	check(metrics.has_method("frame_limit"),"Web renderer has explicit foreground/background frame budgets")
	if metrics.has_method("frame_limit"):
		check(metrics.frame_limit(true)==60 and metrics.frame_limit(false)==20,"frame-budget policy selects 60 for foreground and 20 for background")
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);current_scene=game;game.combat.set_natives(false)
	var session=PaperNetSession.new();root.add_child(session);session.game=game;game.network_session=session
	session.is_owner=true;session.ready_to_play=true;session.epoch="perf";session.set_process(false)
	game.set_physics_process(false);game.canvas_node.hide()
	var panel=load("res://scripts/net/online_panel.gd").new();panel.session=session;session.flow_ui=panel;game.add_child(panel)
	for i in 5:await process_frame
	var resizes:={"count":0}
	panel.panel.resized.connect(func():resizes.count+=1)
	for i in 12:
		panel._process(0);await process_frame
	check(resizes.count<=2,"stable room HUD avoids repeated resize/layout work (resizes=%d)" % resizes.count)
	panel.menu.show()
	for i in 4:await process_frame
	var open_height:float=panel.panel.size.y;panel.menu.hide()
	for i in 4:await process_frame
	check(panel.panel.size.y<open_height,"room menu still shrinks after closing")
	panel.show_invite()
	for i in 5:await process_frame
	var dialog_resizes:={"count":0}
	panel.invite_dialog.panel.resized.connect(func():dialog_resizes.count+=1)
	for i in 12:await process_frame
	check(dialog_resizes.count<=2,"static invitation avoids repeated resize/layout (resizes=%d)" % dialog_resizes.count)
	panel.invite_dialog.hide();panel.invite_dialog.confirmed.emit()
	# Tool buttons never inspect weapon geometry; a large equipped drawing must not
	# be stringified merely to decide whether the toolbar changed.
	var points:Array=[]
	for i in 5000:points.append(Vector2(i*.001,sin(i*.01)))
	game.equipped_weapon={"paths":[{"points":points}],"role":"weapon"}
	var toolbar_start:=Time.get_ticks_usec()
	for i in 120:game.toolbar.update_buttons()
	print("TOOLBAR: 120 updates with 5000 points, ",(Time.get_ticks_usec()-toolbar_start)/1000.0," ms; state chars ",game.toolbar.last_state.length())
	check(game.toolbar.last_state.length()<2048,"toolbar change detection stays bounded with complex weapons")
	game.equipped_weapon={}
	var world:=ScannedWorld.new();world.game=game;game.medieval_world=world
	var records:Array=[]
	for i in 300:
		var entity:=FixtureEntity.new();entity.entity_id="fixture-%d" % i;world.entities.append(entity)
		records.append({"id":entity.entity_id,"x":i+1,"y":0,"health":90,"alive":true,"state":"idle","facing":1,"cuts":[]})
	records.append({"id":"missing","x":0,"y":0,"health":90,"alive":true,"state":"idle","facing":1,"cuts":[]})
	var start:=Time.get_ticks_usec()
	for i in 60:session.apply_frame({"epoch":"perf","tick":i,"entities":records})
	var cost:=(Time.get_ticks_usec()-start)/1000.0
	check(world.scanned<=300*60*3,"entity update work scales linearly rather than repeated full scans (scans=%d)" % world.scanned)
	check(world.entities[299].position.x==300 and world.entities[0].health==90,"large frame updates actual entity states and tolerates missing IDs")
	records[0].x=999
	session.apply_frame({"epoch":"old","tick":1000,"entities":records})
	session.apply_frame({"epoch":"perf","tick":59,"entities":records})
	check(world.entities[0].position.x==1,"epoch and stale tick protections remain intact")
	print("FRAME APPLY: 60 x 300 entities, ",cost," ms; HUD resizes ",resizes.count)
	game.medieval_world=null
	for entity in world.entities:entity.free()
	world.free();game.network_session=null;session.free();game.free()
	print("WEB_PERFORMANCE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
