"""Safety gates for deriving a separate device-test IPA from the CI artifact."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('eight_core_test',
    Path(__file__).resolve().parents[1] / 'package_eight_core_test.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


def macho(platform=2, minimum=26 << 16, cpu=0x100000c):
    return (struct.pack('<8I', 0xfeedfacf, cpu, 0, 6, 1, 24, 0, 0)
            + struct.pack('<6I', 0x32, 24, platform, minimum, 26 << 16, 0))


class EightCoreTestPackaging(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.target = self.root / 'test-copy'
        self.info = {'CFBundleIdentifier': 'com.jamespauley.retroarchlab',
                     'CFBundleDisplayName': 'RetroArch Lab', 'MinimumOSVersion': '26.0',
                     'ALTBundleIdentifier': 'com.jamespauley.retroarchlab',
                     'LSSupportsOpeningDocumentsInPlace': True,
                     'CFBundleDocumentTypes': [{'CFBundleTypeName': 'ROM'}],
                     'NSUbiquitousContainers': {'iCloud.com.jamespauley.retroarchlab': {}},
                     'UTExportedTypeDeclarations': [], 'UIFileSharingEnabled': True}
        self.manifest = {'bundle_id': self.info['CFBundleIdentifier'],
                         'retroarch_commit': 'a' * 40, 'minimum_ios': '26.0',
                         'device_signed': False, 'device_tested': False, 'cores': [],
                         'icloud_drive': {'container': 'iCloud.com.jamespauley.retroarchlab'}}
        self.entries = {package.PREFIX + 'RetroArch': macho(),
                        package.PREFIX + 'Frameworks/MoltenVK.framework/MoltenVK': macho(minimum=13 << 16),
                        package.PREFIX + 'PlugIns/widget.appex/Info.plist': plistlib.dumps({'CFBundleIdentifier': 'working.widget'})}
        assets = io.BytesIO()
        with zipfile.ZipFile(assets, 'w') as archive:
            for name in sorted(package.CORES):
                framework = name.replace('_', '.') + '.libretro'
                path = package.PREFIX + 'Frameworks/' + framework + '.framework/' + framework
                binary = macho() + name.encode()
                self.entries[path] = binary
                self.manifest['cores'].append({'name': name, 'binary_path': path,
                                               'sha256': package.sha256(binary)})
                archive.writestr('info/' + name + '_libretro.info', name)
        self.entries[package.PREFIX + 'assets.zip'] = assets.getvalue()

    def write_input(self):
        self.entries[package.PREFIX + 'Info.plist'] = plistlib.dumps(self.info)
        self.entries[package.PREFIX + 'retroarch-lab-build.json'] = json.dumps(self.manifest).encode()
        path = self.source / 'RetroArch-Lab-unsigned.ipa'
        with zipfile.ZipFile(path, 'w') as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)
        external = dict(self.manifest, ipa_sha256=package.sha256(path.read_bytes()))
        (self.source / 'build-manifest.json').write_text(json.dumps(external))
        return path

    def test_isolates_identity_without_changing_binaries_or_input(self):
        original = self.write_input()
        before = original.read_bytes()
        ipa = package.package(self.source, self.target)
        manifest = json.loads((self.target / 'build-manifest.json').read_text())
        with zipfile.ZipFile(ipa) as archive:
            package.validate_archive(archive, manifest, isolated=True)
            info = plistlib.loads(archive.read(package.PREFIX + 'Info.plist'))
            self.assertTrue(info['UIFileSharingEnabled'])
            self.assertTrue(info['LSSupportsOpeningDocumentsInPlace'])
            for name, data in self.entries.items():
                if '/Frameworks/' in name or name.endswith('/RetroArch'):
                    self.assertEqual(data, archive.read(name))
        self.assertEqual(original.read_bytes(), before)
        self.assertEqual(manifest['derivative']['input_ipa_sha256'], package.sha256(before))
        self.assertEqual(manifest['ipa_sha256'], package.sha256(ipa.read_bytes()))
        self.assertFalse(manifest['device_tested'])

    def test_rejects_test_copy_hidden_from_files(self):
        self.write_input()
        ipa = package.package(self.source, self.target)
        manifest = json.loads((self.target / 'build-manifest.json').read_text())
        with zipfile.ZipFile(ipa) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        for key in ('UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace'):
            for value in (False, None):
                with self.subTest(key=key, value=value):
                    info = plistlib.loads(entries[package.PREFIX + 'Info.plist'])
                    if value is None:
                        info.pop(key)
                    else:
                        info[key] = value
                    data = io.BytesIO()
                    with zipfile.ZipFile(data, 'w') as broken:
                        for name, content in entries.items():
                            broken.writestr(name, plistlib.dumps(info)
                                            if name == package.PREFIX + 'Info.plist' else content)
                    with zipfile.ZipFile(data) as broken:
                        with self.assertRaisesRegex(ValueError, 'visible in Files'):
                            package.validate_archive(broken, manifest, isolated=True)

    def test_bad_input_checksum_creates_no_test_copy(self):
        path = self.write_input()
        path.write_bytes(path.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'Input IPA checksum'):
            package.package(self.source, self.target)
        self.assertFalse(self.target.exists())

    def test_rejects_changed_core_even_with_updated_ipa_hash(self):
        core = self.manifest['cores'][0]
        self.entries[core['binary_path']] += b'tampered'
        self.write_input()
        with self.assertRaisesRegex(ValueError, 'Core path/checksum'):
            package.package(self.source, self.target)

    def test_rejects_missing_or_extra_core(self):
        for extra in (False, True):
            with self.subTest(extra=extra):
                original = copy.deepcopy(self.entries)
                if extra:
                    self.entries[package.PREFIX + 'Frameworks/unknown.libretro.framework/unknown.libretro'] = macho()
                else:
                    del self.entries[self.manifest['cores'][0]['binary_path']]
                self.write_input()
                with self.assertRaisesRegex(ValueError, 'Framework inventory'):
                    package.package(self.source, self.target)
                self.entries = original

    def test_rejects_wrong_binary_os_platform_and_architecture(self):
        for binary in (macho(minimum=17 << 16), macho(platform=7), macho(cpu=0x1000007)):
            with self.subTest(binary=binary):
                self.entries[package.PREFIX + 'RetroArch'] = binary
                self.write_input()
                with self.assertRaises(ValueError):
                    package.package(self.source, self.target)

    def test_rejects_wrong_identity_and_signed_inputs(self):
        self.info['CFBundleIdentifier'] = 'com.example.other'
        self.write_input()
        with self.assertRaisesRegex(ValueError, 'identity'):
            package.package(self.source, self.target)
        self.info['CFBundleIdentifier'] = self.manifest['bundle_id']
        self.entries[package.PREFIX + 'embedded.mobileprovision'] = b'profile'
        self.write_input()
        with self.assertRaisesRegex(ValueError, 'already provisioned'):
            package.package(self.source, self.target)

    def test_reads_universal_arm64_and_rejects_entitlements(self):
        binary = macho()
        fat = struct.pack('>7I', 0xcafebabe, 1, 0x100000c, 0, 28, len(binary), 0) + binary
        self.assertEqual(package.inspect_macho(fat)['minimum_ios'], '26.0.0')
        signed = bytearray(macho())
        struct.pack_into('<2I', signed, 16, 2, 40)
        blob = struct.pack('>5I', 0xfade0cc0, 28, 1, 5, 20) + struct.pack('>2I', 0xfade7171, 8)
        signed += struct.pack('<4I', 0x1d, 16, 72, len(blob)) + blob
        with self.assertRaisesRegex(ValueError, 'carries entitlements'):
            package.inspect_macho(signed)

    def test_refuses_to_overwrite_an_existing_destination(self):
        self.write_input()
        self.target.mkdir()
        marker = self.target / 'keep'
        marker.write_text('existing test evidence')
        with self.assertRaises(FileExistsError):
            package.package(self.source, self.target)
        self.assertEqual(marker.read_text(), 'existing test evidence')


if __name__ == '__main__':
    unittest.main()
