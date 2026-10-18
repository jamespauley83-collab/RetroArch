# Eight-core artifact inspection — October 17, 2026

This is the historical October 17 artifact record. Build 42 and later installed
signing/backup evidence supersede its pending-status statements; see the
[October 18 release assessment](EIGHT-CORE-RELEASE-REVIEW-2026-10-18.md) and
[current device record](EIGHT-CORE-DEVICE-TEST.md). Do not repeat completed tests
from this older snapshot.

## Decision

The original artifact is an unsigned **update** to the working Lab identity.
Do not install it for first combined-core testing. A separately identified
unsigned test copy has been produced and checked locally. Sideloadly reported
installation complete; James reported both apps open and the working library
is intact. A Files visibility defect in that test package was subsequently
confirmed and corrected. PR #12 subsequently records successful installation of the correction,
Saturn gameplay in Lab 8 Test, and ARMSX2 launch recovery after the app-specific
StikDebug `universal.js` retry. Final signed-profile inspection, backup
verification and the remaining combined-app acceptance checks are still pending.
The launch recovery does not validate the later uninstalled JIT source changes.
PR #12 stays draft; see the [current device evidence](EIGHT-CORE-DEVICE-TEST.md#october-18-acceptance-continuation).

## Input and integrity evidence

- PR: <https://github.com/jamespauley83-collab/RetroArch/pull/12>
- Successful run: <https://github.com/jamespauley83-collab/RetroArch/actions/runs/38996899047>
- Artifact: `12088342038`, 337,634,560 bytes; expires 2026-10-31 03:35:23 UTC.
- Branch head for that run: `9ead37ecc076cf110d0773b8ad646481ec169646`.
- Built PR merge revision in the artifact name and manifests:
  `81c576053d24e9eca796089335bb527138bcd967`. These are different Git references;
  identify device results with the built revision and actual package hash.

| Item | Verified SHA-256 |
| --- | --- |
| Downloaded GitHub artifact ZIP; matches GitHub's reported digest | `9fdf5c405879517eed4b9f7df8118be33c15888f23090e9cf11fe0736e603c05` |
| Original unsigned IPA; matches external manifest | `51cc686ef42a15c763028615277ad758bb28ef534d1af01e5ac73947da490028` |
| Initial isolated unsigned IPA; superseded due to hidden Files folder | `6cbfae0b60884b57a4a4ecf68b16f9348ab6a20930f11a3f2a1b6ae96edf53af` |
| Corrected isolated unsigned IPA; Files flags enabled | `ff7605ec654490b81abaad91ea75b199167f831819b12b801184fa6dcc2e4fc7` |

The original IPA passed ZIP CRC checking. Its embedded manifest matches the
external manifest except the expected whole-IPA hash field. All eight final
packaged core hashes match; both system-resource archives match their hashes.
ARMSX2's four supplied patches match their provenance hashes, its source/frontend
revision matches the build manifest, and its stage is `device-test` with gameplay
enabled. The required Roboto font is present. Pinned core/dependency source
archives and licenses are included in the original artifact.

Direct Mach-O inspection confirms the frontend and all eight cores are ARM64,
iPhoneOS, minimum 26.0. The shared MoltenVK framework is ARM64/iPhoneOS with a
13.0 minimum. Core dependencies are system libraries/frameworks; the frontend's
MoltenVK dependency is packaged. The inspected executables have no embedded
entitlement slots. The original app includes a Lab widget, and the outer
artifact supplies Lab iCloud entitlements. It has no device provisioning profile.
Checksums and ad-hoc framework signatures are not Apple device signing or an
independently verified build attestation.

## Inventory and prerequisites

FCEUmm, Snes9x 2010, Opera, Dolphin, Play!, Beetle Saturn, Yabause and ARMSX2 are
present, with core metadata. Yabause is pinned to
`8926b0c6c347f8c5c755911ddb0ac695420ffbf8`; ARMSX2 to
`e58489d349cdcd635fc6264546087e347c84bf8c` plus the four recorded patches.
Yabause's build disables both dynamic recompilers. ARMSX2 requires working JIT
for this app process and accepts RWX/dual-map memory, not WX toggle.

