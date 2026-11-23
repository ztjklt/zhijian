"""Install the pinned credential client or provision an existing official connection."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

CLIENT_HASH = "669d1b0c116a9383992de0b95fd3949be0c71ce996c9d58943dd92444f24de80"
CLIENT_NAME = "zhijian-credential"
OFFICIAL = "https://api.deepseek.com"
GODS = ("companion", "priest", "war_god")


def ensure_client():
    base = Path.home() / "Library/Application Support/Zhijian/Credentials/v1"
    base.mkdir(parents=True, exist_ok=True, mode=0o700)
    for directory in (base, base.parent, base.parent.parent):
        st = directory.lstat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o022:
            raise ValueError("凭据程序目录的所有者或权限不符。")
    target = base / CLIENT_NAME
    if not os.path.lexists(target):
        source = Path(__file__).resolve().with_name(CLIENT_NAME)
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != CLIENT_HASH:
            raise ValueError("发行包凭据程序校验失败。")
        with tempfile.NamedTemporaryFile(dir=base, delete=False) as out:
            path = Path(out.name)
            try:
                out.write(data)
                out.flush()
                os.fchmod(out.fileno(), 0o700)
                os.fsync(out.fileno())
                try:
                    os.link(path, target)
                except FileExistsError:
                    pass
            finally:
                path.unlink(missing_ok=True)
    info = target.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or
            stat.S_IMODE(info.st_mode) != 0o700 or hashlib.sha256(target.read_bytes()).hexdigest() != CLIENT_HASH):
        raise ValueError("本机凭据程序校验失败。")
    return target


def provision():
    parser = argparse.ArgumentParser(description="在本机登录钥匙串安装、核对或移除已有官方连接。Key 从终端掩码输入或标准输入读取。")
    parser.add_argument("operation", nargs="?", choices=("install", "status", "remove"), default="install")
    parser.add_argument("--connection-id", help="已有官方连接的 24 位编号，缺省取三神共同绑定")
    parser.add_argument("--profile", default="ZhijianTeamWorlds", help="Godot 的本机资料名称")
    parser.add_argument("--stdin", action="store_true", help="使用上游私有管道输入一行")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", args.profile):
        raise ValueError("无效资料名称。")
    directory = Path.home() / "Library/Application Support/Godot/app_userdata" / args.profile
    path = directory / "harness_connections.json"
    if not path.is_file():
        raise ValueError("这个资料中还没有保存连接，请先在游戏设置里添加。")
    data = json.loads(path.read_bytes())
    bindings = data["bindings"]
    cid = args.connection_id
    if cid is None:
        ids = {bindings.get(role) for role in GODS}
        if len(ids) != 1 or not all(ids):
            raise ValueError("三位神尚未共用一条连接。请在设置中选择同一条，或指定已有官方连接的 --connection-id。")
        cid = ids.pop()
    if not re.fullmatch(r"[0-9a-f]{24}", cid):
        raise ValueError("无效的连接编号。")
    row = next((r for r in data["connections"] if r.get("id") == cid), {})
    if row.get("provider") != "deepseek-official" or row.get("base_url") != OFFICIAL:
        raise ValueError("所选连接不是这份资料的 DeepSeek 官方地址。")
    if args.stdin and sys.stdin.isatty():
        raise ValueError("--stdin 需要上游管道；交互输入请省略该选项。")
    client = ensure_client()
    digest = lambda value: hashlib.sha256(value.encode("utf-8")).hexdigest()
    operation = {"install":"store", "status":"status", "remove":"remove"}[args.operation]
    command = [str(client), operation, digest(str(directory)), cid, "deepseek-official", digest(OFFICIAL)]
    result = subprocess.run(command, stdout=subprocess.PIPE, check=False)
    if result.returncode == 3:
        print("此连接尚无钥匙串条目。")
        return 3
    if result.returncode:
        raise ValueError("钥匙串操作失败。请检查登录钥匙串是否已解锁及输入格式。")
    print({"install":"已在本机登录钥匙串保存。", "status":"此连接已存入登录钥匙串。", "remove":"已从登录钥匙串移除。"}[args.operation])
    return 0


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["ensure"]:
            ensure_client()
        else:
            sys.exit(provision())
    except (ValueError, OSError, KeyError, TypeError):
        # Do not propagate exceptions containing an input value or JSON contents.
        print("未完成。请检查资料、三神绑定、钥匙串解锁状态和凭据程序。可用 --help 查看选项。", file=sys.stderr)
        sys.exit(1)
