# RetroArch Lab 8 Test — isolated iPad acceptance

Do not install `RetroArch-Lab-unsigned.ipa` from the original eight-core artifact
over the working Lab. It has the same app identity and iCloud configuration.
Use the derived **RetroArch-Lab-8-Test-unsigned.ipa** only after the signing gate
below. No device installation or gameplay is established by packaging tests.

## What this test copy changes

| Property | Working Lab / original candidate | Isolated test copy |
| --- | --- | --- |
| Bundle identifier | `com.jamespauley.retroarchlab` | `com.jamespauley.retroarchlab.eightcoretest` |
| Display name | RetroArch Lab | RetroArch Lab 8 Test |
| URL scheme | `retroarchlab` | `retroarchlab8test` |
| Widget | Included | Omitted to avoid an additional signing identity |
| Cloud access | Lab container when provisioned | Must be signed with no iCloud or app-group access |
| External document registration | Registered file types, open in place | Removed; use copies in the test app's Documents |
| Local Documents in Files | Enabled | Enabled through both file-sharing plist flags |
| Runtime | Eight-core iOS 26 candidate | Same frontend, core and MoltenVK bytes before signing |

The cloud backend remains compiled into these reused binaries. Changing the
bundle ID does **not** retarget it: it still names the working Lab container.
The no-cloud signing requirement is therefore essential. This copy cannot test
successful iCloud sync. Do not supply the working Lab iCloud entitlements.

## Prerequisites and signing gate

1. Record iPad model and exact iPadOS version from **Settings > General > About**.
   This entire eight-core app requires **26.0 or later**, even to use Yabause.
   Do not edit MinimumOSVersion to bypass it. If the device is older, stop and
   use a separately built seven-core candidate without ARMSX2.
2. Preserve the working Lab and PS2 Test installations. Before testing, export a
   dated copy of the working Lab's Documents, configuration, playlists, ordinary
   saves/states, `Play Data Files`, and any existing `system/pcsx2` directory.
   Copy, never move. Preserve the current iCloud settings and cloud files.
   An iCloud folder alone is not a verified backup of every core's save data.
3. Check the test IPA's SHA-256 against `ipa_sha256` in its `build-manifest.json`:

   ```powershell
   Get-FileHash .\RetroArch-Lab-8-Test-unsigned.ipa -Algorithm SHA256
   ```

4. Use the established Sideloadly/Apple signing setup with this test IPA. Confirm
   its final bundle ID remains `com.jamespauley.retroarchlab.eightcoretest` and
   the selected device is the iPad. If automatic signing proposes a different
   identifier, inspect that unique ID before proceeding; do not reuse any
   installed Lab or PS2 Test identity. Do not inject tweaks or restore a backup.
   The empty `Test-No-Cloud.entitlements` records the intended absence of cloud
   rights; it does not replace the normal account/signing entitlements.
5. Inspect the signed output and provisioning profile before installation where
   the signer provides an export. The app's `application-identifier` must end in
   `.com.jamespauley.retroarchlab.eightcoretest`, and match the signing team and
   profile. The profile must include the iPad and be unexpired. A debugger-based
   JIT setup normally needs `get-task-allow=true` in the signed development app
   and permitted by the profile. Signing alone does not activate JIT.
6. Reject signed app entitlements containing `com.apple.developer.icloud-*`,
   `com.apple.developer.ubiquity-*`, or `com.apple.security.application-groups`.
   Any keychain access group must be limited to the test identity. Every embedded
   framework must be signed. If signed output is unavailable, record that as an
   unresolved signing check and inspect the signer/profile configuration before
   allowing installation; unsigned checks do not certify the signer's output.

   On macOS, after extracting the signed IPA:

   ```sh
   codesign --display --entitlements - --xml Payload/RetroArch.app
   codesign --verify --deep --strict Payload/RetroArch.app
   security cms -D -i Payload/RetroArch.app/embedded.mobileprovision > profile.plist
   ```

