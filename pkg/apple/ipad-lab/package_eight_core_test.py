#!/usr/bin/env python3
"""Make an isolated unsigned test copy of a verified eight-core Lab artifact."""
import argparse
import copy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import struct
import zipfile

PREFIX = 'Payload/RetroArch.app/'
BUNDLE_ID = 'com.jamespauley.retroarchlab.eightcoretest'
DISPLAY_NAME = 'RetroArch Lab 8 Test'
SCHEME = 'retroarchlab8test'
HELPER = PREFIX + 'PlugIns/RALabJITHelper.appex/'
JIT_FRAMEWORK = PREFIX + 'Frameworks/StikJIT.framework/'
STIKJIT_COMMIT = '32287268fa5824f9edce4cb359f5833ce0cf7b00'
CORES = {'fceumm', 'snes9x2010', 'opera', 'dolphin', 'play',
         'mednafen_saturn', 'yabause', 'armsx2'}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def inspect_macho(data):
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        if count != 1:
            raise ValueError('Expected one ARM64 slice.')
        cpu, subtype, offset, size, align = struct.unpack_from('>5I', data, 8)
        if offset + size > len(data) or cpu != 0x100000c:
            raise ValueError('Invalid ARM64 universal binary.')
        data = data[offset:offset + size]
    if len(data) < 32 or data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a 64-bit little-endian Mach-O.')
    magic, cpu, subtype, kind, count, size, flags, reserved = struct.unpack_from('<8I', data)
    if cpu != 0x100000c or 32 + size > len(data):
        raise ValueError('Expected a complete ARM64 Mach-O.')
    versions, dependencies, entitlements = [], [], []
    position = 32
    for unused in range(count):
        command, length = struct.unpack_from('<2I', data, position)
        if length < 8 or position + length > 32 + size:
            raise ValueError('Invalid Mach-O load command.')
        if command == 0x32:
            platform, minimum = struct.unpack_from('<2I', data, position + 8)
            versions.append((platform, minimum))
        elif command == 0x25:
            versions.append((2, struct.unpack_from('<I', data, position + 8)[0]))
        elif command in (0xc, 0x80000018, 0x8000001f):
            start = struct.unpack_from('<I', data, position + 8)[0]
            dependencies.append(data[position + start:position + length].split(b'\0')[0].decode())
        elif command == 0x1d:
            offset, length_blob = struct.unpack_from('<2I', data, position + 8)
            blob = data[offset:offset + length_blob]
            marker, total, slots = struct.unpack_from('>3I', blob)
            if marker != 0xfade0cc0 or total > len(blob):
                raise ValueError('Invalid embedded signature container.')
            for index in range(slots):
                slot, offset_slot = struct.unpack_from('>2I', blob, 12 + 8 * index)
                if slot in (5, 7):
                    entitlements.append(slot)
        position += length
    if position != 32 + size or len(versions) != 1 or versions[0][0] != 2:
        raise ValueError('Expected one iPhoneOS deployment command.')
    if entitlements:
        raise ValueError('Input executable carries entitlements; use the unsigned CI artifact.')
    minimum = versions[0][1]
    return {'architecture': 'arm64', 'platform': 'iOS',
            'minimum_ios': '%d.%d.%d' % (minimum >> 16, (minimum >> 8) & 255, minimum & 255),
            'dependencies': dependencies, 'entitlement_slots': entitlements}


