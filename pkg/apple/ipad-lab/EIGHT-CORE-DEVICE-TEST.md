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

### October 17 ARMSX2 failure: next diagnostic check

The recovered 08:41 screenshot shows **Need for Speed - Most Wanted - Black
Edition (USA)** in the Advanced menu, with the exact error:

> ARMSX2 requires iOS 26+ with JIT enabled and a 305 MiB RWX/dual-map arena; WX-toggle is unsupported.

This message is emitted only when `CodeArena::Prepare()` fails, before the
execute/patch probe and VM boot. It does not identify which memory operation
failed and does not establish a BIOS problem. The Advanced-menu route bypasses
the native Library gate. James already reported that StikDebug showed successful
JIT activation for **this test app** while the error persisted. Successful attach
does not establish that the executable region was prepared successfully.

The earlier troubleshooting asked for `universal.js` to be assigned to this app
in StikDebug, followed by a fresh activation and ARMSX2 as the first core. The
result of that script-specific retry is not recorded. Preserve that distinction;
do not send James back through the already completed generic activation check.

1. In this test app, enable **Settings > Logging > Logging Verbosity** and
   **Log to File**, with frontend/core log levels at **1 (Info)**. Note
   **Settings > Directory > Logs**, then save configuration. Copy any existing
   failure log before restarting so it is not overwritten.
2. Save/close any active content normally. If the script-specific retry is still
   outstanding, use the established StikDebug setup to assign **universal.js**
   to **RetroArch Lab 8 Test**, ID
   `com.jamespauley.retroarchlab.eightcoretest`, and activate it for a fresh
   process. Open ARMSX2 first, without force-quitting after activation.
3. If it still fails, retain the **StikDebug script output** and the test app's
   **RetroArch log** from that same attempt. Share copies through Files. These
   two logs are needed to distinguish attach success from region preparation or
   allocation failure. No reinstall, BIOS replacement or save migration is needed.
4. Check the actual System/BIOS directory in this app only. Expected files are
   `<System/BIOS>/pcsx2/bios/<BIOS file>` and
   `<System/BIOS>/pcsx2/resources/fonts/Roboto-Regular.ttf`. A folder named
   `System/BIOS` is not a literal required path; use the directory shown in
   settings. Do not redirect it to another app or iCloud. BIOS validity remains
   unverified until the memory check passes and BIOS boot runs.

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

October 17 update: James reports the original library is intact and Yabause
works in Lab 8 Test. ARMSX2 fails at arena preparation. Preserve those results;
continue at the ARMSX2 diagnostic check before marking combined-app PS2, switching,
save persistence or iCloud regression checks passed. Automated tests do not
replace these device observations.

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