7. Keep Developer Mode enabled. Install as an additional app only. Cancel any
   attempt to replace or remove the working Lab. Confirm distinct icons for
   working Lab, this test app, and the existing PS2 Test if installed. If the
   account's app limit blocks installation, stop; do not delete working apps to
   make room. Confirm the working Lab still opens with its existing library.

## Prepare fresh local test data

Leave cloud sync OFF in the test app. Do not import existing configuration,
playlists, memory cards, states, or directory overrides. Copy one test game and
BIOS per system into this app's local Documents through Files/file sharing.
Create new playlist entries pointing to those local copies. An empty initial
library is expected. Never select the working Lab or its cloud folder as a path.

Open the test app once, then use **Files > Browse > On My iPad > RetroArch Lab
8 Test**. The initial isolated package disabled `LSSupportsOpeningDocumentsInPlace`
and hid this folder. The corrected package enables that key together with
`UIFileSharingEnabled`. These settings expose this app's own Documents; they do
not grant cloud-container access. Always copy games and BIOS into the test
folder before loading them. Update the existing test identity with the same
signing account; do not uninstall either app to apply this packaging correction.

In Advanced, inspect **Settings > Directory** for System/BIOS, Save Files,
Save States and Logs. Enable **Settings > Saving > Sort Saves into Folders by
Core Name** and **Sort Save States into Folders by Core Name** (show advanced
settings if necessary), save configuration and reopen. Verify the actual
directories after the first save; do not assume a core follows frontend paths.

| Core | Firmware/resources | Save handling in this test |
| --- | --- | --- |
| Yabause | Copy Saturn BIOS as `saturn_bios.bin` into this app's System/BIOS directory. Leave Force HLE BIOS off. A real BIOS is recommended and required for M3U multi-disc use. | Writes `<game>.srm` into the frontend Save directory; verify its Yabause subfolder. Close Content normally to flush backup RAM. States stay in the Yabause state folder. |
| Beetle Saturn | Preserve original BIOS; put independent copies of `mpr-17933.bin` (US/EU) or `sega_101.bin` (Japan) in this test System/BIOS directory. | Separate Beetle save/state folders; no Yabause save/state conversion or renaming. |
| ARMSX2 | Extract `ARMSX2-system-files.zip` in this app's System/BIOS directory, retaining `pcsx2/resources/fonts/Roboto-Regular.ttf`. Copy your PS2 BIOS into `pcsx2/bios`. | Pinned source roots its data in **System/BIOS/pcsx2**, including `memcards`, `sstates`, caches and `inis`. Back up this whole test folder separately. Sorting frontend saves does not move these memory cards. |
| Play! | No external PS2 BIOS. | Its own `Play Data Files` in this app's Documents; do not reuse existing Play! cards. |

Games and BIOS are not included. Use local `.chd` or `.cue` plus all referenced
tracks for the first Saturn test, and an extracted PS2 `.iso`/`.chd` for ARMSX2.
Start at default settings and native/1x resolution.

Yabause is the pinned v0.9.15 libretro core, **not YabaSanshiro**. Both Yabause
dynamic recompilers were disabled in this build; it uses software rendering and
does not require external JIT. James reports Saturn gameplay works in Lab 8 Test;
extended-session performance has not been independently measured.

ARMSX2 needs functional JIT for **RetroArch Lab 8 Test**, separately from PS2 Test
and working Lab. Use the previously working activation method if compatible
with this iPadOS version and this new app ID. It requires frontend memory mode
2 (RWX) or 4 (dual-map), and rejects mode 3 (WX toggle). Enable file logging before
boot; look for `JIT execute/patch test passed`. Record a missing-JIT error or a
crash as a failure, not a gameplay pass. Re-enable JIT after process termination
when required by the activation method. Do not assume one successful activation
persists across force quits, restarts, or app changes.

### October 17 ARMSX2 launch recovery and recurrence diagnostics

The recovered 08:41 screenshot shows **Need for Speed - Most Wanted - Black
Edition (USA)** in the Advanced menu, with the exact error:

