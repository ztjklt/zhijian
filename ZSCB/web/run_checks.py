"""Run web-client behavior checks in an isolated Godot project and profile."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile
import uuid

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from runtime_tools import resolve_godot, user_data_path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project',type=Path,default=ROOT/'dist/纸间网页候选-r22/project')
parser.add_argument('--tests-source',type=Path,help='Matched frozen core tests; defaults to WEB_RELEASE source')
parser.add_argument('--all',action='store_true',help='Run all matched core behavior checks with the Web MSAA expectation')
parser.add_argument('tests',nargs='*',default=['movement_ack_test.gd','online_ack_reconcile_test.gd','online_jitter_burst_test.gd','online_rubberband_test.gd','online_latency_test.gd','online_prediction_transition_test.gd','online_prediction_delay_test.gd','web_performance_test.gd','online_flow_test.gd','online_session_test.gd','network_lobby_restore_test.gd','network_save_return_test.gd','network_client_test.gd'])
args=parser.parse_args()
if args.tests_source is None:
    import json
    manifest=args.project.parent/'WEB_RELEASE.json'
    source=ROOT/json.loads(manifest.read_text())['source'] if manifest.is_file() else HERE.parent
    args.tests_source=source/'tests'
name='PaperOnlineCheck_'+uuid.uuid4().hex
godot=resolve_godot()
data=user_data_path(name)
with tempfile.TemporaryDirectory(prefix='paper-online-check-') as temp:
    project=Path(temp)/'project'
    shutil.copytree(args.project,project,ignore=shutil.ignore_patterns('.godot'))
    config=project/'project.godot'
    config.write_text(re.sub(r'^config/name=.*$',f'config/name="{name}"',config.read_text(),flags=re.M))
    shutil.copytree(args.tests_source,project/'tests',dirs_exist_ok=True)
    shutil.copytree(HERE/'tests',project/'tests',dirs_exist_ok=True)
    if args.all:
        # The fixed native test expects 4x MSAA. WebGL2 export deliberately
        # disables this unsupported option; retain all 32 sword-pose checks
        # and assert the actual browser-build preference instead.
        sword=project/'tests/sword_pose_test.gd'
        old='check(root.msaa_2d == Viewport.MSAA_4X, "the running 2D viewport enables 4x MSAA")'
        new='check(root.msaa_2d == Viewport.MSAA_DISABLED, "the Web viewport keeps unsupported 2D MSAA disabled")'
        if sword.read_text().count(old)!=1:raise RuntimeError('Fixed native MSAA assertion changed; review Web adaptation')
        sword.write_text(sword.read_text().replace(old,new,1))
        print('Web adaptation: sword pose retains all checks; unsupported 2D MSAA must be disabled',flush=True)
        args.tests=['test_runner.gd']+sorted(p.name for p in (project/'tests').glob('*_test.gd'))
        if 'func save_feedback(' in (project/'scripts/net/session.gd').read_text():
            args.tests.remove('online_save_legacy_test.gd')
            print('SKIP online_save_legacy_test.gd: requires a frozen session without queued-save capability; current queued-save behavior is covered by network_save_feedback_test.gd',flush=True)
    try:
        imported=subprocess.run([str(godot),'--headless','--path',str(project),'--editor','--import','--quit'],capture_output=True,text=True,timeout=90)
        if imported.returncode or 'ERROR:' in imported.stdout+imported.stderr:
            print((imported.stdout+imported.stderr)[-7000:]);raise SystemExit(1)
        failed=[]
        for test in args.tests:
            try:
                result=subprocess.run([str(godot),'--headless','--path',str(project),'--script','res://tests/'+test],capture_output=True,text=True,timeout=60)
                output=result.stdout+result.stderr
                successful=result.returncode==0 and 'ERROR:' not in output
            except subprocess.TimeoutExpired as error:
                output='TIMEOUT '+str(error.stdout or '')+str(error.stderr or '')
                successful=False
            print(('PASS ' if successful else 'FAIL ')+test,flush=True)
            if not successful: print(output[-5500:],flush=True)
            if not successful: failed.append(test)
            if data.exists(): shutil.rmtree(data)
        print(f'{len(args.tests)-len(failed)}/{len(args.tests)} checks passed')
        raise SystemExit(1 if failed else 0)
    finally:
        if data.exists():shutil.rmtree(data)