Source inspection confirms Yabause writes its `.srm` in the frontend save
directory and flushes through its own lifecycle. ARMSX2 uses `system/pcsx2` as
its data root, with defaults including `memcards`, `sstates` and `inis`. These
paths require separate test copies and backups; frontend Sync Saves coverage
must not be assumed. See the [device checklist](EIGHT-CORE-DEVICE-TEST.md).

## Derived package and validation limits

`RetroArch-Lab-8-Test-unsigned.ipa` uses
`com.jamespauley.retroarchlab.eightcoretest` and `retroarchlab8test`. The working
widget and document registrations are removed. Both `UIFileSharingEnabled`
and `LSSupportsOpeningDocumentsInPlace` are enabled so the test app's Documents
can appear in Files. This does not grant access to the working cloud container.
Every retained file apart from Info.plist and the embedded manifest was compared
byte-for-byte with the original, including the frontend, all cores and MoltenVK.
The derivative manifest records the original IPA hash and packager source hash.

Nine local safety regression tests pass, covering Files visibility flags,
isolation/preservation,
checksums, missing/extra cores, OS/platform/architecture mismatch, original
identity/provisioning rejection, universal ARM64/entitlement handling, and
refusing to overwrite an existing output directory. Python compilation and
workflow YAML parsing pass. The packager also ran successfully on the actual
downloaded artifact. No new native build was needed for the unchanged binaries;
the new workflow packaging step has not yet executed on GitHub Actions.

The existing successful workflow remains automated build evidence. James's
earlier Need for Speed success applies only to the separate PS2 Test app.

## Device evidence and Files correction

- The Lenovo's Sideloadly reported iPadOS 27.2 and completed installation of
  the initial isolated IPA. Its bundle ID field was explicitly set to the test
  ID, automatic bundle ID was off, custom entitlements and injection were off.
  The signer cache is the unsigned input, not an export of the installed signed
  app; final signed entitlements/profile have not been independently inspected.
- James reported both apps open and his original library is intact. This is
  user-reported launch/coexistence evidence, not a save or iCloud integrity audit.
- James initially reported Yabause gameplay/audio/controls/save-reload passed,
  then reported no test-app folder for copying ROMs. Attribution of that early
  full result remains unresolved. His later report explicitly confirms Saturn
  gameplay in Lab 8 Test; retain that result without inferring restart/save-path
  coverage from the ambiguous earlier report.
- PR #12 records the Files-Fix installation retry completed with **Done, 100%**.
  James later confirmed ARMSX2 runs after the app-specific `universal.js` retry.
  These supersede the earlier installation/gameplay uncertainty, but do not
  establish sustained PS2 play, card persistence, switching or post-update Files
  visibility. No fresh inspection of the installed signed binary is claimed.
- His 08:12 EDT Files screenshot shows RetroArch, RetroArch Lab and RetroArch
  PS2 Test, with no RetroArch Lab 8 Test folder. Direct package inspection found
  `LSSupportsOpeningDocumentsInPlace=false` despite file sharing being enabled.
  The packager now enables both flags and rejects missing/false flags. Apple
  documents the pair as required for exposing Documents through the local file
  provider. Corrected-package Files visibility still needs device confirmation.

Update only the existing eight-core test app with the same signing account and
test bundle ID. Do not uninstall either app. Preserve original library data and
settings; use copies in the new test folder for subsequent tests.

Reference: [Apple file-sharing keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html).

The test copy must receive no cloud/app-group entitlements. Its reused cloud
backend still targets the working Lab container; it is unsuitable for successful
candidate iCloud testing. Preserve working-app sync and use a future dedicated
test-container build for candidate cloud acceptance.