> ARMSX2 requires iOS 26+ with JIT enabled and a 305 MiB RWX/dual-map arena; WX-toggle is unsupported.

This message is emitted only when `CodeArena::Prepare()` fails, before the
execute/patch probe and VM boot. It does not identify which memory operation
failed and does not establish a BIOS problem. The Advanced-menu route bypasses
the native Library gate. James already reported that StikDebug showed successful
JIT activation for **this test app** while the error persisted. Successful attach
does not establish that the executable region was prepared successfully.

James subsequently answered the question about assigning **universal.js**
specifically to **RetroArch Lab 8 Test** and retrying ARMSX2: **"The game now
runs."** Record combined-app launch as passed by user report. This supports an
app-specific JIT/script setup explanation, but no failed-attempt log establishes
the exact memory operation. The recovery does not validate the later source
correction or all gameplay/save/switching checks.

Continue with the remaining physical tests below. Use the diagnostic steps here
only if the failure recurs, or to preserve logs that already exist. Do not
reinstall, replace BIOS, migrate saves or deliberately recreate the old failure.

1. In this test app, enable **Settings > Logging > Logging Verbosity** and
   **Log to File**, with frontend/core log levels at **1 (Info)**. Note
   **Settings > Directory > Logs**, then save configuration. Copy any existing
   failure log before restarting so it is not overwritten.
2. If the launch failure recurs, save/close active content normally. Confirm
   **universal.js** remains assigned in StikDebug to **RetroArch Lab 8 Test**,
   ID `com.jamespauley.retroarchlab.eightcoretest`, and activate it for a fresh
   process. Open ARMSX2 first, without force-quitting after activation.
3. If it still fails, retain the **StikDebug script output** and the test app's
   **RetroArch log** from that same attempt. Share copies through Files. These
   two logs are needed to distinguish attach success from region preparation or
   allocation failure. No reinstall, BIOS replacement or save migration is needed.
4. Check the actual System/BIOS directory in this app only. Expected files are
   `<System/BIOS>/pcsx2/bios/<BIOS file>` and
   `<System/BIOS>/pcsx2/resources/fonts/Roboto-Regular.ttf`. A folder named
   `System/BIOS` is not a literal required path; use the directory shown in
   settings. Do not redirect it to another app or iCloud. The reported game
   launch demonstrates sufficient setup for that attempt; the exact BIOS file,
   paths and separate BIOS-menu check have not been independently recorded.

The source follow-up removes ARMSX2's duplicate generic Library gate, leaving
the core's required allocation check authoritative for both entry points. It
adds distinct failure messages plus an `ARMSX2 arena:` log with requested size,
probe mode/capacity and returned allocation. Frontend `[JIT]` lines include the
running bundle ID and failed mmap, region preparation or mirror operation.
These new diagnostics require a newly compiled app; the existing Files-Fix IPA
does not contain them. Modes 2/4 remain required; mode 3 is still rejected.

| Evidence | Interpretation |
| --- | --- |
| `probe_mode=0`, no pool/CS_DEBUGGED | This process has no available executable arena; inspect activation for the logged app/PID. |
| `probe_mode=3` | WX-toggle was offered and correctly rejected; verify installed OS/build rather than allowing this mode. |
| `Pool/Arena TXM blessing failed` | Region preparation was not handled; inspect the assigned script and its output. |
| mmap/vm_remap/mprotect error | Mapping failed; retain the numeric OS error. An attach-success message alone cannot fix this. |
| `probe_bytes` below requested size | Insufficient remaining arena capacity; investigate prior core usage/teardown. |
| `JIT execute/patch test passed` followed by BIOS/boot error | The arena check passed; investigate the subsequent error and recorded paths. |

See [PS2-LAUNCH-INVESTIGATION-2026-10-17.md](PS2-LAUNCH-INVESTIGATION-2026-10-17.md)
for source comparison and the separation between automated and device evidence.

## Focused physical tests

