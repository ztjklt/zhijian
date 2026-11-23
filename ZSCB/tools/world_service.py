"""Run one desktop sandbox per save slot and coordinate its local writer."""
import argparse
import contextlib
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

ROOT = "team_worlds_v1"
SLOT = re.compile(r"[0-9a-f]{32}\Z")


def birth(pid):
    if not isinstance(pid, int) or pid < 1:
        return ""
    row = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat=,lstart="],
                         text=True, capture_output=True).stdout.strip().split(None, 1)
    return row[1] if len(row) == 2 and not row[0].startswith("Z") else ""


def runtime(args):
    if not SLOT.fullmatch(args.slot):
        raise ValueError("队伍槽编号无效。")
    return Path(args.data).resolve() / ROOT / args.slot / ".runtime"


def write_json(path, value):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as tmp:
        json.dump(value, tmp, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    os.replace(tmp.name, path)


@contextlib.contextmanager
def transaction(folder):
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (folder / "control.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = folder / "control.json"
        data = json.loads(path.read_text()) if path.exists() else {}
        original = data.copy()
        for attr in ("owner", "supervisor", "standby"):
            rec = data.get(attr)
            if rec and (not rec.get("birth") or birth(rec["pid"]) != rec["birth"]):
                data.pop(attr)
        yield data
        if data != original:
            write_json(path, data)


def identity(pid, kind):
    started = birth(pid)
    if not started:
        raise ValueError("发起进程已退出。")
    return {"pid": pid, "birth": started, "kind": kind}


def detached(argv, folder):
    with (folder / "supervisor.log").open("ab") as log:
        return subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                start_new_session=True, close_fds=True)


def watch_legacy(args, folder, state):
    """For a pre-handshake writer, preserve the launch options of its live supervisor."""
    old = state.get("supervisor", {})
    if not old or old.get("kind") != "supervisor":
        return False
    proc = subprocess.run(["/bin/ps", "-ww", "-p", str(old["pid"]), "-o", "command="],
                          capture_output=True, text=True).stdout.strip()
    _, sep, options = proc.partition("/tools/world_service.py supervise --project ")
    project, fields, rest = options.partition(" --data %s --slot %s --godot " %
                                              (Path(args.data).resolve(), args.slot))
    godot, stamp, _ = rest.partition(" --generation " + state["generation"])
    if not sep or not fields or not stamp or not Path(project, "scenes/world_runner.tscn").is_file() or not os.access(godot, os.X_OK):
        return False
    argv = [sys.executable, str(Path(__file__).resolve()), "standby", "--project", project,
            "--godot", godot, "--data", str(Path(args.data).resolve()), "--slot", args.slot,
            "--generation", state["generation"]]
    if state.get("share_adventurer"):
        argv.append("--share-adventurer")
    guard = detached(argv, folder)
    state["standby"] = identity(guard.pid, "standby")
    return True


def same_ticket(args, state):
    transfer = state.get("transfer", {})
    return (state.get("desired") == "foreground" and args.ticket
            and transfer.get("ticket") == args.ticket and transfer.get("pid") == args.pid
            and state.get("generation") == args.generation)


def request(args):
    folder = runtime(args)
    with transaction(folder) as state:
        want = state.get("desired", "paused")
        owner = state.get("owner", {})
        if args.action == "status":
            dirs = sorted(p.name for p in folder.parent.glob("[0-9]" * 9) if p.is_dir())
            return {"ok": True, "slot": args.slot, "revision": int(dirs[-1]) if dirs else 0,
                    "uncertain_roles": [p.name.split(".",1)[0] for p in sorted(folder.glob("*.pending"))], **state}
        if args.action == "claim":
            if args.kind == "foreground" and not args.ticket and state.get("transfer", {}).get("pid", args.pid) != args.pid:
                return {"ok": False, "message": "这支队伍正在交接。请从队伍列表重新选择继续。"}
            if args.ticket and same_ticket(args, state):
                current = max((int(p.name) for p in folder.parent.glob("[0-9]" * 9) if p.is_dir()), default=0)
                if current != args.revision:
                    return {"ok": False, "message": "队伍的最后一次保存已经变化，请再选择继续。"}
            if args.ticket and not same_ticket(args, state):
                return {"ok": False, "message": "后台运行状态已改变，请重新选择这个世界。"}
            if owner and owner["pid"] != args.pid:
                return {"ok": False, "message": "这个世界正在另一进程中运行。"}
            if args.kind == "background" and (want != "background" or state.get("generation") != args.generation):
                return {"ok": False, "message": "这次后台交接已结束。"}
            if args.kind == "foreground" and want == "background":
                return {"ok": False, "message": "请先接回后台的世界。"}
            state["owner"] = identity(args.pid, args.kind)
            if args.kind == "foreground":
                state["accepted_generation"] = state.get("generation", "")
                state.pop("transfer", None)
            return {"ok": True, "enabled": bool(state.get("enabled"))}
        if args.action == "ready":
            if owner.get("pid") != args.pid:
                return {"ok": False, "message": "当前进程不持有世界。"}
            state["last_error"] = ""
            return {"ok": True}
        if args.action == "release":
            if owner.get("pid") == args.pid:
                state.pop("owner")
            return {"ok": True}
        if args.action == "cancel-take":
            if not same_ticket(args, state) or owner.get("kind") == "foreground":
                return {"ok": False, "message": "其他窗口已接管或改变了后台状态。"}
            state.pop("transfer", None)
            state["desired"] = "background"
            return {"ok": True}
        if args.action in ("take", "pause"):
            if owner.get("kind") == "foreground" and owner["pid"] != args.pid:
                return {"ok": False, "message": "这个世界已由另一个游戏窗口接管。"}
            if args.action == "pause":
                state.pop("transfer", None)
                state["desired"] = "paused"
                state["enabled"] = False
                return {"ok": True}
            if want not in ("background","foreground") or args.generation and args.generation != state.get("generation"):
                return {"ok": False, "message": "后台状态已改变，请重新查看这个队伍。"}
            if args.generation and state.get("handoff_protocol") != 2 and not state.get("standby"):
                if not watch_legacy(args, folder, state):
                    return {"ok": False, "message": "无法确认旧版后台的启动路径。请从启动该队的版本保存并暂停，再从这里继续。"}
            if not args.generation and not args.pid:
                state["desired"] = "foreground"
                return {"ok": True}
            claim = identity(args.pid, "claimant")
            claim["ticket"] = uuid.uuid4().hex
            state["transfer"] = claim
            state["desired"] = "foreground"
            return {"ok": True, "ticket": claim["ticket"], "generation": state.get("generation", "")}
        if owner.get("kind") == "foreground" and owner["pid"] != args.pid:
            return {"ok": False, "message": "请在正在游玩的那个窗口交接。"}
        if want == "background" and state.get("supervisor"):
            return {"ok": True, "slot": args.slot}
        if not args.name and not any(folder.parent.glob("[0-9]" * 9)):
            return {"ok": False, "message": "这个世界还没有完整存档。"}
        project = Path(args.project).resolve()
        if not (project / "scenes/world_runner.tscn").is_file() or not os.access(args.godot, os.X_OK):
            raise ValueError("找不到本版本的世界服务或 Godot。")
        generation = uuid.uuid4().hex
        argv = [sys.executable, str(Path(__file__).resolve()), "supervise", "--project", str(project),
                "--data", str(Path(args.data).resolve()), "--slot", args.slot, "--godot", args.godot,
                "--generation", generation]
        if args.name:
            argv.extend(["--name", args.name])
        if args.share_adventurer or state.get("share_adventurer"):
            argv.append("--share-adventurer")
        proc = detached(argv, folder)
        state.pop("transfer", None)
        state.update(desired="background", enabled=True, generation=generation, handoff_protocol=2,
                     share_adventurer="--share-adventurer" in argv,
                     supervisor=identity(proc.pid, "supervisor"), last_error="")
        return {"ok": True, "slot": args.slot, "supervisor": proc.pid}


def await_handoff(args, folder, standby=False):
    # The original supervisor retains its project, engine and optional one-night binding.
    # Old readers have no completion token. Give them time to claim the final revision.
    empty_since = None
    while True:
        with transaction(folder) as state:
            if state.get("generation") != args.generation or state.get("desired") == "paused":
                return False
            if state.get("accepted_generation") == args.generation or (state.get("desired") == "foreground" and state.get("owner", {}).get("kind") == "foreground"):
                return False
            background_owner = state.get("owner", {}).get("kind") == "background"
            if state.get("desired") == "foreground" and not background_owner:
                if empty_since is None:
                    empty_since = time.monotonic()
                transfer = state.get("transfer", {})
                abandoned = transfer and birth(transfer["pid"]) != transfer["birth"]
                grace = 120 if transfer else 12
                if abandoned or time.monotonic() - empty_since >= grace:
                    state.pop("transfer", None)
                    state["desired"] = "background"
            if state.get("desired") == "background":
                if not standby:
                    return True
                if not state.get("supervisor"):
                    state["supervisor"] = identity(os.getpid(), "supervisor")
                    state.pop("standby", None)
                    state["handoff_protocol"] = 2
                    return True
                if background_owner:
                    return False
        time.sleep(.15)


def supervise(args):
    folder = runtime(args)
    failures = 0
    if args.action == "standby" and not await_handoff(args, folder, True):
        return
    while True:
        if not await_handoff(args, folder):
            return
        with transaction(folder) as state:
            available = state.get("desired") == "background" and not state.get("owner")
        if not available:
            time.sleep(0.3)
            continue
        started = time.monotonic()
        cmd = [args.godot, "--headless", "--path", args.project, "--max-fps", "30",
               "--log-file", str(folder / "engine.log"), "res://scenes/world_runner.tscn",
               "--", "--world-slot", args.slot, "--world-data", args.data,
               "--world-generation", args.generation]
        if args.name:
            cmd.extend(["--world-name", args.name])
        if args.share_adventurer:
            cmd.append("--world-share-adventurer")
        with (folder / "engine-console.log").open("ab") as log:
            env = dict(os.environ)
            for key in ("DEEPSEEK_API_KEY", "NODE_OPTIONS", "ZHIJIAN_PAINTER_MAILBOX", "ZHIJIAN_DIVINE_DEMO_LAUNCHER"):
                env.pop(key, None)
            child = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                     env=env, start_new_session=True, close_fds=True)
            code = child.wait()
        # Only this worker's process group. A killed engine may leave a Node request behind.
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        with transaction(folder) as state:
            if state.get("generation") != args.generation or state.get("desired") == "paused":
                return
            if state.get("desired") == "foreground" or code == 0:
                continue
            failures = 1 if time.monotonic() - started > 60 else failures + 1
            state["restarts"] = int(state.get("restarts", 0)) + 1
            state["last_error"] = "世界进程退出 (%s)，将从完整检查点恢复。" % code
            if failures >= 4 or code == 65:
                state["desired"] = "paused"
                state["enabled"] = False
                state["last_error"] = "世界进程无法继续 (%s)，请检查存档和运行日志。" % code
                return
        time.sleep(min(2 ** failures, 15))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["new", "start", "pause", "take", "status", "claim", "release", "ready", "cancel-take", "supervise", "standby"])
    parser.add_argument("--data", required=True)
    parser.add_argument("--slot", default="")
    parser.add_argument("--name", default="")
    parser.add_argument("--pid", type=int, default=0)
    parser.add_argument("--kind", choices=["foreground", "background"], default="foreground")
    parser.add_argument("--project", default="")
    parser.add_argument("--godot", default="")
    parser.add_argument("--generation", default="")
    parser.add_argument("--ticket", default="")
    parser.add_argument("--revision", type=int, default=0)
    parser.add_argument("--share-adventurer", action="store_true")
    args = parser.parse_args()
    if args.action == "new":
        if not args.name.strip() or len(args.name) > 48:
            parser.error("请为独立夜间队伍起名（1–48字）。")
        args.slot = uuid.uuid4().hex
    if args.action in ("supervise", "standby"):
        supervise(args)
        return
    try:
        result = request(args)
    except (OSError, ValueError) as exc:
        result = {"ok": False, "message": str(exc)}
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
