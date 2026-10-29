extends SceneTree
class CapturingSession extends PaperNetSession:
	var outgoing:Array=[]
	func _send(message:Dictionary)->void:outgoing.append(message.duplicate(true))
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL DRAWING PREVIEW: ",label)
func previews(session)->Array:
	return session.outgoing.filter(func(message):return message.get("op","")=="preview")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);game.set_physics_process(false);game.combat.set_natives(false)
	var session:=CapturingSession.new();root.add_child(session);session.set_process(false)
	session.game=game;game.network_session=session;session.ready_to_play=true;game.draw_mode=3
	for stroke in 128:
		var points:Array=[]
		for point in 64:points.append(game.player.position+Vector2(stroke/128.0,1.0+point/64.0))
		game.draft.append({"points":points,"collision":true})
	var original:Array=game.draft.duplicate(true)
	session.tick(.16)
	var sent:Array=previews(session)
	check(sent.size()==1,"one bounded preview is sent for a new draft")
	var paths:Array=sent.back().paths
	check(paths.size()==128,"all128 valid strokes remain visible instead of starving later strokes")
	var total:=0;var endpoints:=paths.size()==128
	for i in paths.size():
		total+=paths[i].points.size()
		endpoints=endpoints and paths[i].points.front()==original[i].points.front() and paths[i].points.back()==original[i].points.back()
	check(endpoints,"every stroke retains its actual first and final recorded points")
	check(total<=500 and total>0,"preview stays within the existing500-point network budget")
	check(game.draft==original and game.objects.is_empty(),"sampling never changes full8192-point draft or creates physics")
	session.outgoing.clear();session.tick(.16)
	check(previews(session).is_empty(),"an unchanged draft is not uploaded repeatedly")
	game.draft.clear();session.outgoing.clear();session.tick(.001)
	check(previews(session).size()==1 and previews(session).back().paths.is_empty(),"clearing sends empty preview without waiting150ms")
	game.active_stroke={"points":[Vector2(0,1),Vector2(1,1)]}
	session.outgoing.clear();session.tick(.001)
	check(previews(session).size()==1,"starting a new active stroke updates the preview promptly")
	game.active_stroke.points.append(Vector2(2,1));game.draft.append(game.active_stroke);game.active_stroke=null
	session.outgoing.clear();session.tick(.001)
	check(previews(session).size()==1 and previews(session).back().paths[0].points.back()==Vector2(2,1),"pen release promptly sends the final point")
	game.draw_mode=1;game.draft=[{"points":[Vector2(3,2),Vector2(4,2)]}]
	session.outgoing.clear();session.tick(.001)
	check(previews(session).size()==1 and previews(session).back().paths[0].points.back()==Vector2(4,2),"switching source tools updates even with the same stroke count")
	game.active_stroke={"points":[Vector2(0,3)]}
	session.tick(.001);session.outgoing.clear()
	game.active_stroke.points.append(Vector2(1,3));session.tick(.001)
	check(previews(session).size()==1 and previews(session).back().paths.back().points.size()==2,"first visible segment uploads promptly after the initial pen-down dot")
	game.active_stroke=null
	var sampling=load("res://scripts/net/drawing_preview.gd")
	check(sampling.sample([]).is_empty(),"empty source has an empty bounded preview")
	check(sampling.sample([{"points":[Vector2(2,3)]}])[0].points==[Vector2(2,3)],"one-point active source stays one point")
	check(sampling.sample([{"points":[Vector2(2,3),Vector2(4,5)]}])[0].points==[Vector2(2,3),Vector2(4,5)],"two-point strokes retain both exact endpoints")
	check(sampling.sample(original).size()==128 and sampling.sample(original).back().points.size()>=2,"repeated sampling never starves the last stroke")
	session.tick(.16);session.outgoing.clear()
	session._result({"op":"preview","seq":session.seq,"ok":false,"error":"out of range"})
	session.tick(.16)
	check(previews(session).size()==1,"rejected unchanged preview is eligible again after returning within range")
	session.player_id="self";session.outgoing.clear()
	var state:={"id":"self","position":game.player.position,"connected":true,"health":0,"dead":3.0}
	session._actor(state);state.health=100;state.dead=0.0;session._actor(state)
	session.tick(.001)
	check(previews(session).size()==1,"respawn resends retained stationary draft after authority clears its dead preview")
	var remote=load("res://scripts/net/remote_actor.gd").new();remote.display_game=game;game.add_child(remote)
	remote.apply({"position":Vector2.ZERO,"preview":[{"points":[Vector2.ZERO,Vector2.ONE]}]})
	remote.apply({"position":Vector2.ONE})
	check(remote.preview.size()==1,"omitted optional preview retains the last confirmed strokes")
	remote.apply({"position":Vector2.ONE,"preview":[]})
	check(remote.preview.is_empty(),"explicit empty preview still clears the remote drawing")
	game.network_session=null;session.game=null;session.free();game.free();await process_frame
	print("NETWORK DRAWING PREVIEW: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
