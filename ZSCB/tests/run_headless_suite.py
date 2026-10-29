from runtime_tools import resolve_godot, user_data_path
"""Run all behavior tests once in a disposable project, with private data per test."""
from pathlib import Path
import re, shutil, subprocess, tempfile, uuid
source=Path(__file__).resolve().parents[1]
godot=resolve_godot()
failed=[]; names=[]
with tempfile.TemporaryDirectory(prefix='paper-full-suite-') as folder:
    project=Path(folder)/'project'
    shutil.copytree(source,project,ignore=shutil.ignore_patterns('.godot','__pycache__','releases','previews','evidence'))
    # Documentation captures are evidence, not runtime/importable assets.
    (project / 'docs' / '.gdignore').touch()
    config=project/'project.godot'; original=config.read_text()
    def configure(name):
        names.append(name)
        config.write_text(re.sub(r'^config/name=.*$',f'config/name="{name}"',original,flags=re.M))
    configure('PaperFullSuite_'+uuid.uuid4().hex)
    try:
        imported=subprocess.run([str(godot),'--headless','--path',str(project),'--editor','--import','--quit'],capture_output=True,text=True,timeout=45)
        if imported.returncode or 'ERROR:' in imported.stderr:
            print(imported.stdout+imported.stderr); raise SystemExit(1)
        scripts=[project/'tests/test_runner.gd']+sorted((project/'tests').glob('*_test.gd'))
        for script in scripts:
            configure('PaperFullSuite_'+uuid.uuid4().hex)
            try:
                result=subprocess.run([str(godot),'--headless','--path',str(project),'--script','res://tests/'+script.name],capture_output=True,text=True,timeout=45)
                output=result.stdout+result.stderr
                ok=result.returncode==0 and 'ERROR:' not in output and 'SCRIPT ERROR' not in output
            except subprocess.TimeoutExpired as error:
                output=str(error.stdout or '')+str(error.stderr or '')
                ok=False
            print(('PASS ' if ok else 'FAIL ')+script.name,flush=True)
            if not ok:
                failed.append(script.name); print(output[-12000:],flush=True)
            else:
                for line in output.splitlines():
                    if any(word in line for word in (' checks','assertions','NETWORK_','TESTS PASSED')): print('  '+line,flush=True)
        print(f'FULL HEADLESS SUITE: {len(scripts)-len(failed)}/{len(scripts)} passed; failures={failed}',flush=True)
        raise SystemExit(1 if failed else 0)
    finally:
        for name in names:
            data=user_data_path(name)
            if data.exists(): shutil.rmtree(data)
