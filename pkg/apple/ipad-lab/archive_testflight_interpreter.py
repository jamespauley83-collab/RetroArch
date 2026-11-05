#!/usr/bin/env python3
"""Archive the native Lab with verified, debugger-free emulator backends."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess


CORES = {
    'armsx2.libretro.framework': 'EE/IOP/VU0/VU1 interpreters',
    'dolphin.libretro.framework': 'PowerPC interpreter, DSP HLE, software vertex loader',
    'fceumm.libretro.framework': 'standard',
    'mednafen.saturn.libretro.framework': 'standard',
    'opera.libretro.framework': 'standard',
    'snes9x2010.libretro.framework': 'standard',
    'yabause.libretro.framework': 'standard',
    'RPCS3Core.framework': 'PPU/SPU static interpreters',
}
FORBIDDEN_IMPORTS = (
    '_SecTaskCreateFromSelf', '_SecTaskCopyValueForEntitlement', '_csops', '_ptrace',
)
FORBIDDEN_LOOKUPS = (b'mach_memory_entry_ownership',)


def run(args):
    subprocess.run([str(arg) for arg in args], check=True)


def digest(path):
    with path.open('rb') as stream:
        hasher = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


def verify_binary(binary):
    imports = subprocess.check_output(['nm', '-u', str(binary)], text=True)
    matches = [item for item in FORBIDDEN_IMPORTS if item in imports]
    content = binary.read_bytes()
    matches.extend(item.decode() for item in FORBIDDEN_LOOKUPS if item in content)
    if matches:
        raise RuntimeError('Distribution contains private debugger helpers: '
                           + str(binary) + ': ' + ', '.join(matches))
    archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    if archs != ['arm64']:
        raise RuntimeError('Expected an arm64 iOS binary: ' + str(binary))


def framework_binary(framework):
    info = plistlib.loads((framework / 'Info.plist').read_bytes())
    return framework / info['CFBundleExecutable']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-app', type=Path, required=True)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--armsx2', type=Path, required=True)
    parser.add_argument('--rpcs3', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--build', type=int, required=True)
    parser.add_argument('--signing-identity', required=True)
    args = parser.parse_args()
    if args.archive.exists():
        parser.error('Archive already exists; choose a new output path.')
    if args.build <= 10:
        parser.error('The interpreter release must use a new build number.')

    base_info = plistlib.loads((args.base_app / 'Info.plist').read_bytes())
    if base_info['CFBundleIdentifier'] != 'com.jamespauley.retroarchlab.ps3bridge':
        parser.error('Use the preserved full RetroArch Lab app as the resource base.')
    host_symbols = subprocess.check_output(['nm', str(args.host)], text=True)
    if 'OBJC_CLASS_$_RALabJIT' in host_symbols:
        parser.error('The TestFlight host must exclude the debugger activation class.')
    if 'OBJC_CLASS_$_RALabPS3Controller' not in host_symbols:
        parser.error('The native PS3 library is missing from the host.')
    host_data = args.host.read_bytes()
    for marker in [b'Hide routine popups', b'RPCS3_IOS_JITLESS',
                   b'RPCS3Core.framework/RPCS3Core']:
        if marker not in host_data:
            parser.error('The native library, Game Mode or PS3 interpreter wiring is missing.')
    if b'ARMSX2 interpreter mode:' not in args.armsx2.read_bytes():
        parser.error('ARMSX2 must be built with RETROARCH_LAB_ARMSX2_NO_JIT.')
    if b'RPCS3 interpreter-only distribution' not in args.rpcs3.read_bytes():
        parser.error('RPCS3 must be built with RPCS3_IOS_JITLESS_ONLY.')
    for binary in [args.host, args.armsx2, args.rpcs3]:
        verify_binary(binary)

    app = args.archive / 'Products/Applications/RetroArch.app'
    app.parent.mkdir(parents=True)
    run(['ditto', '--noextattr', '--norsrc', args.base_app, app])
    shutil.copyfile(args.host, app / 'RetroArch')
    (app / 'RetroArch').chmod(0o755)
    frameworks = app / 'Frameworks'
    # PS2 is provided by the ARMSX2 interpreter. The alternate Play! backend
    # requires generated native code and is not offered by this release.
    shutil.rmtree(frameworks / 'play.libretro.framework', ignore_errors=True)
    (frameworks / 'libRPCS3Core.dylib').unlink(missing_ok=True)
    ps2 = framework_binary(frameworks / 'armsx2.libretro.framework')
    shutil.copyfile(args.armsx2, ps2)
    ps2.chmod(0o755)
    run(['install_name_tool', '-id', '@rpath/armsx2.libretro.framework/armsx2.libretro', ps2])

    ps3_framework = frameworks / 'RPCS3Core.framework'
    ps3_framework.mkdir()
    ps3 = ps3_framework / 'RPCS3Core'
    shutil.copyfile(args.rpcs3, ps3)
    ps3.chmod(0o755)
    run(['install_name_tool', '-id', '@rpath/RPCS3Core.framework/RPCS3Core', ps3])
    ps3_info = {
        'CFBundleExecutable': 'RPCS3Core', 'CFBundleName': 'RPCS3Core',
        'CFBundleIdentifier': 'com.jamespauley.retroarchlab.core.rpcs3',
        'CFBundleShortVersionString': '0.12', 'CFBundleVersion': str(args.build),
        'CFBundlePackageType': 'FMWK', 'CFBundleInfoDictionaryVersion': '6.0',
        'CFBundleSupportedPlatforms': ['iPhoneOS'], 'MinimumOSVersion': '26.0',
    }
    (ps3_framework / 'Info.plist').write_bytes(plistlib.dumps(ps3_info))

    expected = set(CORES) | {'MoltenVK.framework'}
    if {path.name for path in frameworks.iterdir()} != expected:
        raise RuntimeError('Unexpected or missing framework in the full interpreter package.')
    manifest = {
        'build': args.build, 'bundle_identifier': base_info['CFBundleIdentifier'],
        'version': base_info['CFBundleShortVersionString'],
        'runtime_mode': 'interpreter distribution; no debugger attachment',
        'base_host_sha256': digest(args.base_app / 'RetroArch'),
        'source_host_sha256': digest(args.host),
        'alternate_backends_omitted': {'Play!': 'PS2 uses the ARMSX2 interpreter'},
        'frameworks': {},
    }
    for framework in sorted(frameworks.iterdir()):
        binary = framework_binary(framework)
        verify_binary(binary)
        manifest['frameworks'][framework.name] = {
            'mode': CORES.get(framework.name, 'Vulkan/Metal translation'),
            'unsigned_sha256': digest(binary),
        }
        run(['xattr', '-cr', framework])
        run(['codesign', '--force', '--sign', args.signing_identity, framework])

    info = dict(base_info)
    info['CFBundleVersion'] = str(args.build)
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    support = args.archive / 'SwiftSupport/iphoneos'
    run(['xcrun', 'swift-stdlib-tool', '--copy', '--scan-executable', app / 'RetroArch',
         '--scan-folder', frameworks, '--platform', 'iphoneos', '--destination', frameworks,
         '--unsigned-destination', support.parent, '--sign', args.signing_identity])
    for library in frameworks.glob('*.dylib'):
        if not library.name.startswith('libswift') or not (support / library.name).exists():
            raise RuntimeError('Unsupported standalone library: ' + str(library))
    if support.parent.exists() and not any(p.is_file() for p in support.parent.rglob('*')):
        shutil.rmtree(support.parent)

    entitlements = plistlib.loads(subprocess.check_output(
        ['codesign', '-d', '--entitlements', ':-', str(args.base_app)],
        stderr=subprocess.DEVNULL))
    # Device acceptance can use this exact executable with debugging forbidden.
    # App Store export will apply the distribution provisioning profile.
    entitlements.pop('get-task-allow', None)
    entitlements_path = args.archive / 'SigningEntitlements.plist'
    entitlements_path.write_bytes(plistlib.dumps(entitlements))
    run(['xattr', '-cr', app])
    run(['codesign', '--force', '--sign', args.signing_identity,
         '--entitlements', entitlements_path, app])
    entitlements_path.unlink()
    run(['codesign', '--verify', '--deep', '--strict', app])
    metadata = {
        'ApplicationProperties': {
            'ApplicationPath': 'Applications/RetroArch.app', 'Architectures': ['arm64'],
            'CFBundleIdentifier': info['CFBundleIdentifier'],
            'CFBundleShortVersionString': info['CFBundleShortVersionString'],
            'CFBundleVersion': info['CFBundleVersion'],
            'SigningIdentity': args.signing_identity,
            'Team': entitlements['com.apple.developer.team-identifier'],
        },
        'ArchiveVersion': 2,
        'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
        'Name': 'RetroArch Lab', 'SchemeName': 'RetroArchiOS',
    }
    (args.archive / 'Info.plist').write_bytes(plistlib.dumps(metadata))
    manifest['archive'] = str(args.archive)
    manifest['get_task_allow'] = False
    manifest['debugger_entitlement_present'] = False
    manifest['signed_host_sha256'] = digest(app / 'RetroArch')
    manifest['swift_support'] = sorted(p.name for p in support.iterdir()) if support.exists() else []
    (args.archive / 'InterpreterManifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
