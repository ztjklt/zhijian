"""Offline native, Python and matched Web checks. No cloud access or publishing."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from runtime_tools import resolve_godot

CORE = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--stages', nargs='+', choices=['native', 'python', 'web', 'cooperation'], default=['native', 'python', 'web'])
    parser.add_argument('--logs', type=Path, help='Keep complete stage logs in this directory')
    args = parser.parse_args()
    godot = resolve_godot(args.godot)
    env = dict(os.environ, GODOT_BIN=godot, PYTHONUNBUFFERED='1')
    failures = []
    with tempfile.TemporaryDirectory(prefix='paper-aggregate-') as temp:
        scratch = Path(temp)
        logs = args.logs.resolve() if args.logs else scratch / 'logs'
        logs.mkdir(parents=True, exist_ok=True)
        for stage in dict.fromkeys(args.stages):
            try:
                if stage == 'native':
                    commands = [[sys.executable, str(CORE/'tests/run_headless_suite.py')]]
                elif stage == 'python':
                    commands = [[sys.executable, '-m', 'unittest', 'discover', '-s', str(CORE/'tests'), '-p', 'test_*.py'],
                                [sys.executable, '-m', 'unittest', 'discover', '-s', str(CORE/'web/tests'), '-p', 'test_*.py'],
                                [sys.executable, str(CORE/'tests/network_transport_test.py'), '--godot']]
                elif stage == 'cooperation':
                    sys.path.insert(0, str(CORE/'web'))
                    from build_web import prepare_project
                    project, _ = prepare_project(SimpleNamespace(source=CORE, output=scratch/'cooperation-web'))
                    common = ['--cooperation', '--latency-ms', '600', '--bandwidth-kbps', '256']
                    commands = [[sys.executable, str(CORE/'tests/run_network_clients.py'), *common, '--evidence-dir', str(logs/'cooperation-native')],
                                [sys.executable, str(CORE/'web/tests/run_network_checks.py'), '--client-project', str(project), '--matched-source', str(CORE), *common, '--evidence-dir', str(logs/'cooperation-web')]]
                else:
                    sys.path.insert(0, str(CORE/'web'))
                    from build_web import prepare_project
                    project, _ = prepare_project(SimpleNamespace(source=CORE, output=scratch/'web'))
                    commands = [[sys.executable, str(CORE/'web/run_checks.py'), '--project', str(project), '--tests-source', str(CORE/'tests'), '--all']]
                good = True
                with (logs/(stage+'.log')).open('w') as stream:
                    for command in commands:
                        result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=1800)
                        good = good and result.returncode == 0
                if not good: raise RuntimeError((logs/(stage+'.log')).read_text()[-9000:])
                print('PASS '+stage, flush=True)
            except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
                failures.append(stage)
                print('FAIL '+stage+': '+str(error)[-9000:], flush=True)
        print('CHECKS: '+str(len(args.stages)-len(failures))+'/'+str(len(args.stages))+' stages passed; failures='+str(failures), flush=True)
        return 1 if failures else 0

if __name__ == '__main__': raise SystemExit(main())
