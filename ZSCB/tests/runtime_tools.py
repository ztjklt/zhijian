"""Portable Godot discovery and disposable profile locations (stdlib only)."""
import os
from pathlib import Path
import shutil
import sys


def resolve_godot(explicit=None) -> str:
    requested = str(explicit or os.environ.get('GODOT_BIN', ''))
    candidates = [requested] if requested else ['godot', 'godot4', 'Godot', str(Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot'), '/Applications/Godot.app/Contents/MacOS/Godot']
    for candidate in candidates:
        executable = shutil.which(candidate)
        if executable: return str(Path(executable).resolve())
    raise FileNotFoundError('Godot executable unavailable: ' + (requested or 'set --godot, GODOT_BIN or add Godot to PATH'))


def user_data_path(name: str) -> Path:
    if not name or any(char in name for char in '/\\') or name in ('.', '..'):
        raise ValueError('A single private profile name is required')
    if sys.platform == 'darwin':
        base = Path.home() / 'Library/Application Support/Godot'
    elif sys.platform == 'win32':
        base = Path(os.environ['APPDATA']) / 'Godot'
    else:
        base = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'godot'
    return base / 'app_userdata' / name
