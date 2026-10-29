"""Port the proven Web flow/prediction without downgrading current gameplay."""
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_client import prepare

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'dist/纸间联机最新版-20261025-r7'


class LatestPrepareTest(unittest.TestCase):
    def test_latest_gameplay_and_ui_survive_web_preparation(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            shutil.copytree(SOURCE / 'scripts', project / 'scripts')
            try:
                prepare(project)
            except ValueError as error:
                self.fail('Latest source must prepare without obsolete r2 anchors: ' + str(error))
            for name in ['weapon_types.gd', 'weapon_type_wheel.gd', 'object_damage.gd',
                         'combat_audio.gd', 'vitals_hud.gd', 'backpack_panel.gd', 'paper_theme.gd']:
                self.assertEqual((project / 'scripts' / name).read_bytes(),
                                 (SOURCE / 'scripts' / name).read_bytes(), name)
            session = (project / 'scripts/net/session.gd').read_text()
            self.assertIn('prediction.receive(game,state', session)
            self.assertIn('prediction.sent_input(input_number,controls)', session)
            self.assertIn('flow_ui.session=self', session)
            self.assertIn('PaperObjectDamage.valid_cuts', session)
            self.assertIn('game.ink.amount', session)
            self.assertIn('last_event=cursor if feedback_epoch!=epoch else maxi(last_event,cursor)', session)
            self.assertIn('const PROTOCOL := 6', (project / 'scripts/net/codec.gd').read_text())
            actor = (project / 'scripts/net/actor.gd').read_text()
            for field in ['"input_ack":input_seq', '"input_age":input_age', '"movement_reset":movement_reset']:
                self.assertIn(field, actor)


    def test_r13_gameplay_survives_legacy_movement_preparation(self):
        source = ROOT / 'dist/纸间第一件作品候选-20261026-r13'
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            shutil.copytree(source / 'scripts', project / 'scripts')
            prepare(project)
            for name in ['first_work.gd', 'structure_links.gd', 'weapon_lab.gd', 'net/cooperation.gd']:
                self.assertEqual((project / 'scripts' / name).read_bytes(),
                                 (source / 'scripts' / name).read_bytes(), name)
            self.assertTrue((project / 'scripts/net/local_prediction.gd').is_file())

    def test_native_movement_source_prepares_without_overwriting_matched_predictor(self):
        core = Path(__file__).resolve().parents[2]
        from prepare_authority import prepare_authority
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            shutil.copytree(core / 'scripts', project / 'scripts')
            predictor = (project / 'scripts/net/local_prediction.gd').read_bytes()
            actor = (project / 'scripts/net/actor.gd').read_bytes()
            room = (project / 'scripts/net/room.gd').read_bytes()
            prepare(project)
            self.assertEqual((project / 'scripts/net/local_prediction.gd').read_bytes(), predictor)
            self.assertEqual((project / 'scripts/net/actor.gd').read_bytes(), actor)
            self.assertEqual((project / 'scripts/net/room.gd').read_bytes(), room)
            # A dedicated authority preparation after Web metadata must be a no-op.
            prepare_authority(project)
            self.assertEqual((project / 'scripts/net/actor.gd').read_bytes(), actor)
            self.assertEqual((project / 'scripts/net/room.gd').read_bytes(), room)


if __name__ == '__main__':
    unittest.main()