October 17 update: James reports the original library is intact, Yabause works,
and ARMSX2 now runs a game in Lab 8 Test after the app-specific script retry.
Keep these observations separate from automated tests and the standalone PS2
Test pass. The ARMSX2 launch symptom is resolved by user report; sustained
graphics/audio/controls, fresh save/reload after restart, core switching and
working-app/iCloud regression still need their own evidence. This is the
October 17 baseline; the October 18 continuation below records the subsequent
PS2 gameplay/save/restart pass and the remaining evidence gaps.

Record app revision from the manifest, package SHA, iPad model/OS, signer/final
ID, JIT method, BIOS region, exact game edition/title ID, and controller used.
James's earlier Need for Speed result belongs to the separate PS2 Test app;
repeat it here and identify the edition. Use in-game saves as the primary test.

| Order | Test | Pass evidence |
| --- | --- | --- |
| 1 | Launch and isolation | Eight cores present: FCEUmm, Snes9x 2010, Opera, Dolphin, Play!, Beetle Saturn, Yabause, ARMSX2. Fresh local library; working app and files unchanged. |
| 2 | Yabause without JIT | One Saturn game boots; readable graphics, correct orientation, controls and audio during 10 minutes of play. Record slowdown/dropouts, not just boot success. |
| 3 | Yabause persistence | New in-game save; normal Close Content; reopen and load. Quit/relaunch the app and load again. Check the `.srm` location. Test pause/resume and reset separately. |
| 4 | ARMSX2 prerequisites | Activate JIT for this app, then BIOS boot with default settings; visible responsive BIOS menu and execute/patch log evidence. |
| 5 | ARMSX2 game | Repeat the known Need for Speed game: graphics, sustained audio, buttons/sticks, pause/resume and reset at 1x. Note heat, FPS/slowdown and any crash. |
| 6 | ARMSX2 persistence | New memory-card save; Close Content; reopen. Quit/relaunch, re-enable JIT as needed, reload the same save. Confirm files under this test's `pcsx2/memcards`. |
| 7 | Switching and core assignments | ARMSX2 → Yabause → NES/SNES → ARMSX2, closing content between games, three cycles. Check no crash/stale audio, intended core stays assigned, and each new save reloads. |
| 8 | Saturn comparison | A second test playlist entry explicitly assigned to Beetle; same copied game/scene. Verify separate saves/states and that changing one entry does not change the other. |
| 9 | State/lifecycle checks | Only after in-game saves pass: create/reload a disposable same-core state if supported. Background/foreground and lock/unlock; check sound/input recovery. Never load a state from another core/version. |
| 10 | Working app/iCloud regression | Reopen working Lab; verify library and known saves, unchanged cloud settings and existing sync behavior. Keep test app sync OFF; its lack of cloud access is expected. |

Dolphin and Play! use different frontend video drivers (`vulkan` and `gl`
respectively), so include a saved driver change and full restart when testing
those transitions. Do not interpret a required renderer restart as a save
migration. ARMSX2's Metal CPU-readback bridge still needs device validation.

For existing iCloud behavior, use only a disposable, uniquely named save in a
known-good core on the working app, and observe its existing second-device sync
if that setup is available. Keep Destructive Cloud Sync off. Do not use a
valuable save as the probe or transfer test memory cards into working Lab.
Candidate iCloud acceptance needs a **future separately compiled test build**
targeting a dedicated test container and matching profiles on both devices.
Do not add cloud entitlements to this repackaged candidate: its binary still
targets the working container. No ARMSX2 cloud-save coverage is established.

On failure, stop at the first failing step and retain the test log and iOS crash
report. Record expected/observed behavior, core/game, whether JIT was active and
whether the failure survives a fresh app launch. Do not repeatedly reuse or
overwrite a failing save. Uninstalling only this separate test app is a later
cleanup option after exporting any desired test evidence; do not uninstall Lab.

## October 18 acceptance continuation

