# RetroArch Lab and standalone RPCS3

The owner separated the project directions on November 10, 2026.

| Project | Source | Next work |
| --- | --- | --- |
| RetroArch Lab | This repository | PS2 through ARMSX2's existing libretro integration |
| Standalone RPCS3 / PS3 Lab | [RPCS3-iOS-Lab](https://github.com/jamespauley83-collab/RPCS3-iOS-Lab) | Standalone PS3 frontend, game compatibility, controls, saves and performance |

The existing native PS3 bridge stays in this tree for compatibility. Do not remove
it from an installed user's next build merely because standalone development has
moved. Do not copy RetroArch app identity, cloud-container settings or release
numbers into the standalone project. A shared upstream core revision can be
referenced by both projects, but patches and release evidence must be pinned and
reviewed separately; neither release consumes a mutable sibling workspace.

## Retained identity records

| App | Bundle ID | Recorded baseline, not a live device inventory |
| --- | --- | --- |
| Original RPCS3 | `com.jamespauley.rpcs3standalone` | XITRIX 0.12; prior user-confirmed JIT gameplay |
| PS3 Lab | `com.jamespauley.rpcs3lab` | Standalone 0.1.0 (2), interpreter beta |
| RetroArch Lab PS3 bridge | `com.jamespauley.retroarchlab.ps3bridge` | Development 1.22.2 (16), JIT |

The original Lab, PS2 Test and eight-core test identities also appear in older
instructions. Preserve any working installation and its data. A historical
installer is not automatically the intended update for a current device.

This separation changes ownership and build preparation, not installed apps.
It does not authorize a device replacement, sandbox migration, TestFlight group
change or removal of PS3 functionality. Verify which actual iPad app the owner
is using before any future replacement; the display name alone is insufficient.

## Next RetroArch work

Follow the current milestone in [PS2-DEVELOPMENT.md](PS2-DEVELOPMENT.md).
Retain the multi-system library, non-PS2 cores and per-core save behavior.
The source history at PR #23 includes the working JIT handoff and prior storage,
logging and packaging corrections; starting at the repository's older default
branch would discard that work.
