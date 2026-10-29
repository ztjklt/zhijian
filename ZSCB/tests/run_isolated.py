from runtime_tools import resolve_godot, user_data_path
"""Run Godot checks in a temporary project with separate user data."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--script', default='res://tests/test_runner.gd')
parser.add_argument('--visual', action='store_true', help='Use a real window/renderer for isolated visual and audio checks')
args = parser.parse_args()
source = Path(__file__).resolve().parents[1]
godot = resolve_godot()
name = 'PaperCastleCheck_' + uuid.uuid4().hex
with tempfile.TemporaryDirectory(prefix='paper-castle-check-') as folder:
    project = Path(folder) / 'project'
    shutil.copytree(source, project, ignore=shutil.ignore_patterns('.godot','__pycache__','releases','previews','evidence'))
    # Documentation captures are evidence, not runtime/importable assets.
    (project / 'docs').mkdir(exist_ok=True)
    (project / 'docs' / '.gdignore').touch()
    config = project / 'project.godot'
    config.write_text(re.sub(r'^config/name=.*$', f'config/name="{name}"', config.read_text(), flags=re.M))
    try:
        imported = subprocess.run([str(godot), '--headless', '--path', str(project), '--editor', '--import', '--quit'], capture_output=True, text=True, timeout=40)
        if imported.returncode or 'ERROR:' in imported.stderr or 'SCRIPT ERROR' in imported.stderr:
            print(imported.stdout + imported.stderr)
            raise SystemExit(imported.returncode or 1)
        runtime_options = [] if args.visual else ['--headless']
        result = subprocess.run([str(godot), *runtime_options, '--path', str(project), '--script', args.script], capture_output=True, text=True, timeout=45)
        print(result.stdout + result.stderr)
        raise SystemExit(result.returncode or (1 if 'ERROR:' in result.stderr or 'SCRIPT ERROR' in result.stderr else 0))
    except subprocess.TimeoutExpired as exc:
        print("Godot test timed out; partial output follows:")
        print((exc.stdout or b" ").decode(errors="replace") if isinstance(exc.stdout, bytes) else exc.stdout or "")
        print((exc.stderr or b" ").decode(errors="replace") if isinstance(exc.stderr, bytes) else exc.stderr or "")
        raise SystemExit(1)
    finally:
        data = user_data_path(name)
        if data.exists():
            shutil.rmtree(data)
