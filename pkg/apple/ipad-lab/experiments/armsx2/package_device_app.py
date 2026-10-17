"""Package the experimental ARMSX2 core in a separate, unsigned RetroArch app."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
import build as lab

BUNDLE_ID = 'com.jamespauley.retroarchlab.ps2test'
DISPLAY_NAME = 'RetroArch PS2 Test'
MINIMUM_IOS = '26.0'
CORE_INFO = '''display_name = "Sony - PlayStation 2 (ARMSX2 Lab Test)"
corename = "ARMSX2 Lab Test"
systemname = "PlayStation 2"
systemid = "ps2"
manufacturer = "Sony"
supported_extensions = "elf|iso|ciso|chd|cso|zso|bin|mdf|nrg|dump|gz|img|irx|m3u"
license = "GPLv3"
permissions = "dynarec"
supports_no_game = "true"
firmware_count = 0
notes = "Experimental device test; requires iOS 26+. Supply your PS2 BIOS under system/pcsx2/bios. Enable JIT before starting."
'''


def validate_core_manifest(manifest, binary):
    if manifest.get('stage') != 'device-test' or manifest.get('gameplay_enabled') is not True:
        raise ValueError('Only the explicit device-test core may enter this test app.')
    if manifest.get('architecture') != 'arm64' or manifest.get('platform') != 'iOS':
        raise ValueError('Expected an ARM64 iPhoneOS core.')
    if manifest.get('minimum_ios') != MINIMUM_IOS:
        raise ValueError('ARMSX2 core requires an iOS 26.0 deployment target.')
    if hashlib.sha256(binary.read_bytes()).hexdigest() != manifest.get('sha256'):
        raise ValueError('Core checksum differs from its verified manifest.')


def customize_test_plist(path):
    info = plistlib.loads(path.read_bytes())
    info['CFBundleDisplayName'] = DISPLAY_NAME
    info['CFBundleName'] = DISPLAY_NAME
    info['CFBundleURLTypes'] = [{'CFBundleURLName': BUNDLE_ID,
                               'CFBundleURLSchemes': ['retroarchps2test']}]
    path.write_bytes(plistlib.dumps(info))


def verify_test_info(info):
    version = info.get('MinimumOSVersion')
    if not isinstance(version, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', version):
        raise ValueError('Test app must declare MinimumOSVersion of iOS 26.0 or later.')
    parts = tuple(int(part) for part in version.split('.'))
    if parts + (0,) * (3 - len(parts)) < (26, 0, 0):
        raise ValueError('Test app requires iOS 26.0 or later for its frontend JIT memory mode.')
    if info.get('NSUbiquitousContainers'):
        raise ValueError('Test app must not declare iCloud containers.')
    if info.get('CFBundleIdentifier') != BUNDLE_ID or info.get('CFBundleDisplayName') != DISPLAY_NAME:
        raise ValueError('Test app identity is not isolated.')
    if info.get('CFBundleURLTypes') != [{'CFBundleURLName': BUNDLE_ID,
                                       'CFBundleURLSchemes': ['retroarchps2test']}]:
        raise ValueError('Test app URL scheme is not isolated.')

def verify_isolation(app):
    verify_test_info(plistlib.loads((app / 'Info.plist').read_bytes()))
    cores = sorted(p.name for p in (app / 'Frameworks').glob('*.libretro.framework'))
    if cores != ['armsx2.libretro.framework']:
        raise ValueError('Test app must contain only the ARMSX2 core.')


def verify_packaged_app(ipa):
    with zipfile.ZipFile(ipa) as archive:
        prefix = 'Payload/RetroArch.app/'
        verify_test_info(plistlib.loads(archive.read(prefix + 'Info.plist')))
        cores = {name[len(prefix):].split('/')[1] for name in archive.namelist()
                 if name.startswith(prefix + 'Frameworks/')
                 and len(name[len(prefix):].split('/')) > 2
                 and name[len(prefix):].split('/')[1].endswith('.libretro.framework')}
        if cores != {'armsx2.libretro.framework'}:
            raise ValueError('Packaged test app must contain only the ARMSX2 core.')


def main():
    root = Path(lab.output('git', '-C', HERE, 'rev-parse', '--show-toplevel'))
    revision = lab.output('git', '-C', root, 'rev-parse', 'HEAD')
    work = root / '.armsx2-prototype'
    artifacts = work / 'artifacts'
    binary = artifacts / 'armsx2_libretro.dylib'
    core_manifest = json.loads((artifacts / 'manifest.json').read_text())
    validate_core_manifest(core_manifest, binary)
    if core_manifest['lab_commit'] != revision:
        raise ValueError('Core and app must use the same Lab revision.')
    source = work / 'app-source'
    source.mkdir()
    archive = work / 'retroarch-source.tar'
    lab.run('git', '-C', root, 'archive', '--format=tar', '--output=' + str(archive), 'HEAD')
    lab.run('tar', '-xf', archive, '-C', source)
    archive.unlink()
    (source / '.git_version.h').write_text('#define GIT_VERSION ' + revision[:8] + '\n')
    apple = source / 'pkg/apple'
    customize_test_plist(apple / 'iOS/Info.plist')
    modules = apple / 'iOS/modules'
    modules.mkdir(exist_ok=True)
    if list(modules.glob('*.dylib')):
        raise ValueError('Unexpected prebuilt cores in source tree.')
    shutil.copy2(binary, modules / 'armsx2_libretro_ios.dylib')
    with zipfile.ZipFile(apple / 'assets.zip', 'a') as assets:
        assets.writestr('info/armsx2_libretro.info', CORE_INFO)
    entitlements = work / 'PS2-Test.entitlements'
    entitlements.write_bytes(plistlib.dumps({}))
    with (work / 'app-build.log').open('w') as log:
        subprocess.run([
            'xcodebuild', '-project', str(apple / 'RetroArch_iOS13.xcodeproj'),
            '-scheme', 'RetroArch iOS Release', '-configuration', 'Release',
            '-destination', 'generic/platform=iOS', '-derivedDataPath', str(work / 'AppDerivedData'),
            '-xcconfig', str(apple / 'GitHubCI.xcconfig'),
            'IOS_BUNDLE_IDENTIFIER=' + BUNDLE_ID,
            'IOS_CODE_SIGN_ENTITLEMENTS=' + str(entitlements),
            'RA_IPHONEOS_DEPLOYMENT_TARGET=' + MINIMUM_IOS,
            'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=NO', 'DEVELOPMENT_TEAM=',
            'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
            'CODE_SIGN_IDENTITY=-', 'PROVISIONING_PROFILE_SPECIFIER=', 'APPSTORE_BUILD=', 'build',
        ], cwd=apple, stdout=log, stderr=subprocess.STDOUT, check=True)
    app = work / 'AppDerivedData/Build/Products/Release-iphoneos/RetroArch.app'
    lock = {'bundle_id': BUNDLE_ID, 'display_name': DISPLAY_NAME, 'cores': [{'name': 'armsx2'}]}
    lab.validate_app(app, lock)
    verify_isolation(app)
    lab.run('xcrun', 'lipo', app / 'RetroArch', '-verify_arch', 'arm64')
    manifest = {
        'retroarch_commit': revision, 'bundle_id': BUNDLE_ID, 'display_name': DISPLAY_NAME,
        'stage': 'device-test', 'gameplay_enabled': True, 'device_signed': False,
        'device_tested': False, 'icloud_drive': {'enabled': False},
        'minimum_ios': plistlib.loads((app / 'Info.plist').read_bytes())['MinimumOSVersion'],
        'cores': [{'name': 'armsx2', 'upstream_commit': core_manifest['upstream_commit'],
                   'patches': core_manifest['patches']}],
    }
    ipa = lab.package_app(app, work, artifacts, manifest)
    verify_packaged_app(ipa)
    ipa.rename(artifacts / 'RetroArch-PS2-Test-unsigned.ipa')
    shutil.copy2(HERE / 'DEVICE-TEST.md', artifacts)
    shutil.copy2(source / 'COPYING', artifacts / 'RetroArch-COPYING')
    lab.run('tar', '-czf', artifacts / 'retroarch-test-app-source.tar.gz', '-C', source, '.')
    with zipfile.ZipFile(artifacts / 'ARMSX2-system-files.zip', 'w', zipfile.ZIP_DEFLATED) as assets:
        fonts = work / 'source/bin/resources/fonts'
        if not (fonts / 'Roboto-Regular.ttf').is_file():
            raise ValueError('Required font resources missing.')
        for path in sorted(fonts.iterdir()):
            if path.is_file():
                assets.write(path, 'pcsx2/resources/fonts/' + path.name)
    print('Isolated unsigned device-test IPA packaged; device validation remains pending.')


if __name__ == '__main__':
    main()
