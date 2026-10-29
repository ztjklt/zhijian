extends SceneTree
## Loopback-only authority. Public HTTP/WSS is handled by gateway.py.
const Room := preload("res://scripts/net/room.gd")
const Store := preload("res://scripts/net/world_store.gd")
const Codec := preload("res://scripts/net/codec.gd")
const MAX_PACKET := 1048576
const MAX_SNAPSHOT := 16 * 1024 * 1024
const CHUNK_CHARS := 8192
const MAX_RELIABLE := 32
const MAX_QUEUE_BYTES := 2097152
const OUTBOUND_LIMIT := 2097152
const MAPS := ["paper", "knowledge-v1", "nature-v1", "medieval-v1"]
var listener := TCPServer.new()
var clients: Dictionary = {}
var rooms: Dictionary = {}
var store: RefCounted
var next_client := 1
var broadcast_clock := 0.0
var max_rooms := 4
var max_connections := 32

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	if not (Room as Script).can_instantiate() or not (Store as Script).can_instantiate():
		printerr("network authority dependencies did not compile")
		quit(1)
		return
	max_rooms = _setting("NET_MAX_ROOMS", 4, 1, 16)
	max_connections = _setting("NET_MAX_CONNECTIONS", 32, 4, 128)
	var directory := OS.get_environment("NET_DATA_DIR")
	if directory == "": directory = "user://network-worlds"
	store = Store.new(directory)
	var port := _setting("NET_PORT", 9081, 1024, 65535)
	var status := listener.listen(port, "127.0.0.1")
	if status != OK:
		printerr("network listen failed: ", error_string(status))
		quit(1)
		return
	print("paper authority ready on loopback port ", port)

func _setting(key: String, fallback: int, low: int, high: int) -> int:
	var value := OS.get_environment(key)
	return clampi(int(value), low, high) if value.is_valid_int() else fallback

func _process(delta: float) -> bool:
	while listener.is_connection_available():
		var stream := listener.take_connection()
		if clients.size() >= max_connections:
			stream.disconnect_from_host()
			continue
		var socket := WebSocketPeer.new()
		socket.inbound_buffer_size = MAX_PACKET
		socket.outbound_buffer_size = 2097152
		socket.max_queued_packets = 32
		socket.heartbeat_interval = 5.0
		if socket.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		socket.set_no_delay(true)
		clients[next_client] = {"socket":socket,"stream":stream,"room":"","player_id":"","ready":false,
			"age":0.0,"idle":0.0,"ready_wait":0.0,"join_wait":0.0,"rate_clock":0.0,"rate":0,"bytes":0,"queue":[],"queue_bytes":0,
			"snapshot":"","snapshot_index":0,"snapshot_chunks":0,"snapshot_done":false,"epoch":"","last_resync":-100.0,"closing":false,"equipment_versions":{},"entity_records":{}}
		next_client += 1
	for id in clients.keys():
		var client: Dictionary = clients[id]
		var socket: WebSocketPeer = client.socket
		client.age += delta
		client.idle += delta
		client.ready_wait = client.ready_wait + delta if client.room != "" and not client.ready else 0.0
		client.join_wait = client.join_wait + delta if client.room == "" else 0.0
		client.rate_clock += delta
		if client.rate_clock >= 1.0:
			client.rate_clock = 0.0
			client.rate = 0
			client.bytes = 0
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_drop(id)
			continue
		if client.idle > 20.0 or client.join_wait > 10.0 or client.ready_wait > 60.0:
			_close(id, "timeout")
			continue
		if socket.get_ready_state() != WebSocketPeer.STATE_OPEN: continue
		var packets := 0
		while socket.get_available_packet_count() > 0 and packets < 16 and not client.closing:
			var packet := socket.get_packet()
			packets += 1
			client.rate += 1
			client.bytes += packet.size()
			if not socket.was_string_packet() or packet.size() > MAX_PACKET or client.rate > 100 or client.bytes > 2097152:
				_close(id, "packet_limit")
				break
			client.idle = 0.0
			var message: Variant = Codec.decode(packet.get_string_from_utf8())
			if not message is Dictionary:
				_error(client, "invalid_message")
				continue
			_handle(id, message)
		if clients.has(id): _flush(id)
	broadcast_clock += delta
	if broadcast_clock >= 0.05:
		broadcast_clock = fmod(broadcast_clock, 0.05)
		_broadcast()
	return false

