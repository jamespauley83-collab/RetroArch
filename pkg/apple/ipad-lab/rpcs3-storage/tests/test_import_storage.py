#!/usr/bin/env python3
"""Exercise the production ISO preflight and Apple capacity query in isolation."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def preflight(source):
    start = source.index("game_iso_install_result install_game_iso(")
    end = source.index("\tstatic std::atomic<u64> import_counter", start)
    section = source[start:end]
    anchor = "\tu64 available_capacity = 0;" if "\tu64 available_capacity = 0;" in section else "\tfs::device_stat device{};"
    return section[section.index(anchor):]


def platform_helper(source):
    start = source.index("bool available_capacity_for_import(")
    end = source.index("bool display_sleep_control_supported()", start)
    return source[start:end]


PREFLIGHT_PREFIX = r"""
#include <cstdint>
#include <iostream>
#include <limits>
#include <string>
using u64 = std::uint64_t;
struct Result { bool ok; std::string detail; };
Result iso_installation_failed(std::string detail) { return {false, detail}; }
// Formatting and logging are adapters; storage decisions are production code.
std::string formatted_byte_size(u64 value) { return std::to_string(value); }
namespace fmt {
template<class... Args> std::string format(const char* text, const Args&... args) {
    std::string result(text); ((result += "|" + args), ...); return result;
}}
struct Logger { template<class... Args> void notice(const char*, const Args&...) {} };
Logger ios_game_library_log;
bool important_ok, raw_ok;
u64 important_bytes, raw_bytes;
bool available_capacity_for_import(const std::string&, u64& bytes) {
    if (important_ok) bytes = important_bytes;
    return important_ok;
}
namespace fs {
struct device_stat { u64 avail_free = 0; };
bool statfs(const std::string&, device_stat& info) {
    if (raw_ok) info.avail_free = raw_bytes;
    return raw_ok;
}}
Result check([[maybe_unused]] u64 iso_size, u64 total_size) {
    const std::string root = "/test/destination";
"""

PREFLIGHT_SUFFIX = r"""
    return {true, {}};
}
int main() {
    int failures = 0, checks = 0;
    auto expect = [&](bool ok, const char* name) {
        ++checks; if (!ok) { ++failures; std::cerr << "FAIL: " << name << "\n"; }
    };
    auto run = [&](bool api, u64 api_bytes, bool raw, u64 disk_bytes,
                   u64 iso = 6710000000ULL, u64 total = 6710000000ULL) {
        important_ok = api; important_bytes = api_bytes;
        raw_ok = raw; raw_bytes = disk_bytes;
        return check(iso, total);
    };
    expect(run(true, 43000000000ULL, true, 2470000000ULL).ok,
           "reported iPhone discrepancy allows import");
    auto shortage = run(true, 3000000000ULL, true, 2000000000ULL);
    expect(!shortage.ok, "genuine shortage blocks import");
    expect(shortage.detail.find("6710000000") != std::string::npos &&
           shortage.detail.find("3000000000") != std::string::npos &&
           shortage.detail.find("3710000000") != std::string::npos,
           "shortage reports ISO, available and additional bytes");
    expect(run(true, 6710000000ULL, true, 1).ok, "exact capacity is accepted");
    expect(!run(true, 0, true, 43000000000ULL).ok,
           "valid zero important capacity is authoritative");
    expect(!run(true, 3000000000ULL, true, 43000000000ULL).ok,
           "important capacity below raw is not overridden");
    expect(run(false, 0, true, 43000000000ULL).ok,
           "failed Apple query falls back to filesystem");
    expect(!run(false, 0, true, 2000000000ULL).ok,
           "fallback still rejects insufficient capacity");
    expect(run(true, 43000000000ULL, false, 0).ok,
           "valid Apple query survives filesystem query failure");
    auto unavailable = run(false, 0, false, 0);
    expect(!unavailable.ok && unavailable.detail.find("Unable to determine") != std::string::npos,
           "both unavailable queries fail closed");
    expect(run(true, 1ULL << 40, true, 0, 1ULL << 39, 1ULL << 39).ok,
           "capacities retain more than 32 bits");
    expect(!run(true, 6710000000ULL, true, 6710000000ULL,
                6710000000ULL, 6710000100ULL).ok,
           "optional key size remains in required total");
    expect(run(false, 0, true, std::numeric_limits<u64>::max()).ok,
           "large unsigned filesystem capacity does not wrap");
    std::cout << checks << " preflight checks, " << failures << " failures\n";
    return failures ? 1 : 0;
}
"""

APPLE_PREFIX = r"""
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <cstdint>
#include <iostream>
#include <string>
static id test_value;
static BOOL test_success;
static bool correct_key;
static bool correct_path;
static BOOL query(id object, SEL, id* result, NSURLResourceKey key, NSError**) {
    correct_key = [key isEqualToString:NSURLVolumeAvailableCapacityForImportantUsageKey];
    correct_path = [[(NSURL*)object path] isEqualToString:@"/tmp"];
    if (result) *result = test_value;
    return test_success;
}
namespace rpcs3::ios {
"""

APPLE_SUFFIX = r"""
}
int main() {
    @autoreleasepool {
        Method method = class_getInstanceMethod(NSURL.class,
            @selector(getResourceValue:forKey:error:));
        IMP original = method_setImplementation(method, (IMP)query);
        int checks = 0, failures = 0;
        auto expect = [&](bool ok, const char* name) {
            ++checks; if (!ok) { ++failures; std::cerr << "FAIL: " << name << "\n"; }
        };
        auto run = [&](id value, BOOL success, bool expected, std::uint64_t bytes) {
            test_value = value; test_success = success;
            std::uint64_t result = 123;
            bool ok = rpcs3::ios::available_capacity_for_import("/tmp", result);
            expect(ok == expected && result == bytes, "Apple query result");
        };
        run(@43000000000LL, YES, true, 43000000000ULL);
        expect(correct_key && correct_path, "important capacity queried on destination volume");
        run(@0, YES, true, 0);
        run(@(-1), YES, false, 123);
        run(nil, YES, false, 123);
        run(@"43000000000", YES, false, 123);
        run(@43000000000LL, NO, false, 123);
        run(@(1LL << 40), YES, true, 1ULL << 40);
        run(@18446744073709551615ULL, YES, false, 123);
        method_setImplementation(method, original);
        std::cout << checks << " Apple API checks, " << failures << " failures\n";
        return failures ? 1 : 0;
    }
}
"""


def compile_run(source, directory, name, objc=False):
    path = directory / (name + (".mm" if objc else ".cpp"))
    path.write_text(source)
    executable = directory / name
    command = ["xcrun", "clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror"]
    if objc:
        command += ["-fno-objc-arc", "-framework", "Foundation"]
    subprocess.run(command + [str(path), "-o", str(executable)], check=True)
    return subprocess.run([str(executable)], capture_output=True, text=True), path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--patched", required=True, type=Path)
    parser.add_argument("--platform", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rpcs3-storage-tests-") as temporary:
        directory = Path(temporary)
        patched, _ = compile_run(PREFLIGHT_PREFIX + preflight(args.patched.read_text())
                                 + PREFLIGHT_SUFFIX, directory, "preflight")
        print(patched.stdout, end="")
        if patched.returncode:
            raise RuntimeError(patched.stderr)
        baseline, _ = compile_run(PREFLIGHT_PREFIX + preflight(args.baseline.read_text())
                                  + PREFLIGHT_SUFFIX, directory, "baseline")
        if baseline.returncode == 0:
            raise RuntimeError("Unchanged preflight unexpectedly passes the regression checks")
        print("Negative control:", baseline.stdout.strip())
        apple, apple_source = compile_run(APPLE_PREFIX
            + platform_helper(args.platform.read_text()) + APPLE_SUFFIX,
            directory, "apple_capacity", objc=True)
        print(apple.stdout, end="")
        if apple.returncode:
            raise RuntimeError(apple.stderr)
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
        subprocess.run(["xcrun", "clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror",
                        "-fno-objc-arc", "-fsyntax-only", "-isysroot", sdk, "-arch", "arm64",
                        "-miphoneos-version-min=16.0", str(apple_source)], check=True)
        print("Production Apple capacity helper compiles for iOS arm64 / minimum iOS 16")
        print(json.dumps({"preflight_passed": 13, "apple_api_passed": 9,
                          "old_preflight_rejected": True,
                          "ios_arm64_syntax": "passed",
                          "scope": "production decision/query bodies with explicit adapters; no device import"}))


if __name__ == "__main__":
    main()
