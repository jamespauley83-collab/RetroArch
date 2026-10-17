import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest import mock
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

    def archive_payload(self, *args):
        if shutil.which('ditto'):
            return self.run_command(*args)
        payload, ipa = args[-2:]
        with zipfile.ZipFile(ipa, 'w') as archive:
            for path in payload.rglob('*'):
                if path.is_file():
                    archive.write(path, path.relative_to(payload.parent))

    def package(self, archive=None):
        artifacts = self.root / 'artifacts'
        artifacts.mkdir()
        raw_hash = hashlib.sha256(b'original dylib').hexdigest()
        manifest = {'cores': [dict(core, patches={'diagnostics.patch': 'patch-hash'},
                                   sha256=raw_hash) for core in self.lock['cores']]}
        self.run_command = build.run
        with mock.patch.object(build, 'run', side_effect=archive or self.archive_payload):
            ipa = build.package_app(self.app, self.root, artifacts, manifest)
        return ipa, json.loads((artifacts / 'build-manifest.json').read_text())

    def test_manifest_hashes_match_final_ipa_executables(self):
        expected = {}
        for core in self.lock['cores']:
            name = core['name'].replace('_', '.') + '.libretro'
            relative = 'Frameworks/' + name + '.framework/' + name
            data = ('framework after conversion and signing: ' + core['name']).encode()
            (self.app / relative).write_bytes(data)
            expected[core['name']] = ('Payload/RetroArch.app/' + relative, data)
        ipa, manifest = self.package()
        with zipfile.ZipFile(ipa) as archive:
            embedded = json.loads(archive.read('Payload/RetroArch.app/retroarch-lab-build.json'))
            self.assertEqual(embedded['cores'], manifest['cores'])
            self.assertNotIn('ipa_sha256', embedded)
            for core in manifest['cores']:
                path, data = expected[core['name']]
                self.assertEqual(core['binary_path'], path)
                self.assertEqual(archive.read(path), data)
                self.assertEqual(core['sha256'], hashlib.sha256(archive.read(path)).hexdigest())
                self.assertNotEqual(core['sha256'], hashlib.sha256(b'original dylib').hexdigest())
                self.assertEqual(core['patches'], {'diagnostics.patch': 'patch-hash'})
        self.assertEqual(manifest['ipa_sha256'], hashlib.sha256(ipa.read_bytes()).hexdigest())

    def test_archive_checksum_mismatch_stops_packaging(self):
        def changed_archive(*args):
            payload = args[-2]
            next((payload / self.app.name / 'Frameworks').glob('*/*')).write_bytes(b'changed')
            self.archive_payload(*args)

        with self.assertRaisesRegex(ValueError, 'core checksum mismatch'):
            self.package(changed_archive)
        self.assertFalse((self.root / 'artifacts/build-manifest.json').exists())

    def test_missing_final_core_stops_manifest_creation(self):
        next((self.app / 'Frameworks').glob('*/*')).unlink()
        with self.assertRaises(FileNotFoundError):
            self.package()
        self.assertFalse((self.root / 'artifacts/build-manifest.json').exists())

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

    def test_dolphin_system_archive_has_installable_layout(self):
        sys_dir = self.root / 'dolphin/Data/Sys'
        (sys_dir / 'GameSettings').mkdir(parents=True)
        (sys_dir / 'codehandler.bin').write_bytes(b'handler')
        (sys_dir / 'GameSettings/example.ini').write_text('[Core]\n')
        artifacts = self.root / 'artifacts'
        artifacts.mkdir()
        record = build.package_dolphin_system(self.root / 'dolphin', artifacts)
        archive_path = artifacts / record['file']
        with zipfile.ZipFile(archive_path) as archive:
            self.assertEqual(archive.read('dolphin-emu/Sys/codehandler.bin'), b'handler')
            self.assertEqual(archive.read('dolphin-emu/Sys/GameSettings/example.ini'), b'[Core]\n')
        self.assertEqual(record['sha256'], hashlib.sha256(archive_path.read_bytes()).hexdigest())

    def test_missing_dolphin_system_files_stop_packaging(self):
        with self.assertRaisesRegex(ValueError, 'system files are missing'):
            build.package_dolphin_system(self.root, self.root)

    def test_unknown_recipe_is_rejected(self):
        lock = copy.deepcopy(self.lock)
        lock['cores'][0]['recipe'] = 'unknown'
        path = self.root / 'lock.json'
        path.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, 'Unsupported core build recipe'):
            build.load_lock(path)

    def test_yabause_recipe_builds_in_nested_directory_without_jit(self):
        repo = self.root / 'yabause'
        directory = repo / 'yabause/src/libretro'
        directory.mkdir(parents=True)
        (directory / 'Makefile').write_text(
            'all:\n'
            '\t@test "$(platform)" = "ios-arm64"\n'
            '\t@test "$(DYNAREC)" = "0"\n'
            '\t@test "$(USE_PLAY_JIT)" = "0"\n'
            '\t@printf "%s" "$(MINVERSION)" > yabause_libretro_ios.dylib\n')
        core = next(c for c in self.lock['cores'] if c['name'] == 'yabause')
        for version in ('15.0', '17.4'):
            with self.subTest(minimum_ios=version):
                binary = build.compile_core(core, repo, self.root, version)
                self.assertEqual(binary, directory / 'yabause_libretro_ios.dylib')
                self.assertEqual(binary.read_text(), '-miphoneos-version-min=' + version)

    def test_icloud_entitlements_are_isolated_and_follow_lab_identity(self):
        lock = dict(self.lock, bundle_id='com.jamespauley.retroarchlab.test')
        entitlements = build.icloud_entitlements(lock)
        container = 'iCloud.com.jamespauley.retroarchlab.test'
        self.assertEqual(entitlements['com.apple.developer.icloud-container-identifiers'], [container])
        self.assertEqual(entitlements['com.apple.developer.ubiquity-container-identifiers'], [container])
        self.assertEqual(entitlements['com.apple.developer.icloud-services'], ['CloudDocuments'])


if __name__ == '__main__':
    unittest.main()
