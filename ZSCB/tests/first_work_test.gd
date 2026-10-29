extends SceneTree
var game
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL FIRST WORK: ",label)
func draw_piece(at:Vector2,mode:int=1)->void:
	game.set_draw_mode(mode);game.generator="own"
	var points=[at+Vector2(-.65,-.12),at+Vector2(.65,-.12),at+Vector2(.65,.12),at+Vector2(-.65,.12),at+Vector2(-.65,-.12)]
	game.pointer_down(game.world_to_screen(points[0]))
	for i in range(1,points.size()):game.pointer_move(game.world_to_screen(points[i]))
	game.pointer_up(game.world_to_screen(points[-1]))
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.player.position=Vector2(-5.6,-2.51);game.combat.set_natives(false)
	var goal=game.get("first_work")
	check(goal!=null,"core has an optional first-work goal")
	if goal==null:game.queue_free();quit(1);return
	check(not goal.visible,"isolated nonpersistent test does not auto-start")
	goal.start();check(goal.visible and goal.stage==0,"explicit start begins drawing without creating entities")
	var origin:Vector2=game.player.position
	game.pointer_down(game.world_to_screen(Vector2(-2,0)));game.pointer_up(game.world_to_screen(Vector2(-2,0)))
	check(goal.stage==0,"invalid tiny stroke never counts")
	game.set_draw_mode(2);game.draft=[{"points":[Vector2(-2,0),Vector2(-1,1)]}];goal.note_drawn(2)
	check(goal.stage==0,"weapon drawing does not pretend to be a physical platform")
	game.draft=[];game.mode_drafts[2]=[]
	draw_piece(Vector2(-2,0))
	check(goal.stage==1 and game.objects.is_empty(),"normal pointer records draft but never auto-generates")
	goal.action()
	check(goal.stage==2 and game.objects.size()==1 and goal.target_key==game.objects[0].structure_id,"actual confirmed generation binds its real body")
	check(game.player.position==origin,"tutorial never moves player or gives a platform")
	var key:String=goal.target_key;var object:Dictionary=game.objects[0]
	goal.step(1.0)
	check(goal.stage==2,"gravity or waiting cannot count as using creation")
	goal.note_moved(object,Vector2.ZERO,Vector2(.1,0));check(goal.stage==2,"tiny drag is not meaningful use")
	var foreign=object.duplicate(true);foreign.structure_id="not_target"
	goal.note_moved(foreign,Vector2.ZERO,Vector2(1,0));check(goal.stage==2,"moving another piece cannot complete target")
	game.set_draw_mode(4)
	var start:Vector2=Vector2(object.x,object.y)
	game.pointer_down(game.world_to_screen(start));game.pointer_move(game.world_to_screen(start+Vector2(.4,0)));game.pointer_up(game.world_to_screen(start+Vector2(.4,0)))
	check(goal.stage==3,"actual4drag advances to explicit save")
	goal.note_saved(false);check(goal.stage==3 and goal.visible,"failed save retains target and retry")
	check(game.save_game() and goal.stage==4,"actual successful disk save completes loop")
	var saved:Dictionary=SaveStore.load_game()
	check(saved.error=="" and saved.data.objects[0].structure_id==key,"saved work actually contains the tracked creation")
	goal.dismiss();check(not goal.visible,"completed goal can return to free creation")
	var before:int=game.objects.size();goal.start()
	check(goal.stage==0 and game.objects.size()==before,"replay preserves existing work and requires a new piece")
	goal.note_created(object);check(goal.stage==0,"old creation cannot replay the successful generation event")
	game.set_draw_mode(1);game.draft=[];draw_piece(Vector2(1,0));goal.action()
	check(goal.stage==2,"new drawing starts another genuine loop")
	game.objects.remove_at(1);game.object_nodes[1].queue_free();game.object_nodes.remove_at(1);goal.step(.1)
	check(goal.stage==0 and goal.target_key=="","deleted target returns to drawing instead of a false success")
	goal.start();draw_piece(Vector2(3,0));game.toolbar.clear_button.pressed.emit()
	draw_piece(Vector2(3,1),3)
	check(goal.stage==1 and goal.drawing_mode==3,"clear and redraw in2building rebinds lesson to latest valid draft")
	goal.action()
	check(goal.stage==2,"lesson action actually generates replacement draft in its correct tool")
	goal.start();game.network_session=PaperNetSession.new();var was_visible:bool=goal.visible
	check(not goal.start() and goal.visible==was_visible,"online room cannot start or mutate the single-player course")
	game.network_session.free();game.network_session=null
	game.queue_free();await process_frame
	print("FIRST WORK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
