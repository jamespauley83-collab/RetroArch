# ARMSX2 launch investigation — October 17, 2026

Status: James reports the game now runs in **RetroArch Lab 8 Test** after the
app-specific `universal.js` retry. The launch symptom is resolved by user report;
the exact failed memory operation remains unobserved. Keep PR #12 draft for the
remaining combined-app checks. This follow-up changes documentation only; it
does not install an app or alter games, memory cards, JIT settings or iCloud data.

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
- James initially reported successful StikDebug activation for Lab 8 Test with
  the same failure. When later asked, "What happened after assigning universal.js
  specifically to RetroArch Lab 8 Test and retrying ARMSX2?", he replied:
  **"The game now runs."** This is combined-app launch evidence from the user.
  It does not establish every step of the suggested retry, the executable-memory
  mode, or a full graphics/audio/controls/save/lifecycle pass.
- The recovery supports an application-specific JIT/script setup explanation.
  Without paired script/runtime logs, it does not isolate failed region
  preparation from mapping, capacity or other process-state differences.
  No source rebuild or BIOS replacement was reported as part of the recovery.
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

Commit `b0a26e4107e37112292a85754b4adadc2398b261` already contains this correction
and its regression tests. The successful retry is separate device evidence and
must not be attributed to these unbuilt source changes. No additional source
defect is established by the recovery report.

## Automated validation recorded for b0a26e4

- 39 Lab Python tests pass, including packaging/isolation and the ARMSX2 gate
  regression; 12 ARMSX2 packaging/validation Python tests pass.
- Five native C++ executables pass against the pinned source with patches
  0001–0005 applied. They cover supported/rejected modes, failed/malformed
  allocations, capacity failures, diagnostic classification, retry, ownership,
  cache-call ordering and frame transport. Cache operations are stubbed; no
  generated ARM64 code or complete PS2 VM executes in these tests.
- These are the previously recorded results for the source correction, not a
  fresh test run for this documentation follow-up. The correction and regression
  coverage were re-inspected; no executable source is changed here.
- No iPhoneOS build or signed IPA containing the correction is claimed. The
  existing Files-Fix package lacks the new diagnostics. James's launch recovery
  is a user-reported device result for his installed test app.
- This documentation update uses `[skip ci]` to avoid unnecessary broad platform
  builds. A targeted iPad build remains necessary to compile and device-test
  the source correction before promoting it.

## Remaining device evidence

Continue with the combined-app gameplay, fresh local memory-card save/reload,
restart with JIT reactivation as needed, and core-switching checks in
[EIGHT-CORE-DEVICE-TEST.md](EIGHT-CORE-DEVICE-TEST.md). Preserve the reported
Yabause pass and original-library observation. The standalone PS2 Test save
result does not establish Lab 8 Test save persistence.

Do not repeat a successful launch solely to recreate the old failure. Retain
existing failed-attempt logs if available; if the error recurs, capture the
StikDebug script output and RetroArch log from that same process. The exact
failed operation can remain unknown without blocking use of the working test
configuration. Keep the working Lab, standalone PS2 Test, their saves and cloud
data intact; use fresh local test data and leave test-app cloud sync off.
