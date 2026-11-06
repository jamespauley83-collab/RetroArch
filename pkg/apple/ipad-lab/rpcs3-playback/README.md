# Native PS3 playback corrections

This package contains two focused native fixes for the **1.22.2 build 13
candidate**. Focused native and host checks passed. App Store Connect rejected
the earlier build-12 upload because that build number was already used; build 13
reuses the same validated code. Its signed archive and export completed, the
upload succeeded, and an in-place development installation was verified as
1.22.2 (13). Apple reported processing at upload completion; TestFlight
availability and publication of the saved tester notes remain unverified.
Physical gameplay has not been run, and no FPS or audio improvement has been
measured.

## Source and application order

Use [XITRIX/rpcs3](https://github.com/XITRIX/rpcs3) at
`f88bff947b83730c0cf8a3949f59338b992b3ca0`, the same native source pinned for
build 11. In a separate clean checkout:

1. Apply `../testflight-interpreters/rpcs3-interpreter-only.patch` first.
2. Apply this directory's `native-core.patch` second.
3. Build the existing iOS native target with `RPCS3_FRONTEND=IOS`,
   `RPCS3_IOS_JITLESS_ONLY=ON` and `WITH_LLVM=OFF`.

Run `git apply --check` before applying each patch. The playback patch changes
only `rpcs3/ios/RPCS3IOS.cpp` and `rpcs3/Emu/Cell/Modules/cellMic.cpp`.
The interpreter restriction, ABI, emulated clock settings, audio buffering and
renderer configuration are unchanged.

## Defects addressed

**Native logger initialization.** The iOS entry point installed a callback
listener without completing the logger's startup phase. Every emitted message
therefore remained in the startup vector and used the global registry mutex.
Calling `logs::set_init({})` after installing the listener flushes startup
messages and ends that retention. The host's separately bounded log console
cannot by itself correct this native accumulation.

**Microphone attachment.** `cellMicIsAttached` reported every slot as attached,
even with no registered microphone. After microphone initialization, it now
uses the existing synchronized, bounds-checked registration lookup. It preserves
the earlier behavior before initialization. This prevents false attachment
reports that can trigger repeated headset-open attempts.

The microphone correction is adapted from
[emelin2004/rpcs3-xbox PR #43](https://github.com/emelin2004/rpcs3-xbox/pull/43),
“cellMic: report a device as attached only when it can be opened,” by
`emelin2004` (head `9fbb7355e6a17a2d3993f6333a6b52749c6bb015`).
That fork's result is not evidence of iPad performance; this package validates
the applied functions separately against the pinned XITRIX source.

## Focused regression checks

Keep an unchanged baseline source copy and a copy with both patches applied.
Pass explicit source paths; generated includes, executables and result files
are created in temporary directories and removed when each command exits.
A C++20 compiler is required; `--cxx` or `CXX` selects it.

```sh
python3 tests/run_native_logger_tests.py \
  --core-root /path/to/baseline-rpcs3 \
  --baseline /path/to/baseline-rpcs3/rpcs3/ios/RPCS3IOS.cpp \
  --patched /path/to/patched-rpcs3/rpcs3/ios/RPCS3IOS.cpp

python3 tests/test_mic_attachment.py \
  --baseline /path/to/baseline-rpcs3/rpcs3/Emu/Cell/Modules/cellMic.cpp \
  --patched /path/to/patched-rpcs3/rpcs3/Emu/Cell/Modules/cellMic.cpp
```

The logger harness extracts the production registry, dispatch, startup buffering,
finalization, native forwarding and initialization block. OS hooks, static
message formatting and the registry mutex have explicit test adapters. The
microphone harness executes the production attachment and registration-check
bodies with a minimal microphone context. Both reject the old implementation
as a negative control. Neither runs a game or tests microphone hardware.

The actual host callbacks were also reviewed for native API/logger reentry;
they use Foundation logging or a separate bounded ring and do not reenter the
native logger during its startup flush. The lifecycle permits one initialization
per process. A message emitted in the narrow listener-install/finalization
interval can be replayed under the existing upstream startup contract; runtime
messages and repeated finalization are covered by the duplicate-delivery checks.

See [VALIDATION.md](VALIDATION.md) and
[native-core-manifest.json](native-core-manifest.json) for observations, candidate
hashes, confirmed upload/installation, and the remaining gameplay and
TestFlight acceptance work.

Build-specific notes for the TestFlight What to Test field are in
[WHAT_TO_TEST.txt](WHAT_TO_TEST.txt). Saving that file does not publish the notes.
