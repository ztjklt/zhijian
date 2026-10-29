extends "res://tests/carry_drop_test.gd"
func run()->void:
	await fresh(Vector2(0,2))
	var key:String=game.carried_id
	var wall:=wall_at(game.object_nodes[0].position)
	for frame in 3:await physics_frame
	check(touches(game.object_nodes[0],wall),"fixture has an actually obstructed collisionless carry pose")
	game.set_draw_mode(1);game.generator="own"
	game.pointer_down(game.world_to_screen(Vector2(-2,2)));game.pointer_move(game.world_to_screen(Vector2(-1,3)));game.pointer_up(game.world_to_screen(Vector2(-1,3)))
	check(game.draft.size()==1 and game.carried_id==key,"real stroke is recorded while carrying")
	game.undo()
	check(game.draft.is_empty() and game.carried_id==key,"undo removes only the new drawing and retains surviving carry identity")
	var held:RigidBody2D=game.object_nodes[0]
	check(held.freeze and held.collision_layer==0 and held.collision_mask==0,"undo never materializes a colliding held body inside the wall")
	game.redo();held=game.object_nodes[0]
	check(game.draft.size()==1 and game.carried_id==key and held.freeze and held.collision_layer==0,"redo preserves same stable carry state")
	check(game.drop_carried() and not touches(held,wall),"subsequent explicit drop still resolves real clearance")
	await finish()
