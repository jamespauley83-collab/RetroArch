"""Exercise development package inputs without signing or touching a device."""
from datetime import datetime, timedelta
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

spec = importlib.util.spec_from_file_location(
    "package_development", Path(__file__).with_name("package_development.py"))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class DevelopmentPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.resource = self.root / "resources.app"
        self.development = self.root / "development.app"
        self.host = self.root / "host.app"
        self.output = self.root / "output"
        for app in (self.resource, self.development, self.host):
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": package.IDENTITY,
                "CFBundleExecutable": "RetroArch",
                "CFBundleShortVersionString": "1.22.2",
            }))
        self.entries = {
            "info/" + name.replace(".", "_") + "_libretro.info":
                'corename = "' + name + '"\n' for name in package.CORES
        }
        self.write_assets()
        self.binaries = {}
        for name in package.CORES:
            binary = self.development / "Frameworks" / (name + ".libretro.framework") / (name + ".libretro")
            binary.parent.mkdir(parents=True)
            binary.write_bytes(("fixture " + name).encode())
            self.binaries[name] = binary
        self.fonts = self.root / "fonts.zip"
        self.write_fonts({"pcsx2/resources/fonts/Roboto-Regular.ttf": b"font fixture"})
        (self.host / "RetroArch").write_bytes(
            b"RALabPS3Controller Enable PS3 JIT "
            b"PS3 executable-memory self-test returned an invalid result.")
        self.core = self.root / "native-core"
        self.core.write_bytes(package.LLVM.encode() + b'"jit":"sealed-arena"')
        (self.development / "embedded.mobileprovision").write_bytes(b"profile fixture")
        self.entitlements = {
            "application-identifier": "TEAM." + package.IDENTITY,
            "get-task-allow": True,
            "com.apple.developer.kernel.extended-virtual-addressing": True,
            "com.apple.developer.kernel.increased-memory-limit": True,
        }

    def write_assets(self, extra=None):
        with zipfile.ZipFile(self.resource / "assets.zip", "w") as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)
            if extra:
                archive.writestr(*extra)

    def write_fonts(self, entries):
        with zipfile.ZipFile(self.fonts, "w") as archive:
            for name, data in entries.items():
                archive.writestr(name, data)

    def command(self, *args):
        args = tuple(str(arg) for arg in args)
        if args[:3] == ("xcrun", "lipo", "-archs"):
            return b"arm64\n"
        if args[:3] == ("security", "cms", "-D"):
            return plistlib.dumps({"ExpirationDate": datetime.utcnow() + timedelta(days=10),
                                   "Entitlements": self.entitlements})
        if args[:2] == ("codesign", "-d"):
            return plistlib.dumps(self.entitlements)
        if args[:3] == ("xcrun", "otool", "-D"):
            return b"fixture:\n@rpath/libRPCS3Core.dylib\n"
        if args[:2] in (("codesign", "--force"), ("codesign", "--verify")):
            return b""
        raise AssertionError("Unexpected external command: " + repr(args))

    def arguments(self):
        return ["package_development.py", "--resource-app", str(self.resource),
                "--development-app", str(self.development), "--host-app", str(self.host),
                "--native-core", str(self.core), "--output", str(self.output),
                "--armsx2-system-files", str(self.fonts), "--build", "19",
                "--signing-identity", "test identity"]

    def test_packages_font_sidecar_and_records_exact_inputs(self):
        originals = {path: path.read_bytes() for app in (self.resource, self.development, self.host)
                     for path in app.rglob("*") if path.is_file()}
        before_fonts = self.fonts.read_bytes()
        with mock.patch.object(sys, "argv", self.arguments()), mock.patch.object(package, "run", side_effect=self.command):
            package.main()
        record = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual((self.output / package.ARMSX2_SYSTEM_FILES).read_bytes(), before_fonts)
        self.assertEqual(record["armsx2_system_files"]["sha256"], hashlib.sha256(before_fonts).hexdigest())
        self.assertTrue(record["armsx2_system_files"]["extraction_required"])
        self.assertFalse(record["armsx2_system_files"]["contains_bios_or_saves"])
        target = self.output / "Payload/RetroArch.app"
        self.assertFalse((target / "pcsx2").exists())
        self.assertEqual(set(record["libretro_inputs"]), set(package.CORES))
        for name, binary in self.binaries.items():
            self.assertEqual(record["libretro_inputs"][name]["input_sha256"], package.digest(binary))
            packaged = target / "Frameworks" / binary.parent.name / binary.name
            self.assertEqual(packaged.read_bytes(), binary.read_bytes())
        self.assertEqual({path: path.read_bytes() for path in originals}, originals)
        self.assertEqual(self.fonts.read_bytes(), before_fonts)

    def test_rejects_empty_or_missing_executable_for_each_core(self):
        for name, binary in self.binaries.items():
            original = binary.read_bytes()
            for empty in (True, False):
                with self.subTest(core=name, empty=empty):
                    if empty:
                        binary.write_bytes(b"")
                    else:
                        binary.unlink()
                    with self.assertRaisesRegex(ValueError, "core executable: " + name):
                        package.validate_libretro_inputs(self.resource, self.development)
                    binary.write_bytes(original)

    def test_rejects_missing_empty_or_duplicate_core_info(self):
        for name in list(self.entries):
            original = self.entries.pop(name)
            self.write_assets()
            with self.subTest(path=name), self.assertRaisesRegex(ValueError, "core metadata"):
                package.validate_libretro_inputs(self.resource, self.development)
            self.entries[name] = original
        name = "info/armsx2_libretro.info"
        self.entries[name] = " \n"
        self.write_assets()
        with self.assertRaisesRegex(ValueError, "core metadata"):
            package.validate_libretro_inputs(self.resource, self.development)
        self.entries[name] = "ARMSX2"
        with self.assertWarns(UserWarning):
            self.write_assets((name, "duplicate"))
        with self.assertRaisesRegex(ValueError, "core metadata"):
            package.validate_libretro_inputs(self.resource, self.development)

    def test_rejects_bios_saves_unrelated_fonts_and_traversal(self):
        required = "pcsx2/resources/fonts/Roboto-Regular.ttf"
        for name in ("pcsx2/bios/scph39001.bin", "pcsx2/memcards/Mcd001.ps2",
                     "pcsx2/sstates/save.p2s", "Play Data Files/mcd0", "game.iso",
                     "pcsx2/resources/fonts/unknown.ttf", "../Roboto-Regular.ttf",
                     "/pcsx2/resources/fonts/Roboto-Regular.ttf"):
            with self.subTest(path=name):
                self.write_fonts({required: b"font", name: b"do not copy"})
                with self.assertRaisesRegex(ValueError, "only the pinned fonts"):
                    package.validate_armsx2_system_files(self.fonts)

    def test_rejects_missing_empty_duplicate_and_symlink_fonts(self):
        required = "pcsx2/resources/fonts/Roboto-Regular.ttf"
        for entries in ({}, {required: b""}):
            self.write_fonts(entries)
            with self.assertRaisesRegex(ValueError, "missing Roboto-Regular"):
                package.validate_armsx2_system_files(self.fonts)
        self.write_fonts({required: b"font"})
        with zipfile.ZipFile(self.fonts, "a") as archive, self.assertWarns(UserWarning):
            archive.writestr(required, b"duplicate")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            package.validate_armsx2_system_files(self.fonts)
        with zipfile.ZipFile(self.fonts, "w") as archive:
            link = zipfile.ZipInfo(required)
            link.create_system = 3
            link.external_attr = (0o120777 << 16)
            archive.writestr(link, "/private/source")
        with self.assertRaisesRegex(ValueError, "only the pinned fonts"):
            package.validate_armsx2_system_files(self.fonts)

    def test_accepts_pinned_fonts_licenses_and_directory_entries(self):
        entries = {"pcsx2/resources/fonts/" + name: b"resource" for name in package.ARMSX2_FONT_FILES}
        entries.update({name: b"" for name in ("pcsx2/", "pcsx2/resources/", "pcsx2/resources/fonts/")})
        self.write_fonts(entries)
        record = package.validate_armsx2_system_files(self.fonts)
        self.assertEqual(record["sha256"], package.digest(self.fonts))

    def test_invalid_resources_fail_before_commands_or_output(self):
        self.write_fonts({"pcsx2/bios/scph39001.bin": b"BIOS fixture"})
        with mock.patch.object(sys, "argv", self.arguments()), mock.patch.object(package, "run") as commands:
            with self.assertRaisesRegex(ValueError, "only the pinned fonts"):
                package.main()
        commands.assert_not_called()
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
