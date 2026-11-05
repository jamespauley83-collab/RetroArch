# Device validation — build 11

Validation date: November 5, 2026. All tests used a physical iPhone and locally
built software. The iPad's development build 8 and its data were unchanged.

## PS2 interpreter

The new ARMSX2 binary booted the user's existing BIOS copy inside a separate QA
app. The app claimed no debugger entitlement and no debugger was attached.

- 600 paced run calls.
- 420 nonempty video frames at 640 × 448; 339 frames had colored RGB pixels.
- 366,720 stereo audio frames.
- Zero executable-memory requests.
- Runtime reported code generation, EE/IOP/VU0/VU1 recompilers, fastmem and MTVU
  all disabled.
- The captured frame was visually checked and showed the actual PS2 BIOS
  startup animation.

Scope: BIOS startup, rendering and audio. Commercial-game compatibility and
performance were not established. QA memory cards and BIOS NVRAM stayed in the
separate QA container.

## Dolphin interpreter

The unchanged Dolphin framework from the build-11 archive executed an authored
320-byte GameCube DOL in the separate QA app, without a debugger entitlement or
attached debugger.

- Runtime explicitly reported CPU Core: Interpreter and Fastmem enabled: No.
- DSP HLE was enabled; DSP JIT and the fastmem arena were disabled.
- Expected emulated RAM marker `0x52414c42` appeared.
- The test program's RAM counter advanced to 319,708,205 with 109 independently
  observed changes.
- 120 run calls completed; audio callbacks reported 63,552 frames.
- Zero nonzero executable-memory requests; one zero-byte availability probe.
- The final run unloaded cleanly.

Scope: actual PowerPC instruction execution using the Null renderer. This test
does not validate hardware graphics, audible output or commercial games.
An initial harness-only renderer-initialization error was fixed before the
successful run; the shipped Dolphin binary was not modified.

## Native app and PS3

The complete build-11 app was installed on the iPhone with its legitimate
memory entitlements and no debugger entitlement. A separate XCTest runner
launched it as an external installed app, not as its debug target.

The focused test passed: **one test, zero failures, 8.978 seconds**.

- Native library, Game Mode, Performance and PS3 controls were present.
- JIT setup controls were absent.
- The native PS3 screen opened.
- Start PS3 initialized the new interpreter-only native core.
- Import became enabled; status showed Interpreter and Firmware, and the PS3
  games table was present.

The first automation attempt encountered Apple's Games overlay intercepting
the tap. The runner was adjusted to dismiss/wait for that observed system
overlay. No app code change was needed.

Scope: native UI and PS3 core initialization. Firmware import, PS3 game boot,
game compatibility and performance remain unverified.

## Signing and distribution scope

The device app signatures omitted `get-task-allow`; the development profiles
permitted it, but the apps did not claim it. These tests establish execution
without debugger access, not a completed TestFlight installation.

The host and packaged core binaries passed the checked private API/import
audits. The archive passed deep strict code-signature verification and includes
all required frameworks.

App Store export/upload is still pending Xcode Apple Account sign-in. No
TestFlight delivery success is claimed in this validation record.
