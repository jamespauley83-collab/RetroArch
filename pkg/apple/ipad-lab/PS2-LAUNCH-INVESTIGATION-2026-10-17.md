# ARMSX2 launch investigation — October 17, 2026

Status: failure stage identified; underlying device cause and gameplay recovery
remain unconfirmed. Keep PR #12 draft. No application installation, JIT setting,
game, memory card or iCloud data was changed by this investigation.

## Evidence

- James reports Yabause runs a Saturn game in Lab 8 Test. The earlier Need for
  Speed gameplay/audio/controls/save result belongs to the separate PS2 Test.
  Its installed binary revision/hash is not established.
- The supplied October 17 08:41 screenshot has the playlist title **Need for
  Speed - Most Wanted - Black Edition (USA)**, ARMSX2 version `e58489d`, and the
  generic 305 MiB RWX/dual-map error. The screen itself does not expose the bundle
  ID; its Lab 8 attribution comes from James's report.
- That exact text has one emission site in patch 0002: failed
  `CodeArena::Prepare(environ_cb, HostMemoryMap::CodeSize)`. It precedes the
  execution/cache probe, memory reservation and CPU/VM boot. Configuration has
  already initialized. This is not the core's later BIOS/VM boot error.
- James already reported successful StikDebug activation for Lab 8 Test with
  the same failure. A later assistant instruction asked for `universal.js`
  assignment and ARMSX2-first retry. No outcome or script/RetroArch log from that
  retry was available. Do not infer that the script was assigned or ran correctly.
- The installer and earlier report identify iPadOS 27.2; a later abbreviated
  context says iPadOS 26. Both meet the 26+ floor, but a device log should record
  the exact current version. The screenshot alone does not establish OS/model.
- The Lenovo was reachable, but its USB inventory exposed no connected iPad.
  The retained test kit contains build manifests and installation inputs, not
  a device runtime log. No executable-memory mode was observed on the device.

## Source comparison

Compared PR #12 head `de3d08f0274193022958271bf551508e789ced6a` with
PR #11 head `2b6e8c23f4d4cb9f562c1b2bf23f53ccadf0b30a`:

| Area | Finding |
| --- | --- |
| Core | Same upstream pin `e58489d349cdcd635fc6264546087e347c84bf8c`, patches 0001–0004 and device-test recipe. Combined packaging copies the core after provenance/hash verification. This compares reviewed sources, not the unidentified installed standalone binary. |
| Frontend allocator | `JITSupport.m` and the `runloop.c` executable-memory ABI are unchanged between those two heads. The bridge uses the matching ABI layout, tested natively. |
| Native Library gate | PR #12 added ARMSX2 to `jit_available()`. This does not check the required mode/capacity, and the warning names the working Lab instead of the running app. The screenshot's Advanced-menu launch bypasses this gate, so it is not the demonstrated error's source. |
| Application identity | Standalone: `com.jamespauley.retroarchlab.ps2test`. Integration test: `com.jamespauley.retroarchlab.eightcoretest`. Process JIT/pool state is separate; a success in one does not activate the other. |
| Memory | ARMSX2 requires RWX (2) or dual-map (4) plus a valid 305 MiB arena. iOS 26+ normally uses a pre-prepared 544 MiB pool or a direct dual mapping. Attach, TXM region preparation, mapping and remaining capacity are separate failure points. WX-toggle (3) remains unsafe for this bridge. |
| BIOS/resources | Both derive their root from the frontend's configured System directory plus `pcsx2`. BIOS: `pcsx2/bios`; fonts: `pcsx2/resources/fonts`. Memory cards also live under this root. Actual device contents/overrides were not available. |

## Focused source correction

Remove ARMSX2 from the generic Library gate and keep its existing core-owned
arena preparation as the authoritative check for every launch route. Preserve
Dolphin/Play! gating; name the actual running app in their activation message.
No memory mode is newly accepted, no allocation/reset/free semantics are changed,
and no core is permitted to execute without its existing arena validation.

Patch 0005 distinguishes API unavailable, no executable memory, unsupported mode,
insufficient reported capacity, allocation failure and invalid mapping. It logs
probe/allocation mode, capacity and actual BIOS/resource paths. Frontend logs
record the app ID/PID and mapping or region-preparation error. The earlier single
message collapsed these failures and could not support a root-cause diagnosis.

This corrects the independent gate/diagnostic defects; it is **not evidence that
the reported iPad launch failure is fixed**.

## Automated validation

- 39 Lab Python tests pass, including packaging/isolation and the ARMSX2 gate
  regression; 12 ARMSX2 packaging/validation Python tests pass.
- Five native C++ executables pass against the pinned source with patches
  0001–0005 applied. They cover supported/rejected modes, failed/malformed
  allocations, capacity failures, diagnostic classification, retry, ownership,
  cache-call ordering and frame transport. Cache operations are stubbed; no
  generated ARM64 code or complete PS2 VM executes in these tests.
- No new iPhoneOS build, signed IPA or physical-device pass is claimed. The
  existing Files-Fix package remains unchanged and lacks these new diagnostics.
- Use `[skip ci]` for this source investigation to avoid the repository's broad
  automatic platform builds while the existing installed app's script/log check
  is pending. A targeted iPad build is needed before using the new diagnostics.

## Remaining device evidence

Follow the script-specific retry/log capture in
[EIGHT-CORE-DEVICE-TEST.md](EIGHT-CORE-DEVICE-TEST.md). Obtain the StikDebug script
output and RetroArch log from the same failed process. If it boots after that
retry, record the result as a device configuration outcome and repeat the
combined-app gameplay/save/switching checks. If it still fails, use the logs (and
a targeted diagnostic build if needed) to select a correction rather than
relaxing mode requirements, replacing BIOS blindly or overwriting another app.
