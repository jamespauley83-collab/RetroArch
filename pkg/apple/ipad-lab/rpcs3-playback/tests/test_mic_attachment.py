#!/usr/bin/env python3
"""Behavior-check the actual cellMicIsAttached source and reject its old stub."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

def extract_function(text, signature):
    start = text.index(signature)
    opening = text.index("{", start)
    depth = 0
    for i in range(opening, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    raise ValueError("Function body did not close: " + signature)

STUB = r"""
#include <array>
#include <cstdint>
#include <iostream>
#include <mutex>
#include <limits>
using s32 = std::int32_t;
using u32 = std::uint32_t;
struct microphone_device {
    bool registered = false;
    bool opened = false;
    bool is_registered() const { return registered; }
};
template<class T, std::size_t N>
T& at32(std::array<T, N>& items, u32 index) { return items.at(index); }
struct mic_context {
    std::array<microphone_device, 8> mic_list{};
    std::mutex mutex;
    int init = 0;
    bool check_device(u32 dev_num);
};
using mic_thread = mic_context;
struct FakeFxo {
    mic_context context;
    template<class T> T& get() { return context; }
} fxo;
FakeFxo* g_fxo = &fxo;
struct Logger {
    template<class... Args> void trace(const char*, Args...) {}
} cellMic;
"""
CASES = r"""
int main() {
    int checks = 0;
    int failures = 0;
    auto expect = [&](s32 slot, s32 wanted, const char* state) {
        ++checks;
        const s32 got = cellMicIsAttached(slot);
        if (got != wanted) {
            ++failures;
            std::cerr << state << " slot=" << slot << " wanted=" << wanted
                      << " got=" << got << "\n";
        }
    };
    auto& ctx = fxo.context;
    expect(0, 1, "preinit preserves old behavior");
    expect(7, 1, "preinit preserves old behavior");
    expect(-1, 1, "preinit preserves old behavior");
    expect(8, 1, "preinit preserves old behavior");
    ctx.init = 1;
    for (s32 slot = 0; slot < 8; ++slot)
        expect(slot, 0, "initialized no microphones");
    for (s32 slot : {-1, std::numeric_limits<s32>::min(), 8, std::numeric_limits<s32>::max()})
        expect(slot, 0, "invalid slot");
    ctx.mic_list[3].registered = true;
    for (s32 slot = 0; slot < 8; ++slot)
        expect(slot, slot == 3 ? 1 : 0, "one registered closed microphone");
    ctx.mic_list[3].opened = true;
    expect(3, 1, "registered open microphone");
    ctx.mic_list[3].registered = false;
    expect(3, 0, "unregistered microphone");
    ctx.mic_list[0].registered = true;
    ctx.mic_list[7].registered = true;
    expect(0, 1, "first slot registered");
    expect(7, 1, "last slot registered");
    expect(8, 0, "past last registered slot");
    expect(-1, 0, "negative with registered microphones");
    ctx.init = 0;
    expect(3, 1, "after end preserves preinit behavior");
    std::cout << "checks=" << checks << " failures=" << failures << "\n";
    return failures ? 1 : 0;
}
"""

def run(args, output):
    compiler = args.cxx
    baseline = args.baseline.read_text()
    check_device = extract_function(baseline, "bool mic_context::check_device(u32 dev_num)")
    evidence = {"method": "Actual production cellMicIsAttached and check_device bodies; minimal context stubs. Not an emulator integration or microphone hardware test.", "runs": {}}
    for name, path in [("baseline", args.baseline), ("patched", args.patched)]:
        source = path.read_text()
        function = extract_function(source, "s32 cellMicIsAttached(s32 dev_num)")
        harness = output / ("mic_attachment_" + name + ".cpp")
        binary = output / ("mic_attachment_" + name)
        harness.write_text(STUB + "\n" + check_device + "\n" + function + "\n" + CASES)
        command = [compiler, "-std=c++20", "-Wall", "-Wextra", "-Werror",
                   str(harness), "-o", str(binary)]
        compiled = subprocess.run(command, capture_output=True, text=True)
        if compiled.returncode:
            raise RuntimeError(name + " compile failed:\n" + compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True)
        evidence["runs"][name] = {
            "source": str(path), "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
            "function_sha256": hashlib.sha256(function.encode()).hexdigest(),
            "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
            "compile_command": command,
        }
        print(name + ": " + result.stdout.strip(), flush=True)
    assert evidence["runs"]["baseline"]["exit_code"] == 1, "Regression harness must reject old implementation"
    assert evidence["runs"]["patched"]["exit_code"] == 0, "Patched function must pass"
    (output / "mic_attachment_results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("PASS: original stub rejected; patched production function passed.", flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True,
                        help="cellMic.cpp before the attachment correction")
    parser.add_argument("--patched", type=Path, required=True,
                        help="cellMic.cpp after the attachment correction")
    parser.add_argument("--cxx", default=os.environ.get("CXX", "clang++"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rpcs3-mic-attachment-") as directory:
        run(args, Path(directory))


if __name__ == "__main__":
    main()