Evidence carried forward from James's October 17 reports and PR #12, followed
by his October 18 acceptance response: **"Gameplay, saving, and reload after
restart all passed."** This response was explicitly to the Lab 8 Test PS2
session, so it establishes user-reported gameplay and fresh in-game memory-card
save/reload after a full app restart in the combined app. It is not borrowed
from the standalone PS2 Test result. The guided session included graphics,
audio, controls and pause/resume; James reported the overall pass without
separate measurements. Exact duration, game/edition, controller, resolution,
card filenames/paths and screenshots were not supplied. Do not claim a measured
15-minute run or independently inspected card files. This earlier session used
the Files-Fix package; the later build 42 update and smoke test are recorded below.

| Check | Current evidence |
| --- | --- |
| Working Lab coexistence | Initially, James reported both apps open and the original library is intact. The later build 42 follow-up below adds a user-reported original-library and known-save pass; all-save integrity and cloud behavior remain unverified. |
| Yabause in Lab 8 Test | Saturn gameplay confirmed by James; October 18 switching report confirms its save, sound and controls survived three round trips. Exact save path and Yabause persistence after full app restart remain unrecorded. |
| ARMSX2 in Lab 8 Test | Game launch recovered after the app-specific StikDebug `universal.js` retry. |
| ARMSX2 sustained session | James reports the guided gameplay test passed on October 18. Exact duration and per-check measurements were not provided; no measured 15-minute result is claimed. |
| Fresh PS2 memory-card save | Passed by James's October 18 report: saving and reload after restart in Lab 8 Test. Actual card path/files and saved-progress identifier remain unrecorded. |
| ARMSX2/Yabause switching | Passed by James's October 18 report: all three requested round trips passed, with both saves, sound and controls intact. No restart/JIT recovery or failure was reported. NES/SNES-inclusive switching from the broader checklist is not established. |
| Actual iPad save locations | Confirmed by October 18 USB inspection: `Documents/RetroArch/system/pcsx2/memcards/Mcd001.ps2` and `Mcd002.ps2`; `Documents/RetroArch/saves/Yabause/Alien Trilogy (US).srm`. Copied and hash-verified; see the backup section below. |
| Latest JIT source correction | Build 42 compiled the correction and its unsigned package was verified. James reports the guided update and PS2/Yabause launch with existing saves; see the build 42 section below. Signed output remains uninspected. |

### PS2 procedure used for the reported pass

Use the currently installed **RetroArch Lab 8 Test**; no rebuild or reinstall
is needed for these checks. Keep working Lab, PS2 Test, their games/saves and
iCloud configuration unchanged. Use only fresh local test data, with test-app
cloud sync off.

1. Read **Advanced > Settings > Directory > System/BIOS** and **Save Files**;
   do not change them. Verify they belong to this test app. If a path points
   into iCloud or another app, stop before making a save.
2. Use the already working ARMSX2 game and app-specific JIT setup. Play for
   **15 minutes** as the next focused acceptance interval; note the actual
   duration, game/edition, graphics, audio, buttons/sticks, pause/resume,
   slowdown, heat and any failure. Preserve the existing settings and record
   resolution; do not silently count a higher-resolution test as a 1x test.
3. Create a new in-game memory-card save with recognizable progress or a
   unique profile/slot, without overwriting valued data. A RetroArch save state
   is not evidence for this check. Wait for the game's save indicator to finish,
   then use **Quick Menu > Close Content** so the core can flush its files.
4. In **Files > On My iPad > RetroArch Lab 8 Test**, follow the configured
   System/BIOS path to `pcsx2/memcards`. Record actual card filenames and their
   modified times/sizes where shown; retain a screenshot with the folder path.
   A folder's existence alone does not establish which card was written.
   Do not move, rename, delete or replace cards, or change a directory to match
   the expected path. If the folder is missing, pause and inspect configuration.
5. Reopen the game and load the new progress. Close Content normally again,
   fully quit only this test app, then relaunch and reactivate StikDebug
   `universal.js` for `com.jamespauley.retroarchlab.eightcoretest` as needed.
   Load through the game's own Load/Continue function and verify the same
   progress after the new process starts. Merely resuming a suspended game or
   loading a RetroArch state does not pass restart persistence.
