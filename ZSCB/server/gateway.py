#!/usr/bin/env python3
"""Bounded HTTP / WebSocket gateway. Railway terminates TLS before this process."""
from __future__ import annotations
import base64
import hashlib
import os
import selectors
import socket
import socketserver
import threading
import time

MAX_HEADERS = 8192
RELAY_BUFFER = 262144
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class HeaderTooLarge(ValueError):
    pass


def read_headers(sock):
    data = bytearray()
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(min(2048, MAX_HEADERS + 1 - len(data)))
        if not chunk:
            raise ConnectionError("Incomplete headers")
        data.extend(chunk)
        if len(data) > MAX_HEADERS:
            raise HeaderTooLarge()
    header, tail = bytes(data).split(b"\r\n\r\n", 1)
    return header, tail


def parse_headers(raw):
    lines = raw.decode("ascii").split("\r\n")
    first = lines.pop(0).split(" ", 2)
    if len(first) != 3:
        raise ValueError("Invalid request line")
    headers = {}
    for line in lines:
        name, value = line.split(":", 1)
        if not name or name.strip() != name or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-" for c in name):
            raise ValueError("Invalid header name")
        name = name.lower()
        if name in headers or "\r" in value or "\n" in value:
            raise ValueError("Duplicate or invalid header")
        headers[name] = value.strip()
    return first, headers


def valid_upgrade(headers):
    try:
        key = base64.b64decode(headers.get("sec-websocket-key", ""), validate=True)
    except ValueError:
        return False
    return (headers.get("upgrade", "").lower() == "websocket"
            and "upgrade" in [v.strip().lower() for v in headers.get("connection", "").split(",")]
            and headers.get("sec-websocket-version") == "13" and len(key) == 16)


def upstream_handshake(address, key):
    sock = socket.create_connection(address, timeout=2)
    try:
        sock.settimeout(2)
        request = (f"GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                   f"Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n")
        sock.sendall(request.encode("ascii"))
        header, tail = read_headers(sock)
        first, response = parse_headers(header)
        expected = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest()).decode("ascii")
        if first[:2] != ["HTTP/1.1", "101"] or response.get("sec-websocket-accept") != expected:
            raise ConnectionError("Godot did not accept WebSocket handshake")
        return sock, header + b"\r\n\r\n", tail
    except Exception:
        sock.close()
        raise


def relay(client, upstream, client_tail=b"", upstream_tail=b""):
    """Apply backpressure instead of accumulating an unlimited game-state queue."""
    client.setblocking(False)
    upstream.setblocking(False)
    sockets = (client, upstream)
    output = {client: bytearray(upstream_tail), upstream: bytearray(client_tail)}
    last_activity = time.monotonic()
    input_closed = set()
    write_closed = set()
    with selectors.DefaultSelector() as selector:
        while time.monotonic() - last_activity < 45:
            for current, other in ((client, upstream), (upstream, client)):
                events = (selectors.EVENT_READ if current not in input_closed and len(output[other]) < RELAY_BUFFER else 0)
                if output[current]:
                    events |= selectors.EVENT_WRITE
                try:
                    selector.get_key(current)
                    if events:
                        selector.modify(current, events)
                    else:
                        selector.unregister(current)
                except KeyError:
                    if events:
                        selector.register(current, events)
            for key, events in selector.select(timeout=1):
                current = key.fileobj
                other = upstream if current is client else client
                try:
                    if events & selectors.EVENT_READ:
                        data = current.recv(min(65536, RELAY_BUFFER - len(output[other])))
                        if not data:
                            input_closed.add(current)
                        output[other].extend(data)
                        last_activity = time.monotonic()
                    if events & selectors.EVENT_WRITE:
                        sent = current.send(output[current])
                        del output[current][:sent]
                        last_activity = time.monotonic()
                except BlockingIOError:
                    continue
                except OSError:
                    return
            for current, other in ((client, upstream), (upstream, client)):
                if current in input_closed and not output[other] and other not in write_closed:
                    try:
                        other.shutdown(socket.SHUT_WR)
                    except OSError:
                        pass
                    write_closed.add(other)
            if len(input_closed) == 2 and not any(output.values()):
                return


class GatewayHandler(socketserver.BaseRequestHandler):
    def reply(self, status, reason, body):
        payload = body.encode("ascii")
        self.request.sendall((f"HTTP/1.1 {status} {reason}\r\nContent-Type: text/plain; charset=utf-8\r\n"
                              f"Content-Length: {len(payload)}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n").encode("ascii") + payload)

    def handle(self):
        self.request.settimeout(5)
        try:
            raw, tail = read_headers(self.request)
            first, headers = parse_headers(raw)
            method, path, version = first
            if version != "HTTP/1.1" or not headers.get("host"):
                self.reply(400, "Bad Request", "Invalid HTTP request\n")
                return
            if method != "GET":
                self.reply(405, "Method Not Allowed", "GET required\n")
                return
            if headers.get("transfer-encoding") or headers.get("content-length", "0") != "0":
                self.reply(400, "Bad Request", "Request body not supported\n")
                return
            if path == "/healthz":
                try:
                    probe, _, _ = upstream_handshake(self.server.upstream, base64.b64encode(os.urandom(16)).decode("ascii"))
                    probe.close()
                    self.reply(200, "OK", "ready\n")
                except (OSError, ValueError):
                    self.reply(503, "Service Unavailable", "Godot unavailable\n")
                return
            if path != "/ws":
                self.reply(404, "Not Found", "Unknown endpoint\n")
                return
            if not valid_upgrade(headers):
                self.reply(400, "Bad Request", "WebSocket upgrade required\n")
                return
            try:
                upstream, response, upstream_tail = upstream_handshake(self.server.upstream, headers["sec-websocket-key"])
            except (OSError, ValueError):
                self.reply(503, "Service Unavailable", "Godot unavailable\n")
                return
            with upstream:
                self.request.sendall(response)
                relay(self.request, upstream, tail, upstream_tail)
        except HeaderTooLarge:
            self.reply(431, "Request Header Fields Too Large", "Headers too large\n")
        except (ValueError, UnicodeError):
            self.reply(400, "Bad Request", "Malformed request\n")
        except OSError:
            pass


class GatewayServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 32

    def __init__(self, address, upstream, max_connections=64):
        self.upstream = upstream
        self.slots = threading.BoundedSemaphore(max_connections)
        super().__init__(address, GatewayHandler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        # Never print untrusted request contents or credentials.
        print("gateway connection failed", flush=True)


def main():
    port = int(os.environ.get("PORT", "9080"))
    upstream_port = int(os.environ.get("NET_PORT", "9081"))
    with GatewayServer(("0.0.0.0", port), ("127.0.0.1", upstream_port)) as server:
        print(f"gateway listening on {port}", flush=True)
        server.serve_forever(poll_interval=0.2)


if __name__ == "__main__":
    main()
