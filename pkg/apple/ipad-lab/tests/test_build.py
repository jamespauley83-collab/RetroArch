import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('ipad_build', Path(__file__).resolve().parents[1] / 'build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lock = build.load_lock(build.ROOT / build.LAB / 'cores.lock.json')
        self.app = self.root / 'RetroArch.app'
        self.app.mkdir()
        self.info = {'CFBundleIdentifier': self.lock['bundle_id'],
                     'CFBundleDisplayName': self.lock['display_name'],
                     'CFBundleExecutable': 'RetroArch', 'UIFileSharingEnabled': True}
        self.write_info()
        (self.app / 'RetroArch').touch()
        for core in self.lock['cores']:
            name = core['name'].replace('_', '.') + '.libretro'
            directory = self.app / 'Frameworks' / (name + '.framework')
            directory.mkdir(parents=True)
            (directory / name).touch()
        with zipfile.ZipFile(self.app / 'assets.zip', 'w') as assets:
            for core in self.lock['cores']:
                assets.writestr('info/' + core['name'] + '_libretro.info', '')

    def write_info(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_complete_package(self):
        build.validate_app(self.app, self.lock)

    def test_core_info_overlay_preserves_other_assets(self):
        assets_path = self.root / 'pkg/apple/assets.zip'
        assets_path.parent.mkdir(parents=True)
        info = self.root / build.LAB / 'info'
        info.mkdir(parents=True)
        (info / 'opera_libretro.info').write_text('corename = "Opera"')
        with zipfile.ZipFile(assets_path, 'w') as assets:
            assets.writestr('menu/icon.png', b'original icon')
            assets.writestr('info/opera_libretro.info', 'old info')
        build.overlay_core_info(self.root)
        with zipfile.ZipFile(assets_path) as assets:
            self.assertEqual(assets.read('menu/icon.png'), b'original icon')
            self.assertEqual(assets.read('info/opera_libretro.info'), b'corename = "Opera"')
            self.assertEqual(assets.namelist().count('info/opera_libretro.info'), 1)

    def test_rejects_official_app_identity(self):
        self.info['CFBundleIdentifier'] = 'com.libretro.RetroArchiOS11'
        self.write_info()
        with self.assertRaisesRegex(ValueError, 'bundle identifier'):
            build.validate_app(self.app, self.lock)

    def test_missing_core_stops_packaging(self):
        next((self.app / 'Frameworks').glob('*/*')).unlink()
        with self.assertRaisesRegex(ValueError, 'core is missing'):
            build.validate_app(self.app, self.lock)

    def test_extension_must_use_lab_identity(self):
        extension = self.app / 'PlugIns/widget.appex'
        extension.mkdir(parents=True)
        (extension / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.libretro.widget'}))
        with self.assertRaisesRegex(ValueError, 'Extension identifier'):
            build.validate_app(self.app, self.lock)

    def test_customization_preserves_file_sharing(self):
        build.customize_plist(self.app / 'Info.plist', self.lock)
        info = plistlib.loads((self.app / 'Info.plist').read_bytes())
        self.assertTrue(info['UIFileSharingEnabled'])
        self.assertEqual(info['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['retroarchlab'])

    def test_rejects_moving_core_ref(self):
        lock = copy.deepcopy(self.lock)
        lock['cores'][0]['commit'] = 'master'
        path = self.root / 'lock.json'
        path.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, 'complete commit SHA'):
            build.load_lock(path)

    def test_missing_core_info_stops_packaging(self):
        with zipfile.ZipFile(self.app / 'assets.zip', 'w'):
            pass
        with self.assertRaisesRegex(ValueError, 'core info is missing'):
            build.validate_app(self.app, self.lock)


if __name__ == '__main__':
    unittest.main()
