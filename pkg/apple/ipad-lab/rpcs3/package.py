#!/usr/bin/env python3
"""Package an unsigned, isolated native PS3 test build. Never signs or installs."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import zipfile

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / 'core.lock.json').read_text())
IDENTITY = LOCK['bundle_id']
CORE_PATH = 'Payload/RPCS3.app/Frameworks/libRPCS3Core.dylib'


def verified_core(ipa):
    if hashlib.sha256(ipa.read_bytes()).hexdigest() != LOCK['ipa_sha256']:
        raise ValueError('Expected the pinned XITRIX 0.12 ARMv8.4-A IPA.')
    with zipfile.ZipFile(ipa) as archive:
        if archive.namelist().count(CORE_PATH) != 1:
            raise ValueError('Expected exactly one RPCS3 core.')
        core = archive.read(CORE_PATH)
    if hashlib.sha256(core).hexdigest() != LOCK['core_sha256']:
        raise ValueError('RPCS3 core hash mismatch.')
    return core


def package(app, ipa, destination):
    if destination.exists():
        raise ValueError('Use a new output directory to preserve previous builds.')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != IDENTITY:
        raise ValueError('Build the host with the isolated PS3 bridge identifier.')
    binary = (app / info['CFBundleExecutable']).read_bytes()
    if b'RALabPS3Controller' not in binary:
        raise ValueError('This host does not contain the native PS3 bridge.')
    core = verified_core(ipa)
    target = destination / 'Payload/RetroArch.app'
    shutil.copytree(app, target)
    for path in target.rglob('embedded.mobileprovision'):
        path.unlink()
    for path in list(target.rglob('_CodeSignature')):
        shutil.rmtree(path)
    # Unrelated widget extensions are not needed by the bridge test identity.
    shutil.rmtree(target / 'PlugIns', ignore_errors=True)
    frameworks = target / 'Frameworks'
    frameworks.mkdir(exist_ok=True)
    (frameworks / 'libRPCS3Core.dylib').write_bytes(core)
    info['CFBundleName'] = info['CFBundleDisplayName'] = LOCK['display_name']
    info['CFBundleURLTypes'] = [{'CFBundleURLName': IDENTITY,
                                'CFBundleURLSchemes': ['retroarchlabps3bridge']}]
    info['UIFileSharingEnabled'] = True
    info['LSSupportsOpeningDocumentsInPlace'] = True
    (target / 'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2(HERE / 'NOTICE.md', target / 'RPCS3-NOTICE.md')
    shutil.copy2(HERE / 'RPCS3-LICENSE', target / 'RPCS3-LICENSE')
    shutil.copy2(HERE / 'core.lock.json', target / 'RPCS3-core.lock.json')
    manifest = dict(LOCK, signed=False, physical_gameplay_verified=False,
                    host_sha256=hashlib.sha256(binary).hexdigest())
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host-app', type=Path, required=True)
    parser.add_argument('--xitrix-ipa', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(package(args.host_app, args.xitrix_ipa, args.output))


if __name__ == '__main__':
    main()
