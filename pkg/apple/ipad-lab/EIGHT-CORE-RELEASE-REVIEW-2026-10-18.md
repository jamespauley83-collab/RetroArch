# Eight-core merge and release assessment — October 18, 2026

## Decision

**Keep PR #12 draft and unmerged.** The existing isolated installation can
continue local, cloud-disabled testing. It is not ready to replace working Lab
or to claim eight-core/cloud release acceptance. Do not start another Actions
build while the included minutes are exhausted.

Reviewed head: `beda6d82f30249aa0cf8f226f3ec77546323755d`. PR #12 targets
`codex/ipad-lab-armsx2-prototype`, not the working Lab branch; its parent
[PR #11](https://github.com/jamespauley83-collab/RetroArch/pull/11) is also open.
Merging this stack and releasing an installed working-app update are separate
decisions. Recheck the target and latest diff when the gates below are complete.

This assessment carries forward the [device record](EIGHT-CORE-DEVICE-TEST.md).
No fresh gameplay, USB save inspection, restore or signed-IPA cryptographic
verification was performed for this review. No installed app, game, save,
memory card or iCloud configuration was changed.

## Evidence retained without repeating successful tests

| Evidence | Accepted scope and limits |
| --- | --- |
| Earlier combined-app PS2 session | James reported gameplay, fresh memory-card saving and reload after a full app restart passed. Preserve this result; no measured duration is claimed. |
| Saturn and three switching rounds | James reported Yabause gameplay and three ARMSX2 → Yabause → ARMSX2 rounds with both saves, sound and controls intact. This does not establish NES/SNES-inclusive or renderer-switch coverage. |
| Build 42 update | James reported PS2 and Saturn launch/load of existing progress after the guided update. At 11:56 AM ET he also confirmed sound/input recovery after app switching and lock/unlock, and the original Lab library/known-save check. |
| Private USB file-copy backup | Recorded 5,428 files / 61,694,455 bytes across working Lab and Lab 8 Test, with source/local/archive checks. Actual PS2 card and Yabause save paths are established. It excludes games and is not an atomic snapshot, full device/iCloud backup, or restore-tested recovery point. Standalone PS2 Test is not one of the two backed-up installations. |
| Installed signing at 12:26 PM ET | Recorded exact separate test identity/team, `ProfileValidated=true`, debugging permission, test-only keychain group, and no iCloud/ubiquity/app-group rights. Wildcard and shared token groups are gone. Eight sampled saves still matched the backup. This does not verify the exported signed binary or uniquely identify its embedded profile. |

Do not repeat these completed checks merely to obtain new screenshots, timing
measurements or another confirmation. Preserve their original build/session
attribution. The scoped re-sign has no fresh gameplay report; use the next
otherwise-needed test to observe that installation rather than restarting the
completed PS2/Saturn acceptance sequence.

## Repository and artifact checks completed in this review

[Build 42 / run 39132912729](https://github.com/jamespauley83-collab/RetroArch/actions/runs/39132912729)
is successful at `68f22a39b82c03d5d667c8dc2260bb3b56c111cd`. Its job records
show native library/UI checks, simulated cloud checks, core/app compilation,
separate test packaging and upload all succeeded. Comparing that source to the
reviewed head changes only `EIGHT-CORE-DEVICE-TEST.md`. Thus build 42 covers the
reviewed runtime, including the corrected Library JIT gate and diagnostics.

Artifact `12139268037` was downloaded again and inspected locally:

| Item | SHA-256 |
| --- | --- |
| Artifact ZIP, 380,873,338 bytes; matches GitHub digest | `fb3619236dfd530c97125ec13c31e532ba086ce5decb2f9ee00f8364507c9fae` |
| Original unsigned IPA | `f707ee85836982ed1b2cd220d6bf2a51121912773341cbbc63c87173a4966d9c` |
| Existing isolated unsigned IPA | `14df4b6a5550d53c94555600fd68dc04f7480604f82c0a0ca3c9436e55fb9099` |

Both IPAs passed the strengthened packager's validation: manifests, eight-core
hashes, expected framework inventory, platform/deployment, identity and unsigned
entitlement checks. Resource archives matched their hashes. All five ARMSX2
patches matched the archived provenance and repository. Frontend, eight cores
and MoltenVK bytes are equal between the original and isolated IPAs. A fresh
local repackaging also passed; it was not signed, distributed or installed.

The original IPA still carries working Lab's identity and must not be installed
over it. CI artifacts are unsigned; these checks cannot close signed-binary
verification. Artifact retention currently ends November 1, 2026; retain the
already-downloaded artifact/provenance privately rather than rebuilding just
to obtain another copy.

## Focused corrections

1. **Unlisted packaged code:** the packager checked only names containing
   `.libretro.framework`, permitting a second Payload app, unrelated framework
   or loose library. It now rejects payload outside the intended app and
   requires exactly the eight core framework directories plus MoltenVK.
   Regression cases reproduce all three unwanted inputs on the old code and
   reject them before creating output on the corrected code. Explicit ZIP
   directory entries remain supported. Build 42 contains none of these extras.
2. **Yabause save-state errors:** the pinned `retro_serialize` copied the
   caller's size without checking the returned buffer/error/actual size;
   `YabSaveStateBuffer` discarded a failure from the second state-writing pass.
   Patch `0002-savestate-buffer-errors.patch` propagates that failure, rejects
   failed/null/empty/oversized results, copies only available bytes and zeroes
   remaining caller space. Failed saves leave the caller's output untouched.
   The state format and in-game save paths are unchanged.

Validation: **44 Lab Python tests and 12 ARMSX2 Python tests pass** (56 total).
The new Lab test compiles and runs the state functions against buffer-size,
allocation/error, output-preservation, cleanup and audio-unmute cases. The
patch also applies to the full Yabause source archived with build 42; the
native harness fails on the original functions and passes on those patched
functions. Build-input validation and whitespace checks pass.

**The Yabause runtime correction is not in build 42.** No new iPhoneOS compile
or device pass is claimed. Do not exercise Yabause save states on build 42 as
acceptance for this fix. A future targeted build must include it, with new
artifact provenance and signing checks. Existing in-game save/gameplay results
remain valid evidence for their earlier binaries.

## Remaining gates and where they can be completed

| Gate | Work needed | Environment / release scope |
| --- | --- | --- |
| Updated candidate build | Compile the new Yabause patch with the iPhoneOS SDK; verify the resulting core hash, source archive, patch provenance and separate IPA. Use one planned targeted eight-core build when capacity is available, not broad platform reruns. | macOS/Xcode or later targeted CI; before merge/release of the corrected candidate. |
| Final signed-package verification | Obtain the actual signer's exported IPA. Verify app and every nested executable/framework signature; inspect the embedded profile, signer identity, device eligibility, expiry and allowed entitlements. Confirm the test-only identity/keychain scope and absence of cloud/app-group rights in the signed output. Correlate to the verified candidate and document any signer modifications. Whole-file hashes change during signing. | Signed artifact plus macOS signing tools; CI's unsigned files and installed metadata cannot substitute. Before merge/release. |
| Untested cores/renderers | Record representative FCEUmm/Snes9x 2010/Opera checks and NES/SNES-inclusive transitions. Check explicit Beetle versus Yabause assignments and separate save/state folders. Exercise Dolphin/Vulkan and Play!/GL transitions, with the required saved driver change and full restart. Record actual ARMSX2 renderer/bridge behavior during remaining checks. | Physical iPad, test-local copies only. Before eight-core integration acceptance; do not rerun the completed three PS2/Saturn rounds. |
| Remaining persistence/state coverage | Confirm Yabause in-game reload after a full app restart where still unrecorded. On the corrected build, create/load a disposable same-core Yabause state; similarly check ARMSX2's implemented state path. Record any other supported state functionality claimed for release. Never reuse states across cores/versions or overwrite valuable progress. | Physical iPad; states remain distinct from the already-passed PS2 memory-card test. Before claiming state support and integration acceptance. |
| Working-app cloud regression | With its existing settings unchanged and destructive sync off, observe a uniquely named disposable save syncing through the existing known-good setup and second device, if available. Preserve the already-passed original library/known-save check. If no second device is available, record this gate as unverified. | Physical devices and the existing iCloud account/setup. Before release acceptance; a configured `icloud_drive` flag is not a sync test. |
| Recovery assurance | First restore the private ZIP into a new offline staging directory and compare its manifest. Before replacing working Lab, validate a disposable copy of representative progress in a separate compatible sandbox, without restoring over any existing app or cloud folder. | Private backup/artifact access for extraction; device for actual save usability. Required before a working-app upgrade/recovery claim; not a reason to modify the working installation now. |

No unavailable game, BIOS, controller or device result is assumed. Record title,
core, renderer and candidate identity during the remaining work. A later
runtime-changing build needs checks targeted to its changes, not automatic
repetition of every prior successful session.

## iCloud isolation assessment

For the **current local-only test**, the approach is sufficient as a constrained
isolation design: separate app identity/local paths, no widget, no cloud or
app-group rights, scoped keychain access and cloud sync off. The installed
metadata record supports those controls; final signed-package assurance is
still open. Turning sync off alone is not the boundary. Apple requires the
appropriate entitlements to access a ubiquity container.

`Lab.xcconfig` compiles `ICLOUD_DRIVE_CONTAINER_NAME` from `LAB_ICLOUD_CONTAINER`;
`network/cloud_sync/icloud_drive.m` uses that compiled name explicitly. Merely
changing Info.plist or re-signing cannot retarget build 42. Never grant this
repackaged binary working-container cloud rights. Its inability to synchronize
is intentional, not a failing cloud-enabled acceptance test.

A future independently compiled cloud-enabled candidate requires:

- A dedicated test bundle ID and dedicated iCloud container, with the same
  test container selected in build settings, plist, generated entitlements and
  profiles on both test devices. No working-app container, app-group or shared
  keychain access. Keep a widget omitted unless separately scoped and verified.
- A real frontend rebuild with that container macro; the current no-cloud
  repackager is not that build route. Inspect the final binary/build settings,
  signed entitlements and embedded profile before installation. Record the new
  manifest and signed-package identity separately.
- Native simulated cloud checks for the dedicated container, then two-device
  tests with disposable data for upload/download, offline recovery, conflicts
  and unavailable-container behavior. Keep destructive sync off. Demonstrate
  that no working-container data/settings change.
- An explicit core-by-core sync scope. ARMSX2 cards live under
  `system/pcsx2/memcards` and are not covered merely by enabling frontend save
  sync; do not sync an active memory card or the whole BIOS/cache/resource tree.
  Any new memory-card sync feature needs its own design and acceptance.

Dedicated candidate-cloud acceptance is required before claiming cloud support
for that candidate. It is not permission to enable cloud on the current copy.
The existing working-app cloud regression remains a separate release gate.

References: [Apple iCloud containers and entitlements](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html),
[Apple provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles),
[current acceptance record](EIGHT-CORE-DEVICE-TEST.md).
