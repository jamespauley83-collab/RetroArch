# PS3 bridge validation — October 28, 2026

Installed runtime source: `28fac067ee5010d67c2fda6b82c381057e82bf36` on
`codex/ipad-lab-rpcs3-bridge`, build 3, based on Lab's `45cd6246` built-in-JIT
branch. The initial build/test baseline below was `0c5244a`; the device follow-up
records validation of the JIT handoff and asynchronous startup corrections.

## Completed

- Full ARM64 iOS Release build: Xcode 27.1, SDK 27.1, minimum iOS 26.0.
- Full ARM64 simulator Release build.
- 66 existing Lab Python tests passed.
- Six new packaging tests passed on Linux and macOS.
- Compiled C89-compatible API harness passed: ABI 29/31 and every missing
  required export fail atomically; ABI 30 resolves successfully.
- Ten native simulator lifecycle tests passed against the actual controller
  with a fake ABI: enumeration copies callback data, duplicate boot, missing
  Universal, stop during boot, failed stop/retry, background pause and explicit
  resume, asynchronous startup, background pause after asynchronous startup,
  pause failure and startup failure reporting. These do not run RPCS3 or
  validate PS3 sound, graphics, or speed.
- Full RetroArch UI simulator test passed: native library → PS3 → Start PS3 →
  recoverable missing-Universal message. This caught and fixed native-library
  presentation before the root view was visible under the current SDK.
- Native Lab Objective-C checks passed.
- Packager accepted the exact existing XITRIX 0.12 ARMv8.4-A IPA and core hashes.
  The candidate's host executable matches the final native build.

Installed native host SHA-256 before development signing:
`826c35852dc588d57040467845f17f4ecead18ec8d1b92a975258a826b4e668b`

XITRIX core SHA-256 (before development signing):
`64c942bc435d82627f7ad223ed091be76e1e2ba112c7f95d3596e68c31188237`

## Deployment status

**Build 3 is signed and installed on the M3 iPad Air. JIT, firmware/game import,
game startup, presentation, touch Start and the real-core lifecycle test passed.
Full gameplay, sound, physical controllers and in-game save/reload acceptance
remain pending.**

After the user completed Xcode sign-in, automatic provisioning issued a profile
for `com.jamespauley.retroarchlab.ps3bridge`, expiring October 28, 2027. Its
development debugging, Extended Virtual Addressing, Increased Memory Limit,
Sustained Execution, certificate and iPad registration were checked. Embedded
code was signed before the host; strict recursive signature verification passed.

Physical testing found that attaching to an already-running candidate returned
StikDebug `E96`, followed by `NotConnected`. Asking StikDebug to launch the
candidate with `universal.js` instead succeeded. Build 2 implements that path.
The corrected ARM64 device build and 65 native library checks passed. The
committed `testDeviceJITHandoffInitializesCore` then passed on the actual iPad
using the installed build: native library → PS3 → Enable PS3 JIT → StikDebug
confirmation → relaunched bridge → Start PS3 → enabled Import and firmware/game
enumeration. This necessarily passed the core's LLVM test (input 5, result 22).
The same device test passed again after restarting the candidate during file
browser diagnosis (`ipad-jit-after-files.log`).

The first real boot rendered the core's shader-compilation and PPU-compilation
screens through Metal. It exposed a host lifecycle error: the boot request
returns before emulation reaches RUNNING, so Pause was enabled too early and
returned INVALID_STATE. Build 3 polls the core state on the serialized queue,
keeps Pause disabled during startup, defers background pause until RUNNING,
and retains the correct control label after pause failure. Startup failure
messages survive cleanup. The Metal surface now fills the available play area.
All ten native lifecycle tests, 65 native library checks and the full ARM64
device build passed for this correction. Stopping during compilation passed on
the device before updating the candidate; the game and firmware were retained.
The committed StikDebug/core initialization test passed on installed build 3
(`ipad-jit-build3.log`), and all four original app records still matched the
pre-install inventory (`ipad-apps-build3.json`).

