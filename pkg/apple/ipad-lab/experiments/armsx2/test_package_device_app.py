import hashlib
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

from package_device_app import (BUNDLE_ID, customize_test_plist,
                                validate_core_manifest, verify_isolation, verify_packaged_app)


class DevicePackageValidation(unittest.TestCase):
    def test_rejects_probe_and_changed_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'core.dylib'
            binary.write_bytes(b'device core fixture')
            manifest = dict(stage='device-test', gameplay_enabled=True,
                            architecture='arm64', platform='iOS', minimum_ios='26.0',
                            sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
            validate_core_manifest(manifest, binary)
            for field, value in [('stage', 'build-probe'), ('gameplay_enabled', False),
                                 ('architecture', 'x86_64'), ('platform', 'iOS Simulator'),
                                 ('minimum_ios', '17.4'), ('minimum_ios', '25.9'),
                                 ('minimum_ios', None), ('sha256', 'incorrect')]:
                with self.subTest(field=field), self.assertRaises(ValueError):
                    validate_core_manifest(dict(manifest, **{field: value}), binary)

    def test_rejects_shared_identity_and_extra_core(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            info_path = app / 'Info.plist'
            info_path.write_bytes(plistlib.dumps({'CFBundleIdentifier': BUNDLE_ID, 'MinimumOSVersion': '26.0'}))
            customize_test_plist(info_path)
            frameworks = app / 'Frameworks'
            (frameworks / 'armsx2.libretro.framework').mkdir(parents=True)
            verify_isolation(app)
            extra = frameworks / 'play.libretro.framework'
            extra.mkdir()
            with self.assertRaises(ValueError):
                verify_isolation(app)
            extra.rmdir()
            good = plistlib.loads(info_path.read_bytes())
            for field, value in [('CFBundleIdentifier', 'com.jamespauley.retroarchlab'),
                                 ('CFBundleURLTypes', [{'CFBundleURLSchemes': ['retroarchlab']}])]:
                info_path.write_bytes(plistlib.dumps(dict(good, **{field: value})))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    verify_isolation(app)

    def test_final_app_and_ipa_require_ios_26(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'RetroArch.app'
            (app / 'Frameworks/armsx2.libretro.framework').mkdir(parents=True)
            info_path = app / 'Info.plist'
            info_path.write_bytes(plistlib.dumps({'CFBundleIdentifier': BUNDLE_ID}))
            customize_test_plist(info_path)
            original = plistlib.loads(info_path.read_bytes())
            for version in [None, '', '15.0', '17', '17.3.99', '17.4beta',
                            '26.0.0.1', 26.0, True, '17.4', '18.0', '25.9',
                            '26beta', '26', '26.0', '26.0.0', '26.0.1', '27.0']:
                with self.subTest(version=version):
                    info = dict(original)
                    if version is not None:
                        info['MinimumOSVersion'] = version
                    info_path.write_bytes(plistlib.dumps(info))
                    ipa = Path(directory) / 'test.ipa'
                    with zipfile.ZipFile(ipa, 'w') as archive:
                        archive.write(info_path, 'Payload/RetroArch.app/Info.plist')
                        archive.writestr('Payload/RetroArch.app/Frameworks/'
                                         'armsx2.libretro.framework/armsx2.libretro', b'fixture')
                    if version in ('26', '26.0', '26.0.0', '26.0.1', '27.0'):
                        verify_isolation(app)
                        verify_packaged_app(ipa)
                    else:
                        with self.assertRaisesRegex(ValueError, 'iOS 26.0'):
                            verify_isolation(app)
                        with self.assertRaisesRegex(ValueError, 'iOS 26.0'):
                            verify_packaged_app(ipa)

    def test_final_ipa_rejects_shared_identity_cloud_and_extra_core(self):
        with tempfile.TemporaryDirectory() as directory:
            info_path = Path(directory) / 'Info.plist'
            info_path.write_bytes(plistlib.dumps({'CFBundleIdentifier': BUNDLE_ID,
                                                  'MinimumOSVersion': '26.0'}))
            customize_test_plist(info_path)
            original = plistlib.loads(info_path.read_bytes())
            for field, value in [('CFBundleIdentifier', 'com.jamespauley.retroarchlab'),
                                 ('CFBundleURLTypes', []),
                                 ('NSUbiquitousContainers', {'iCloud.shared': {}}),
                                 ('extra_core', True)]:
                with self.subTest(field=field):
                    ipa = Path(directory) / 'test.ipa'
                    with zipfile.ZipFile(ipa, 'w') as archive:
                        archive.writestr('Payload/RetroArch.app/Info.plist',
                                         plistlib.dumps(dict(original, **{field: value})))
                        for core in (['armsx2', 'play'] if field == 'extra_core' else ['armsx2']):
                            archive.writestr('Payload/RetroArch.app/Frameworks/' + core +
                                             '.libretro.framework/' + core + '.libretro', b'fixture')
                    with self.assertRaises(ValueError):
                        verify_packaged_app(ipa)


if __name__ == '__main__':
    unittest.main()
