"""Test-only stream delay/rate limit. No external services or persistent state."""
import select
import socket
import socketserver
import threading
import time
from collections import deque


class DelayProxy(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, upstream, latency_ms=0, bandwidth_kbps=0):
        self.upstream = upstream
        self.one_way = latency_ms / 2000
        self.rate = bandwidth_kbps * 1024
        super().__init__(("127.0.0.1", 0), Relay)


class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            with socket.create_connection(self.server.upstream, timeout=5) as upstream:
                sockets = (self.request, upstream)
                pending = {stream: deque() for stream in sockets}
                next_slot = {stream: 0.0 for stream in sockets}
                for stream in sockets:
                    stream.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                while True:
                    now = time.monotonic()
                    for target, chunks in pending.items():
                        while chunks and chunks[0][0] <= now:
                            _, data = chunks.popleft()
                            target.sendall(data)
                    deadlines = [chunks[0][0] for chunks in pending.values() if chunks]
                    timeout = min(.1, max(0, min(deadlines) - now)) if deadlines else .1
                    readable, _, _ = select.select(sockets, [], [], timeout)
                    for source in readable:
                        data = source.recv(8192)
                        if not data:
                            return
                        target = upstream if source is self.request else self.request
                        delivery = max(time.monotonic() + self.server.one_way, next_slot[target])
                        if self.server.rate:
                            delivery += len(data) / self.server.rate
                        next_slot[target] = delivery
                        pending[target].append((delivery, data))
                        if sum(len(item[1]) for item in pending[target]) > 2 * 1024 * 1024:
                            return
        except (OSError, ValueError):
            return


def start_delay_proxy(upstream, latency_ms=0, bandwidth_kbps=0):
    proxy = DelayProxy(upstream, latency_ms, bandwidth_kbps)
    threading.Thread(target=proxy.serve_forever, daemon=True).start()
    return proxy
