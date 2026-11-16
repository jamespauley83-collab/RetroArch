# PS3 JIT handoff correction — build 16

Date: November 8, 2026 (America/New_York). Version: **1.22.2 (16)**.
Built host source: local commit `b2fdae168708e71a59a3a5815f33b07ed84f47e9`.
Published source: `371134a869936d42e888b0a0c1f33125600b774d`. Both have the identical
Git tree `3429883de2b8b8685b949e4f8da3e3216a71a7d4`; publication through the connected
GitHub account preserves every source file.

## Reproduced failure and controlled comparison

The installed build-15 button sent both the bundle identifier and the current
process ID to StikDebug. The iPad test completed **Enable and Run Script**,
returned to RetroArch Lab, then reproduced the owner's exact **Universal JIT
handshake did not complete** message. Import stayed disabled. That test failed
after 73.566 seconds. Xcode subsequently stalled while collecting results; its
completed-test log was retained and that collection process was cancelled.

A second test used the same installed app and native core, but invoked
StikDebug with the bundle identifier and `universal.js`, without the PID.
StikDebug relaunched the app. The Universal probe, native initialization and
LLVM execution self-test all passed: Import became enabled and the status read
**Firmware 4.93 · 1 games · Connect a controller for analog sticks.**
This controlled test passed in 10.721 seconds.

This repeats the launch-versus-attach distinction already recorded for the
working iPad build in `../rpcs3/VALIDATION-2026-10-28.md`. It establishes this
app/device's observed behavior; it is not a claim that current-PID attachment
fails in every StikDebug integration.

## Correction and local checks

- The PS3 button restores the demonstrated StikDebug launch URL without `pid`.
- The existing entitlement checks, activation lease, Universal probe and LLVM
  execution self-test remain required.
- Before handing off, an active performance recording synchronously drains its
  queued events, writes an end row with reason `jit_relaunch`, flushes and closes.
  A user can start a new recording after StikDebug returns.
- Two focused simulator checks passed: handoff recording preservation and
  recording-stop behavior with the live overlay enabled.
- The complete production host compiled and linked successfully with the
  established development flags. Independent source review found no blockers.
- Packaging and deep strict signature verification passed. The eight existing
  libretro cores and native RPCS3 remain included.
- The native core was reused from build 15. Its unsigned input SHA-256 and
  executable `__TEXT,__text` section match; its new code signature differs.
- Current recovery copies from both devices retain PPU and SPU
  **Recompiler (LLVM)** selections. No decoder settings were changed.

## Installed devices and recovery verification

Build 16 was installed in place under the established
`com.jamespauley.retroarchlab.ps3bridge` identity on both the M3 iPad Air and
iPhone 17 Pro Max. Fresh application inventories confirm version and build.
No app was uninstalled. Recovery copies were taken before installation.

| Device | Before/after Documents entries | Save/configuration hashes |
| --- | --- | --- |
| iPhone | 45,573 / 45,573; all recorded paths, sizes and types match | 21 of 21 match |
| iPad | 6,139 / 6,140; runtime changes described below | 76 of 78 match; two saves changed before installation |

The iPad backup was not a quiescent snapshot. Its initial inventory was taken
at **12:22:27 UTC**, and copying continued through **12:24:45 UTC**. Two PS3
`PAYLOAD` saves changed at **12:22:56** and **12:22:58 UTC**. Native game data,
shader cache and log modifications occurred at **12:23 UTC**. Installation
started later, at **12:25:09 UTC**, and completed at **12:25:26 UTC**.

The post-install inventory also omits an Unreal Engine `___LOCK` file; its
parent directory's modification time is 12:23:45 UTC, before installation.
Both the original and newer save copies are retained. Neither copy was restored
over the device. These timestamps and game-related file changes are consistent
with game activity during the backup. This is not a claim that all iPad data
was byte-for-byte identical across the full backup window.

iOS-managed launch snapshots are excluded from save/configuration hash counts,
as in the build-15 verification. Game/firmware inventory checks are not a full
content hash of every game and firmware file.

## Installed build-16 runtime acceptance

The actual **Enable PS3 JIT → Enable and Run Script → Start PS3** flow passed
on both physical devices after they were unlocked:

| Device | Actual-button test | Result |
| --- | --- | --- |
| iPhone 17 Pro Max | 17.172 seconds | Universal probe, core initialization and LLVM execution self-test passed |
| M3 iPad Air | 18.099 seconds | Universal probe, core initialization and LLVM execution self-test passed |

Both reported **Firmware 4.93 · 1 games · Connect a controller for analog
sticks.** Import became enabled. The real native LLVM check returns 22 for
input 5 before the host enables the library.

The first build-16 iPad attempt waited at the device lock, then failed before
reaching the JIT screen. A subsequent inspection found the app at the native
game library. The acceptance fixture now explicitly terminates its external
app before launching, establishing the fresh process needed for this startup
test. That repeat passed without a production-code change. The earlier failed
run and diagnostic inspection are retained rather than counted as successes.

The separate iPad startup-state test passed in **37.157 seconds**: the host
reported **Game running. Save in the game before stopping.**, accepted Pause,
and then reported **Paused.** The app was left paused. The immediately captured
running screenshot has a black render area, so this verifies the running/pause
transitions, not visible gameplay or a completed title-screen presentation.

The iPhone startup-state test reached its 600-second wait limit and failed
in **603.323 seconds** while the same app process was still compiling:
**Compiling PPU Modules... | Files 76 of 76 | Modules 166 of 203**.
A read-only cache query at **12:46:09 UTC** found 77 additional completed objects
(13,946,081 bytes) since 12:38:57, with the newest object written at 12:46:06,
after the test timed out at 12:45:47. The process was left running to preserve
this progress. This is an observer timeout during active compilation; iPhone
running/pause acceptance remains incomplete. It is not counted as a passed
game-boot test. Xcode stalled while collecting the completed timeout result;
the collector was stopped after preserving the test log. The device app was
not terminated.

Audible audio, rendered gameplay and sustained gameplay performance have not
been verified in these build-16 checks. No FPS improvement is claimed.

## Artifacts and cost

`build-16.json` records the package identities. The build, focused test result,
signed package, before/after device recovery copies and runtime logs are retained
under `/Users/jamespauley/Developer/RetroArch-JIT-Build-20261108` on the build Mac.
The build-16 device records are in its `handshake-build16` subdirectory.

All compilation and verification ran locally. No GitHub Actions build was
requested. Publication commits include `[skip ci]`. This remains a development
JIT installation; the interpreter TestFlight package is a different execution
configuration.
