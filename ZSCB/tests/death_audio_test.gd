extends SceneTree
var failures:Array[String]=[]
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("DEATH AUDIO: "+label)
func _init()->void:call_deferred("run")
func cries(feedback)->Array:return feedback.events.filter(func(e):return e.kind=="voice")
func run()->void:
	var game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.onboarding.dismiss();game.feedback.set_process(false)
	var world=game.medieval_world;world.set_physics_process(false)
	for kind in ["villager","queen","horse","rabbit","deer","bat","dragon","wall"]:
		var entity:=MedievalEntity.new();entity.setup(kind,game.player.position+Vector2(2,0),"audio_"+kind,game.GROUND_Y)
		world.add_child(entity);world.entities.append(entity)
		game.feedback.events.clear()
		world.damage_entity(entity,1,entity.position,Vector2.RIGHT)
		check(cries(game.feedback).is_empty(),kind+" nonlethal hit never screams death")
		world.damage_entity(entity,1000,entity.position,Vector2.RIGHT)
		var expected:=0 if kind=="wall" else 1
		check(cries(game.feedback).size()==expected,kind+" death produces exactly the appropriate one cry")
		world.damage_entity(entity,1000,entity.position,Vector2.RIGHT)
		check(cries(game.feedback).size()==expected,kind+" corpse cannot scream again")
		if expected==1 and not cries(game.feedback).is_empty():
			var key:String=cries(game.feedback)[0].get("audio","")
			check(key==("death_human_high" if kind=="queen" else "death_human_low" if kind=="villager" else "death_"+kind),kind+" uses its own voice rather than a building break")
	game.feedback.events.clear();game.combat.health=1;game.combat.invulnerable=0
	game.combat.hurt_player(10,Vector2.RIGHT)
	check(cries(game.feedback).size()==1,"local player death emits one human scream before respawn")
	game.feedback.events.clear();game.combat.set_natives(true)
	var native=game.combat.natives[0];native.health=1;native.take_hit(10,Vector2.RIGHT);native.take_hit(10,Vector2.RIGHT)
	check(cries(game.feedback).size()==1,"native fighter death cries once")
	game.queue_free();await process_frame
	print("DEATH AUDIO: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
