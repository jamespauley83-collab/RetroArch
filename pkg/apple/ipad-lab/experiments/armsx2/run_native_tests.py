"""Run portable tests against the applied upstream sources, without an iOS SDK."""
from pathlib import Path
import subprocess
import sys


def function(source, signature):
    start = source.index(signature + '\n{')
    end = source.index('\n}', start) + 2
    return source[start:end] + '\n'


def main():
    source, root, work = (Path(arg).resolve() for arg in sys.argv[1:])
    here = Path(__file__).resolve().parent
    work.mkdir(parents=True, exist_ok=True)
    darwin = (source / 'common/Darwin/DarwinMisc.cpp').read_text()
    memory = (source / 'pcsx2/Memory.cpp').read_text()
    (work / 'memory_under_test.inc').write_text(
        function(darwin, 'void* DarwinMisc::MmapCodeDualMap(size_t size)') +
        function(darwin, 'void DarwinMisc::MunmapCodeDualMap(void* rx_ptr, size_t size)') +
        function(memory, 'void SysMemory::Reset()'))
    for test in ['gate_test', 'bridge_test', 'darwin_memory_test']:
        binary = work / test
        subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror', '-pthread',
                        '-I' + str(source / '3rdparty/libretro'),
                        '-I' + str(source / 'pcsx2-libretro'), '-I' + str(source),
                        '-I' + str(root), '-I' + str(work), str(here / (test + '.cpp')),
                        '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    main()
