import unittest
from verify import REQUIRED, validate


class ArtifactValidation(unittest.TestCase):
    def setUp(self):
        self.report = dict(
            architectures='arm64\n',
            build_version='      platform IOS\n         minos 17.4\n',
            symbols='\n'.join('_' + name for name in REQUIRED),
            dependencies='core:\n\t@rpath/armsx2_libretro.dylib (compatibility version 0.0.0)\n'
                         '\t/usr/lib/libc++.1.dylib (compatibility version 1.0.0)\n'
                         '\t/System/Library/Frameworks/Metal.framework/Metal (compatibility version 1.0.0)\n')

    def test_accepts_ios_system_dependencies(self):
        self.assertEqual(len(validate(**self.report)), 3)

    def test_rejects_other_architecture(self):
        self.report['architectures'] = 'arm64 x86_64'
        with self.assertRaises(ValueError):
            validate(**self.report)

    def test_rejects_simulator_and_macos(self):
        for platform in ['IOSSIMULATOR', 'MACOS', '2', '']:
            with self.subTest(platform=platform):
                self.report['build_version'] = 'platform ' + platform + '\nminos 17.4\n'
                with self.assertRaises(ValueError):
                    validate(**self.report)

    def test_rejects_wrong_deployment(self):
        self.report['build_version'] = 'platform IOS\nminos 18.0\n'
        with self.assertRaises(ValueError):
            validate(**self.report)

    def test_rejects_missing_entry_point(self):
        self.report['symbols'] = self.report['symbols'].replace('_retro_load_game\n', '')
        # Split explicitly because set order can place the symbol last.
        self.report['symbols'] = '\n'.join(s for s in self.report['symbols'].splitlines()
                                           if s != '_retro_load_game')
        with self.assertRaises(ValueError):
            validate(**self.report)

    def test_rejects_symbol_leak(self):
        self.report['symbols'] += '\n_internal_vm_symbol'
        with self.assertRaises(ValueError):
            validate(**self.report)

    def test_rejects_external_dynamic_library(self):
        for path in ['@rpath/libSDL3.dylib', '/opt/homebrew/lib/libpng.dylib']:
            with self.subTest(path=path):
                report = dict(self.report)
                report['dependencies'] += '\t' + path + ' (compatibility version 1.0.0)\n'
                with self.assertRaises(ValueError):
                    validate(**report)


if __name__ == '__main__':
    unittest.main()
