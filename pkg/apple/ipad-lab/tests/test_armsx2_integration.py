"""Exercise optional ARMSX2 provenance, packaging, and deployment gates."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import unittest
import zipfile
import test_build

build = test_build.build


class Armsx2IntegrationTests(unittest.TestCase):
    write_info = test_build.PackagingTests.write_info
    archive_payload = test_build.PackagingTests.archive_payload
    package = test_build.PackagingTests.package

    def setUp(self):
        test_build.PackagingTests.setUp(self)
        self.revision = 'a' * 40
        self.inputs = self.root / '.armsx2-prototype/artifacts'
        self.inputs.mkdir(parents=True)
        source_patches = build.ROOT / build.LAB / 'experiments/armsx2/patches'
        patches = self.root / build.LAB / 'experiments/armsx2/patches'
        shutil.copytree(source_patches, patches)
        hashes = {}
        for patch in patches.glob('*.patch'):
            hashes[patch.name] = hashlib.sha256(patch.read_bytes()).hexdigest()
            shutil.copy2(patch, self.inputs)
        self.binary = self.inputs / 'armsx2_libretro.dylib'
        self.binary.write_bytes(b'ARMSX2 Lab device test: experimental boot')
        self.core_manifest = {
            'upstream_commit': 'e58489d349cdcd635fc6264546087e347c84bf8c',
            'lab_commit': self.revision, 'stage': 'device-test', 'gameplay_enabled': True,
            'architecture': 'arm64', 'platform': 'iOS', 'minimum_ios': '17.4',
            'sha256': hashlib.sha256(self.binary.read_bytes()).hexdigest(), 'patches': hashes,
        }
        self.write_manifest()
        for name in ('binary-inspection.json', 'armsx2-pinned-source.tar.gz',
                     'dependency-sources.tar.gz', 'dependency-SHASUMS', 'ARMSX2-COPYING.GPLv3'):
            (self.inputs / name).write_bytes(b'fixture')
        fonts = self.root / '.armsx2-prototype/source/bin/resources/fonts'
        fonts.mkdir(parents=True)
        (fonts / 'Roboto-Regular.ttf').write_bytes(b'font fixture')

    def write_manifest(self):
        (self.inputs / 'manifest.json').write_text(json.dumps(self.core_manifest))

    def test_rejects_wrong_revision_stage_architecture_or_patch_provenance(self):
        original = copy.deepcopy(self.core_manifest)
        for field, value in [('lab_commit', 'b' * 40), ('upstream_commit', 'b' * 40),
                             ('stage', 'build-probe'), ('architecture', 'x86_64'),
                             ('platform', 'macOS'), ('minimum_ios', '15.0'),
                             ('gameplay_enabled', False), ('patches', {})]:
            with self.subTest(field=field):
                self.core_manifest = dict(original, **{field: value})
                self.write_manifest()
                with self.assertRaises(ValueError):
                    build.armsx2_inputs(self.root, self.revision)

    def test_rejects_changed_binary_and_disabled_marker(self):
        self.binary.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            build.armsx2_inputs(self.root, self.revision)
        self.core_manifest['sha256'] = hashlib.sha256(self.binary.read_bytes()).hexdigest()
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'stage marker'):
            build.armsx2_inputs(self.root, self.revision)

    def test_rejects_missing_source_archive_and_changed_archived_patch(self):
        archive = self.inputs / 'dependency-sources.tar.gz'
        archive.unlink()
        with self.assertRaisesRegex(ValueError, 'provenance file missing'):
            build.armsx2_inputs(self.root, self.revision)
        archive.write_bytes(b'fixture')
        next(self.inputs.glob('*.patch')).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'archived patch checksum'):
            build.armsx2_inputs(self.root, self.revision)

    def test_additional_core_preserves_existing_cores_identity_and_cloud(self):
        modules = self.root / 'modules'
        modules.mkdir()
        (modules / 'play_libretro_ios.dylib').write_bytes(b'existing Play!')
        artifacts = self.root / 'addition'
        artifacts.mkdir()
        original = copy.deepcopy(self.lock)
        manifest = {'cores': copy.deepcopy(self.lock['cores'])}
        build.add_armsx2(self.root, self.revision, modules, artifacts, self.lock, manifest)
        self.assertEqual(self.lock['cores'][:-1], original['cores'])
        self.assertEqual(self.lock['bundle_id'], original['bundle_id'])
        self.assertEqual(build.icloud_entitlements(self.lock), build.icloud_entitlements(original))
        self.assertEqual((modules / 'play_libretro_ios.dylib').read_bytes(), b'existing Play!')
        self.assertEqual((modules / 'armsx2_libretro_ios.dylib').read_bytes(), self.binary.read_bytes())
        self.assertEqual(manifest['preferred_ps2_core'], 'armsx2')
        self.assertEqual(manifest['cores'][-1]['input_sha256'], self.core_manifest['sha256'])
        with zipfile.ZipFile(artifacts / 'ARMSX2-system-files.zip') as archive:
            self.assertEqual(archive.read('pcsx2/resources/fonts/Roboto-Regular.ttf'), b'font fixture')
        self.assertTrue((artifacts / 'ARMSX2-provenance/armsx2-pinned-source.tar.gz').is_file())
        core = self.lock['cores'][-1]
        binary = self.app / build.core_binary_path(core)
        binary.parent.mkdir(parents=True)
        binary.write_bytes(self.binary.read_bytes())
        with zipfile.ZipFile(self.app / 'assets.zip', 'a') as archive:
            archive.writestr('info/armsx2_libretro.info', 'ARMSX2')
        for version in ('15.0', '17.3.99', '17.4beta', True, ''):
            self.info['MinimumOSVersion'] = version
            self.write_info()
            with self.assertRaisesRegex(ValueError, 'ARMSX2 requires'):
                build.validate_app(self.app, self.lock)
        self.info['MinimumOSVersion'] = '17.4'
        self.write_info()
        build.validate_app(self.app, self.lock)
        ipa, result = self.package()
        self.assertEqual(len(result['cores']), len(original['cores']) + 1)
        with zipfile.ZipFile(ipa) as archive:
            last = result['cores'][-1]
            self.assertEqual(hashlib.sha256(archive.read(last['binary_path'])).hexdigest(), last['sha256'])


if __name__ == '__main__':
    unittest.main()
