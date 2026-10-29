import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('ps3_package', Path(__file__).with_name('package.py'))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.app = self.root / 'Host.app'
        self.app.mkdir()
        self.info = {'CFBundleIdentifier': package.IDENTITY, 'CFBundleExecutable': 'Host'}
        self.plist()
        (self.app / 'Host').write_bytes(b'host RALabPS3Controller')
        (self.app / 'embedded.mobileprovision').write_bytes(b'old profile')
        (self.app / 'PlugIns').mkdir()
        self.ipa = self.root / 'core.ipa'
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr(package.CORE_PATH, b'test core')
        self.lock = package.LOCK.copy()
        package.LOCK['ipa_sha256'] = hashlib.sha256(self.ipa.read_bytes()).hexdigest()
        package.LOCK['core_sha256'] = hashlib.sha256(b'test core').hexdigest()
        self.destination = self.root / 'output'

    def tearDown(self):
        package.LOCK = self.lock
        self.temp.cleanup()

    def plist(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_isolated_copy_preserves_input(self):
        target = package.package(self.app, self.ipa, self.destination)
        self.assertTrue((self.app / 'embedded.mobileprovision').exists())
        self.assertFalse((target / 'embedded.mobileprovision').exists())
        self.assertFalse((target / 'PlugIns').exists())
        info = plistlib.loads((target / 'Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], package.IDENTITY)
        self.assertEqual(info['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['retroarchlabps3bridge'])
        self.assertEqual((target / 'Frameworks/libRPCS3Core.dylib').read_bytes(), b'test core')

    def test_rejects_existing_output(self):
        self.destination.mkdir()
        with self.assertRaises(ValueError):
            package.package(self.app, self.ipa, self.destination)

    def test_rejects_working_app_identity(self):
        self.info['CFBundleIdentifier'] = 'com.jamespauley.retroarchlab'
        self.plist()
        with self.assertRaises(ValueError):
            package.package(self.app, self.ipa, self.destination)
        self.assertFalse(self.destination.exists())

    def test_rejects_host_without_bridge(self):
        (self.app / 'Host').write_bytes(b'old host')
        with self.assertRaises(ValueError):
            package.package(self.app, self.ipa, self.destination)

    def test_rejects_tampered_ipa(self):
        self.ipa.write_bytes(self.ipa.read_bytes() + b'tampered')
        with self.assertRaises(ValueError):
            package.package(self.app, self.ipa, self.destination)
        self.assertFalse(self.destination.exists())

    def test_rejects_wrong_core_hash(self):
        package.LOCK['core_sha256'] = '0' * 64
        with self.assertRaises(ValueError):
            package.package(self.app, self.ipa, self.destination)


if __name__ == '__main__':
    unittest.main()
