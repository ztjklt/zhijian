import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from runtime_tools import resolve_godot, user_data_path

class RuntimeToolsTest(unittest.TestCase):
    def test_explicit_and_environment_take_precedence_over_path(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'godot'
            binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
            with patch.dict(os.environ, {'GODOT_BIN': str(binary)}):
                self.assertEqual(resolve_godot(), str(binary.resolve()))
                with self.assertRaises(FileNotFoundError): resolve_godot(str(binary) + '-missing')
            with patch.dict(os.environ, {'PATH': folder}, clear=True):
                self.assertEqual(resolve_godot(), str(binary.resolve()))
    def test_platform_profile_locations(self):
        with patch('sys.platform', 'linux'), patch.dict(os.environ, {'XDG_DATA_HOME':'/tmp/xdg-test'}):
            self.assertEqual(user_data_path('private'), Path('/tmp/xdg-test/godot/app_userdata/private'))
        with patch('sys.platform', 'win32'), patch.dict(os.environ, {'APPDATA':'C:/private'}):
            self.assertEqual(user_data_path('private'), Path('C:/private/Godot/app_userdata/private'))
        with self.assertRaises(ValueError): user_data_path('../real-profile')
    def test_aggregate_propagates_failed_runtime_stage(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'broken-godot'
            binary.write_text('#!/bin/sh\necho intentional-runtime-failure\nexit 7\n'); binary.chmod(0o755)
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('run_checks.py')), '--godot', str(binary), '--stages', 'native'], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('FAIL native', result.stdout)
            self.assertIn('intentional-runtime-failure', result.stdout)

if __name__ == '__main__': unittest.main()
