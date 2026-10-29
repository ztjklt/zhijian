"""Run matched full-client networking checks against a frozen Web client.

Examples:
  python3 ZSCB/web/tests/run_network_checks.py --duel --map paper --latency-ms 300 --bandwidth-kbps 256
  python3 ZSCB/web/tests/run_network_checks.py --map medieval-v1 --address wss://paper-server-production-4b68.up.railway.app/ws
The second command creates and normally saves/closes a disposable cloud test room.
"""
from pathlib import Path
import argparse
import re
import runpy
import shutil
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser(add_help=False)
parser.add_argument('--client-project',type=Path,default=ROOT/'dist/纸间网页版-20261025-r7/project')
parser.add_argument('--matched-source',type=Path,help='Frozen source for server and tests; defaults to Web release manifest')
args,forwarded=parser.parse_known_args()
if args.matched_source is None:
    import json
    manifest=args.client_project.parent/'WEB_RELEASE.json'
    args.matched_source=ROOT/json.loads(manifest.read_text())['source'] if manifest.is_file() else args.client_project
fixed=args.matched_source
def protocol(project):
    return int(re.search(r'const PROTOCOL := (\d+)',(project/'scripts/net/codec.gd').read_text()).group(1))
version=protocol(args.client_project)
if version!=protocol(fixed):raise RuntimeError('Client and matched source protocol must agree before launching tests')
with tempfile.TemporaryDirectory(prefix='paper-web-network-') as temp:
    fixture=Path(temp)/'source'
    shutil.copytree(args.client_project,fixture,ignore=shutil.ignore_patterns('.godot','__pycache__'))
    # This harness runs native Godot. Browser sample playback is Web-only;
    # retain the native driver's default for real audio validation here.
    config=fixture/'project.godot'
    config.write_text(re.sub(r'^general/default_playback_type=1\n','',config.read_text(),flags=re.M))
    shutil.copytree(fixed/'server',fixture/'server',dirs_exist_ok=True)
    # Specialized full-client bots inherit other scripts by res://tests paths.
    # Include those real dependencies in the isolated project, not only beside
    # the Python runner, so vitals/audio validation can execute its actual bot.
    shutil.copytree(fixed/'tests',fixture/'tests',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    tests=Path(temp)/'tests'
    shutil.copytree(fixed/'tests',tests,ignore=shutil.ignore_patterns('__pycache__'))
    if version>=4:
        # The older generic bot skipped the now-required weapon-type wheel.
        # Drive the real latest create/grip/type/confirm flow instead of setting
        # internal flags or weakening the server-confirmation assertion.
        bot=tests/'network_bot.gd'
        old='\t\tgame.selecting_weapon_grip=true\n\t\tgame.equip_weapon_at(grip)'
        new='\t\tgame.create_weapon()\n\t\tgame.select_weapon_grip(grip)\n\t\tgame.generate()\n\t\tgame.select_weapon_type("sword")\n\t\tgame.generate()'
        if bot.read_text().count(old)!=1:raise RuntimeError('Review latest weapon-flow fixture before use')
        bot.write_text(bot.read_text().replace(old,new,1))
        feedback=tests/'network_feedback_bot.gd'
        old='feedback.sound_banks[event.kind].has(voice.stream)'
        new='feedback.sound_banks[event.get("audio",event.kind)].has(voice.stream)'
        if feedback.read_text().count(old)!=1:raise RuntimeError('Review typed audio fixture before use')
        feedback.write_text(feedback.read_text().replace(old,new,1))
        shutil.copy2(feedback,fixture/'tests/network_feedback_bot.gd')
    runner=tests/'run_network_clients.py'
    source=runner.read_text().replace('import argparse','import argparse, re')
    old='cfg.read_text().replace(\'config/name="纸上城堡 · 火柴人沙盒"\',f\'config/name="{name}"\')'
    new='re.sub(r\'^config/name=.*$\',f\'config/name="{name}"\',cfg.read_text(),flags=re.M)'
    if source.count(old)!=1:raise RuntimeError('Review fixed-r2 runner profile isolation before use')
    runner.write_text(source.replace(old,new,1))
    # The frozen runner's client rename then targets the unique seed namespace.
    sys.argv=[str(runner),'--project-source',str(fixture),*forwarded]
    sys.path.insert(0,str(tests))
    runpy.run_path(str(runner),run_name='__main__')
