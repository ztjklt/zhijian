extends SceneTree
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var room=PaperNetRoom.new()
	room.configure("ACK00001","paper","fixture-only",load("res://scripts/net/world_store.gd").new("user://ack-test"),"ack-world")
	root.add_child(room)
	var identity:Dictionary=room.join("","fixture");room.ready(identity.player_id)
	var actor=room.actors[identity.player_id]
	var result:Dictionary=room.command(identity.player_id,{"op":"input","seq":17,"right":true})
	var state:Dictionary=actor.state()
	check(result.ok and state.has("input_ack") and state.has("input_age"),"authority includes accepted input sequence and simulation age")
	if state.has("input_ack"):
		check(state.input_ack==17 and state.input_age==0,"input ACK identifies the current accepted command")
		for i in 8:await physics_frame
		state=actor.state();var age:float=state.input_age
		check(age>.06 and state.input_ack==17,"ACK age advances with actual authority simulation")
		room.command(identity.player_id,{"op":"input","seq":16,"left":true})
		check(actor.state().input_ack==17 and actor.state().input_age==age,"stale duplicate cannot change acknowledgement or refresh input timeout")
		var reset_before:int=state.get("movement_reset",-1)
		room.command(identity.player_id,{"op":"respawn","seq":18})
		check(actor.state().get("movement_reset",-1)>reset_before,"server relocation carries an explicit reset marker")
		check(actor.player.linear_velocity.length()<.01,"reset metadata does not change existing respawn authority behavior")
	room.free();await process_frame
	print("MOVEMENT_ACK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
