# Build 7 performance recorder validation

- Base: `ef556b7dcf7931dc80864df52ba5fe8a52fc85ed` (existing RPCS3 bridge branch).
- Installed app: RetroArch Lab 1.22.2 (7), `com.jamespauley.retroarchlab.ps3bridge`.
- iPad Air 11-inch (M3), iPadOS 27.2. In-place installation and launch succeeded.
- All eight libretro frameworks, MoltenVK and the PS3 library are unchanged from
  signed combined build 5. Existing app identity/data container retained.
- Apple Development signature passed deep strict verification.
- Signed host SHA-256: `00825e957dc3201a16101f08ba37b619b48aedf5fcb25d9a35dbba6cf7f807ef`.

Local validation passed: 69 Lab Python checks, 65 native library helper checks,
iOS syntax checks, C89 aggregation checks (60/50/30 Hz, stalls, pause, altered
speed, missing target), and four executable simulator recorder tests covering
actual JSON export, audio deltas/resets, missing PS3 metrics and retention.
The physical iPad UI test also passed: start, wait for a sample, mark slowdown,
stop, choose reports, dismiss. A device-exported report was parsed and verified
as build 7 with seven valid JSON rows, the slowdown marker, and a clean
`user_stopped` ending. Its 3.48-second menu session was 3,905 bytes; no game was
running, and FPS correctly remained unavailable. The initial UI test expected an
iPhone-style Cancel row; the assertion was corrected for iPad popover behavior.
No GitHub Actions run was started.

The host compiled and linked. Xcode's final framework packaging script hit the
existing FinderInfo extended-attribute signing problem in the synced build
folder. The app was assembled in `/tmp` using the unchanged verified build-5
frameworks and newly linked host, with Finder attributes stripped, then signed
and verified. This is a successfully assembled/signed app, not a green end-to-end
Xcode packaging run.

StikDebug 3.1.13's saved `BundleScriptMap` contains the current app mapped to
`universal.js`. The installed script is byte-identical to the 3.1.13 bundled
script (SHA-256 `e9828331a815c10c2077df6c66c2a974dfec235d03231aba4e50044c6015ea14`).
The PS3 handoff now sends the current PID alongside bundle ID and script name.
The failure message distinguishes assignment from successful handshaking.
Physical PS3 attachment, gameplay and performance overhead remain unverified;
standalone RPCS3 is retained as the working fallback.
