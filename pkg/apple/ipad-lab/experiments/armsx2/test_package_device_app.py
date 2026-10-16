import hashlib
from pathlib import Path
import plistlib
import tempfile
import unittest

from package_device_app import (BUNDLE_ID, customize_test_plist,
                                validate_core_manifest, verify_isolation)


class DevicePackageValidation(unittest.TestCase):
    def test_rejects_probe_and_changed_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'core.dylib'
            binary.write_bytes(b'device core fixture')
            manifest = dict(stage='device-test', gameplay_enabled=True,
                            architecture='arm64', platform='iOS',
                            sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
            validate_core_manifest(manifest, binary)
            for field, value in [('stage', 'build-probe'), ('gameplay_enabled', False),
                                 ('architecture', 'x86_64'), ('platform', 'iOS Simulator'),
                                 ('sha256', 'incorrect')]:
                with self.subTest(field=field), self.assertRaises(ValueError):
                    validate_core_manifest(dict(manifest, **{field: value}), binary)

    def test_rejects_shared_identity_and_extra_core(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            info_path = app / 'Info.plist'
            info_path.write_bytes(plistlib.dumps({'CFBundleIdentifier': BUNDLE_ID}))
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


if __name__ == '__main__':
    unittest.main()
