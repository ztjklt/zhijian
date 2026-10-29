"""Prepare a separate frozen authority with optional motion ACK metadata."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess
from prepare_authority import prepare_authority
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from runtime_tools import resolve_godot
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,default=HERE.parent)
parser.add_argument('--output',type=Path,default=ROOT/'dist/纸间权威候选-r22')
parser.add_argument('--godot')
args=parser.parse_args()
source=args.source.resolve()
output=args.output.resolve()
if output==ROOT/'dist/纸间服务校正版-20261025-r2a':raise ValueError('Refusing to replace published r2a rollback authority')
if output==source or source in output.parents or output in source.parents:raise ValueError('Authority output must be separate from source')
marker=output/'.paper-ack-authority'
if output.exists() and any(output.iterdir()) and not marker.exists():raise RuntimeError('Refusing to replace unowned authority output')
output.mkdir(parents=True,exist_ok=True);marker.touch()
project=output/'project'
if project.exists():shutil.rmtree(project)
project.mkdir()
for name in ['scripts','scenes','animations','assets','server']:
    shutil.copytree(source/name,project/name,ignore=shutil.ignore_patterns('.DS_Store','__pycache__'))
shutil.copy2(source/'project.godot',project/'project.godot')
prepare_authority(project)
(project/'.dockerignore').write_text('.godot\n__pycache__\n**/.DS_Store\n')
(project/'.railwayignore').write_text('.godot/\n__pycache__/\n**/__pycache__/\n**/.DS_Store\n')
godot=resolve_godot(args.godot)
result=subprocess.run([str(godot),'--headless','--editor','--path',str(project),'--import','--quit'],capture_output=True,text=True,timeout=180)
(output/'import.log').write_text(result.stdout+result.stderr)
if result.returncode or 'ERROR:' in result.stdout+result.stderr:raise RuntimeError('Authority import failed; inspect import.log')
files={str(p.relative_to(project)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(project.rglob('*')) if p.is_file() and '.godot' not in p.parts}
protocol=int(re.search(r'const PROTOCOL := (\d+)',(source/'scripts/net/codec.gd').read_text()).group(1))
(output/'AUTHORITY_RELEASE.json').write_text(json.dumps({'source':str(source.relative_to(ROOT)) if source.is_relative_to(ROOT) else str(source),'protocol':protocol,'optional_motion_ack':1,'files':files},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'project':str(project),'files':len(files)},ensure_ascii=False))