func _handle(id: int, message: Dictionary) -> void:
	var client: Dictionary = clients[id]
	var kind: String = str(message.get("type", ""))
	if kind == "ping":
		_queue(client, {"type":"pong","stamp":message.get("stamp",0)})
		return
	if kind in ["create", "join"]:
		if client.room != "":
			_error(client, "already_joined")
			return
		_join(id, message)
		return
	if client.room == "" or not rooms.has(client.room):
		_error(client, "not_joined")
		return
	var room = rooms[client.room]
	if kind == "resync":
		if client.age - client.last_resync < 1.0:
			_error(client, "resync_rate_limit")
			return
		client.last_resync = client.age
		if client.epoch != room.epoch:
			_queue(client, {"type":"world_changed","epoch":room.epoch})
		_snapshot(client, room)
	elif kind == "ready":
		if str(message.get("epoch", "")) != client.epoch or client.epoch != room.epoch or not client.snapshot_done:
			_error(client, "snapshot_not_ready")
			return
		client.ready = true
		room.ready(client.player_id)
		_queue(client, {"type":"ready","epoch":client.epoch})
		_send_frame(client, room.frame())
	elif kind == "command":
		if not message.get("epoch") is String or message.epoch != client.epoch or message.epoch != room.epoch:
			_reject_command(client, message, "stale_epoch")
			return
		if not client.ready:
			_reject_command(client, message, "not_ready")
			return
		var sequence: Variant = message.get("seq")
		if not (sequence is int or sequence is float) or not is_finite(float(sequence)) or float(sequence) != floorf(float(sequence)) or float(sequence) < 1 or float(sequence) > 2147483647:
			_error(client, "invalid_sequence")
			return
		if not message.get("op") is String:
			_error(client, "invalid_command")
			return
		if message.op == "input":
			for field in ["left", "right", "up", "down", "jump", "blocked", "combat_blocked"]:
				if message.has(field) and not message[field] is bool:
					_error(client, "invalid_input")
					return
		var result: Dictionary = room.command(client.player_id, message)
		result = result.duplicate()
		result["type"] = "result"
		result["seq"] = message.get("seq", 0)
		result["epoch"] = client.epoch
		_queue(client, result)
	else:
		_error(client, "unknown_message")

func _join(id: int, message: Dictionary) -> void:
	var client: Dictionary = clients[id]
	if message.get("protocol",0) != Codec.PROTOCOL:
		_error(client, "version_mismatch")
		return
	var room: Variant
	var code := str(message.get("code", "")).strip_edges().to_upper()
	if str(message.type) == "create":
		if rooms.size() >= max_rooms:
			_error(client, "service_full")
			return
		var map_id := str(message.get("map_id", "medieval-v1"))
		if map_id not in MAPS:
			_error(client, "invalid_map")
			return
		var world_id := str(message.get("world_id", ""))
		var credential := Store.token()
		if world_id != "":
			for existing in rooms.values():
				if existing.world_id == world_id:
					_error(client, "world_already_open")
					return
			var loaded: Dictionary = store.load_world(world_id)
			if not loaded.get("ok", false) or str(message.get("owner_token", "")) != str(loaded.get("data", {}).get("owner_token", "")):
				_error(client, "invalid_owner")
				return
			credential = str(loaded.data.owner_token)
		else:
			world_id = Store.token()
		code = Store.token().left(8).to_upper()
		while rooms.has(code): code = Store.token().left(8).to_upper()
		room = Room.new()
		room.configure(code, map_id, credential, store, world_id)
		root.add_child(room)
		if room.error != "":
			_error(client, room.error)
			room.queue_free()
			return
		rooms[code] = room
	else:
		if not rooms.has(code):
			_error(client, "room_not_found")
			return
		room = rooms[code]
	var token := str(message.get("token", "")) if str(message.type) == "join" else ""
	if token == "" and str(message.type) == "join" and message.has("known_tokens"):
		var known: Variant = message.known_tokens
		if not known is Dictionary or known.size() > 256:
			_error(client, "invalid_token")
			return
		for key in known:
			if not key is String or key.length() > 96 or not known[key] is String or known[key].length() > 256:
				_error(client, "invalid_token")
				return
		token = known.get(room.world_id, "")
	if token == "" and room.actors.size() >= 2:
		_error(client, "room_full")
		return
	if token.length() > 256:
		_error(client, "invalid_token")
		return
	var identity: Dictionary = room.join(token, str(message.get("name", "画家")).left(64))
	if not identity.get("ok", false):
		_error(client, str(identity.get("error", "join_failed")))
		return
	client.room = code
	client.player_id = identity.player_id
	client.preview_delta = message.get("preview_delta",false) == true
	var welcome := identity.duplicate()
	welcome.merge({"type":"welcome","protocol":Codec.PROTOCOL,"code":code,"world_id":room.world_id,"epoch":room.epoch,"map_id":room.map_id}, true)
	_queue(client, welcome)
	_snapshot(client, room)

func _snapshot(client: Dictionary, room) -> void:
	client.ready = false
	client.ready_wait = 0.0
	client.snapshot_done = false
	client.equipment_versions.clear()
	client.preview_records = {}
	client.entity_records.clear()
	client.epoch = room.epoch
	var data: String = Codec.encode(room.snapshot())
	if data.is_empty():
		_error(client, "snapshot_invalid")
		return
	if data.to_utf8_buffer().size() > MAX_SNAPSHOT:
		_error(client, "snapshot_too_large")
		client.closing = true
		return
	client.snapshot = data
	client.snapshot_index = 0
	client.snapshot_chunks = ceili(float(data.length()) / CHUNK_CHARS)
	_queue(client, {"type":"snapshot_begin","epoch":client.epoch,"chunks":client.snapshot_chunks})

