from runtime_tools import resolve_godot, user_data_path
"""Three actual Godot processes sharing one random private test profile."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--project-source', type=Path)
parser.add_argument('--tests-source', type=Path)
parser.add_argument('--evidence-dir', type=Path)
parser.add_argument('--check-close', action='store_true')
args = parser.parse_args()
core = Path(__file__).resolve().parents[1]
source = args.project_source.resolve() if args.project_source else core
tests = args.tests_source.resolve() if args.tests_source else core / 'tests'
godot = resolve_godot()
name = 'PaperProfileRestart_' + uuid.uuid4().hex
data = user_data_path(name)
with tempfile.TemporaryDirectory(prefix='paper-profile-restart-') as folder:
    project = Path(folder) / 'project'
    shutil.copytree(source, project, ignore=shutil.ignore_patterns('.godot', '__pycache__'))
    shutil.copytree(tests, project / 'tests', dirs_exist_ok=True)
    if (project / 'docs').is_dir(): (project / 'docs/.gdignore').touch()
    config = project / 'project.godot'
    config.write_text(re.sub(r'^config/name=.*$', f'config/name="{name}"', config.read_text(), flags=re.M))
    try:
        imported = subprocess.run([str(godot), '--headless', '--path', str(project), '--editor', '--import', '--quit'], capture_output=True, text=True, timeout=90)
        if imported.returncode or 'ERROR:' in imported.stdout + imported.stderr:
            print((imported.stdout + imported.stderr)[-6000:]); raise SystemExit(1)
        stages = ['write', 'read', 'recheck'] + (['close'] if args.check_close else [])
        for stage in stages:
            result = subprocess.run([str(godot), '--headless', '--path', str(project), '--script', 'res://tests/profile_restart_probe.gd', '--', f'--stage={stage}'], capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            if args.evidence_dir:
                args.evidence_dir.mkdir(parents=True, exist_ok=True)
                (args.evidence_dir / f'{stage}.log').write_text(output)
            print(output, flush=True)
            if result.returncode or 'ERROR:' in output: raise SystemExit(1)
            if stage == 'close' and 'PROFILE_CLOSE_PRESERVED' not in output:
                raise SystemExit('Window close exited before preserving unsaved personal data')
        print(f'PROFILE_RESTART_PROCESSES: {len(stages)}/{len(stages)} passed; private profile; no network commands replayed')
    finally:
        if data.exists(): shutil.rmtree(data)
