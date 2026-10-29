extends SceneTree

var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("FUSION ENTRY: "+label)
func run() -> void:
	var menu = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.cards.get_child_count() == 2,"start offers fused landscape plus textbook, not two separate unfinished landscapes")
	check(not menu.continue_buttons.has("nature-v1"),"new nature card is retired while legacy API remains available")
	menu.free()
	var state := {"id":"medieval-v1","player_y":0.0,"camera_y":0.0,"entities":[],"terrain_version":2}
	check(SaveStore.save_game("draft",[],BlueprintBag.new_bag(),3,3,{},state).ok,"new terrain version saves")
	check(SaveStore.load_game("medieval-v1").error.is_empty(),"JSON numeric terrain version round-trips")
	var good := FileAccess.get_file_as_string(SaveStore.MEDIEVAL_SAVE_PATH)
	for invalid in [0,4,1.5,"2",NAN]:
		state.terrain_version = invalid
		check(not SaveStore.save_game("draft",[],BlueprintBag.new_bag(),3,3,{},state).ok,"reject invalid terrain version "+str(invalid))
	check(FileAccess.get_file_as_string(SaveStore.MEDIEVAL_SAVE_PATH) == good,"invalid version keeps prior save")
	state.erase("terrain_version")
	check(SaveStore.save_game("draft",[],BlueprintBag.new_bag(),3,3,{},state).ok,"legacy missing terrain version remains readable")
	var old_nature := {"id":"nature-v1","player_y":1.0,"camera_y":0.0,"checkpoint":{"x":3.0,"y":1.0},"bookmarks":[]}
	check(SaveStore.save_game("draft",[],BlueprintBag.new_bag(),3,3,{},old_nature).ok,"legacy nature save remains separate and valid")
	menu = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.get("legacy_nature_button") != null and menu.legacy_nature_button.visible,"saved old nature work has explicit continue access")
	check(menu.cards.get_child_count() == 2,"legacy continue is not a fresh duplicate landscape card")
	menu.free()
	print("FUSION ENTRY: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
