# RetroArch PS2 Test

This unsigned IPA enables experimental ARMSX2 boot. A successful build proves
compilation and packaging only. Graphics, audio, input, saves and sustained
gameplay have not been validated on an iPhone or iPad.

## Signing gate

Use only a replacement artifact whose workflow passed **both** variants and
whose source includes `0004-exclusive-code-arena.patch`. The October 16 artifact
from run 38903866768 predates this correction and must not be installed.

1. Confirm the device runs iOS/iPadOS **17.4 or later**. Extract the replacement
   artifact and retain `build-manifest.json`. Compare the unsigned IPA's SHA-256
   with `ipa_sha256` in that manifest (PowerShell:
   `Get-FileHash .\RetroArch-PS2-Test-unsigned.ipa -Algorithm SHA256`). Signing
   changes the IPA, so this checksum applies before signing.
2. Use the existing Sideloadly/Apple signing setup, selecting only
   `RetroArch-PS2-Test-unsigned.ipa`. Review its bundle ID before starting:
   **`com.jamespauley.retroarchlab.ps2test`**, display name **RetroArch PS2 Test**.
   Do not select the normal Lab IPA or change the identifier to its identifier.
   If the signer requires an identifier change, stop and resolve that before
   installation. Do not inject tweaks, restore an app backup, or reuse Lab's
   entitlements. A manually managed profile must cover this test App ID and the
   test device, with iCloud and shared app groups disabled.
3. Where the signing tool exposes the signed app/profile, verify that
   `application-identifier` ends in `.com.jamespauley.retroarchlab.ps2test`.
   The signed app must have no `com.apple.developer.icloud-*`,
   `com.apple.developer.ubiquity-*`, or `com.apple.security.application-groups`
   entitlements. On a Mac, inspect with
   `codesign --display --entitlements - --xml Payload/RetroArch.app` and check
   the signature with `codesign --verify --deep --strict Payload/RetroArch.app`.
   Automated unsigned-package checks do not verify a later signing tool's output.
4. Install only after the identity checks pass. Keep the working RetroArch Lab
   installed. Confirm **two separate app icons** and that the test app's core
   list contains only ARMSX2. If installation offers to replace Lab, cancel.
   Verify the working Lab still opens with its existing six-core list.

Signing references: [Sideloadly](https://sideloadly.io/),
[Apple provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

## Prepare the isolated app

1. Extract `ARMSX2-system-files.zip` from the same replacement artifact.
2. Do not import the normal Lab configuration, playlists, save states or memory
   cards. Leave all test paths in this app's local sandbox. Do not point any
   directory at the normal Lab or its iCloud container, or grant the test app
   open-in-place access to those files. Use only independent test copies.

3. Launch once. In **Settings > Directory > System/BIOS**, note this app's system
   directory. Extract the system-files ZIP there, preserving the `pcsx2` folder.
   The result must include `pcsx2/resources/fonts/Roboto-Regular.ttf`.
4. Copy your own PS2 BIOS (never move the original) into `pcsx2/bios` beneath that system directory. BIOS
   files and games are not included. Close and relaunch after copying the BIOS.
5. Enable JIT for **RetroArch PS2 Test** with your existing device setup before
   starting the core. Enabling it for the normal Lab app does not enable it for
   this separate process. This bridge requires a frontend RWX or dual-map arena;
   unsupported allocation modes produce an error before emulator startup.
6. Enable **Settings > Logging > Logging Verbosity** and **Log to File** before
   the first boot. Note the log location under **Settings > Directory > Logs**.

## First test: BIOS

Choose **Load Core > Sony - PlayStation 2 (ARMSX2 Lab Test)**, then **Start Core**
without loading a game. Use the default renderer and 1x resolution. The expected
log message before boot is:

```text
ARMSX2 Lab device test: experimental boot; JIT execute/patch test passed.
```

This checks executing a small ARM64 function, changing it through the writable
mapping, and observing the changed result through the executable mapping. It
does not prove the emulator's complete recompiler works. Invalid executable
permissions can crash the process during this check; capture the device crash
report if that happens.

Record whether the BIOS menu appears, responds to controls, and has sound.
Close content, start it again, and test reset. A boot error should be reported
instead of leaving an unexplained black screen. If the app exits or stays blank,
save the log and crash report before retrying.

## Then test one game

Copy one of your own game images into the test sandbox and load that copy at 1x. Check picture orientation and colors,
controls, audio, pause/resume, reset, and an in-game memory-card save. Quit the
app, re-enable JIT if needed, reopen, and confirm the save loads. Keep test saves
inside this app; do not replace existing Play! memory cards.

Report the device model, iOS version, JIT method, build commit from
`build-manifest.json`, BIOS region, game/title ID, first failing step, and logs.
Frame pacing and Metal CPU readback performance remain development work.

## Record device results separately

| Check | Evidence to record | Initial status |
| --- | --- | --- |
| Installation/isolation | Two apps; exact test ID; one core; private local paths | Pending |
| JIT | Execute/patch message, then VM boot; log or crash report | Pending |
| BIOS | Region, visible menu, reset and close/reopen | Pending |
| Graphics | Orientation, colors, PAL/NTSC aspect and sustained frames | Pending |
| Audio | Sound, distortion/dropouts, pause/resume | Pending |
| Controller | Buttons, sticks, menu and in-game input | Pending |
| Memory card | New test-only save, quit, relaunch/JIT, successful reload | Pending |

The native tests exercise the actual Darwin borrow/return functions and the
memory-reset portion of VM reset with stubbed data resets. They do not execute
the whole VM or ARM64 JIT on the device. Metal remains a fixed 640x448 CPU
readback baseline; record PAL/aspect behavior separately from allocation bugs.
Do not transfer test saves back into the working Lab during these checks.
