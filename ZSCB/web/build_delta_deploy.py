"""Package verified r7 artifacts as exact binary deltas for slow upload links.

Run with bsdiff4==1.3.1 installed. The Railway builder downloads the existing
public baseline, verifies it, applies a BSDIFF40 patch, and verifies the full
output. The new static image retains the baseline at an immutable release path
so this deployment remains rebuildable after the public root changes.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile
import bsdiff4

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "dist/纸间网页版-20261025-ack/site"
WEB = ROOT / "dist/纸间网页版-20261025-r7/site"
PACK = ROOT / "dist/纸间权威资源包-20261025-r7/deploy"
OUT = ROOT / "dist/纸间增量部署-20261025-r7"
ORIGIN = "https://zhijian-web-production.up.railway.app"
RETAINED = "releases/20261025-ack"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verified(folder, manifest):
    for name, entry in json.loads(manifest.read_text())["files"].items():
        digest = entry["sha256"] if isinstance(entry, dict) else entry
        if sha(folder / name) != digest:
            raise RuntimeError("Release manifest mismatch: " + name)


REBUILD = '''from pathlib import Path
import argparse, hashlib, json, shutil, subprocess

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

p=argparse.ArgumentParser();p.add_argument('--local-base');args=p.parse_args()
m=json.loads(Path('rebuild.json').read_text())
for asset in m['base']:
    out=Path(asset['output']);out.parent.mkdir(parents=True,exist_ok=True)
    if args.local_base:
        shutil.copy2(Path(args.local_base)/asset['name'],out)
    else:
        for url in asset['urls']:
            result=subprocess.run(['curl','--http1.1','--fail','--silent',
                '--show-error','--retry','2','--retry-all-errors','--retry-delay','1',
                '--connect-timeout','20','--max-time','90','--output',str(out),url])
            if result.returncode==0 and sha(out)==asset['sha256']:
                break
        else:
            raise RuntimeError('No verified baseline available: '+asset['name'])
    if sha(out)!=asset['sha256']:
        raise RuntimeError('Baseline checksum mismatch: '+asset['name'])
    print('BASELINE_VERIFIED',asset['name'],flush=True)
for item in m['patches']:
    out=Path(item['output']);out.parent.mkdir(parents=True,exist_ok=True)
    if sha(Path(item['patch']))!=item['patch_sha256']:
        raise RuntimeError('Patch checksum mismatch')
    subprocess.run(['bspatch',item['base'],str(out),item['patch']],check=True)
    if sha(out)!=item['sha256']:
        raise RuntimeError('Reconstructed output checksum mismatch')
    print('OUTPUT_VERIFIED',item['output'],item['sha256'],flush=True)
for item in m.get('copies',[]):
    out=Path(item['output']);out.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(item['source'],out)
'''


def baseline(name):
    return {"name": name, "output": "base/" + name, "sha256": sha(BASE / name),
            "urls": [f"{ORIGIN}/{RETAINED}/{name}", f"{ORIGIN}/{name}"]}


def package(kind, target):
    folder = OUT / kind
    folder.mkdir(parents=True, exist_ok=True)
    patch_name = target.name + ".bsdiff"
    patch = folder / patch_name
    bsdiff4.file_diff(str(BASE / "index.pck"), str(target), str(patch))
    output_name = "game.pck" if kind == "authority" else "site/index.pck"
    data = {"base": [baseline("index.pck")], "patches": [{
        "base": "base/index.pck", "patch": patch_name, "output": output_name,
        "patch_sha256": sha(patch), "sha256": sha(target)}]}
    if kind == "web":
        data["base"].append(baseline("index.wasm"))
        data["copies"] = [
            {"source": "base/index.wasm", "output": "site/index.wasm"},
            {"source": "base/index.pck", "output": f"site/{RETAINED}/index.pck"},
            {"source": "base/index.wasm", "output": f"site/{RETAINED}/index.wasm"},
        ]
        assert sha(BASE / "index.wasm") == sha(WEB / "index.wasm")
        (folder / "site").mkdir(exist_ok=True)
        for path in WEB.iterdir():
            if path.is_file() and path.name not in {"index.pck", "index.wasm", "Dockerfile", "Caddyfile"}:
                shutil.copy2(path, folder / "site" / path.name)
        shutil.copy2(WEB / "Caddyfile", folder / "Caddyfile")
    else:
        shutil.copytree(PACK / "server", folder / "server", ignore=shutil.ignore_patterns("__pycache__"))
    (folder / "rebuild.py").write_text(REBUILD)
    (folder / "rebuild.json").write_text(json.dumps(data, indent=2) + "\n")
    (folder / ".railwayignore").write_text("__pycache__/\n**/__pycache__/\n**/.DS_Store\n")
    assemble = '''FROM debian:bookworm-slim AS assemble
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl python3 bsdiff && rm -rf /var/lib/apt/lists/*
WORKDIR /assemble
'''
    if kind == "authority":
        docker = (PACK / "server/Dockerfile").read_text().replace(
            "COPY game.pck /app/game.pck", "COPY --from=assemble /assemble/game.pck /app/game.pck")
        docker = assemble + "COPY rebuild.py rebuild.json game.pck.bsdiff ./\nRUN python3 rebuild.py\n" + docker
        (folder / "server/Dockerfile").write_text(docker)
    else:
        docker = assemble + '''COPY site/ ./site/
COPY rebuild.py rebuild.json index.pck.bsdiff ./
RUN python3 rebuild.py
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=assemble /assemble/site /srv
EXPOSE 8080
'''
        (folder / "Dockerfile").write_text(docker)
    # Exercise the exact builder script using the frozen baseline, in a temp
    # directory so reconstructed large files cannot enter the upload context.
    with tempfile.TemporaryDirectory(prefix="paper-r7-delta-check-") as tmp:
        check = Path(tmp) / kind
        shutil.copytree(folder, check)
        subprocess.run(["python3", "rebuild.py", "--local-base", str(BASE)], cwd=check, check=True)
        assert sha(check / output_name) == sha(target)
        if kind == "web":
            for path in WEB.iterdir():
                if path.is_file() and path.name not in {"Dockerfile", "Caddyfile"}:
                    assert sha(check / "site" / path.name) == sha(path), path.name
    files = {str(p.relative_to(folder)): sha(p) for p in sorted(folder.rglob("*")) if p.is_file()}
    manifest = {"protocol": 6, "baseline": str(BASE.relative_to(ROOT)), "canonical_target": str(target.relative_to(ROOT)), "canonical_sha256": sha(target), "files": files}
    (OUT / (kind.upper() + "_DELTA_RELEASE.json")).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"kind": kind, "patch_bytes": patch.stat().st_size, "upload_files": len(files), "output_verified": sha(target)}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    verified(BASE, BASE.parent / "WEB_RELEASE.json")
    verified(WEB, WEB.parent / "WEB_RELEASE.json")
    verified(PACK, PACK.parent / "PACK_RELEASE.json")
    marker = OUT / ".paper-delta-deploy"
    if OUT.exists() and any(OUT.iterdir()) and not marker.exists():
        raise RuntimeError("Refusing to replace an unowned delta output")
    OUT.mkdir(exist_ok=True)
    marker.touch()
    for kind in ["authority", "web"]:
        if (OUT / kind).exists():
            shutil.rmtree(OUT / kind)
    package("authority", PACK / "game.pck")
    package("web", WEB / "index.pck")
