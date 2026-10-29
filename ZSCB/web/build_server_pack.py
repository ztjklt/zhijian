"""Build a compact Linux PCK deployment from the verified frozen authority."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[2]
authority=ROOT/'dist/纸间权威服务-20261025-r7'
output=ROOT/'dist/纸间权威资源包-20261025-r7'
marker=output/'.paper-server-pack'
if output.exists() and any(output.iterdir()) and not marker.exists():
    raise RuntimeError('Refusing to replace an unowned server pack output')
output.mkdir(exist_ok=True);marker.touch()
manifest=json.loads((authority/'AUTHORITY_RELEASE.json').read_text())
for name,want in manifest['files'].items():
    if hashlib.sha256((authority/'project'/name).read_bytes()).hexdigest()!=want:
        raise RuntimeError('Authority source changed: '+name)
source=output/'build-source';deploy=output/'deploy'
if source.exists():shutil.rmtree(source)
shutil.copytree(authority/'project',source)
deploy.mkdir(exist_ok=True);(deploy/'server').mkdir(exist_ok=True)
(source/'export_presets.cfg').write_text('''[preset.0]
name="LinuxServerPack"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter="*.json,*.txt"
exclude_filter=""
export_path="../deploy/game.pck"

[preset.0.options]
custom_template/debug=""
custom_template/release=""
binary_format/architecture="x86_64"
texture_format/bptc=true
texture_format/s3tc=true
''')
godot=Path.home()/'Applications/Godot.app/Contents/MacOS/Godot'
with (output/'export.log').open('w') as log:
    result=subprocess.run([str(godot),'--headless','--path',str(source),'--export-pack','LinuxServerPack',str(deploy/'game.pck')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
if result.returncode or 'ERROR:' in (output/'export.log').read_text():
    raise RuntimeError('Linux pack export failed; inspect export.log')
for name in ['start_local.py','gateway.py']:
    shutil.copy2(source/'server'/name,deploy/'server'/name)
launcher=deploy/'server/start_local.py'
old='"--path", str(project), "--script", "res://server/server.gd"'
new='"--main-pack", str(project / "game.pck"), "--script", "res://server/server.gd"'
text=launcher.read_text()
if text.count(old)!=1:raise RuntimeError('Review packed authority launcher')
launcher.write_text(text.replace(old,new,1))
docker=(source/'server/Dockerfile').read_text()
prefix=docker.split('COPY project.godot /app/')[0]
suffix=docker[docker.index('ENV GODOT_BIN='):]
(deploy/'server/Dockerfile').write_text(prefix+'COPY game.pck /app/game.pck\nCOPY server/gateway.py server/start_local.py /app/server/\n'+suffix)
(deploy/'.railwayignore').write_text('__pycache__/\n**/__pycache__/\n**/.DS_Store\n')
files={str(p.relative_to(deploy)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(deploy.rglob('*')) if p.is_file() and '__pycache__' not in p.parts}
(output/'PACK_RELEASE.json').write_text(json.dumps({'source':str(authority.relative_to(ROOT)),'protocol':manifest['protocol'],'platform':'Linux x86_64','visual_resources_retained':True,'files':files},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'deploy':str(deploy),'pck_bytes':(deploy/'game.pck').stat().st_size,'protocol':manifest['protocol']},ensure_ascii=False))
