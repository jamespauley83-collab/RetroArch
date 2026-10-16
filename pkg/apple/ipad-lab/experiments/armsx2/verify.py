"""Reject non-iOS, incomplete, or externally dependent prototype binaries."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

PIN = 'e58489d349cdcd635fc6264546087e347c84bf8c'
REQUIRED = {
    'retro_init', 'retro_deinit', 'retro_api_version', 'retro_get_system_info',
    'retro_get_system_av_info', 'retro_set_environment', 'retro_set_video_refresh',
    'retro_set_audio_sample', 'retro_set_audio_sample_batch', 'retro_set_input_poll',
    'retro_set_input_state', 'retro_set_controller_port_device', 'retro_reset',
    'retro_run', 'retro_serialize_size', 'retro_serialize', 'retro_unserialize',
    'retro_cheat_reset', 'retro_cheat_set', 'retro_load_game',
    'retro_load_game_special', 'retro_unload_game', 'retro_get_region',
    'retro_get_memory_data', 'retro_get_memory_size',
}


def validate(architectures, build_version, symbols, dependencies):
    if architectures.strip() != 'arm64':
        raise ValueError('Expected an ARM64-only binary.')
    platforms = re.findall(r'^\s*platform\s+(\S+)', build_version, re.M)
    if platforms != ['IOS']:
        raise ValueError('Expected iPhoneOS, not macOS or the simulator.')
    versions = re.findall(r'^\s*minos\s+(\S+)', build_version, re.M)
    if versions != ['17.4']:
        raise ValueError('Unexpected deployment target.')
    exports = set(symbols.split())
    if not {'_' + name for name in REQUIRED}.issubset(exports):
        raise ValueError('Missing libretro entry points.')
    if any(not name.startswith('_retro_') for name in exports):
        raise ValueError('Core exports internal symbols into the frontend.')
    # otool -L includes the dylib's own LC_ID_DYLIB before its dependencies.
    lines = [line.strip().split(' (', 1)[0] for line in dependencies.splitlines()[1:] if line.strip()]
    if not lines or Path(lines[0]).name != 'armsx2_libretro.dylib':
        raise ValueError('Unexpected library identity.')
    for dependency in lines[1:]:
        if not dependency.startswith(('/System/Library/Frameworks/', '/usr/lib/')):
            raise ValueError('Non-system dynamic dependency: ' + dependency)
    return lines


def output(*args):
    return subprocess.check_output(args, text=True)


def main():
    binary, artifacts, source = map(Path, sys.argv[1:])
    if output('git', '-C', str(source), 'rev-parse', 'HEAD').strip() != PIN:
        raise ValueError('Source pin mismatch.')
    reports = {
        'architectures': output('xcrun', 'lipo', '-archs', str(binary)),
        'build_version': output('xcrun', 'vtool', '-show-build', str(binary)),
        'symbols': output('xcrun', 'nm', '-gUj', str(binary)),
        'dependencies': output('xcrun', 'otool', '-L', str(binary)),
    }
    dependencies = validate(**reports)
    # Verify the built executable retained the explicit load gate.
    if b'ARMSX2 Lab build probe: gameplay disabled' not in binary.read_bytes():
        raise ValueError('Prototype load gate missing from binary.')
    artifacts.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, artifacts / binary.name)
    here = Path(__file__).resolve().parent
    manifest = {
        'upstream_repository': 'https://github.com/ARMSX2/ARMSX2',
        'upstream_commit': PIN,
        'lab_commit': output('git', '-C', str(here), 'rev-parse', 'HEAD').strip(),
        'stage': 'build-probe', 'gameplay_enabled': False,
        'device_signed': False, 'device_tested': False,
        'architecture': 'arm64', 'platform': 'iOS', 'minimum_ios': '17.4',
        'binary': binary.name,
        'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'patches': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted((here / 'patches').glob('*.patch'))},
        'dependencies': dependencies,
        'xcode': output('xcodebuild', '-version').strip(),
        'sdk': output('xcrun', '--sdk', 'iphoneos', '--show-sdk-version').strip(),
        'bridges': {'graphics': 'Metal CPU readback', 'jit': 'frontend RWX/dual-map arena'},
        'remaining': ['device graphics and JIT validation', 'frame pacing and readback optimization',
                      'isolated app packaging', 'device gameplay/audio/save testing'],
    }
    (artifacts / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (artifacts / 'binary-inspection.json').write_text(json.dumps(reports, indent=2) + '\n')


if __name__ == '__main__':
    main()