The real-core `testDeviceReadyGameLifecycle` passed on build 3 (155.571 seconds):
startup reached RUNNING, explicit pause/resume worked, leaving the app paused
the core without automatically resuming, rotation completed, stop restored the
game library, and a second boot reached RUNNING and paused successfully. The
test captured portrait and landscape frames. The landscape frame showed the
game's own required-data installation screen. These checks validate lifecycle
and presentation, not sound, physical controllers or in-game save reload.
The earlier eight-minute diagnostic budget expired while PPU compilation was
still progressing (157/191 remaining modules); the final test continued that
startup with a longer budget. It did not report an emulator startup error.
After the final reboot, the game completed its required-data installation and
displayed its Press START screen. Pressing the bridge's touch Start control
opened the game's main menu, confirming game presentation and digital input.
The captured evidence is in `game-content-screenshot` and
`touch-start-screenshot`; this is not a claim of level gameplay or save reload.

The initial physical navigation test runner exited unexpectedly; subsequent
device inspection confirmed navigation and recoverable missing-JIT behavior.
Diagnostic test cases that only captured UI state are not counted as successful
JIT tests. The committed end-to-end device test is the initialization evidence.

All four original RPCS3/Lab app records, including their installed bundle URLs,
were unchanged after the isolated installation. No firmware, game, save,
configuration or pairing file was written to a working app's container. A copy
of the existing Mac firmware PUP was staged in the candidate's Documents folder
and imported through the bridge. The native callback completed and the UI
reported `Firmware 4.93 · 0 games`; `ipad-firmware-import2.log` records the passing
assertion. The native ISO importer then copied the selected decrypted
`50 Cent - Blood on the Sand (USA) (En,Fr).dec.iso` from the standalone app via
the system picker into the candidate's own `Data/games/DiscImages/BLUS30256`.
`ipad-game-import.log` records the passing `Firmware 4.93 · 1 games` assertion.
The standalone games-directory entries and metadata matched before/after
(`standalone-games-before.json` and `standalone-games-after.json`). The source
was opened for reading; no source save or configuration was imported or changed.
Full graphics/audio/controller/save/reload acceptance remains pending. The
standalone gameplay result remains the baseline.

The import sheet presented Apple's document picker, but its Recents view stayed
blank and accessibility queries timed out. The device recorded a scene-update
watchdog termination of `com.apple.DocumentManager.Service` at 20:20:14 EDT,
October 28. Files itself initially displayed an empty view and responded after
being reopened. A fresh picker subsequently loaded its locations and completed
the firmware import; no speculative runtime workaround was added. Diagnostic
evidence is in `ipad-picker-snapshot.log`, `ipad-files-refresh.log`, and
`document-picker-crash.ips` on the Mac.

## Mac handoff

Work directory:
`/Users/jamespauley/Developer/RetroArch-PS3-Bridge-20261028`

Signed installed candidate:
`signed-candidate-28fac06/Payload/RetroArch.app`

Initial logs: `build-final.log`, `simulator-build2.log`, `tests-final.log`,
`ui-tests2.log`, `native-checks.log`, and `package.log`. Device follow-up:
`signing-after-login.log`, `build-jit-launch.log`,
`native-checks-jit-launch.log`, `ipad-install-a6a48ff.json`, and
`ipad-jit-final-test.log`. The final device result bundle is under
`PhysicalTestDerivedData/Logs/Test/Test-LabUITests-2026.10.28_20-15-30--0400.xcresult`.
Build 3 logs: `build-async-boot.log`, `tests-async-boot.log`,
`native-checks-async-boot.log`, `ipad-install-28fac06.json`, and
`ipad-stop-compilation.log` (the pre-update stop test).
The passing final game lifecycle result is
`PhysicalTestDerivedData/Logs/Test/Test-LabUITests-2026.10.28_20-44-28--0400.xcresult`,
with `ipad-final-game-lifecycle.log` and `final-lifecycle-screenshots` beside it
under the work directory. The ready-game test can continue an in-progress
startup so first compilation need not be discarded after a short diagnostic.
The source worktree is `source`; `signing-template` is scoped to the candidate.
The accepted standalone download/signing directory and all previous Lab source
directories were preserved. No combined binary was published.
