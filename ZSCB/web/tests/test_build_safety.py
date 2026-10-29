"""Keep published rollback packages out of the destructive build path."""
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_web


class BuildSafetyTest(unittest.TestCase):
    def test_protected_output_is_rejected_before_removal(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp).resolve()
            (output / '.zhijian-web-build').touch()
            sentinel = output / 'project' / 'saved-release'
            sentinel.parent.mkdir()
            sentinel.write_text('immutable')
            with patch.object(build_web, 'PROTECTED_OUTPUTS', {output}, create=True), \
                 patch.object(build_web.shutil, 'rmtree', side_effect=AssertionError('release deletion')):
                with self.assertRaisesRegex(ValueError, 'published rollback'):
                    build_web.run(SimpleNamespace(source=build_web.DEFAULT_SOURCE, output=output))
            self.assertEqual(sentinel.read_text(), 'immutable')


if __name__ == '__main__':
    unittest.main()
