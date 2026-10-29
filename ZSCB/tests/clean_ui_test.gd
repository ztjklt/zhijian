extends SceneTree
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); print("FAIL: ",text)
func settle() -> void:
	for i in range(6): await process_frame
func click(button: BaseButton) -> void:
	var p := button.get_global_rect().get_center()
	for down in [true,false]:
		var e := InputEventMouseButton.new(); e.position=p; e.global_position=p; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down
		root.push_input(e,true)
	await settle()
func run() -> void:
	root.size=Vector2i(1280,720)
	var game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);await settle();game.onboarding.dismiss();game.combat.set_natives(false)
	check(game.toolbar.tool_button.text.contains("造物"),"freehand and building share the named creation entry")
	if not game.toolbar.tool_button.text.contains("造物"):
		game.free();quit(1);return
	check(not game.toolbar.mode_buttons[1].get_parent()==game.toolbar.mode_group,"building is a creation subtool, not another main dock entry")
	await click(game.toolbar.tool_button)
	check(game.draw_mode==1,"creation entry opens freehand")
	game.draft=[{"points":[Vector2(0,2),Vector2(1,2)]}]
	await click(game.toolbar.mode_buttons[1])
	check(game.draw_mode==3 and game.objects.is_empty(),"building subtool switches without committing freehand draft")
	await click(game.toolbar.free_button)
	check(game.draw_mode==1 and game.draft.size()==1,"freehand draft survives creation subtype switch")
	var alpha:=BlueprintBag.add_entry(game.bag,{"kind":"freehand","paths":[{"points":[Vector2.ZERO,Vector2.RIGHT]}]})
	var beta:=BlueprintBag.add_entry(game.bag,{"kind":"freehand","paths":[{"points":[Vector2.ZERO,Vector2.UP]}]})
	game.toggle_bag();game.select_blueprint(alpha.entry.id);await settle()
	game.backpack_panel.name_field.grab_focus();game.backpack_panel.name_field.text="Alpha edited"
	var beta_card:BaseButton
	for card in game.backpack_panel.grid.get_children():
		if card.tooltip_text.begins_with(beta.entry.name+" · "):beta_card=card
	await click(beta_card)
	check(game.selected_blueprint_id==beta.entry.id and game.backpack_panel.name_field.text==beta.entry.name,"switching cards cannot carry another blueprint's rename draft")
	game.toggle_bag()
	for dimensions in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		root.size=dimensions;await settle()
		var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
		check(bounds.encloses(game.toolbar.mode_group.get_global_rect()),"dock fits "+str(dimensions))
		var world_gap:Vector2=Vector2(dimensions.x*.5,(game.toolbar.bottom.get_global_rect().end.y+dimensions.y-100)*.5) if dimensions.y<500 or dimensions.x<600 else Vector2(dimensions.x*.5,dimensions.y*.4)
		check(not game.toolbar.blocks_canvas(world_gap),"empty world remains drawable "+str(dimensions))
		game.toggle_bag();await settle()
		check(bounds.encloses(game.backpack_panel.get_global_rect()),"collection fits "+str(dimensions))
		check(game.backpack_panel.shade.visible,"open collection dims busy world")
		check(bounds.encloses(game.backpack_panel.place_button.get_global_rect()),"primary reuse remains visible "+str(dimensions))
		game.toggle_bag();await settle()
		check(not game.backpack_panel.shade.visible,"closing collection releases shade")
	game.free();print("CLEAN UI: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
