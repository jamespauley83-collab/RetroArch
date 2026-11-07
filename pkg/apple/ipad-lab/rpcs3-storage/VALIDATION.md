# Release validation — storage correction, build 14

Date: November 7, 2026. Version: **1.22.2 (14)**.

## Result

The corrected app is installed in place on the iPhone. Its installed-app
metadata confirms version 1.22.2, build 14. App Store Connect accepted the upload
and reported that processing had begun at 2026-11-07T21:35:48.886448+00:00. TestFlight
availability and publication of the saved tester notes remain unverified.
The Browser connector lacked the originating authenticated browser context;
a separate altool status request lacked its required authentication. Neither
limitation was bypassed. The existing Xcode account completed export and upload.

The initial external-app launch check stopped at Xcode's device preflight:
"Unlock Dad phone to Continue." It was cancelled without running the test. A
later unlocked-device follow-up verified the imported ISO, installed the missing
firmware and reached the game's title screen. The iPad remains on build 13.

## Firmware follow-up and actual game boot

The follow-up on November 7 confirmed build 14 and the imported **50 Cent: Blood
On The Sand**, **BLUS30256**, with a **6,709,772,288-byte** `disc.iso`. The user's
screenshot also showed the game in the library. The new error was "Firmware is
missing." The app's firmware directories were empty in both the pre-update and
follow-up inventories; the update had not removed installed firmware.

Installed the user's existing **PS3 4.93** recovery PUP through the app's
**Import → Firmware (.PUP)** flow. Its MD5,
`a2b60b6ac1d2e49e230144345616927c`, matches the checksum embedded in the download
URL linked from [Sony's official PS3 system-software page](https://www.playstation.com/en-us/support/hardware/ps3/system-software/).
The original Mac copy was retained. Firmware verification found **1,075 files**,
**195,078,808 bytes**, and `release:04.9300:` in `dev_flash/vsh/etc/version.txt`.
All **7** imported game files retained their sizes and modification times across
firmware installation. This is a check of those game files, not a fresh inventory
of every save or the iCloud source.

The first boot probe exceeded its **180-second** timeout while the app still
reported initialization and first-time shader compilation. That probe failed
its timeout; it did not report a firmware or emulator failure. A later check
reported **"Game running"**, and visual inspection of its captured screenshot
confirmed the game's **"Press START button" title screen**. The native log showed
shader compilation and audio frame delivery. Audible output and audio quality
were not observed.

A final UI check successfully paused the game at **2026-11-07T22:03:30Z**. Its
screenshot showed **Paused**, **Resume**, and the same title screen. Firmware
import, follow-up log capture and pause checks each passed. The game was left
paused for the user. No additional production app build was needed, and no
firmware or game content is included in this repository.

Local evidence under the retained build directory includes
`iphone-firmware-verification.json`, `FirmwareImport3.xcresult`,
`FirmwareGameBoot.xcresult` (the timed-out probe), `StartupLog.xcresult`,
`PausedTitle.xcresult`, and their logs/screenshots. This verifies import completion
and boot to the title screen. It does not establish the exact original storage
discrepancy, actual storage reclamation, level gameplay or sustained performance.

## Build and package checks

- Full native core rebuilt locally from pinned XITRIX/rpcs3 revision
  `f88bff947b83730c0cf8a3949f59338b992b3ca0`. Interpreter, playback and storage patches were
  applied and verified against the built tree. LLVM/JIT remain disabled.
- Complete current TestFlight host compiled and linked with Xcode 27.2.
- MoltenVK 1.4.2 and FFmpeg 8.1.1 downloads matched the recorded SHA-256 hashes.
- The package retains all eight emulator backends and MoltenVK. Its app identity,
  established resources and existing interpreter behavior are preserved.
- The native binary contains the new capacity API import and storage diagnostic.
- Architecture/private-debugger import checks and deep strict signatures passed.
- The exported IPA contains the new disk-space privacy declaration and build 14.
- App Store Connect export and upload both exited 0; the upload log reports
  "Upload succeeded" and "Uploaded package is processing."
- No hosted build was requested. Source/record commits use `[skip ci]`.

The focused source harness results remain: 13 preflight checks and 9 Foundation
helper checks passed, with 7 failures from the unchanged preflight negative
control. Their adapters and limits are described in [README](README.md).
The initial device-launch runner compiled, but the locked phone prevented that
first check from running. The later device checks are recorded above.

## In-place data verification

Before installation, the app's configuration and metadata were copied to a
recovery directory. Its local save/state directories were empty. After the
installation, all **44,038** Documents inventory entries remained present with
unchanged sizes and file/directory types. All **7** copied configuration/metadata
files matched their earlier SHA-256 hashes. This verification covers the current
app's local container; it does not claim a complete backup of iCloud Drive.
No source ISO or other app data was removed.

## Artifact identity

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Unsigned host | 16885088 | `c49f41ce18f22fdd0889eb49418dc23d63e5a0a807486e8bd031f571b8b19443` |
| Unsigned native core | 47288760 | `b5313c47d0fce7c3560fe43699fd9eb88cdad0f93e2a2a730220d04fe2390255` |
| App Store Connect export | 54988845 | `79a81ace8e2f6c905f039ed3a45b3c3219964c6fb01685b62b8b667b7a12e03d` |

The native and host binaries were built from source commit `71543962a8686e622129f9371d20aa11f2d76022`.
The [machine-readable record](build-14.json) includes patch and dependency hashes.
Build logs, source/dependency caches, archive, exported IPA and recovery copies
are retained under `/Users/jamespauley/Developer/RetroArch-Storage-Build-20261107`.

## Remaining acceptance

Hands-on gameplay, controller input, audible sound, sustained performance and
save/relaunch behavior remain unverified. A real shortage/recovery scenario and
actual iOS storage reclamation have not been exercised. The raw filesystem and
important-usage readings from the original failure were not captured, so the
precise original capacity discrepancy remains an inference. These limits do not
change the observed successful import and firmware recovery on the iPhone.