6. Report which step passed/failed, actual paths/card names, game/profile or
   saved progress, controller and session duration. Record iPad model/current
   iPadOS and build identity when available; do not infer them from an older
   installer log. Redact private container UUIDs in any public evidence.

### Switching procedure and remaining save-location evidence

James answered the three-round switching question: **"All three passed; both
saves, sound, and controls stayed intact."** This records a user-reported pass
for the following same-process sequence in Lab 8 Test, without independently
observed logs or file inspection. Preserve that result and do not repeat the
completed rounds solely to reconfirm them. Actual System/BIOS, memory-card and
Yabause save-folder screenshots are still needed.

The guided procedure was normal Close Content between
**ARMSX2 -> Yabause -> ARMSX2**, three rounds in one test-app process. Reuse
the proven Saturn game for switching rather than repeating its full acceptance
session. Verify the intended core and sound/input each time, load the new PS2
save on every return, and verify a disposable Saturn in-game save after leaving
and returning to Yabause. Inspect the actual `.srm` beneath the configured
Save Files directory. Record any required app restart or JIT reactivation as
part of the switching result; recovery after a restart does not turn the failed
same-process transition into a pass.

Stop on a crash, missing/corrupt save or recurring arena error. Preserve the
first relevant logs before retrying or overwriting a failing save; paired
StikDebug/RetroArch logs are needed if the launch error returns. No new defect
is established until an observed failure is reported.

Keep PR #12 draft. In addition to these results, the existing checklist still
tracks signed-output isolation, backup verification, device/build details,
remaining lifecycle/core comparisons and working-app regression evidence.
This session does not change working-app data to exercise cloud sync. Candidate
cloud acceptance requires a future dedicated test-container build; this
repackaged app must never receive working-container cloud entitlements.

## October 18 build 42 update and smoke test

