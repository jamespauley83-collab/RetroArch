#!/usr/bin/env python3
"""Exercise native logger initialization using production source and a failing control."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def part(source, start, end):
    a = source.index(start)
    return source[a:source.index(end, a)]


def run(args, output):
    root = args.core_root.resolve()
    logger = (root / "rpcs3/util/logs.cpp").read_text()
    original = args.baseline.read_text()
    fixed = args.patched.read_text()
    (output / "LoggerRegistry.inc").write_text(part(logger, "\tstruct root_listener final", "\n\tstatic u64 get_stamp()"))
    (output / "LoggerSetInit.inc").write_text(part(logger, "\tvoid set_init(std::initializer_list<stored_message> init_msg)", "\n}\n\nlogs::listener::~listener()"))
    (output / "LoggerDispatch.inc").write_text(part(logger, "logs::listener::~listener()", "\nlogs::file_writer::file_writer("))
    (output / "NativeEmitLog.inc").write_text(part(original, "void emit_log(int32_t level, std::string_view message)", "\nvoid emit_jit_arena_statistics"))
    (output / "NativeListener.inc").write_text(part(original, "class callback_log_listener final", "\nstd::unique_ptr<callback_log_listener> g_log_listener;"))
    for filename, source in [("OriginalInit.inc", original), ("FixedInit.inc", fixed)]:
        (output / filename).write_text(part(source, "\t\tg_log_listener = std::make_unique<callback_log_listener>();", "\n\n\t\t// A developer can request"))
    formatter = (root / "Utilities/StrFmt.cpp").read_text()
    a = formatter.index("template <>\nvoid fmt_class_string<std::string_view>::format")
    b = formatter.index("\n}\n", a) + 3
    (output / "StringViewFormatter.inc").write_text(formatter[a:b])
    harness = Path(__file__).with_name("NativeLoggerInitTests.cpp")
    binary = output / "NativeLoggerInitTests"
    command = [args.cxx, "-std=c++20", "-Wall", "-Wextra", "-Werror", "-pthread",
               "-I", str(root), "-I", str(root / "rpcs3"), "-I", str(root / "rpcs3/ios"),
               "-I", str(output), str(harness), "-o", str(binary)]
    subprocess.run(command, cwd=output, check=True)
    results = {}
    for mode in ["original", "fixed"]:
        result = subprocess.run([str(binary), mode], cwd=output, capture_output=True, text=True, timeout=15)
        results[mode] = result
        print(mode + ": " + result.stdout.strip() + result.stderr.strip(), flush=True)
    if results["original"].returncode != 1 or "native initialization must finalize logging" not in results["original"].stderr:
        raise RuntimeError("The regression control must reject the original native initialization")
    if results["fixed"].returncode != 0:
        raise RuntimeError("Patched native initialization failed")
    print("PASS: original native initialization rejected; patched production initialization passed.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--core-root", type=Path, required=True,
                        help="Pinned native core checkout supplying production logger and headers")
    parser.add_argument("--baseline", type=Path, required=True,
                        help="RPCS3IOS.cpp before this playback patch")
    parser.add_argument("--patched", type=Path, required=True,
                        help="RPCS3IOS.cpp after this playback patch")
    parser.add_argument("--cxx", default=os.environ.get("CXX", "clang++"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rpcs3-native-logger-") as directory:
        run(args, Path(directory))


if __name__ == "__main__":
    main()