def validate_archive(archive, manifest, isolated=False):
    names = archive.namelist()
    if len(names) != len(set(names)):
        raise ValueError('Duplicate archive entries.')
    if any((name != 'Payload/' and not name.startswith(PREFIX))
           or '..' in PurePosixPath(name).parts for name in names):
        raise ValueError('Unexpected archive paths.')
    if archive.testzip() is not None:
        raise ValueError('Archive CRC failure.')
    if any(name.endswith('embedded.mobileprovision') for name in names):
        raise ValueError('Input is already provisioned; use the unsigned CI artifact.')
    info = plistlib.loads(archive.read(PREFIX + 'Info.plist'))
    identity = BUNDLE_ID if isolated else 'com.jamespauley.retroarchlab'
    if info.get('CFBundleIdentifier') != identity or manifest.get('bundle_id') != identity:
        raise ValueError('Unexpected app identity.')
    if info.get('MinimumOSVersion') != '26.0' or manifest.get('minimum_ios') != '26.0':
        raise ValueError('Expected the iOS 26.0 eight-core candidate.')
    if manifest.get('device_signed') is not False or manifest.get('device_tested') is not False:
        raise ValueError('Expected an unsigned, device-untested candidate.')
    embedded = json.loads(archive.read(PREFIX + 'retroarch-lab-build.json'))
    if embedded != {key: value for key, value in manifest.items() if key != 'ipa_sha256'}:
        raise ValueError('Embedded and external manifests differ.')
    if len(manifest['cores']) != 8 or {core['name'] for core in manifest['cores']} != CORES:
        raise ValueError('Expected exactly eight named cores.')
    expected = {core['name'].replace('_', '.') + '.libretro.framework' for core in manifest['cores']}
    expected.add('MoltenVK.framework')
    jit = manifest.get('stikjit')
    if jit:
        expected.add('StikJIT.framework')
    actual = {name[len(PREFIX + 'Frameworks/'):].split('/')[0] for name in names
              if name.startswith(PREFIX + 'Frameworks/') and name != PREFIX + 'Frameworks/'}
    if actual != expected:
        raise ValueError('Framework inventory differs from the manifest.')
    binaries = {PREFIX + 'RetroArch': archive.read(PREFIX + 'RetroArch')}
    with zipfile.ZipFile(io.BytesIO(archive.read(PREFIX + 'assets.zip'))) as assets:
        for core in manifest['cores']:
            framework = core['name'].replace('_', '.') + '.libretro'
            path = PREFIX + 'Frameworks/' + framework + '.framework/' + framework
            if core['binary_path'] != path or sha256(archive.read(path)) != core['sha256']:
                raise ValueError('Core path/checksum mismatch: ' + core['name'])
            if 'info/' + core['name'] + '_libretro.info' not in assets.namelist():
                raise ValueError('Missing core metadata: ' + core['name'])
            binaries[path] = archive.read(path)
    reports = {name: inspect_macho(data) for name, data in binaries.items()}
    for name, report in reports.items():
        if report['minimum_ios'] != '26.0.0':
            raise ValueError('Binary deployment differs from iOS 26.0: ' + name)
        for dependency in report['dependencies']:
            if dependency.startswith(('/System/Library/Frameworks/', '/usr/lib/')):
                continue
            if name == PREFIX + 'RetroArch' and dependency == '@rpath/MoltenVK.framework/MoltenVK':
                continue
            raise ValueError('Unresolved dynamic dependency: ' + dependency)
    molten = PREFIX + 'Frameworks/MoltenVK.framework/MoltenVK'
    reports[molten] = inspect_macho(archive.read(molten))
    if jit:
        if jit.get('commit') != STIKJIT_COMMIT:
            raise ValueError('Unpinned StikJIT source.')
        helper_info = plistlib.loads(archive.read(HELPER + 'Info.plist'))
        if (helper_info.get('CFBundleIdentifier') != identity + '.JITHelper'
                or jit.get('helper_bundle_id') != identity + '.JITHelper'
                or helper_info.get('CFBundleExecutable') != 'RALabJITHelper'):
            raise ValueError('JIT helper identity differs from the host.')
        extension = helper_info.get('NSExtension', {})
        if (extension.get('NSExtensionPrincipalClass') != 'RALabJITHelper'
                or extension.get('NSExtensionPointIdentifier') != 'com.apple.ar.viewer'):
            raise ValueError('Unexpected JIT helper entry point.')
        for key in ('NSUbiquitousContainers', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations'):
            if key in helper_info:
                raise ValueError('Helper must not declare cloud or shared documents.')
        for path, key in ((HELPER + 'RALabJITHelper', 'helper_sha256'),
                          (JIT_FRAMEWORK + 'StikJIT', 'framework_sha256')):
            data = archive.read(path)
            if sha256(data) != jit.get(key):
                raise ValueError('JIT binary checksum mismatch.')
            reports[path] = inspect_macho(data)
            for dependency in reports[path]['dependencies']:
                if dependency.startswith(('/System/Library/Frameworks/', '/usr/lib/')):
                    continue
                if path == HELPER + 'RALabJITHelper' and dependency == '@rpath/StikJIT.framework/StikJIT':
                    continue
                raise ValueError('Unresolved JIT dependency: ' + dependency)
        if reports[HELPER + 'RALabJITHelper']['minimum_ios'] != '26.0.0':
            raise ValueError('Helper must target iOS 26.')
        # Nothing else may add executable code inside either permitted bundle.
        for name in names:
            if name.startswith((HELPER, JIT_FRAMEWORK)) and name not in reports:
                data = archive.read(name)
                if data[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe') or '/Frameworks/' in name[len(HELPER):] or name.endswith('.dylib'):
                    raise ValueError('Unexpected nested JIT executable.')
    if isolated:
        if (info.get('ALTBundleIdentifier') != BUNDLE_ID or info.get('CFBundleDisplayName') != DISPLAY_NAME
                or info.get('CFBundleURLTypes') != [{'CFBundleURLName': BUNDLE_ID, 'CFBundleURLSchemes': [SCHEME]}]):
            raise ValueError('Test app identifiers are not isolated.')
        if any(key in info for key in ('NSUbiquitousContainers', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations')):
            raise ValueError('Test app declares cloud or shared document registrations.')
        if (info.get('UIFileSharingEnabled') is not True
                or info.get('LSSupportsOpeningDocumentsInPlace') is not True):
            raise ValueError('Test app Documents must be visible in Files.')
        if any(name.startswith(PREFIX + 'PlugIns/') and name != PREFIX + 'PlugIns/'
               and not (jit and name.startswith(HELPER)) for name in names):
            raise ValueError('Test copy must not carry the working app widget.')
        if manifest.get('icloud_drive') != {'enabled': False, 'requires_no_cloud_entitlements': True}:
            raise ValueError('Test manifest must prohibit cloud entitlements.')
    return reports


def package(artifacts, destination):
    original = artifacts / 'RetroArch-Lab-unsigned.ipa'
    manifest = json.loads((artifacts / 'build-manifest.json').read_text())
    if sha256(original.read_bytes()) != manifest.get('ipa_sha256'):
        raise ValueError('Input IPA checksum mismatch.')
    with zipfile.ZipFile(original) as archive:
        reports = validate_archive(archive, manifest)
        for core in manifest['cores']:
            if 'system_files' in core:
                support = core['system_files']
                if Path(support['file']).name != support['file'] or sha256((artifacts / support['file']).read_bytes()) != support['sha256']:
                    raise ValueError('System resource checksum mismatch.')
        destination.mkdir(parents=True, exist_ok=False)
        derived = copy.deepcopy(manifest)
        derived.pop('ipa_sha256')
        derived.update(bundle_id=BUNDLE_ID, display_name=DISPLAY_NAME,
                       icloud_drive={'enabled': False, 'requires_no_cloud_entitlements': True},
                       derivative={'input_ipa_sha256': manifest['ipa_sha256'],
                                   'packager_sha256': sha256(Path(__file__).read_bytes()),
                                   'runtime_binaries_unchanged': True, 'widget_removed': True})
        if derived.get('stikjit'):
            derived['stikjit']['helper_bundle_id'] = BUNDLE_ID + '.JITHelper'
        info = plistlib.loads(archive.read(PREFIX + 'Info.plist'))
        info.update(CFBundleIdentifier=BUNDLE_ID, ALTBundleIdentifier=BUNDLE_ID,
                    CFBundleDisplayName=DISPLAY_NAME, CFBundleName=DISPLAY_NAME,
                    CFBundleURLTypes=[{'CFBundleURLName': BUNDLE_ID, 'CFBundleURLSchemes': [SCHEME]}],
                    UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
        for key in ('NSUbiquitousContainers', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'ALTDeviceID'):
            info.pop(key, None)
        replacements = {PREFIX + 'Info.plist': plistlib.dumps(info),
                        PREFIX + 'retroarch-lab-build.json': (json.dumps(derived, indent=2) + '\n').encode()}
        if derived.get('stikjit'):
            helper_info = plistlib.loads(archive.read(HELPER + 'Info.plist'))
            helper_info['CFBundleIdentifier'] = BUNDLE_ID + '.JITHelper'
            replacements[HELPER + 'Info.plist'] = plistlib.dumps(helper_info)
        ipa = destination / 'RetroArch-Lab-8-Test-unsigned.ipa'
        with zipfile.ZipFile(ipa, 'w') as output:
            for entry in archive.infolist():
                if entry.filename.startswith(PREFIX + '_CodeSignature/'):
                    continue
                if entry.filename.startswith(PREFIX + 'PlugIns/'):
                    if not (derived.get('stikjit') and entry.filename.startswith(HELPER)):
                        continue
                output.writestr(copy.copy(entry), replacements.get(entry.filename, archive.read(entry.filename)))
        with zipfile.ZipFile(ipa) as output:
            validate_archive(output, derived, isolated=True)
            for entry in output.namelist():
                if entry not in replacements and output.read(entry) != archive.read(entry):
                    raise ValueError('Unexpected change while repackaging: ' + entry)
    derived['ipa_sha256'] = sha256(ipa.read_bytes())
    (destination / 'build-manifest.json').write_text(json.dumps(derived, indent=2) + '\n')
    (destination / 'input-build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (destination / 'binary-inspection.json').write_text(json.dumps(reports, indent=2) + '\n')
    (destination / 'Test-No-Cloud.entitlements').write_bytes(plistlib.dumps({}))
    for core in manifest['cores']:
        if 'system_files' in core:
            shutil.copy2(artifacts / core['system_files']['file'], destination)
    guide = Path(__file__).with_name('EIGHT-CORE-DEVICE-TEST.md')
    shutil.copy2(guide, destination)
    print('Isolated unsigned test copy:', ipa)
    print('SHA-256:', derived['ipa_sha256'])
    print('Signing and all physical-device tests remain pending.')
    return ipa


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifacts', type=Path, help='Directory containing the original IPA and manifest')
    parser.add_argument('destination', type=Path, help='New directory for the isolated test kit')
    args = parser.parse_args()
    package(args.artifacts, args.destination)


if __name__ == '__main__':
    main()
