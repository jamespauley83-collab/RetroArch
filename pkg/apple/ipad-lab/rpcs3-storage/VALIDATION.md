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

The attempted external-app launch check stopped at Xcode's device preflight:
"Unlock Dad phone to Continue." It was cancelled without running the test.
No successful PS3 initialization, ISO import, storage reclamation or game boot
is claimed for this candidate. The iPad remains on build 13.

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
The separate device-launch runner compiled, but the locked phone prevented it
from running.

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

On the unlocked iPhone, open RetroArch Lab, open PS3, start the core if prompted,
and import the same 6.71 GB ISO from iCloud Drive. Confirm the original remains
available and the game appears in the PS3 library. If import fails, export the
PS3 log and retain the new error, which includes ISO size and available capacity.
The diagnostic records selected capacity, its source and raw filesystem bytes.
A successful import still does not establish game compatibility or performance.
