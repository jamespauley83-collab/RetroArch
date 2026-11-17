# PS2 core selection review — November 17, 2026

Status: local source candidate, not published or installed. No TestFlight changes.
Base: `d8b4288308576196ed91be0a30afc30e89b41ab7`, the current head of open
[PR #23](https://github.com/jamespauley83-collab/RetroArch/pull/23).
This reuses the existing ARMSX2 core and leaves XMB startup unchanged.

## Findings and limits

| Question | Observed result |
| --- | --- |
| What is installed now? | Two fresh read-only device queries per device reported 1.22.2 build 13 for `com.jamespauley.retroarchlab.ps3bridge` on both iPad Air M3 and iPhone 17 Pro Max, around 11 AM ET November 17. This conflicts with the November 16 build 18 installation receipts. The reason is unknown. |
| Did build 18 package ARMSX2? | Yes. The retained package contains all eight libretro cores, including Play! and ARMSX2. Its ARMSX2 binary is 23,234,352 bytes, SHA-256 `e1c75ba7be9f3472b7b3ad57f83561bf39541046f2cd793bd86abeac1d504523`. This does not identify the binary currently installed in build 13. |
| Does the current iPad playlist select Play!? | No. The PS2 playlist default, all three entries, and two PS2 history entries already select `:/Frameworks/armsx2.libretro.framework`. The new planner reports zero changes for these exported files. The iPhone had no file at either inspected playlist/history path. |
| Is a BIOS present? | Both devices list `Documents/RetroArch/system/pcsx2/bios/scph39001.bin`, 4 MiB. Presence and size do not prove validity or successful boot. |
| Does the saved failure prove a current BIOS problem? | No. The iPad log is from November 15 at 16:30 UTC; the BIOS file arrived at 16:43 UTC. The log reports interpreter execution and BIOS initialization failure before that copy. No later gameplay log was established. |
| Are resources complete? | Neither device has files under the inspected `pcsx2/resources` directory. The development packager omitted the separate resource archive. The pinned core has font fallback behavior, so missing fonts alone do not prove the BIOS failure. |
| Is core metadata accurate? | Both devices retain generic upstream ARMSX2 metadata describing Vulkan/OpenGL and required resource folders. Build 18 carries different Lab metadata. Presence checks and hashes do not establish correct descriptions or refresh existing Documents metadata. |

Supported device-file APIs did not expose installed application-bundle bytes.
No app launch, device-file write, game session, JIT activation, installation,
publishing or distribution change was performed during this review.

## Why Play! can still be selected

`preferred_ps2_core = armsx2` in `build.py` is build-manifest metadata; no runtime
consumer applies it to playlists. `RetroArchPlaylistManager.getAllGames` prefers
an explicit entry core over the playlist default. History and favorites retain
their own assignments. The library resolver intentionally honors those
assignments and never infers a console from shared `.iso` or `.chd` extensions.
Thus changing a playlist default alone cannot fix every stale Play! entry.
This is an established source behavior, not proof that today's inspected iPad
entries are wrong.

## Local corrections

1. Native Library: a legacy Play! assignment now opens **Choose PS2 core**.
   **Use ARMSX2** appears first when installed; development builds retain an
   explicit **Use Play!** option. Cancel launches nothing. TestFlight policy
   still excludes Play!. Missing or ambiguous ARMSX2 never silently falls back.
   A choice applies to that launch and preserves existing JIT and game-switch
   checks. XMB and URL launch routes continue using their explicit assignments.
2. `ps2_core_selection.py`: audits explicitly selected exported JSON playlists.
   It repairs explicit Play! associations and unambiguous PS2 default/DETECT
   entries in separate review copies, preserves original bytes alongside them,
   and reports every field change and hash. It never overwrites the input
   export or touches a device. Unsupported/compressed/malformed playlists fail
   without a repair package. Other cores and ambiguous disc files are retained.
3. Development packaging: requires all eight core executables and core-info
   entries and retains a validated `ARMSX2-system-files.zip` beside the app.
   Only the pinned font/license paths are allowed; BIOS, games, cards and states
   are rejected. The manifest records input hashes and `extraction_required`.
   This does not install fonts or refresh device metadata automatically.

Example audit (paths must refer to real exported data and a retained app):

```sh
python3 pkg/apple/ipad-lab/ps2_core_selection.py \
  --export-root /path/to/copied-data \
  --app /path/to/retained/Payload/RetroArch.app \
  --playlist 'Documents/RetroArch/playlists/Sony - PlayStation 2.lpl' \
  --playlist Documents/RetroArch/playlists/builtin/content_history.lpl
```

Add `--output /path/to/new-review-directory` only to create separate proposed
files and original backups. The tool does not deploy them.

## BIOS, cards and save states

The pinned ARMSX2 adapter derives its root from the configured System directory
plus `pcsx2`. Defaults are `bios`, `resources`, `memcards`, and `sstates` under
that root; `[Folders]` settings in `inis/armsx2-libretro.ini` can override them.
The copied iPad INI uses relative defaults and leaves the BIOS filename empty
(automatic selection). Active core/content options still need checking on the
device. The BIOS options enumerator scans `pcsx2/bios`.

Play! retains `Documents/Play Data Files`. Do not copy its cards into ARMSX2 or
load its states with another core. Both current configurations enable per-core
RetroArch save/state sorting. Verify those settings and any core/content
overrides before future tests. No patch here changes, moves or converts games,
BIOS, cards, states, XMB settings, or ARMSX2 INI files.

## Validation

- 86 Lab Python tests passed, including 15 behavioral playlist-repair cases and
  12 library wiring checks (startup/manual navigation guards included).
- Seven development-package tests passed with signing commands mocked.
- 76 native Objective-C helper checks passed on the Mac.
- iOS source type-checks passed for ordinary Lab, StikJIT development, and
  TestFlight policy variants. Tested native file hashes match the local patch.
- The planner ran against the actual copied iPad playlist/history and retained
  build 18 package: zero proposed changes; input and device files untouched.
- `git diff --check` passed. No full app build, signed new IPA, GPU execution,
  gameplay, audio, save/reload, performance, or lifecycle acceptance is claimed.

## Approval proposal

Next proposed external action: publish this reviewed patch on
`codex/ps2-core-selection-20261117` and open one draft PR titled
**Require explicit PS2 core selection and retain ARMSX2 resources**, based on
`codex/restore-jit-20261108` (stacked on #23). Use `[skip ci]`; do not dispatch
hosted builds or merge either PR. Recheck the base before publishing and stop
for review if it has changed. Explicit owner approval is required first.

Device replacement and TestFlight changes are not part of that proposal.
Before requesting installation approval, build a specific development
candidate from the reviewed source, identify its exact app/core hashes and
resource archive, and present the target devices/build and file-level changes.
Back up current Documents, cards, states and configuration with hashes; retain
both old and current copies. Never uninstall or restore over newer saves.

After a separately approved in-place install/resource transfer, verify XMB and
manual Library access, actual selected core/version, valid BIOS selection,
resource paths and executable-memory state for that process. Then run an
owner-provided PS2 game at 1x: visible gameplay, sustained audio, input,
in-game save, normal exit, relaunch and reload, pause/resume, background/return,
and a non-PS2 core switch. Keep JIT and interpreter measurements separate.
