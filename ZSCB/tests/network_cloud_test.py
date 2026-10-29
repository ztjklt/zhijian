"""Explicit live WSS checks. Uses only a newly created test world, never player saves.

prepare writes temporary private credentials; restore verifies them after an operator
restarts the server. No Railway account credentials or restart operations are used here.
"""
from pathlib import Path
from urllib.parse import urlsplit
import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import statistics
import time

from network_transport_test import WebSocketClient, read_headers, GUID


class CloudClient(WebSocketClient):
    def __init__(self, address):
        url = urlsplit(address)
        if url.scheme != "wss" or not url.hostname or url.username or url.password:
            raise ValueError("Expected a credential-free wss://host/path address")
        self.epoch, self.pending = "", []
        raw = socket.create_connection((url.hostname, url.port or 443), timeout=15)
        self.sock = ssl.create_default_context().wrap_socket(raw, server_hostname=url.hostname)
        self.sock.settimeout(15)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET {url.path or '/ws'} HTTP/1.1\r\nHost: {url.netloc}\r\n"
                           f"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                           f"Sec-WebSocket-Key: {key}\r\n\r\n").encode())
        header = read_headers(self.sock)
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest())
        assert b"101 Switching Protocols" in header and accept in header, "Invalid WSS handshake"


def operation(client, seq, op, **fields):
    client.send(dict(type="command", seq=seq, op=op, **fields))
    result = client.until("result")
    assert result["seq"] == seq and result["op"] == op
    return result


def run(args):
    clients = []

    def connect():
        client = CloudClient(args.address)
        clients.append(client)
        return client

    try:
        owner = connect()
        if args.phase == "prepare":
            if args.fixture.exists():
                raise FileExistsError("Use a new private fixture path")
            owner.send(dict(type="create", map_id="paper", name="WSS验收甲"))
            identity = owner.until("welcome")
            owner.ready()
            guest = connect()
            guest.send(dict(type="join", code=identity["code"], name="WSS验收乙"))
            guest_id = guest.until("welcome")
            snapshot = guest.ready()
            third = connect()
            third.send(dict(type="join", code=identity["code"], name="WSS验收第三人"))
            assert third.until("error")["error"] == "room_full"
            position = next(a["position"]["_v"] for a in snapshot["actors"] if a["id"] == guest_id["player_id"])
            shape = dict(source="own", kind="freehand", x=position[0]+3, y=position[1]+3,
                         paths=[dict(points=[{"_v": [-.4, 0]}, {"_v": [.4, 0]}], collision=True)], dynamic=True)
            spawned = operation(guest, 1, "spawn", object=shape)
            assert spawned["ok"], spawned.get("error")
            assert not operation(guest, 2, "save")["ok"], "Guest acquired owner permission"
            latencies = []
            for _ in range(10):
                start = time.monotonic()
                owner.send(dict(type="ping")); owner.until("pong")
                latencies.append((time.monotonic()-start)*1000)
            assert operation(owner, 1, "save")["ok"]
            fixture = dict(address=args.address, world_id=identity["world_id"], owner_token=identity["token"],
                           owner_id=identity["player_id"], guest_token=guest_id["token"], guest_id=guest_id["player_id"],
                           object_id=spawned["id"])
            args.fixture.parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(args.fixture, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as file: json.dump(fixture, file)
            owner.send(dict(type="command", seq=2, op="leave")); owner.until("closed")
            print(json.dumps(dict(phase="prepare", status="PASS", wss_certificate_verified=True,
                                  checks=["two_players", "third_rejected", "shared_spawn", "owner_permissions", "save"],
                                  ping_median_ms=round(statistics.median(latencies), 1), ping_max_ms=round(max(latencies), 1))))
        else:
            fixture = json.loads(args.fixture.read_text())
            assert fixture["address"] == args.address, "Fixture belongs to another server"
            owner.send(dict(type="create", world_id=fixture["world_id"], owner_token=fixture["owner_token"]))
            identity = owner.until("welcome")
            assert identity["player_id"] == fixture["owner_id"]
            snapshot = owner.ready()
            saved = next(o for o in snapshot["objects"] if o["id"] == fixture["object_id"])
            guest = connect()
            guest.send(dict(type="join", code=identity["code"], name="WSS验收乙",
                            known_tokens={fixture["world_id"]: fixture["guest_token"]}))
            assert guest.until("welcome")["player_id"] == fixture["guest_id"]
            guest.ready()
            result = operation(guest, 1, "delete", id=saved["id"], version=saved["version"])
            assert result["ok"], "Returning author lost ownership: " + result.get("error", "")
            owner.send(dict(type="command", seq=1, op="leave")); owner.until("closed")
            print(json.dumps(dict(phase="restore", status="PASS",
                                  checks=["world_survived_restart", "owner_identity", "guest_identity", "guest_authorship"])))
    finally:
        for client in clients: client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "restore"])
    parser.add_argument("--address", required=True)
    parser.add_argument("--fixture", type=Path, required=True, help="Private temporary file outside the repository")
    run(parser.parse_args())
