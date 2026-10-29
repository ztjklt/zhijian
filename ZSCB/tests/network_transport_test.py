"""Real TCP tests for the HTTP gateway; no cloud services or user saves."""
from __future__ import annotations
from runtime_tools import resolve_godot, user_data_path
import base64
import hashlib
import importlib.util
import socket
import socketserver
import struct
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import uuid
import threading
import unittest
from pathlib import Path

GATEWAY_FILE = Path(__file__).resolve().parents[1] / "server" / "gateway.py"
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def read_headers(sock):
    data = b""
    while b"\r\n\r\n" not in data:
        block = sock.recv(1)
        if not block:
            break
        data += block
    return data


def handshake(sock, path="/ws"):
    key = base64.b64encode(b"transport-test!!").decode()
    sock.sendall((f"GET {path} HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
                  f"Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                  f"Sec-WebSocket-Key: {key}\r\n\r\n").encode())
    return read_headers(sock)


class EchoSocket(socketserver.BaseRequestHandler):
    """A minimal actual WebSocket endpoint to test the gateway boundary."""
    def handle(self):
        self.request.settimeout(2)
        try:
            header = read_headers(self.request)
            key = next(line.split(b":", 1)[1].strip() for line in header.split(b"\r\n")
                       if line.lower().startswith(b"sec-websocket-key:"))
            accept = base64.b64encode(hashlib.sha1(key + GUID.encode()).digest())
            self.request.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                                 b"Connection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
            frame = self.request.recv(65536)
            if frame:
                self.request.sendall(frame)  # Preserve bytes so proxy corruption is visible.
        except (OSError, StopIteration):
            pass


class HttpOnlySocket(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        try:
            read_headers(self.request)
            self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
        except OSError:
            pass


class Endpoint(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class GatewayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gateway = None
        if not GATEWAY_FILE.exists():
            return
        spec = importlib.util.spec_from_file_location("paper_gateway", GATEWAY_FILE)
        cls.gateway = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.gateway)

    def setUp(self):
        self.assertIsNotNone(self.gateway, "WebSocket gateway implementation is missing")
        self.upstream = Endpoint(("127.0.0.1", 0), EchoSocket)
        threading.Thread(target=self.upstream.serve_forever, daemon=True).start()
        self.server = self.gateway.GatewayServer(("127.0.0.1", 0), self.upstream.server_address)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.upstream.shutdown()
        self.upstream.server_close()

    def request(self, request):
        with socket.create_connection(self.server.server_address, timeout=3) as sock:
            sock.sendall(request)
            return read_headers(sock)

    def test_health_requires_actual_websocket_service(self):
        self.assertIn(b"200 OK", self.request(b"GET /healthz HTTP/1.1\r\nHost: local\r\n\r\n"))
        self.upstream.shutdown()
        self.upstream.server_close()
        self.assertIn(b"503 Service Unavailable", self.request(b"GET /healthz HTTP/1.1\r\nHost: local\r\n\r\n"))

    def test_health_rejects_a_tcp_listener_without_websocket(self):
        with Endpoint(("127.0.0.1", 0), HttpOnlySocket) as http_only:
            worker = threading.Thread(target=http_only.serve_forever, daemon=True)
            worker.start()
            self.server.upstream = http_only.server_address
            self.assertIn(b"503 Service Unavailable", self.request(b"GET /healthz HTTP/1.1\r\nHost: local\r\n\r\n"))
            http_only.shutdown()

    def test_websocket_upgrade_and_bytes_cross_both_directions(self):
        with socket.create_connection(self.server.server_address, timeout=3) as sock:
            self.assertIn(b"101 Switching Protocols", handshake(sock))
            payload = b'{"type":"ping"}'
            masked = bytes(value ^ b"abcd"[i % 4] for i, value in enumerate(payload))
            frame = b"\x81" + bytes([0x80 | len(payload)]) + b"abcd" + masked
            sock.sendall(frame)
            self.assertEqual(frame, sock.recv(65536))

    def test_invalid_upgrade_is_rejected_without_proxying(self):
        self.assertIn(b"400 Bad Request", self.request(b"GET /ws HTTP/1.1\r\nHost: local\r\n\r\n"))
        self.assertIn(b"404 Not Found", self.request(b"GET /other HTTP/1.1\r\nHost: local\r\n\r\n"))
        self.assertIn(b"405 Method Not Allowed", self.request(b"POST /healthz HTTP/1.1\r\nHost: local\r\nContent-Length: 0\r\n\r\n"))

    def test_oversized_headers_are_bounded(self):
        self.assertIn(b"431 Request Header Fields Too Large", self.request(
            b"GET /ws HTTP/1.1\r\nX: " + b"x" * 9000 + b"\r\n\r\n"))

    def test_upgrade_returns_unavailable_if_godot_stopped(self):
        self.upstream.shutdown()
        self.upstream.server_close()
        with socket.create_connection(self.server.server_address, timeout=3) as sock:
            self.assertIn(b"503 Service Unavailable", handshake(sock))




# These tests use a real Godot headless process and the real gateway in an isolated
# project copy. Enable with --godot after all shared room modules are available.
class WebSocketClient:
    def __init__(self, address):
        self.epoch = ""
        self.pending = []
        self.sock = socket.create_connection(address, timeout=5)
        self.sock.settimeout(5)
        response = handshake(self.sock)
        if b"101 Switching Protocols" not in response:
            raise AssertionError(response.decode(errors="replace"))

    def close(self):
        self.sock.close()

    def send(self, value, attach_epoch=True):
        self.sock.sendall(self._frame(value, attach_epoch))

    def send_batch(self, *values):
        self.sock.sendall(b"".join(self._frame(value) for value in values))

    def _frame(self, value, attach_epoch=True):
        if attach_epoch and value.get("type") == "command" and "epoch" not in value:
            value = dict(value, epoch=self.epoch)
        if value.get("type") in ("create", "join") and "protocol" not in value:
            codec = Path(__file__).resolve().parents[1] / "scripts/net/codec.gd"
            version = int(re.search(r"const PROTOCOL := (\d+)", codec.read_text()).group(1))
            value = dict(value, protocol=version)
        payload = json.dumps(value, separators=(",", ":")).encode()
        header = b"\x81"
        if len(payload) < 126:
            header += bytes([0x80 | len(payload)])
        elif len(payload) < 65536:
            header += bytes([0x80 | 126]) + struct.pack("!H", len(payload))
        else:
            header += bytes([0x80 | 127]) + struct.pack("!Q", len(payload))
        mask = os.urandom(4)
        return header + mask + bytes(v ^ mask[i % 4] for i, v in enumerate(payload))

    def exact(self, count):
        result = b""
        while len(result) < count:
            chunk = self.sock.recv(count - len(result))
            if not chunk:
                raise ConnectionError("WebSocket disconnected")
            result += chunk
        return result

    def receive(self):
        return self.pending.pop(0) if self.pending else self._receive_wire()

    def _receive_wire(self):
        while True:
            first, second = self.exact(2)
            count = second & 127
            if count == 126:
                count = struct.unpack("!H", self.exact(2))[0]
            elif count == 127:
                count = struct.unpack("!Q", self.exact(8))[0]
            if count > 8 * 1024 * 1024:
                raise AssertionError("Unbounded server packet")
            payload = self.exact(count)
            if first & 15 == 9:
                mask = b"abcd"
                self.sock.sendall(b"\x8a" + bytes([128 | len(payload)]) + mask + bytes(v ^ mask[i % 4] for i, v in enumerate(payload)))
                continue
            if first & 15 == 8:
                raise ConnectionError("WebSocket closed")
            if first & 15 == 1:
                value = json.loads(payload)
                if value.get("type") == "welcome":
                    self.epoch = value["epoch"]
                return value

    def until(self, message_type):
        for index, message in enumerate(self.pending):
            if message.get("type") == message_type:
                return self.pending.pop(index)
        for _ in range(200):
            message = self._receive_wire()
            if message.get("type") == message_type:
                return message
            if message.get("type") == "error" and message_type != "error":
                raise AssertionError("Protocol error: " + str(message.get("error")))
            if message.get("type") != "frame":
                self.pending.append(message)
        raise AssertionError(f"No {message_type} received")

    def ready(self, before_ready=None):
        begin = self.until("snapshot_begin")
        self.epoch = begin["epoch"]
        chunks = {}
        while True:
            part = self.receive()
            if part.get("type") == "snapshot_chunk":
                if part["epoch"] != begin["epoch"]:
                    raise AssertionError("Snapshot epoch changed mid-stream")
                chunks[part["index"]] = part["data"]
            elif part.get("type") == "snapshot_end":
                break
            elif part.get("type") == "error":
                raise AssertionError("Snapshot failed: " + str(part.get("error")))
        if len(chunks) != begin["chunks"]:
            raise AssertionError("Incomplete snapshot")
        snapshot = json.loads("".join(chunks[i] for i in range(begin["chunks"])))
        if before_ready:
            before_ready()
        self.send({"type": "ready", "epoch": begin["epoch"]})
        self.until("ready")
        return snapshot


@unittest.skipUnless("--godot" in __import__("sys").argv, "pass --godot for isolated real Godot integration")
class GodotTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = None
        cls.process = None
        cls.log = None
        cls.user_name = ""
        cls.temp = tempfile.TemporaryDirectory(prefix="paper-net-transport-")
        cls.addClassCleanup(cls._shutdown)
        cls.project = Path(cls.temp.name) / "project"
        source = Path(__file__).resolve().parents[1]
        shutil.copytree(source, cls.project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
        project_config = cls.project / "project.godot"
        cls.user_name = "PaperTransportIsolated_" + uuid.uuid4().hex
        project_config.write_text(project_config.read_text().replace("纸上城堡 · 火柴人沙盒", cls.user_name))
        cls.godot = resolve_godot()
        imported = subprocess.run([cls.godot, "--headless", "--path", str(cls.project), "--editor", "--import", "--quit"], capture_output=True, text=True, timeout=60)
        if imported.returncode or "SCRIPT ERROR" in imported.stderr:
            raise AssertionError(imported.stdout + imported.stderr)
        cls.log = open(Path(cls.temp.name) / "godot.log", "w+")
        cls.net_port = free_port()
        env = dict(os.environ, NET_PORT=str(cls.net_port), NET_DATA_DIR=str(Path(cls.temp.name) / "worlds"), NET_MAX_ROOMS="4")
        cls.process = subprocess.Popen([cls.godot, "--headless", "--path", str(cls.project), "--script", "res://server/server.gd"], env=env, stdout=cls.log, stderr=subprocess.STDOUT)
        spec = importlib.util.spec_from_file_location("paper_gateway_real", source / "server/gateway.py")
        gateway = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gateway)
        cls.server = gateway.GatewayServer(("127.0.0.1", 0), ("127.0.0.1", cls.net_port))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        for _ in range(120):
            if cls.process.poll() is not None:
                cls.log.seek(0)
                raise AssertionError(cls.log.read())
            try:
                with socket.create_connection(cls.server.server_address, timeout=1) as sock:
                    sock.sendall(b"GET /healthz HTTP/1.1\r\nHost: local\r\n\r\n")
                    if b"200 OK" in read_headers(sock):
                        return
            except OSError:
                pass
            time.sleep(0.05)
        cls.log.seek(0)
        raise AssertionError("Godot transport did not become ready\n" + cls.log.read())

    @classmethod
    def _shutdown(cls):
        if cls.server is not None:
            cls.server.shutdown()
            cls.server.server_close()
        if cls.process is not None:
            cls.process.terminate()
            try:
                cls.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                cls.process.kill()
                cls.process.wait()
        server_output = ""
        if cls.log is not None:
            cls.log.seek(0)
            server_output = cls.log.read()
            cls.log.close()
        cls.temp.cleanup()
        user_data = user_data_path(cls.user_name) if cls.user_name else None
        if cls.user_name and user_data.exists():
            shutil.rmtree(user_data)
        if "SCRIPT ERROR" in server_output or "ERROR:" in server_output:
            raise AssertionError(server_output)

    def setUp(self):
        self.clients = []

    def tearDown(self):
        for client in self.clients:
            client.close()

    def connect(self):
        client = WebSocketClient(self.server.server_address)
        self.clients.append(client)
        return client

    def create(self):
        client = self.connect()
        client.send({"type": "create", "map_id": "nature-v1", "name": "Owner"})
        return client, client.until("welcome")

    def test_static_map_records_are_not_resent_every_frame(self):
        owner = self.connect()
        owner.send({"type": "create", "map_id": "medieval-v1", "name": "Bandwidth"})
        owner.until("welcome")
        snapshot = owner.ready()
        first = owner.until("frame")
        second = owner.until("frame")
        self.assertGreater(len(snapshot["world"]["entities"]), 100)
        self.assertGreater(len(first["entities"]), 100)
        self.assertLess(len(second["entities"]), len(first["entities"]) // 2,
                        "static scenery must not saturate the connection at 20Hz")

    def test_old_client_is_rejected_before_creating_a_room(self):
        legacy = self.connect()
        legacy.send({"type": "create", "map_id": "paper", "protocol": 0})
        self.assertEqual("version_mismatch", legacy.until("error")["error"])

    def test_drawing_preview_delta_is_negotiated_and_resync_safe(self):
        owner = self.connect()
        owner.send({"type": "create", "map_id": "paper", "preview_delta": True})
        welcome = owner.until("welcome")
        owner.ready()
        guest = self.connect()
        guest.send({"type": "join", "code": welcome["code"], "name": "Legacy"})
        guest.until("welcome")
        guest.ready()
        drawing = [{"points": [{"_v": [-5, 0]}, {"_v": [-4, 1]}]}]
        try:
            owner.send({"type": "command", "op": "preview", "seq": 1, "paths": drawing})
            self.assertTrue(owner.until("result")["ok"])
            for _ in range(20):
                state = next(a for a in owner.until("frame")["actors"] if a["id"] == welcome["player_id"])
                if state.get("preview") == drawing:
                    break
            else:
                self.fail("changed drawing never arrived")
            state = next(a for a in owner.until("frame")["actors"] if a["id"] == welcome["player_id"])
            self.assertNotIn("preview", state, "negotiated unchanged strokes must not fill every position frame")
            for _ in range(20):
                state = next(a for a in guest.until("frame")["actors"] if a["id"] == welcome["player_id"])
                if state.get("preview") == drawing:
                    break
            else:
                self.fail("legacy client lost complete drawing")
            state = next(a for a in guest.until("frame")["actors"] if a["id"] == welcome["player_id"])
            self.assertEqual(drawing, state["preview"], "unnegotiated client still receives complete previews")
            owner.send({"type": "resync"})
            snapshot = owner.ready()
            self.assertEqual(drawing, next(a for a in snapshot["actors"] if a["id"] == welcome["player_id"])["preview"])
            owner.send({"type": "command", "op": "preview", "seq": 2, "paths": []})
            self.assertTrue(owner.until("result")["ok"])
            for _ in range(20):
                state = next(a for a in owner.until("frame")["actors"] if a["id"] == welcome["player_id"])
                if "preview" in state and state["preview"] == []:
                    break
            else:
                self.fail("explicit clear never arrived")
        finally:
            owner.send({"type": "command", "seq": 3, "op": "leave"})
            owner.until("closed")

    def test_equipment_changes_arrive_incrementally_and_then_are_omitted(self):
        owner, welcome = self.create()
        owner.ready()
        owner.send({"type": "command", "op": "equip", "seq": 1,
                    "weapon": {"paths": [{"points": [{"_v": [0, 0]}, {"_v": [0, 0.9]}]}], "grip": {"_v": [0, 0]}}})
        self.assertTrue(owner.until("result")["ok"])
        for _ in range(20):
            state = next(a for a in owner.until("frame")["actors"] if a["id"] == welcome["player_id"])
            if state.get("weapon"):
                break
        else:
            self.fail("No incremental equipment update")
        state = next(a for a in owner.until("frame")["actors"] if a["id"] == welcome["player_id"])
        self.assertNotIn("weapon", state, "unchanged geometry must not be resent at 20Hz")
        owner.send({"type": "command", "op": "equip", "seq": 2, "weapon": {}})
        self.assertTrue(owner.until("result")["ok"])
        for _ in range(20):
            state = next(a for a in owner.until("frame")["actors"] if a["id"] == welcome["player_id"])
            if "weapon" in state:
                self.assertEqual({}, state["weapon"])
                break
        else:
            self.fail("Unequip did not reach client")

    def test_ready_gate_two_players_identity_and_resync(self):
        owner, welcome = self.create()
        def blocked_command():
            owner.send({"type": "command", "seq": 1, "op": "save"})
            result = owner.until("result")
            self.assertEqual("not_ready", result["error"])
            self.assertEqual(1, result["seq"])
            self.assertEqual("save", result["op"])
            self.assertFalse(result["ok"])
        snapshot = owner.ready(blocked_command)
        self.assertIn("objects", snapshot)
        guest = self.connect()
        guest.send({"type": "join", "code": welcome["code"], "name": "Guest", "player_id": welcome["player_id"]})
        guest_welcome = guest.until("welcome")
        self.assertNotEqual(welcome["player_id"], guest_welcome["player_id"])
        self.assertFalse(guest_welcome["owner"])
        guest.ready()
        third = self.connect()
        third.send({"type": "join", "code": welcome["code"], "name": "Third"})
        self.assertEqual("room_full", third.until("error")["error"])
        guest.send({"type": "command", "seq": 1, "op": "save", "player_id": welcome["player_id"]})
        self.assertFalse(guest.until("result")["ok"])
        for attempt in range(2):
            if attempt:
                time.sleep(1.05)  # Respect the public resync rate limit.
            owner.send({"type": "resync"})
            refreshed = owner.ready()
            self.assertTrue(next(actor["connected"] for actor in refreshed["actors"] if actor["id"] == welcome["player_id"]),
                            "Routine resync must leave a live actor targetable")
        owner.send({"type": "command", "seq": 2, "op": "leave"})
        self.assertIn("error", guest.until("closed"))

    def test_malformed_sequence_is_rejected_and_connection_survives(self):
        owner, _ = self.create()
        owner.ready()
        owner.send({"type": "command", "seq": {"bad": True}, "op": "input"})
        self.assertEqual("invalid_sequence", owner.until("error")["error"])
        owner.send({"type": "command", "seq": 1, "op": "leave"})
        owner.until("closed")

    def test_guest_reconnect_and_owner_saved_world_resume(self):
        owner, original = self.create()
        snapshot = owner.ready()
        self.assertNotIn(original["token"], json.dumps(snapshot))
        guest = self.connect()
        guest.send({"type": "join", "code": original["code"], "name": "Guest"})
        identity = guest.until("welcome")
        guest.ready()
        guest.send({"type": "command", "seq": 7, "op": "input", "right": False})
        self.assertTrue(guest.until("result")["ok"])
        guest.close()
        for _ in range(100):
            frame = owner.until("frame")
            if any(actor["id"] == identity["player_id"] and not actor["connected"] for actor in frame["actors"]):
                break
        else:
            self.fail("Disconnected guest stayed active")
        reconnected = self.connect()
        reconnected.send({"type": "join", "code": original["code"], "token": identity["token"], "name": "Guest"})
        reconnect_identity = reconnected.until("welcome")
        self.assertEqual(identity["player_id"], reconnect_identity["player_id"])
        self.assertEqual(7, reconnect_identity["next_seq"])
        reconnected.ready()
        owner.send({"type": "command", "seq": 1, "op": "leave"})
        owner.until("closed")
        bad = self.connect()
        bad.send({"type": "create", "world_id": original["world_id"], "owner_token": "wrong"})
        self.assertEqual("invalid_owner", bad.until("error")["error"])
        restored = self.connect()
        restored.send({"type": "create", "world_id": original["world_id"], "owner_token": original["token"]})
        resumed = restored.until("welcome")
        self.assertNotEqual(original["code"], resumed["code"])
        self.assertEqual(original["world_id"], resumed["world_id"])
        self.assertEqual(original["player_id"], resumed["player_id"])
        restored.ready()
        returning_guest = self.connect()
        returning_guest.send({"type": "join", "code": resumed["code"], "name": "Guest",
                              "known_tokens": {resumed["world_id"]: identity["token"]}})
        returning_identity = returning_guest.until("welcome")
        self.assertEqual(identity["player_id"], returning_identity["player_id"])
        returning_guest.ready()
        restored.send({"type": "command", "seq": 1, "op": "leave"})
        restored.until("closed")

    def test_missing_epoch_is_rejected_with_correlated_result(self):
        owner, identity = self.create()
        owner.ready()
        owner.send({"type": "command", "seq": 1, "op": "save"}, attach_epoch=False)
        denied = owner.until("result")
        self.assertEqual((False, "stale_epoch", 1, "save", identity["epoch"]),
                         (denied["ok"], denied["error"], denied["seq"], denied["op"], denied["epoch"]))
        owner.send({"type": "command", "seq": 2, "op": "leave"})
        owner.until("closed")

    def test_import_rotates_epoch_and_rejects_queued_guest_commands(self):
        owner, identity = self.create()
        owner.ready()
        guest = self.connect()
        guest.send({"type": "join", "code": identity["code"], "name": "Guest"})
        guest_id = guest.until("welcome")["player_id"]
        initial = guest.ready()
        position = next(actor["position"]["_v"] for actor in initial["actors"] if actor["id"] == guest_id)
        old_epoch = guest.epoch
        # Both frames arrive in one TCP write: resync must announce the changed
        # epoch even before the periodic broadcast gets a chance to run.
        owner.send_batch({"type": "command", "seq": 1, "op": "import", "data": {"objects": [], "world": {"id": "nature-v1"}}},
                         {"type": "resync"})
        self.assertTrue(owner.until("result")["ok"])
        shape = {"source": "own", "kind": "freehand", "x": position[0] + 2, "y": position[1] + 2,
                 "paths": [{"points": [{"_v": [-0.4, 0]}, {"_v": [0.4, 0]}], "collision": True}], "dynamic": True}
        guest.send({"type": "command", "epoch": old_epoch, "seq": 1, "op": "spawn", "object": shape})
        denied = guest.until("result")
        self.assertEqual((False, "stale_epoch", 1, "spawn"), (denied["ok"], denied["error"], denied["seq"], denied["op"]))
        changed = guest.until("world_changed")
        self.assertNotEqual(old_epoch, changed["epoch"])
        refreshed = guest.ready()
        self.assertEqual(changed["epoch"], refreshed["epoch"])
        self.assertEqual([], refreshed["objects"])
        owner.until("world_changed")
        owner.ready()
        guest.send({"type": "command", "seq": 2, "op": "spawn", "object": shape})
        self.assertTrue(guest.until("result")["ok"], "The same valid shape must be accepted under the current epoch")
        owner.send({"type": "command", "seq": 2, "op": "leave"})
        owner.until("closed")

    def test_room_isolation_and_invalid_map(self):
        invalid = self.connect()
        invalid.send({"type": "create", "map_id": "../../other", "name": "Bad"})
        self.assertEqual("invalid_map", invalid.until("error")["error"])
        first, a = self.create()
        first.ready()
        second, b = self.create()
        second.ready()
        self.assertNotEqual(a["code"], b["code"])
        first.send({"type": "ping"})
        self.assertEqual("pong", first.until("pong")["type"])
        frame = second.until("frame")
        self.assertEqual(1, len(frame["actors"]))
        for client in (first, second):
            client.send({"type": "command", "seq": 1, "op": "leave"})
            client.until("closed")


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


if __name__ == "__main__":
    import sys
    unittest.main(argv=[arg for arg in sys.argv if arg != "--godot"], verbosity=2)