[Build 42](https://github.com/jamespauley83-collab/RetroArch/actions/runs/39132912729)
successfully compiled commit `68f22a39b82c03d5d667c8dc2260bb3b56c111cd`
with ARMSX2 enabled. Native library/UI checks, simulated iCloud checks, core/app
compilation, isolated eight-core packaging and artifact upload all passed.
This build includes the JIT Library-gate correction and launch diagnostics.

Artifact `12139268037` was downloaded and its SHA-256 matched GitHub:
`fb3619236dfd530c97125ec13c31e532ba086ce5decb2f9ee00f8364507c9fae`.
The separate unsigned test IPA SHA-256 is
`14df4b6a5550d53c94555600fd68dc04f7480604f82c0a0ca3c9436e55fb9099`.
Independent inspection passed the IPA checksum, embedded/external manifest
agreement, eight-core inventory and hashes, ARM64/iPhoneOS 26 deployment,
resource hashes, Files visibility, separate identity, absence of the widget
and provisioned/embedded entitlement slots, and runtime equality with the
source CI IPA. The ARMSX2 binary contains the new launch-diagnostics marker.
The artifact ZIP and extracted IPA checksums also matched on the Lenovo.

The Sideloadly setup screenshot displayed iPadOS 27.2, the test IPA and
`com.jamespauley.retroarchlab.eightcoretest`; custom entitlements and tweak
injection were off. Automatic bundle ID was initially on. James was instructed
to disable it, retain the exact test identifier and signing account, back up
the current test saves and update without uninstalling. He replied **"done"**.
No final installer-completion screenshot, signed IPA/profile or backup
inventory was captured; this is a user-reported update, not independently
verified final signing or backup evidence. Do not publish account or device
identifiers from the setup screenshot.

At 11:24 AM America/New_York, James answered **"yes"** to:
**"Do both games launch and load your saved progress?"** The preceding guided
check was app-specific StikDebug `universal.js`, PS2 launch from the native
Library and loading its existing memory-card save, followed by Close Content,
Yabause launch and loading the existing Saturn save.

Record the updated-build launch/save-load smoke test as passed by user report.
The verified input package ties the guided update to build 42, but the
installed binary was not independently read back. This result does not
reassign the earlier sustained gameplay, fresh-save/restart or three-round
switching results to build 42, nor establish all games, cores or iCloud sync.

### Lifecycle recovery and working-Lab follow-up

At 11:56 AM America/New_York on October 18, James answered **"yes"** when
asked whether these two guided checks passed:

1. In each PS2 and Saturn game, switch apps and return, then lock/unlock the
   iPad, confirming sound and controls recover.
2. Open the original RetroArch Lab and confirm its library and a known save
   still work.

Record both checks as **passed by user report** after the guided build 42
update. This adds background/foreground and lock/unlock sound/input recovery
for the two tested games, plus a working-Lab library/known-save regression
pass. No failure, crash or missing save was reported. The response does not
establish same-core save-state recovery, other core/renderer transitions,
independently inspected signed output, a verified backup, all saves or iCloud
sync behavior.

The subsequent USB inspection below records actual save paths, a verified
file-copy backup and installed signing metadata. Remaining release evidence
includes exported signed-binary validation, remaining core/renderer and
save-state checks, and working-Lab cloud regression. The later re-sign check
below resolves the test-app keychain scope.
Keep PR #12 draft and test-app cloud sync off.
Do not repeat the completed launch/save-load, lifecycle recovery or
working-Lab library/known-save checks solely to reconfirm them.

## October 18 USB backup and installed-signing inspection

After James connected the iPad to the Lenovo, read-only USB services reported
model `iPad15,3`, iPadOS `27.2`, and both distinct Lab bundle identifiers.
No app installation, uninstall, device-file write or cloud-setting change was
performed in this inspection.

### Save-copy verification

A dated private backup was created on the Lenovo for **Lab 8 Test and the
original working Lab**, with separate app directories. It contains 5,428 files
(61,694,455 uncompressed bytes): 2,723 from Lab 8 Test and 2,705 from working Lab.
The 22,116,272-byte ZIP contains those files plus the manifest, summary and
recovery notes. All source-to-local SHA-256 comparisons passed, with zero
reported transfer errors. Files under configured save/state and PS2 memory-card
directories also matched a second source read. ZIP CRC checks and SHA-256
comparison of every archived data file against the manifest passed.

Scope: existing local saves, states, configuration, playlists, the complete
test `system/pcsx2` directory, Dolphin data and existing Play Data Files.
Game images, disc-audio tracks and ROM archives mixed into configuration
directories were excluded and enumerated privately. The test app has no
`Documents/Play Data Files`; working Lab has no `system/pcsx2`. These are
recorded absences, not failed transfers. The backup is per-file, not an atomic
device snapshot or a full iCloud/keychain/app backup. No restore into either
app was performed, so restore acceptance remains separate.

The test's inspected configuration points to its own local
`Documents/RetroArch/system`, `saves`, `states`, `config` and `playlists`.
Actual PS2 cards `system/pcsx2/memcards/Mcd001.ps2` and `Mcd002.ps2` are each
8,650,752 bytes. The Saturn file is
`saves/Yabause/Alien Trilogy (US).srm`, 65,536 bytes. These files were copied and
hash-verified. Their contents were not interpreted to independently establish
in-game progress; the earlier user-reported save-load result remains separate.

Test configuration reports `cloud_sync_enable = false` and driver `null`.
Working Lab reports cloud sync enabled with driver `icloud_drive`, with
destructive sync off. These settings were read without modification; they do
not establish a fresh cross-device cloud-sync test.

### Installed signing before correction: keychain scope failed

The iPad's installation service reports:

- Test bundle ID `com.jamespauley.retroarchlab.eightcoretest`; its application
  identifier and team match that identity.
- `ProfileValidated = true` and `get-task-allow = true`.
- No `com.apple.developer.icloud-*`, `com.apple.developer.ubiquity-*` or
  `com.apple.security.application-groups` entitlements in the installed test app.
- **Keychain groups are `<team>.*` and `com.apple.token`, rather than only the
  test application identifier. This fails the test-only keychain requirement.**

Three installed provisioning profiles match the test application identifier.
All list this iPad, permit debugging, lack cloud/app-group rights and are
unexpired as of October 18, 2026. Their expirations fall on October 17–18, 2027.
This profile inventory does not uniquely identify the profile embedded in the
installed app. No exported signed IPA was available for independent
cryptographic validation of its executable/framework signatures or binary
comparison to the CI output. Device-reported entitlements are stronger
evidence than the previous unsigned-cache inspection, but do not satisfy
those remaining checks.

A private `Lab8-Test-Scoped.entitlements.plist` candidate was prepared beside
the verified build 42 IPA. It preserves the observed application identifier,
team and debugging permission, limits `keychain-access-groups` to that exact
test identifier, and contains no cloud/app-group rights. Its plist round-trip
and scope assertions passed. It has **not** been applied, signed or installed.
The next signing step is to use the scoped values when re-signing the same test
identity, then re-read the resulting entitlements; do not assume a signer
honors the requested values. Preserve working Lab and existing saves.

Apple documents app-specific default keychain access and the expansion of
profile wildcards into fully qualified signed entitlements:
[Keychain sharing](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
and [TN2415](https://developer.apple.com/library/archive/technotes/tn2415/).
The observed groups fail this project's isolation gate; no cross-app keychain
access or loss of saves was tested or observed. Keep PR #12 draft.

### Scoped re-sign verified at 12:26 PM

James reported **"done"** after the guided Sideloadly update using
`Lab8-Test-Scoped.entitlements.plist`. A fresh USB inspection at
2026-10-18 16:26 UTC verified that the installed app's entitlements exactly
match that prepared file:

- The separate bundle/application identifier and signing team remain correct.
- `keychain-access-groups` now contains only
  `<team>.com.jamespauley.retroarchlab.eightcoretest`; the wildcard and
  `com.apple.token` entries are absent.
- `get-task-allow = true` and device-reported `ProfileValidated = true`.
- No iCloud, ubiquity or app-group entitlements are present.

**The installed keychain-scope check is now passed.** This supersedes the
earlier failed scope check and the "not installed" status of the prepared
entitlement file. It is direct installed-metadata evidence, not merely the
requested signing configuration.

All eight save files selected from the private backup summary still match
their pre-update SHA-256 values: both test PS2 memory cards, its Saturn save
and five saved-data files in working Lab. This focused comparison does not
claim that every one of the 5,428 backed-up files was re-read after signing.
Working Lab remains installed with its cloud entitlements. Its configuration
still enables `icloud_drive`; test configuration still disables cloud sync.
No device files or cloud settings were modified during verification.

No fresh post-re-sign gameplay was observed. Use the established app-specific
StikDebug `universal.js` setup before the next PS2 launch as needed. Existing
gameplay reports remain attributed to their earlier sessions. Exported signed
executable/framework verification, restore testing, remaining core/renderer
checks and fresh working-app cloud-sync acceptance remain separate. Keep PR
#12 draft; no merge or working-app replacement was performed.

## Reproduce the unsigned test copy

From a verified artifact directory containing the original IPA and manifest:

```sh
python3 pkg/apple/ipad-lab/package_eight_core_test.py /path/to/artifacts /new/test-kit
python3 -m unittest discover -s pkg/apple/ipad-lab/tests -p test_eight_core_test.py -v
```

The packager rejects checksum, inventory, deployment, platform and entitlement
errors, removes the widget, adjusts app metadata, and verifies every retained
non-metadata file is byte-for-byte unchanged. It does not compile or sign code.
Its manifest links the derivative to the input IPA and packager SHA-256.
Integrity checks establish byte identity, not trusted signing, device support,
game compatibility or data recovery. Signing changes hashes; record the signed
output separately and inspect its identity/entitlements again.

References: [Yabause documentation](https://docs.libretro.com/library/yabause/),
[Sideloadly FAQ](https://sideloadly.io/faq),
[Apple provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).
