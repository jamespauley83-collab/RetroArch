#!/usr/bin/env python3
"""Build an isolated iOS app with pinned, source-built libretro cores."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[3]
LAB = Path('pkg/apple/ipad-lab')


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def output(*args, cwd=None):
    return subprocess.check_output([str(arg) for arg in args], cwd=cwd, text=True).strip()


def load_lock(path):
    lock = json.loads(path.read_text())
    if not re.fullmatch(r'com\.jamespauley\.retroarchlab(?:\.[A-Za-z0-9-]+)*', lock['bundle_id']):
        raise ValueError('Use the separate RetroArch Lab bundle identifier.')
    if not lock['cores']:
        raise ValueError('At least one core is required.')
    names = set()
    for core in lock['cores']:
        name = core['name']
        if not re.fullmatch(r'[a-z0-9_]+', name) or name in names:
            raise ValueError('Core names must be unique simple identifiers.')
        names.add(name)
        if not re.fullmatch(r'[0-9a-f]{40}', core['commit']):
            raise ValueError('Pin each core to a complete commit SHA.')
        if not re.fullmatch(r'https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git', core['repository']):
            raise ValueError('Core repositories must be HTTPS GitHub URLs.')
        if not re.fullmatch(r'Makefile[\w.-]*', core['makefile']):
            raise ValueError('Expected a core Makefile in its repository root.')
    return lock


def customize_plist(path, lock):
    with path.open('rb') as stream:
        info = plistlib.load(stream)
    info['CFBundleDisplayName'] = lock['display_name']
    info['CFBundleName'] = lock['display_name']
    info['CFBundleURLTypes'] = [{
        'CFBundleURLName': lock['bundle_id'],
        'CFBundleURLSchemes': ['retroarchlab'],
    }]
    with path.open('wb') as stream:
        plistlib.dump(info, stream)


def overlay_core_info(root):
    assets_path = root / 'pkg/apple/assets.zip'
    additions = {('info/' + path.name): path.read_bytes()
                 for path in (root / LAB / 'info').glob('*_libretro.info')}
    if not additions:
        return
    replacement = assets_path.with_suffix('.lab.zip')
    with zipfile.ZipFile(assets_path) as original, zipfile.ZipFile(replacement, 'w') as updated:
        for entry in original.infolist():
            if entry.filename not in additions:
                updated.writestr(entry, original.read(entry.filename))
        for name, data in additions.items():
            updated.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)
    replacement.replace(assets_path)


def core_binary_path(core):
    framework = core['name'].replace('_', '.') + '.libretro'
    return Path('Frameworks') / (framework + '.framework') / framework


def validate_app(app, lock):
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info['CFBundleIdentifier'] != lock['bundle_id']:
        raise ValueError('Built app has the wrong bundle identifier.')
    if info['CFBundleDisplayName'] != lock['display_name']:
        raise ValueError('Built app has the wrong display name.')
    if not (app / info['CFBundleExecutable']).is_file():
        raise ValueError('Built app executable is missing.')
    for extension in (app / 'PlugIns').glob('*.appex'):
        with (extension / 'Info.plist').open('rb') as stream:
            ext = plistlib.load(stream)
        if not ext['CFBundleIdentifier'].startswith(lock['bundle_id'] + '.'):
            raise ValueError('Extension identifier is not isolated from the official app.')
    for core in lock['cores']:
        binary = app / core_binary_path(core)
        if not binary.is_file():
            raise ValueError('Packaged core is missing: ' + core['name'])
    with zipfile.ZipFile(app / 'assets.zip') as assets:
        for core in lock['cores']:
            if 'info/' + core['name'] + '_libretro.info' not in assets.namelist():
                raise ValueError('Packaged core info is missing: ' + core['name'])


def package_app(app, work, artifacts, manifest):
    payload = work / 'Payload'
    payload.mkdir()
    packaged_app = payload / app.name
    shutil.copytree(app, packaged_app, symlinks=True)
    for core in manifest['cores']:
        binary = packaged_app / core_binary_path(core)
        core['binary_path'] = binary.relative_to(work).as_posix()
        core['sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
    (packaged_app / 'retroarch-lab-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    ipa = artifacts / 'RetroArch-Lab-unsigned.ipa'
    run('ditto', '-c', '-k', '--keepParent', payload, ipa)
    with zipfile.ZipFile(ipa) as archive:
        for core in manifest['cores']:
            if hashlib.sha256(archive.read(core['binary_path'])).hexdigest() != core['sha256']:
                raise ValueError('Packaged core checksum mismatch: ' + core['name'])
    manifest['ipa_sha256'] = hashlib.sha256(ipa.read_bytes()).hexdigest()
    (artifacts / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return ipa


def build(root):
    if platform.system() != 'Darwin' or not shutil.which('xcodebuild'):
        raise RuntimeError('The iPad build requires macOS with full Xcode; use the GitHub Actions workflow.')
    revision = output('git', 'rev-parse', 'HEAD', cwd=root)
    if output('git', 'status', '--porcelain', cwd=root):
        raise RuntimeError('Commit or stash changes first; the build uses exactly committed HEAD.')
    destination = root / '.ipad-lab-build'
    destination.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=revision[:8] + '-', dir=destination))
    print('Build directory: ' + str(work), flush=True)
    source = work / 'source'
    source.mkdir()
    run('git', 'archive', '--format=tar', '--output=' + str(work / 'source.tar'), 'HEAD', cwd=root)
    run('tar', '-xf', work / 'source.tar', '-C', source)
    (work / 'source.tar').unlink()
    lock = load_lock(source / LAB / 'cores.lock.json')
    apple = source / 'pkg/apple'
    overlay_core_info(source)
    customize_plist(apple / 'iOS/Info.plist', lock)
    # The exported tree has no .git directory for the upstream build phase.
    (source / '.git_version.h').write_text('#define GIT_VERSION ' + revision[:8] + '\n')
    modules = apple / 'iOS/modules'
    modules.mkdir(exist_ok=True)
    if list(modules.glob('*.dylib')):
        raise RuntimeError('The source tree must not contain prebuilt iOS cores.')
    manifest = {
        'retroarch_commit': revision,
        'bundle_id': lock['bundle_id'],
        'device_signed': False,
        'xcode': output('xcodebuild', '-version'),
        'sdk': output('xcrun', '--sdk', 'iphoneos', '--show-sdk-version'),
        'cores': [],
    }
    artifacts = work / 'artifacts'
    artifacts.mkdir()
    for core in lock['cores']:
        repo = work / core['name']
        run('git', 'init', repo)
        run('git', 'remote', 'add', 'origin', core['repository'], cwd=repo)
        run('git', 'fetch', '--depth=1', 'origin', core['commit'], cwd=repo)
        run('git', 'checkout', '--detach', 'FETCH_HEAD', cwd=repo)
        if output('git', 'rev-parse', 'HEAD', cwd=repo) != core['commit']:
            raise RuntimeError('Core checkout does not match the lock file.')
        patches = sorted((source / LAB / 'patches' / core['name']).glob('*.patch'))
        patch_hashes = {}
        for patch in patches:
            run('git', 'apply', '--check', patch, cwd=repo)
            run('git', 'apply', patch, cwd=repo)
            patch_hashes[patch.name] = hashlib.sha256(patch.read_bytes()).hexdigest()
        # Include the exact modified core sources with the binary artifact.
        run('tar', '--exclude=.git', '-czf', artifacts / (core['name'] + '-source.tar.gz'), '-C', repo, '.')
        with (work / (core['name'] + '-build.log')).open('w') as log:
            subprocess.run(['make', '-f', core['makefile'], 'platform=ios-arm64',
                            '-j' + str(min(os.cpu_count() or 2, 8))],
                           cwd=repo, stdout=log, stderr=subprocess.STDOUT, check=True)
        binary = repo / (core['name'] + '_libretro_ios.dylib')
        run('xcrun', 'lipo', binary, '-verify_arch', 'arm64')
        shutil.copy2(binary, modules)
        manifest['cores'].append(dict(core, patches=patch_hashes))
    with (work / 'xcodebuild.log').open('w') as log:
        subprocess.run([
            'xcodebuild', '-project', str(apple / 'RetroArch_iOS13.xcodeproj'),
            '-scheme', 'RetroArch iOS Release', '-configuration', 'Release',
            '-destination', 'generic/platform=iOS', '-derivedDataPath', str(work / 'DerivedData'),
            '-xcconfig', str(apple / 'GitHubCI.xcconfig'),
            'IOS_BUNDLE_IDENTIFIER=' + lock['bundle_id'],
            'RA_IPHONEOS_DEPLOYMENT_TARGET=' + lock['minimum_ios'],
            'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=NO', 'DEVELOPMENT_TEAM=',
            'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
            'CODE_SIGN_IDENTITY=-', 'PROVISIONING_PROFILE_SPECIFIER=',
            'APPSTORE_BUILD=', 'build',
        ], cwd=apple, stdout=log, stderr=subprocess.STDOUT, check=True)
    app = work / 'DerivedData/Build/Products/Release-iphoneos/RetroArch.app'
    validate_app(app, lock)
    run('xcrun', 'lipo', app / 'RetroArch', '-verify_arch', 'arm64')
    ipa = package_app(app, work, artifacts, manifest)
    shutil.copy2(source / 'COPYING', artifacts / 'RetroArch-COPYING')
    shutil.copy2(source / LAB / 'README.md', artifacts / 'README.md')
    print('Build complete: ' + str(ipa), flush=True)
    print('This IPA requires device signing before installation.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Validate inputs without Xcode or downloads')
    args = parser.parse_args()
    lock = load_lock(ROOT / LAB / 'cores.lock.json')
    if args.check:
        with zipfile.ZipFile(ROOT / 'pkg/apple/assets.zip') as assets:
            for core in lock['cores']:
                if ('info/' + core['name'] + '_libretro.info' not in assets.namelist()
                        and not (ROOT / LAB / 'info' / (core['name'] + '_libretro.info')).is_file()):
                    raise ValueError('Core info missing from bundled assets: ' + core['name'])
        print('Inputs valid: ' + ', '.join(c['name'] for c in lock['cores']))
    else:
        build(ROOT)


if __name__ == '__main__':
    main()
