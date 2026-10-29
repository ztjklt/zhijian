extends SceneTree

var failures: Array[String] = []
var count := 0
var codec: GDScript
var validation: GDScript
var store_script: GDScript

func check(value: bool, label: String) -> void:
	count += 1
	if not value:
		failures.append(label)
		print("FAIL NETWORK DATA: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for file in ["codec", "validation", "world_store"]:
		check(ResourceLoader.exists("res://scripts/net/" + file + ".gd"), file + " module exists")
	if not failures.is_empty():
		finish()
		return
	codec = load("res://scripts/net/codec.gd")
	validation = load("res://scripts/net/validation.gd")
	store_script = load("res://scripts/net/world_store.gd")
	test_codec()
	test_objects()
	test_weapons()
	test_store()
	test_member_credentials()
	finish()

func test_codec() -> void:
	var original := {"position": Vector2(12.5, -4), "color": Color(0.2, 0.3, 0.4, 0.8), "points": PackedVector2Array([Vector2.ZERO, Vector2(1, 2)]), "nested": [{"ok": true, "nil": null}]}
	var decoded: Variant = codec.decode(codec.encode(original))
	check(decoded is Dictionary and decoded.position == Vector2(12.5, -4), "vectors survive nested JSON transport")
	check(decoded.color is Color and decoded.color.is_equal_approx(original.color), "colors survive JSON transport")
	check(decoded.points is Array and decoded.points[1] == Vector2(1, 2) and decoded.nested[0].nil == null, "packed paths and JSON null survive")
	check(codec.decode("{broken") == null, "malformed JSON is rejected")
	check(codec.decode('{"_v":[1,"wrong"]}') == null, "malformed vector tags are rejected")
	check(codec.decode('{"_v":[1,2],"authority":true}') == null, "ambiguous tagged dictionaries are rejected")
	check(codec.decode('{"value":1e999}') == null, "nonfinite JSON numbers are rejected")
	check(codec.encode({"bad": Vector2(INF, 0)}) == "", "nonfinite vectors cannot be encoded")
	check(codec.encode({"bad": RefCounted.new()}) == "", "objects cannot enter transport")
	check(codec.decode("[".repeat(80) + "0" + "]".repeat(80)) == null, "excessive JSON nesting is rejected before decoding")
	check(codec.encode({"text": "x".repeat(17000000)}) == "", "oversized messages are rejected")
	check(codec.decode('{"text":"[\\\"{}]"}') is Dictionary, "depth scanning respects string escapes")
	var deep: Variant = Vector2.ONE
	for index in 31: deep = [deep]
	var deep_encoded: String = codec.encode(deep)
	check(deep_encoded.is_empty() or codec.decode(deep_encoded) != null, "emitted vector marker depth cannot exceed decoder depth")
	check(codec.encode({"bad": Vector2(1e20, 0)}) == "", "unrepresentable vector components cannot be emitted")
	check(codec.encode({1: "non-string key"}) == "", "transport dictionary keys must be unambiguous strings")
	var snapshot := {"epoch": 1, "objects": [], "players": []}
	snapshot.world = {"id": "paper"}
	snapshot.world.maps = {}
	snapshot.world.maps.paper = {"world": {"id": "paper"}, "objects": []}
	snapshot.players.append({})
	snapshot.players[0].position = Vector2(4, 2)
	snapshot.players[0].player_id = "player-1"
	var snapshot_encoded: String = codec.encode(snapshot)
	var snapshot_decoded: Variant = codec.decode(snapshot_encoded)
	check(not snapshot_encoded.is_empty() and snapshot_decoded is Dictionary and snapshot_decoded.world.maps.paper.world.id == "paper" and snapshot_decoded.players[0].position == Vector2(4, 2), "dot-assigned snapshot StringName keys normalize to JSON strings")

func shape() -> Dictionary:
	return {"source": "own", "role": "building", "kind": "freehand", "x": 5.0, "y": -1.0, "angle": 0.3, "dynamic": true,
		"paths": [{"points": [Vector2(-0.6, -0.2), Vector2(0.6, -0.2), Vector2(0.2, 0.5)], "collision": true}, {"points": [Vector2(-0.4, 0), Vector2(0.2, 0.3)], "collision": false}]}

func test_objects() -> void:
	var original := shape()
	original.merge({"id": "forged", "author": "other", "version": 999, "health": 999999, "max_health": 999999, "velocity": Vector2(300, 0)})
	var result: Dictionary = validation.object(original)
	check(result.ok and result.object.paths == original.paths, "full multi-path geometry and collision flags are preserved")
	check(result.ok and result.object.x == 5 and result.object.angle == 0.3, "local geometry and placement are kept separate")
	check(result.ok and not result.object.has("id") and not result.object.has("author") and not result.object.has("version") and not result.object.has("velocity"), "client identity revisions and velocity are stripped")
	check(result.ok and result.object.health == 120 and result.object.max_health == 120, "server recreation resets building health")
	if result.ok:
		result.object.paths[0].points[0] = Vector2(3, 3)
		check(original.paths[0].points[0] == Vector2(-0.6, -0.2), "validated geometry has independent mutable arrays")
	var many := shape()
	many.paths = []
	for stroke in 128:
		var points: Array = []
		for index in 64: points.append(Vector2(float(index) / 63, float(stroke) / 127))
		many.paths.append({"points": points, "collision": true})
	result = validation.object(many)
	check(result.ok and result.object.paths.size() == 128 and result.object.paths.back().points.back() == Vector2.ONE, "128 full strokes and 8192 points include their final endpoints")
	many.paths[0].points.append(Vector2.ONE)
	check(not validation.object(many).ok, "excess total points are rejected instead of truncated")
	for mutation in [{"x": NAN}, {"x": 100001}, {"angle": INF}, {"dynamic": "true"}, {"paths": [{"points": [Vector2.ZERO, Vector2(8.1, 0)]}]}, {"paths": [{"points": [Vector2.ZERO, Vector2(NAN, 1)]}]}, {"paths": []}, {"role": "weapon"}]:
		var invalid := shape()
		invalid.merge(mutation, true)
		check(not validation.object(invalid).ok, "invalid building boundary rejected " + str(count))
	var bag := BlueprintBag.new_bag()
	var prefab := DrawingRules.building([{"points": [Vector2.ZERO, Vector2(2, 0.8)]}], "wall")
	var entry: Dictionary = BlueprintBag.add_entry(bag, prefab).entry
	check(validation.object(BlueprintBag.make_object(entry, 4, 0)).ok, "library blueprints remain valid building input")
	var packed := shape()
	packed.paths[0].points = PackedVector2Array(packed.paths[0].points)
	check(validation.object(packed).ok, "packed local point arrays are accepted")

func test_weapons() -> void:
	var original := PaperWeaponGrip.practice_sword()
	var result: Dictionary = validation.weapon(original)
	check(result.ok, "actual locally forged weapon is accepted")
	check(result.ok and result.weapon.paths == original.paths and result.weapon.grip.is_equal_approx(original.grip), "weapon shape orientation and selected local grip remain unchanged")
	check(result.ok and is_equal_approx(result.weapon.reach, 0.8) and result.weapon.damage == 25 and is_equal_approx(result.weapon.cooldown, 0.46819277108434), "weapon combat stats are derived from the supplied geometry")
	for mutation in [{"damage": 999}, {"reach": 2.7}, {"cooldown": 0.01}, {"grip": Vector2(2, 2)}, {"paths": [{"points": [Vector2.ZERO, Vector2(3, 0)], "collision": false}]}]:
		var forged := original.duplicate(true)
		forged.merge(mutation, true)
		check(not validation.weapon(forged).ok, "forged weapon data rejected " + str(count))
	var no_stats := original.duplicate(true)
	for key in ["damage", "reach", "cooldown"]: no_stats.erase(key)
	check(validation.weapon(no_stats).ok, "server can derive absent stats without trusting the client")
	var empty_grip := original.duplicate(true)
	empty_grip.grip = original.grip + Vector2(0.02, 0)
	check(validation.weapon(empty_grip).ok, "grip can snap to nearby actual ink")
	var separated := {"paths": [{"points": [Vector2(-0.5, -0.5), Vector2(-0.5, 0.5)]}, {"points": [Vector2(0.5, -0.5), Vector2(0.5, 0.5)]}], "grip": Vector2.ZERO}
	check(not validation.weapon(separated).ok, "empty space between strokes cannot become a grip")

func test_store() -> void:
	var store = store_script.new("user://network_data_worlds")
	var world := {"owner_token": store_script.token(), "map_id": "paper", "paper": "draft", "next_id": 2, "objects": [shape()]}
	world.objects[0].merge({"id": "entity-1", "author": "author-1", "version": 1, "health": 65.0, "max_health": 120.0})
	var secret: String = world.owner_token
	var room_save := world.duplicate(true)
	room_save.owner_id = "owner-1"
	room_save.world = {"id": "paper"}
	room_save.world.maps = {}
	room_save.world.maps.paper = {"world": {"id": "paper"}, "objects": []}
	var room_saved: Dictionary = store.save("room-snapshot", room_save)
	var room_loaded: Dictionary = store.load_world("room-snapshot")
	check(room_saved.ok and room_loaded.ok and room_loaded.data.world.maps.paper.world.id == "paper" and room_loaded.data.owner_id == "owner-1", "room save with real dot-assigned nested state persists and restores")
	check(secret.length() == 64 and secret.is_valid_hex_number(false) and store_script.token() != secret, "credentials contain 32 cryptographic random bytes")
	check(store.save("castle", world).ok, "valid network world saves independently")
	var loaded: Dictionary = store.load_world("castle")
	check(loaded.ok and loaded.data.owner_token == secret and loaded.data.objects[0].paths[0].points[2] == Vector2(0.2, 0.5), "world and private owner identity restore with vector geometry")
	check(loaded.ok and loaded.data.objects[0].health == 65 and loaded.data.objects[0].author == "author-1", "authoritative persisted damage and ownership remain intact")
	var public_text := FileAccess.get_file_as_string("user://network_data_worlds/castle.json")
	check(not public_text.contains(secret) and not public_text.contains("owner_token"), "world snapshots never contain owner credentials")
	world.objects[0].health = 40.0
	check(store.save("castle", world).ok and FileAccess.file_exists("user://network_data_worlds/castle.json.bak"), "atomic replacement retains previous complete world")
	var bad := world.duplicate(true)
	bad.objects[0].paths[0].points[0] = Vector2(INF, 0)
	check(not store.save("castle", bad).ok and store.load_world("castle").data.objects[0].health == 40, "invalid save cannot overwrite last good snapshot")
	for id in ["../escape", "castle/../../bad", "", "bad\\name", "bad:name", "城堡"]:
		check(not store.save(id, world).ok and not store.load_world(id).ok, "traversal or invalid IDs are rejected")
	var corrupt := FileAccess.open("user://network_data_worlds/castle.json", FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	loaded = store.load_world("castle")
	check(loaded.ok and loaded.data.objects[0].health == 65, "corrupt primary recovers previous validated complete backup")
	check(not store.save("castle", bad).ok, "invalid writes also preserve recovery backup")
	check(not FileAccess.file_exists("user://paper_castle_v3.json") and not FileAccess.file_exists("user://paper_castle_v1.json"), "network persistence never touches single-player saves")
	var missing: Dictionary = store.load_world("missing")
	check(not missing.ok and missing.get("not_found", false), "missing save reports not_found separately from corruption")
	var duplicate := world.duplicate(true)
	duplicate.objects.append(duplicate.objects[0].duplicate(true))
	check(not store.save("duplicates", duplicate).ok, "duplicate stable entity IDs cannot enter saved worlds")
	var nested := world.duplicate(true)
	nested.extra = {"owner_token": "must-not-leak"}
	check(not store.save("nested-secret", nested).ok, "nested credentials cannot leak into world metadata")
	var incomplete := world.duplicate(true)
	incomplete.objects[0].erase("x")
	check(not store.save("incomplete", incomplete).ok, "persisted objects require explicit placement")
	check(store.save("corrupt-only", world).ok, "first complete snapshot can be written")
	corrupt = FileAccess.open("user://network_data_worlds/corrupt-only.json", FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var broken: Dictionary = store.load_world("corrupt-only")
	check(not broken.ok and not broken.get("not_found", false), "corrupt world never masquerades as a missing new world")
	var blocker := FileAccess.open("user://network_data_blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	check(not store_script.new("user://network_data_blocker/worlds").save("castle", world).ok, "unwritable world location returns failure")
	if OS.get_name() in ["macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "iOS"]:
		check(FileAccess.get_unix_permissions("user://network_data_worlds_credentials/castle.json") == 384, "stored owner credentials are readable only by OS owner")
		check(FileAccess.get_unix_permissions("user://network_data_worlds_credentials") == 448, "credential directory is traversable only by OS owner")

func test_member_credentials() -> void:
	var store = store_script.new("user://network_member_worlds")
	var world := {"owner_token": "owner-secret", "owner_id": "owner-1", "map_id": "paper", "paper": "draft", "next_id": 2, "objects": [shape()]}
	world.objects[0].merge({"id": "member-work", "author": "guest-1", "version": 1, "health": 65.0, "max_health": 120.0})
	check(store.save("legacy-members", world).ok, "legacy credential-only world remains writable")
	# This is the pre-member private file shape, not a current save() output.
	var legacy_file := FileAccess.open("user://network_member_worlds_credentials/legacy-members.json", FileAccess.WRITE)
	legacy_file.store_string('{"schema":1,"owner_token":"owner-secret"}')
	legacy_file.close()
	var legacy: Dictionary = store.load_world("legacy-members")
	check(legacy.ok and legacy.data.get("member_credentials") == [], "legacy credential file defaults to an empty private member list")
	world.member_credentials = [{"id": "guest-1", "token": "guest-secret-1"}]
	var first: Dictionary = store.save("members", world)
	check(first.ok, "world saves guest identity and credential in private storage")
	if not first.ok: return
	var loaded: Dictionary = store.load_world("members")
	check(loaded.ok and loaded.data.member_credentials == [{"id": "guest-1", "token": "guest-secret-1"}] and loaded.data.objects[0].author == "guest-1", "guest credential restores its stable persisted author identity")
	world.member_credentials.append({"id": "guest-2", "token": "guest-secret-2"})
	world.objects[0].health = 40.0
	check(store.save("members", world).ok, "later save atomically updates the private member list")
	loaded = store_script.new("user://network_member_worlds").load_world("members")
	check(loaded.ok and loaded.data.member_credentials.size() == 2 and loaded.data.member_credentials[0].id == "guest-1" and loaded.data.member_credentials[1].token == "guest-secret-2", "fresh store instance restores old and newly joined guest identities")
	var expected_members: Array = world.member_credentials.duplicate(true)
	for suffix in [".json", ".json.bak"]:
		var public_text := FileAccess.get_file_as_string("user://network_member_worlds/members" + suffix)
		check(not public_text.contains("owner-secret") and not public_text.contains("guest-secret") and not public_text.contains("member_credentials"), "public world and rolling backup contain no member or owner credentials " + suffix)
	var private_text := FileAccess.get_file_as_string("user://network_member_worlds_credentials/members.json")
	check(private_text.contains("guest-secret-1") and private_text.contains("guest-secret-2") and private_text.contains("owner-secret"), "all credential values exist only in private member record")
	world.erase("member_credentials")
	world.objects[0].health = 30.0
	check(store.save("members", world).ok, "save without optional member list remains supported")
	loaded = store.load_world("members")
	check(loaded.ok and loaded.data.member_credentials == expected_members and loaded.data.objects[0].health == 30, "omitting member list preserves existing guest credentials")
	var wrong_owner := world.duplicate(true)
	wrong_owner.owner_token = "wrong-owner-secret"
	wrong_owner.member_credentials = [{"id": "takeover", "token": "takeover-token"}]
	check(not store.save("members", wrong_owner).ok and store.load_world("members").data.member_credentials == expected_members, "wrong owner credential cannot replace private guest identities")
	var invalid_cases: Array = [null, {}, ["guest"], [{"id": "", "token": "valid"}], [{"id": "guest", "token": ""}], [{"id": "x".repeat(97), "token": "valid"}], [{"id": "guest", "token": "x".repeat(257)}],
		[{"id": "duplicate", "token": "one"}, {"id": "duplicate", "token": "two"}], [{"id": "one", "token": "duplicate"}, {"id": "two", "token": "duplicate"}],
		[{"id": "owner-1", "token": "member-token"}], [{"id": "guest", "token": "owner-secret"}]]
	var too_many: Array = []
	for index in 257: too_many.append({"id": "guest-" + str(index), "token": "token-" + str(index)})
	invalid_cases.append(too_many)
	for members in invalid_cases:
		var invalid := world.duplicate(true)
		invalid.member_credentials = members
		invalid.objects[0].health = 5.0
		var saved: Dictionary = store.save("members", invalid)
		loaded = store.load_world("members")
		check(not saved.ok and loaded.ok and loaded.data.member_credentials == expected_members and loaded.data.objects[0].health == 30, "invalid private membership leaves prior snapshot and credentials intact " + str(count))
	var failed_update := world.duplicate(true)
	failed_update.member_credentials = [{"id": "new-guest", "token": "new-token"}]
	failed_update.objects[0].health = 10.0
	var private_temporary := "user://network_member_worlds_credentials/members.json.tmp"
	check(DirAccess.make_dir_absolute(private_temporary) == OK, "private update failure fixture is installed")
	var failed: Dictionary = store.save("members", failed_update)
	DirAccess.remove_absolute(private_temporary)
	loaded = store.load_world("members")
	check(not failed.ok and loaded.ok and loaded.data.objects[0].health == 30 and loaded.data.member_credentials == expected_members, "failed atomic credential update does not replace public world or previous credentials")
	var maximum := world.duplicate(true)
	maximum.member_credentials = too_many.slice(0, 256)
	check(store.save("member-limit", maximum).ok and store.load_world("member-limit").data.member_credentials.size() == 256, "bounded full 256 member author history remains usable")
	if OS.get_name() in ["macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "iOS"]:
		check(FileAccess.get_unix_permissions("user://network_member_worlds_credentials/members.json") == 384, "updated member credential file retains owner-only permissions")

func finish() -> void:
	print("NETWORK DATA TESTS: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
