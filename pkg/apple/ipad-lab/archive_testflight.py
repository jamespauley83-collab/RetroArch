#!/usr/bin/env python3
"""Archive a Lab host compiled with TestFlight.xcconfig and verified cached cores."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base-app', type=Path, required=True)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--build', type=int, required=True)
    parser.add_argument('--signing-identity', required=True)
    args = parser.parse_args()
    if args.archive.exists():
        parser.error('Archive already exists; choose a new output path.')
    symbols = subprocess.check_output(['nm', '-g', str(args.host)], text=True)
    forbidden = ['SecTaskCreateFromSelf', 'SecTaskCopyValueForEntitlement',
                 'OBJC_CLASS_$_RALabJIT', 'OBJC_CLASS_$_RALabPS3Controller']
    if any(symbol in symbols for symbol in forbidden):
        parser.error('Host contains development-only JIT/PS3 APIs. Use TestFlight.xcconfig.')
    if b'Hide routine popups' not in args.host.read_bytes():
        parser.error('Game Mode is missing from the host.')

    app = args.archive / 'Products/Applications/RetroArch.app'
    app.parent.mkdir(parents=True)
    subprocess.run(['cp', '-RX', str(args.base_app), str(app)], check=True)
    shutil.copyfile(args.host, app / 'RetroArch')
    frameworks = app / 'Frameworks'
    for name in ['dolphin.libretro.framework', 'armsx2.libretro.framework',
                 'play.libretro.framework']:
        path = frameworks / name
        if path.exists():
            shutil.rmtree(path)
    (frameworks / 'libRPCS3Core.dylib').unlink(missing_ok=True)
    expected = {'fceumm.libretro.framework', 'snes9x2010.libretro.framework',
                'opera.libretro.framework', 'yabause.libretro.framework',
                'mednafen.saturn.libretro.framework', 'MoltenVK.framework'}
    if {path.name for path in frameworks.iterdir()} != expected:
        raise RuntimeError('Unexpected or missing framework in TestFlight package.')
    for framework in frameworks.iterdir():
        for file in framework.rglob('*'):
            if file.is_file():
                original = args.base_app / file.relative_to(app)
                if hashlib.sha256(file.read_bytes()).digest() != hashlib.sha256(original.read_bytes()).digest():
                    raise RuntimeError('Cached framework changed: ' + str(file))

    info_path = app / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleVersion'] = str(args.build)
    info_path.write_bytes(plistlib.dumps(info))
    support = args.archive / 'SwiftSupport/iphoneos'
    subprocess.run(['xcrun', 'swift-stdlib-tool', '--copy',
                    '--scan-executable', str(app / 'RetroArch'),
                    '--scan-folder', str(frameworks), '--platform', 'iphoneos',
                    '--destination', str(frameworks), '--unsigned-destination', str(support.parent),
                    '--sign', args.signing_identity], check=True)
    for library in frameworks.glob('*.dylib'):
        if not library.name.startswith('libswift') or not (support / library.name).exists():
            raise RuntimeError('Unsupported standalone library: ' + str(library))
    # Modern iOS may need no bundled Swift runtime. An empty SwiftSupport
    # directory is rejected by App Store Connect (ITMS-90424).
    if support.parent.exists() and not any(p.is_file() for p in support.parent.rglob('*')):
        shutil.rmtree(support.parent)
    entitlements = subprocess.check_output(
        ['codesign', '-d', '--entitlements', ':-', str(args.base_app)], stderr=subprocess.DEVNULL)
    entitlements_path = args.archive / 'SigningEntitlements.plist'
    entitlements_path.write_bytes(entitlements)
    subprocess.run(['xattr', '-cr', str(app)], check=True)
    subprocess.run(['codesign', '--force', '--sign', args.signing_identity,
                    '--entitlements', str(entitlements_path), str(app)], check=True)
    entitlements_path.unlink()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    team = plistlib.loads(entitlements)['com.apple.developer.team-identifier']
    metadata = {'ApplicationProperties': {
        'ApplicationPath': 'Applications/RetroArch.app', 'Architectures': ['arm64'],
        'CFBundleIdentifier': info['CFBundleIdentifier'],
        'CFBundleShortVersionString': info['CFBundleShortVersionString'],
        'CFBundleVersion': info['CFBundleVersion'],
        'SigningIdentity': args.signing_identity, 'Team': team},
        'ArchiveVersion': 2, 'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
        'Name': 'RetroArch Lab', 'SchemeName': 'RetroArchiOS'}
    (args.archive / 'Info.plist').write_bytes(plistlib.dumps(metadata))
    print(json.dumps({'archive': str(args.archive), 'build': info['CFBundleVersion'],
                      'frameworks': sorted(expected),
                      'swift_support': [p.name for p in support.iterdir()] if support.exists() else [],
                      'signed_host_sha256': hashlib.sha256((app / 'RetroArch').read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
