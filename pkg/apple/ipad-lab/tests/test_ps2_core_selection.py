import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'ps2_core_selection.py'
spec = importlib.util.spec_from_file_location('ps2_core_selection', SCRIPT)
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


class SelectionTests(unittest.TestCase):
    def test_explicit_play_overrides_armsx2_default_and_keeps_unknown_fields(self):
        original = {'default_core_path': selection.CORE_PATH, 'default_core_name': 'ARMSX2',
                    'extension': {'keep': True}, 'items': [
                        {'path': '/games/game.iso', 'label': 'Keep title',
                         'core_path': '/old/play_libretro_ios.dylib', 'core_name': 'Play!',
                         'db_name': 'Sony - PlayStation 2.lpl', 'crc32': '123|crc',
                         'custom': [1, 2]},
                        {'path': '/games/other.iso', 'core_path': 'dolphin_libretro.so',
                         'core_name': 'Dolphin'}]}
        before = copy.deepcopy(original)
        edited, changes = selection.plan_playlist(original, 'Sony - PlayStation 2.lpl')
        self.assertEqual(original, before)
        expected = copy.deepcopy(original)
        expected['items'][0].update(core_path=selection.CORE_PATH, core_name='ARMSX2')
        self.assertEqual(edited, expected)
        self.assertEqual([change['field'] for change in changes],
                         ['items[0].core_path', 'items[0].core_name'])

    def test_history_and_favorites_follow_explicit_play_not_extension(self):
        for filename in ('content_history.lpl', 'content_favorites.lpl'):
            with self.subTest(filename=filename):
                document = {'items': [
                    {'core_path': ':/Frameworks/play.libretro.framework', 'core_name': 'Play!'},
                    {'path': 'uncertain.iso', 'core_path': 'DETECT', 'core_name': 'DETECT'},
                    {'path': 'also-uncertain.chd'},
                    {'path': 'ps2.iso', 'core_path': 'DETECT',
                     'db_name': 'Sony - PlayStation 2.lpl'}]}
                edited, changes = selection.plan_playlist(document, filename)
                self.assertEqual(edited['items'][0]['core_path'], selection.CORE_PATH)
                self.assertEqual(edited['items'][1:3], document['items'][1:3])
                self.assertEqual(edited['items'][3]['core_path'], selection.CORE_PATH)
                self.assertEqual(len(changes), 4)

    def test_ps2_default_assignment_and_detect_entries_are_corrected(self):
        for default in ('DETECT', '', '/old/play.libretro.framework/play.libretro'):
            with self.subTest(default=default):
                document = {'default_core_path': default,
                            'items': [{'core_path': 'DETECT', 'core_name': 'DETECT'},
                                      {'core_path': 'pcsx2_libretro.so', 'core_name': 'PCSX2'}]}
                edited, unused = selection.plan_playlist(document, 'Sony - PlayStation 2.lpl')
                self.assertEqual(edited['default_core_path'], selection.CORE_PATH)
                self.assertEqual(edited['items'][0]['core_path'], selection.CORE_PATH)
                self.assertEqual(edited['items'][1], document['items'][1])

    def test_non_ps2_default_is_not_overridden_by_database_or_filename(self):
        document = {'default_core_path': 'dolphin_libretro.so',
                    'default_core_name': 'Dolphin', 'items': [
                        {'core_path': 'DETECT', 'db_name': 'Sony - PlayStation 2.lpl'}]}
        edited, changes = selection.plan_playlist(document, 'Sony - PlayStation 2.lpl')
        self.assertEqual(edited, document)
        self.assertEqual(changes, [])

    def test_armsx2_assignment_requires_no_changes_even_with_custom_name(self):
        document = {'default_core_path': selection.CORE_PATH,
                    'default_core_name': 'ARMSX2 Lab',
                    'items': [{'core_path': selection.CORE_PATH, 'core_name': 'ARMSX2 Lab'},
                              {'core_path': 'DETECT'}]}
        edited, changes = selection.plan_playlist(document, 'Sony - PlayStation 2.lpl')
        self.assertEqual(edited, document)
        self.assertEqual(changes, [])

    def test_unrelated_or_misleading_paths_never_select_ps2(self):
        for core in ('/game/play.iso', 'notplay_libretro.so', 'playstation_libretro.so',
                     '/Play!/Dolphin.libretro.framework'):
            document = {'items': [{'path': '/PS2/game.iso', 'core_path': core}]}
            self.assertEqual(selection.plan_playlist(document, 'PS2.lpl'), (document, []))

    def test_invalid_playlist_shapes_are_rejected(self):
        for value in ([], {}, {'items': {}}, {'items': [None]},
                      {'items': [{'core_path': 5}]}, {'items': [], 'default_core_name': None}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                selection.plan_playlist(value, 'test.lpl')


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.export = self.root / 'export'
        self.export.mkdir()
        self.app = self.root / 'RetroArch.app'
        binary = self.app / 'Frameworks/armsx2.libretro.framework/armsx2.libretro'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b'test core executable')
        (self.app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.jamespauley.retroarchlab.ps3bridge',
            'CFBundleVersion': '18'}))
        with zipfile.ZipFile(self.app / 'assets.zip', 'w') as assets:
            assets.writestr('info/armsx2_libretro.info', 'fixture')
        self.playlist = self.export / 'content_history.lpl'
        self.playlist.write_text(' { "items" : [{"core_path":"play_libretro.so",'
                                 '"core_name":"Play!","path":"/game.iso"}], "custom":1 }\n')

    def plan(self, files=None):
        return selection.plan_export(self.export, self.app, files or ['content_history.lpl'])

    def test_dry_run_leaves_every_export_file_unchanged(self):
        for path in ('RetroArch/system/pcsx2/bios/scph39001.bin',
                     'RetroArch/system/pcsx2/memcards/Mcd001.ps2',
                     'Play Data Files/mcd0', 'states/game.state', 'games/game.iso', 'retroarch.cfg'):
            target = self.export / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(('preserve ' + path).encode())
        original = {str(p): p.read_bytes() for p in self.export.rglob('*') if p.is_file()}
        report, payloads = self.plan()
        self.assertEqual(report['changed_files'], 1)
        self.assertFalse(report['source_export_modified'])
        self.assertEqual(original, {str(p): p.read_bytes() for p in self.export.rglob('*') if p.is_file()})
        self.assertEqual(set(payloads), {'content_history.lpl'})

    def test_separate_output_preserves_exact_original_and_no_overwrite(self):
        original = self.playlist.read_bytes()
        report, payloads = self.plan()
        destination = self.root / 'review'
        selection.write_repair_package(destination, report, payloads)
        self.assertEqual((destination / 'originals/content_history.lpl').read_bytes(), original)
        edited = json.loads((destination / 'proposed/content_history.lpl').read_bytes())
        self.assertEqual(edited['items'][0]['core_path'], selection.CORE_PATH)
        self.assertEqual(self.playlist.read_bytes(), original)
        with self.assertRaisesRegex(ValueError, 'already exists'):
            selection.write_repair_package(destination, report, payloads)

    def test_already_correct_has_no_proposed_copy_or_byte_churn(self):
        original = b'{"items" : [{"core_path": ":/Frameworks/armsx2.libretro.framework", "core_name":"ARMSX2"}]} '
        self.playlist.write_bytes(original)
        report, payloads = self.plan()
        self.assertEqual(report['changed_files'], 0)
        self.assertEqual(payloads, {})
        self.assertEqual(self.playlist.read_bytes(), original)

    def test_malformed_compressed_duplicate_keys_fail_before_output(self):
        for data in (b'RZIP\x00compressed', b'{"items":', b'{"items":[],"items":[]}',
                     b'{"items":[],"unknown":NaN}'):
            (self.export / 'bad.lpl').write_bytes(data)
            destination = self.root / 'no-output'
            result = subprocess.run([sys.executable, str(SCRIPT), '--export-root', str(self.export),
                                     '--app', str(self.app), '--playlist', 'content_history.lpl',
                                     '--playlist', 'bad.lpl', '--output', str(destination)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(destination.exists())
            self.assertEqual((self.export / 'bad.lpl').read_bytes(), data)

    def test_only_selected_paths_are_read(self):
        (self.export / 'unselected.lpl').write_bytes(b'not JSON')
        self.assertEqual(len(self.plan()[0]['files']), 1)

    def test_missing_core_and_metadata_reject_plan(self):
        binary = self.app / 'Frameworks/armsx2.libretro.framework/armsx2.libretro'
        binary.unlink()
        with self.assertRaisesRegex(ValueError, 'executable'):
            self.plan()
        binary.write_bytes(b'core')
        with zipfile.ZipFile(self.app / 'assets.zip', 'w'):
            pass
        with self.assertRaisesRegex(ValueError, 'metadata'):
            self.plan()

    def test_unsafe_or_symlink_paths_are_rejected(self):
        (self.export / 'link.lpl').symlink_to(self.playlist)
        for path in ('../content_history.lpl', '/content_history.lpl', 'link.lpl',
                     './content_history.lpl', 'retroarch.cfg', 'dir\\content_history.lpl'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.plan([path])

    def test_cli_rejects_output_inside_export(self):
        result = subprocess.run([sys.executable, str(SCRIPT), '--export-root', str(self.export),
                                 '--app', str(self.app), '--playlist', 'content_history.lpl',
                                 '--output', str(self.export / 'output')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.export / 'output').exists())


if __name__ == '__main__':
    unittest.main()
