# Validation — PS3 playback candidate 13

Date: November 6, 2026. Candidate version: **1.22.2 (13)**.
Status: native/host validation passed. The earlier build-12 signed archive and
App Store Connect export completed, but Apple rejected its upload because build
12 was already used. Build 13 reuses the same validated source and compiled
host/core. Its signed archive and export completed, upload succeeded, and an
in-place development installation was verified as 1.22.2 (13). Apple reported
processing at upload completion. TestFlight availability and publication of the
saved tester notes remain unverified. Physical gameplay has not been launched.

## Original build-11 observations

The submitted approximately 90-second iPad performance recording was captured
on build 11 during native PS3 emulation. Its final 14 playing samples averaged
**28.39 FPS**, with a minimum of **24.59 FPS**. Peak recorded process CPU usage
was **595.76%**, where 100% means one logical CPU. Thermal state remained
`nominal` and Low Power Mode was off.

These are renderer-presentation and process-load measurements, not a measurement
of emulated clock speed or proof of a specific CPU/GPU bottleneck. The recording
did not collect native PS3 audio underrun or producer-queue counters. Its empty
libretro audio fields therefore cannot establish clean PS3 audio.

A separately inspected guest TTY log contained **24,936 repeated headset lines
out of 25,007 lines**. This establishes substantial repeated guest output and
supports investigating false microphone attachment. TTY output is separate from
the native logger's retained startup messages; those counts must not be treated
as a native memory-retention measurement. Neither observation proves that these
patches alone will restore full-speed gameplay.

## Focused native verification

| Check | Result and scope |
| --- | --- |
| Microphone attachment | 31 behavior checks passed against the patched production function and registration lookup. The original stub failed 22 of those checks. Includes empty/registered/unregistered slots, invalid indices and preserved pre-initialization behavior. Context is stubbed; no microphone hardware test. |
| Logger initialization | Production-source harness passed startup replay, notice/warning/error forwarding, idempotence and 20,000 concurrent messages without startup retention or duplicate runtime delivery. The original initialization block failed its negative control. Uses the explicit OS/format/mutex adapters described in README. |
| Complete modified native translation units | `cellMic.cpp` and `RPCS3IOS.cpp` both compiled as arm64 iOS Release code using the build-11 settings, minimum iOS 16.0 and SDK 27.2. Original source, objects and dependency files were preserved. |
| Native link | The two replacement objects linked successfully with cached build-11 dependencies. The emulator static archive retained 520 unchanged members. No hosted build was requested. |
| Integrated host | Compiled and linked locally. All 12 focused tests passed with zero failures on the existing iPhone 17 / iOS 27.2 simulator using the integrated repository source. Covers recorder/HUD/log behavior; this is not physical gameplay acceptance. |
| Build-13 archive/export/upload | Signed archive and `app-store-connect` export completed. Export and upload both exited 0; upload output reported `Upload succeeded` and `Uploaded package is processing`. This establishes upload acceptance; TestFlight availability remains unverified. |
| Build-13 development installation | In-place installation exited 0. A subsequent installed-app query reported version 1.22.2, build 13. The app has not been launched for gameplay validation. |
| Data preservation | All 6,126 Documents inventory entries remained present with unchanged sizes. All 43 backed-up save/configuration files matched their earlier SHA-256 hashes. No other app was added or removed, and only this app's installed build version changed. |
| Superseded build-12 archive/export | Signed archive assembled and `app-store-connect` export completed with exit code 0 and `EXPORT SUCCEEDED`. Apple subsequently rejected the upload because build 12 was already used. No build-12 delivery is claimed from this work. |

The focused runtime checks were also rerun from the portable scripts in this
package. No full emulator rebuild or extra broad test suite was required.

## Candidate artifact identity

Hashes identify the local binaries **before final distribution signing**.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Native RPCS3 core | 48,549,944 | `9d1c5feceae24bbd4f3a870916002972fb62f5a86b818583b0fc49d8942a5167` |
| `RPCS3IOS.cpp` object | 1,007,096 | `b6e5784b780e3dce81999a1692bb83bd5a1a9def333f73b1971516badc63a296` |
| `cellMic.cpp` object | 131,584 | `b384a32d26657b6d0e1829e37ca0871027f5cb64b0b65f6765ff692e16a3a439` |
| Host executable | 16,882,544 | `d5142c26239266c58de8f9c1ac55a74f9147537eb076f3aea0ddd14d7a838f5b` |

## Build-13 export identity

The App Store Connect export is **55,109,223 bytes** with SHA-256
`b45b8a7142f8dc686178a11ea53fc28691cb441db939a17f7e64f1016ed3bbf0`.
Its embedded metadata confirms **1.22.2 (13)**. This exported package was uploaded
successfully. The separately signed development package was installed in place
for subsequent hardware validation.

## Superseded build-12 export identity

The earlier local App Store Connect export is **55,109,228 bytes** with
SHA-256 `cf3fb8fbe8dcb03aa5fc4f9d9b9124c6bfc239cbbe7c6f4b50722432ca50c3be`.
Its embedded metadata confirms **1.22.2 (12)**. Apple rejected this upload because
that build number was already used. These are historical export identifiers,
not the identity of the uploaded build-13 package. The pre-signing host/core hashes
above remain applicable because the compiled code is unchanged.

## Remaining acceptance

Physical gameplay, reduced headset retries on hardware, gameplay FPS and audible
output still require validation. Repeat the same two-minute game section with
the same settings and export both the performance JSONL and native PS3 log to
measure the effect. Interpreter execution remains in place. TestFlight
availability and publication of the tester notes require separate confirmation;
the successful upload is not evidence that testers can already obtain the build.
Build-specific tester instructions are saved in [WHAT_TO_TEST.txt](WHAT_TO_TEST.txt).
