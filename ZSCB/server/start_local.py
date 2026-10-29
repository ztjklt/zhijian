#!/usr/bin/env python3
"""Supervise the local authority and gateway. Does not open or deploy anything."""
from __future__ import annotations
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading


def godot_binary():
    explicit = os.environ.get("GODOT_BIN")
    if explicit:
        return explicit
    installed = shutil.which("godot") or shutil.which("godot4")
    if installed:
        return installed
    return str(Path.home() / "Applications/Godot.app/Contents/MacOS/Godot")


def main():
    project = Path(__file__).resolve().parents[1]
    env = dict(os.environ)
    env.setdefault("NET_DATA_DIR", str(Path.home() / ".local/share/paper-castle-server/worlds"))
    stopped = threading.Event()
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, lambda _signum, _frame: stopped.set())
    processes = []
    try:
        processes.append(subprocess.Popen([godot_binary(), "--headless", "--audio-driver", "Dummy", "--path", str(project), "--script", "res://server/server.gd"], env=env))
        processes.append(subprocess.Popen([sys.executable, str(project / "server/gateway.py")], env=env))
        print(f"Local endpoint: ws://127.0.0.1:{env.get('PORT', '9080')}/ws", flush=True)
        while not stopped.wait(0.2):
            for process in processes:
                if process.poll() is not None:
                    return process.returncode or 1
        return 0
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
        for process in processes:
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
