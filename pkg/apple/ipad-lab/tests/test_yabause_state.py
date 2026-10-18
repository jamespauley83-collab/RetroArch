"""Compile the patched state functions from the pinned Yabause fixture."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent


def function(path, signature):
    source = path.read_text()
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2]


class YabauseStateTests(unittest.TestCase):
    def test_save_errors_and_buffer_sizes(self):
        compiler = shutil.which('cc')
        if not compiler:
            self.skipTest('C compiler is unavailable')
        # Exact function excerpts from 8926b0c6c347f8c5c755911ddb0ac695420ffbf8.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(HERE / 'fixtures/yabause-state', root, dirs_exist_ok=True)
            patch = HERE.parent / 'patches/yabause/0002-savestate-buffer-errors.patch'
            subprocess.run(['git', 'apply', '--check', str(patch)], cwd=root, check=True)
            subprocess.run(['git', 'apply', str(patch)], cwd=root, check=True)
            (root / 'state_functions.inc').write_text(
                function(root / 'yabause/src/memory.c', 'int YabSaveStateBuffer(') + '\n' +
                function(root / 'yabause/src/libretro/libretro.c', 'bool retro_serialize('))
            binary = root / 'state-test'
            subprocess.run([compiler, '-std=c99', '-Wall', '-Wextra', '-Werror',
                            '-I' + str(root), str(HERE / 'yabause_state.c'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
