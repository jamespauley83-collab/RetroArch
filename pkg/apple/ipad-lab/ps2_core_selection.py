#!/usr/bin/env python3
"""Review PS2 assignments in an export; optionally write separate repair copies."""
import argparse
import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import tempfile
import zipfile

CORE_PATH = ':/Frameworks/armsx2.libretro.framework'
CORE_NAME = 'ARMSX2'
PS2_DATABASE = 'Sony - PlayStation 2'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def core_identifier(path):
    name = path.replace('\\', '/').rsplit('/', 1)[-1]
    for suffix in ('_libretro_ios.dylib', '_libretro.dylib', '_libretro.so',
                   '.libretro.framework', '.libretro'):
        if name.endswith(suffix):
            return name[:-len(suffix)]
    return name


def is_ps2_database(name):
    return name in (PS2_DATABASE, PS2_DATABASE + '.lpl')


def unassigned(path):
    return not path or path == 'DETECT'


def plan_playlist(document, filename):
    """Return edited data and field-level actions without mutating the input."""
    if not isinstance(document, dict) or not isinstance(document.get('items'), list):
        raise ValueError('Expected a JSON playlist with an items array: ' + filename)
    result = copy.deepcopy(document)
    changes = []

    def string_field(obj, field):
        value = obj.get(field, '')
        if not isinstance(value, str):
            raise ValueError('Expected string field ' + field + ': ' + filename)
        return value

    def assign(obj, path_field, name_field, location, reason):
        for field, value in ((path_field, CORE_PATH), (name_field, CORE_NAME)):
            if obj.get(field) != value:
                changes.append({'field': location + field, 'before': obj.get(field),
                                'after': value, 'reason': reason})
                obj[field] = value

    default = string_field(result, 'default_core_path')
    string_field(result, 'default_core_name')
    ps2_playlist = is_ps2_database(Path(filename).name)
    default_identifier = core_identifier(default)
    if default_identifier == 'play' or (ps2_playlist and unassigned(default)):
        assign(result, 'default_core_path', 'default_core_name', '',
               'Explicit PS2 core or PS2 playlist default')

    for index, item in enumerate(result['items']):
        if not isinstance(item, dict):
            raise ValueError('Expected object in items: ' + filename)
        assigned = string_field(item, 'core_path')
        string_field(item, 'core_name')
        database = string_field(item, 'db_name')
        identifier = core_identifier(assigned)
        if identifier == 'play':
            assign(item, 'core_path', 'core_name', 'items[%d].' % index,
                   'Explicit PS2 core assignment')
        elif unassigned(assigned) and (
                default_identifier == 'play' or
                (unassigned(default) and (ps2_playlist or is_ps2_database(database)))):
            assign(item, 'core_path', 'core_name', 'items[%d].' % index,
                   'PS2 playlist/database with no conflicting core assignment')
    return result, changes


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key: ' + key)
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError('Invalid JSON constant: ' + value)


def inspect_app(app):
    binary = app / 'Frameworks/armsx2.libretro.framework/armsx2.libretro'
    if not binary.is_file() or not binary.stat().st_size:
        raise ValueError('The supplied app does not contain an ARMSX2 executable.')
    with zipfile.ZipFile(app / 'assets.zip') as assets:
        if 'info/armsx2_libretro.info' not in assets.namelist():
            raise ValueError('The supplied app lacks ARMSX2 core metadata.')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    return {'bundle_id': info.get('CFBundleIdentifier'),
            'build': info.get('CFBundleVersion'),
            'armsx2_sha256': sha256(binary.read_bytes()),
            'evidence_scope': 'Supplied app package; not current device inventory'}


def plan_export(export, app, playlists):
    export = export.resolve(strict=True)
    if not export.is_dir():
        raise ValueError('Expected an exported directory.')
    report = {'app': inspect_app(app), 'files': [], 'changed_files': 0,
              'device_modified': False, 'source_export_modified': False}
    payloads = {}
    if len(playlists) != len(set(playlists)):
        raise ValueError('Duplicate playlist selection.')
    for relative in playlists:
        selected = PurePosixPath(relative)
        if (selected.is_absolute() or '..' in selected.parts or '\\' in relative
                or selected.suffix != '.lpl' or selected.as_posix() != relative):
            raise ValueError('Expected a relative .lpl path within the export: ' + relative)
        path = export / relative
        if (any(parent.is_symlink() for parent in [path, *path.parents] if parent != export)
                or not path.is_file() or not path.resolve().is_relative_to(export)):
            raise ValueError('Playlist must be a regular file within the export: ' + str(path))
        original = path.read_bytes()
        try:
            document = json.loads(original.decode('utf-8-sig'), object_pairs_hook=unique_object,
                                  parse_constant=reject_constant)
            edited, changes = plan_playlist(document, relative)
        except (ValueError, UnicodeError) as error:
            raise ValueError('Cannot safely edit playlist %s: %s' % (relative, error)) from error
        report['files'].append({'path': relative, 'source_sha256': sha256(original),
                                'changes': changes})
        if changes:
            output = (json.dumps(edited, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
            report['files'][-1]['proposed_sha256'] = sha256(output)
            payloads[relative] = (original, output)
    report['changed_files'] = len(payloads)
    return report, payloads


def write_repair_package(destination, report, payloads):
    """Write only new files, with original bytes retained beside repair copies."""
    if destination.exists():
        raise ValueError('Output directory already exists; refusing to overwrite.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.ps2-repair-', dir=destination.parent))
    try:
        for relative, (original, edited) in payloads.items():
            for folder, data in (('originals', original), ('proposed', edited)):
                path = staging / folder / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        (staging / 'review.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        destination.mkdir()
        for child in staging.iterdir():
            child.rename(destination / child.name)
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export-root', required=True, type=Path,
                        help='Copied RetroArch data; never modified')
    parser.add_argument('--app', required=True, type=Path,
                        help='Unpacked app package containing the intended ARMSX2 core')
    parser.add_argument('--playlist', required=True, action='append',
                        help='Exact relative .lpl path in the export; repeat for each file')
    parser.add_argument('--output', type=Path,
                        help='New directory for original backups and proposed playlists')
    args = parser.parse_args()
    if args.output and args.output.resolve().is_relative_to(args.export_root.resolve()):
        parser.error('--output must be outside the source export')
    try:
        report, payloads = plan_export(args.export_root, args.app, args.playlist)
        if args.output:
            write_repair_package(args.output, report, payloads)
    except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
