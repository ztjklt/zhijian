extends Node
const Slots := preload("res://scripts/team_worlds.gd")
const Session := preload("res://scripts/world_session.gd")
const Roles := preload("res://scripts/divine_roles.gd")
var game
var slot := ""
var generation := ""
var poll := 0
const CHECKPOINT_MSEC := 60000
var next_save := 0
var observed_revision := 0
var leaving := false

func arg(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	var n := args.find(key)
	return args[n+1] if n >= 0 and n+1 < args.size() else ""

func _ready() -> void:
	set_process(false)
	_boot.call_deferred()

func _boot() -> void:
	slot = arg("--world-slot")
	generation = arg("--world-generation")
	# The supervisor resolves symlinks. Godot can retain the caller's HOME spelling.
	# POSIX -ef compares the same filesystem device and inode, including symlink targets.
	var same_directory := OS.execute("/bin/test",[OS.get_user_data_dir(),"-ef",arg("--world-data")]) == 0
	if not Slots._valid_id(slot) or not same_directory:
		push_error("世界进程的资料目录或队伍编号不符。")
		get_tree().quit(65)
		return
	if not Session.claim(slot,true,generation).ok:
		get_tree().quit()
		return
	var previous := Slots._latest(slot)
	var saved := Slots.load_slot(slot) if previous > 0 else {}
	if previous > 0 and not saved.error.is_empty() or previous == 0 and arg("--world-name").is_empty():
		push_error("世界检查点无法读取。")
		get_tree().quit(65)
		return
	if OS.get_cmdline_user_args().has("--world-share-adventurer"):
		ModelConnections.share_night_adventurer()
	game = load("res://scenes/medieval.tscn").instantiate()
	game.background_world = true
	game.team_slot = saved.card if previous > 0 else Slots.new_slot(arg("--world-name"))
	game.team_slot.slot_id = slot
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	if previous > 0 and not game.apply_team_work(saved):
		get_tree().quit(65)
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	for role in Roles.NODES:
		if not game.medieval_world.has_node(Roles.NODES[role]):
			push_error("世界角色未能就绪：" + role)
			get_tree().quit(65)
			return
	game.medieval_world.chronicle.record("night:"+generation,"night_started","world","世界进入后台","各角色从这一刻继续行动。")
	if not _checkpoint():
		get_tree().quit(65)
		return
	Session.run("ready",slot)
	observed_revision = int(game.team_slot.revision)
	next_save = Time.get_ticks_msec() + CHECKPOINT_MSEC
	set_process(true)

func _checkpoint() -> bool:
	if not game.save_game(): return false
	print("WORLD_CHECKPOINT ",slot," ",game.team_slot.revision," ",Time.get_unix_time_from_system())
	return true

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < poll: return
	poll = now + 350
	# A settled model receipt already committed the entire running world.
	# Start the fallback timer at that commit, so idle worlds still checkpoint.
	if int(game.team_slot.revision) != observed_revision:
		observed_revision = int(game.team_slot.revision)
		next_save = now + CHECKPOINT_MSEC
	var state := Session.control(slot)
	if state.get("desired") != "background" or state.get("generation") != generation:
		leaving = true
		Session.draining[slot] = true
	if leaving and not Session.has_requests(game):
		var ok := _checkpoint()
		if not ok:
			push_error("无法写入交接存档，保留当前世界等待磁盘恢复。")
			poll = now + 5000
			return
		get_tree().quit()
	elif now >= next_save:
		if not _checkpoint(): push_error("尚未完成后台检查点，稍后重试。")
		next_save = now + CHECKPOINT_MSEC

