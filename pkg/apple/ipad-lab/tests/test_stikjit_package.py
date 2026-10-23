"""Exercise helper retention, identity changes, and executable inventory rejection."""
import io
import json
import plistlib
import unittest
import zipfile
import test_eight_core_test as fixtures

macho = fixtures.macho
package = fixtures.package


class StikJITPackaging(fixtures.EightCoreTestPackaging):
    def setUp(self):
        super().setUp()
        helper = macho() + b'helper'
        framework = macho(minimum=(17 << 16) | (4 << 8)) + b'stikjit'
        self.entries[package.HELPER + 'RALabJITHelper'] = helper
        self.entries[package.HELPER + 'Info.plist'] = plistlib.dumps({
            'CFBundleIdentifier': self.manifest['bundle_id'] + '.JITHelper',
            'CFBundleExecutable': 'RALabJITHelper',
            'NSExtension': {'NSExtensionPrincipalClass': 'RALabJITHelper',
                            'NSExtensionPointIdentifier': 'com.apple.ar.viewer'}})
        self.entries[package.JIT_FRAMEWORK + 'StikJIT'] = framework
        self.manifest['stikjit'] = {'commit': package.STIKJIT_COMMIT,
            'helper_bundle_id': self.manifest['bundle_id'] + '.JITHelper',
            'helper_sha256': package.sha256(helper),
            'framework_sha256': package.sha256(framework)}

    def test_preserves_helper_and_retargets_identity(self):
        self.write_input()
        result = package.package(self.source, self.target)
        with zipfile.ZipFile(result) as archive:
            info = plistlib.loads(archive.read(package.HELPER + 'Info.plist'))
            self.assertEqual(info['CFBundleIdentifier'], package.BUNDLE_ID + '.JITHelper')
            self.assertEqual(archive.read(package.HELPER + 'RALabJITHelper'),
                             self.entries[package.HELPER + 'RALabJITHelper'])
            self.assertFalse(any('widget.appex' in n for n in archive.namelist()))
            manifest = json.loads(archive.read(package.PREFIX + 'retroarch-lab-build.json'))
            self.assertEqual(manifest['stikjit']['helper_bundle_id'], info['CFBundleIdentifier'])

    def test_rejects_tampered_helper(self):
        self.entries[package.HELPER + 'RALabJITHelper'] += b'changed'
        self.write_input()
        with self.assertRaisesRegex(ValueError, 'checksum'):
            package.package(self.source, self.target)

    def test_rejects_helper_with_working_app_identity(self):
        self.manifest['stikjit']['helper_bundle_id'] = 'working.helper'
        self.write_input()
        with self.assertRaisesRegex(ValueError, 'identity'):
            package.package(self.source, self.target)

    def test_rejects_unlisted_nested_executable(self):
        self.entries[package.HELPER + 'hidden.bin'] = macho()
        self.write_input()
        with self.assertRaisesRegex(ValueError, 'nested JIT executable'):
            package.package(self.source, self.target)

    def test_rejects_cloud_registration_in_helper(self):
        path = package.HELPER + 'Info.plist'
        info = plistlib.loads(self.entries[path])
        info['NSUbiquitousContainers'] = {'working': {}}
        self.entries[path] = plistlib.dumps(info)
        self.write_input()
        with self.assertRaisesRegex(ValueError, 'cloud'):
            package.package(self.source, self.target)


if __name__ == '__main__':
    unittest.main()