func _queue(client: Dictionary, value: Dictionary) -> void:
	var data: String = Codec.encode(value)
	if data.is_empty():
		client.closing = true
		return
	var count := data.to_utf8_buffer().size()
	if client.queue.size() >= MAX_RELIABLE or client.queue_bytes + count > MAX_QUEUE_BYTES:
		client.closing = true
		return
	client.queue.append(data)
	client.queue_bytes += count

func _error(client: Dictionary, error: String) -> void:
	_queue(client, {"type":"error","error":error})

func _reject_command(client: Dictionary, message: Dictionary, error: String) -> void:
	_queue(client, {"type":"result","seq":message.get("seq",0),"op":message.get("op",""),"ok":false,"error":error,"epoch":client.epoch})

func _flush(id: int) -> void:
	var client: Dictionary = clients[id]
	var socket: WebSocketPeer = client.socket
	if client.closing:
		_close(id, "slow_consumer")
		return
	if socket.get_current_outbound_buffered_amount() > OUTBOUND_LIMIT: return
	var budget := 4
	while not client.queue.is_empty() and budget > 0:
		var data: String = client.queue.pop_front()
		client.queue_bytes -= data.to_utf8_buffer().size()
		if socket.send_text(data) != OK:
			_close(id, "send_failed")
			return
		budget -= 1
	if not client.queue.is_empty() or client.snapshot == "": return
	for _part in range(2):
		if socket.get_current_outbound_buffered_amount() > OUTBOUND_LIMIT: return
		if client.snapshot_index >= client.snapshot_chunks:
			socket.send_text(Codec.encode({"type":"snapshot_end","epoch":client.epoch}))
			client.snapshot = ""
			client.snapshot_done = true
			return
		var index: int = client.snapshot_index
		var part: String = client.snapshot.substr(index * CHUNK_CHARS, CHUNK_CHARS)
		if socket.send_text(Codec.encode({"type":"snapshot_chunk","epoch":client.epoch,"index":index,"data":part})) != OK:
			_close(id, "send_failed")
			return
		client.snapshot_index += 1

func _broadcast() -> void:
	for code in rooms.keys():
		var room = rooms[code]
		if room.closed:
			for id in clients.keys():
				var client: Dictionary = clients[id]
				if client.room != code: continue
				client.snapshot = ""
				_queue(client, {"type":"closed","error":room.close_reason})
				_flush(id)
				client.room = ""
				client.player_id = ""
				client.ready = false
			rooms.erase(code)
			room.queue_free()
			continue
		var frame: Dictionary = room.frame()
		for client in clients.values():
			if client.room != code: continue
			if client.epoch != room.epoch:
				_queue(client, {"type":"world_changed","epoch":room.epoch})
				_snapshot(client, room)
			elif client.ready:
				_send_frame(client, frame)

func _send_frame(client: Dictionary, frame: Dictionary) -> void:
	var socket: WebSocketPeer = client.socket
	# Skip stale position updates while the TCP connection is backed up.
	if not client.queue.is_empty() or socket.get_current_outbound_buffered_amount() > 65536: return
	var packet := frame.duplicate(true)
	var sent_versions := {}
	var sent_previews := {}
	for state in packet.actors:
		var version := int(state.get("weapon_version",0))
		if client.equipment_versions.get(state.id,-1) == version: state.erase("weapon")
		sent_versions[state.id] = version
		if client.get("preview_delta",false):
			var paths: Array = state.get("preview",[])
			sent_previews[state.id] = paths
			if client.get("preview_records",{}).get(state.id,null) == paths: state.erase("preview")
	var sent_damage := {}
	for body in packet.bodies:
		var version:int=int(body.version)
		if client.get("damage_versions",{}).get(body.id,-1)==version:body.erase("damage_cuts")
		sent_damage[body.id]=version
	var sent_entities := {}
	var changed_entities: Array = []
	for record in packet.entities:
		sent_entities[record.id] = record
		if client.entity_records.get(record.id,{}) != record: changed_entities.append(record)
	packet.entities = changed_entities
	packet["type"] = "frame"
	packet["epoch"] = client.epoch
	var data: String = Codec.encode(packet)
	if data.to_utf8_buffer().size() > OUTBOUND_LIMIT:
		client.closing = true
		return
	if socket.send_text(data) != OK: client.closing = true
	else:
		client.damage_versions = sent_damage
		client.equipment_versions = sent_versions
		client.preview_records = sent_previews
		client.entity_records = sent_entities

func _close(id: int, reason: String) -> void:
	if not clients.has(id): return
	var socket: WebSocketPeer = clients[id].socket
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN: socket.close(1008, reason)
	_drop(id)

func _drop(id: int) -> void:
	if not clients.has(id): return
	var client: Dictionary = clients[id]
	if rooms.has(client.room) and client.player_id != "": rooms[client.room].disconnect_player(client.player_id)
	var stream: StreamPeerTCP = client.stream
	stream.disconnect_from_host()
	clients.erase(id)

func _finalize() -> void:
	for room in rooms.values():
		if not room.closed: room.close_room("服务器停止")
	listener.stop()
