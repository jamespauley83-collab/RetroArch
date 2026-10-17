# PS2 development

## Baseline and next candidates

Assessment: October 15, 2026. The current six-core Lab baseline is
`d988b7d5eba218e2296f7aeb37cf0a4d43437605` on `codex/ipad-lab-saturn`.
Play! remains pinned to `83700b2c31e593bc94e845b4b31b797be84dda59`, with
Lab's frontend executable-memory patch. It provides an existing iOS libretro
build path. That establishes an integration baseline, not superior PS2
compatibility or performance. No recorded comparison establishes that it is
the best engine for this iPad.

| Candidate | Verified source evidence | Remaining Lab work |
| --- | --- | --- |
| Play! | Existing Lab ARM64 build and libretro integration; OpenGL ES; HLE BIOS | Reproduce gameplay, audio and saving failures on the signed build |
| Stock PCSX2 / established LRPS2 releases | Published build documentation still describes x86-64 requirements | Do not treat a desktop core as an installable iOS framework |
| ARMSX2 | PCSX2 fork with native ARM64 recompilers, `platforms/ios`, and `pcsx2-libretro` | Establish a pinned iOS **libretro** build, frontend JIT allocation, graphics handoff, resources/BIOS, input, audio and save behavior |
| Current `libretro/ps2` source | Native ARM64 work with documented Linux testing | Establish Apple/iOS build and runtime support; Linux gameplay evidence is insufficient |

ARMSX2's June 8, 2026 announcement describes an experimental iOS build using
PCSX2 2.7 with native ARM64 JIT. The inspected source revision is
`e58489d349cdcd635fc6264546087e347c84bf8c`. Its unified workflow has a Linux
ARM64 libretro job and a separate iOS app job. An iOS app and a Linux libretro
core do not establish an iOS libretro core. The workflow also labels mobile
jobs non-blocking during reconciliation; verify a specific revision's job
results before using it. Comments in `pcsx2-libretro/Main.cpp` describe early
milestones even though later implementation exists, so audit the code itself.

The next alternate-core milestone is a reproducible ARMSX2 iOS libretro build
in an isolated experiment. Verify exported `retro_*` symbols, ARM64/iOS load
commands and dependencies before packaging. Exercise iOS JIT allocation and
code writes under Lab's actual executable-memory model. Keep graphics and
resource setup explicit. Do not change the production core assignment until
device tests pass. A desktop Metal renderer or standalone iOS frontend does
not automatically integrate with RetroArch's graphics callbacks.

## First refinement: Play! audio delivery

`0002-preserve-audio-batches.patch` changes the pinned libretro audio adapter:

- Queue consecutive VM writes instead of replacing unplayed samples.
- Count stereo frames separately from 16-bit samples and bytes.
- Keep samples the frontend did not accept, including a zero-frame return.
- Protect every buffer access and clear the queue on `Reset()`.
- Bound backlog to one second at the VM's fixed 44100 Hz rate. On overflow,
  discard the oldest complete stereo frames; this avoids unbounded growth
  during a stalled consumer or fast-forward.

The native harness compiles the actual patched audio adapter. It covers
ordering, partial/zero consumption, absent callbacks, reset, capacity,
stereo alignment and concurrent producer/consumer access. The build runs it
before compiling the iOS core. This addresses an independently reproducible
audio-delivery defect. It does not establish the cause of a particular game's
stutter, improve emulation speed by itself, or repair memory-card emulation.

## Device comparison

Start at 1x resolution with the same device, game image/region, gameplay scene,
controller, audio output and JIT status. Record the app/core revision and
settings. Measure real gameplay after warm-up, not just an intro movie. Record
FPS, audio interruptions and sustained performance over a repeatable session.

The earlier session notes report roughly 3 FPS in a Need for Speed title with
saving working, and 40–50 FPS in Burnout 2 with saving failing. These are
historical reports, not measurements from this change. Record the exact Need
for Speed title and both disc IDs before investigating game-specific fixes.

For each core, make an in-game save, exit normally, restart the app, and reload
the save. Keep each experiment's memory cards separate. Play! stores cards in
`Documents/Play Data Files`, outside ordinary RetroArch save sync; a different
core's card format or save states may not be compatible. Preserve a copy of
that directory before device experiments.

## Sources

- [Play! source](https://github.com/jpd002/Play-/tree/83700b2c31e593bc94e845b4b31b797be84dda59)
- [PCSX2 build documentation](https://pcsx2.net/docs/advanced/building/)
- [LRPS2 documentation](https://docs.libretro.com/library/lrps2/)
- [ARMSX2 iOS announcement](https://armsx2.net/updates/iOS-2.0-v1)
- [ARMSX2 inspected source](https://github.com/ARMSX2/ARMSX2/tree/e58489d349cdcd635fc6264546087e347c84bf8c)
- [Libretro PS2 ARM64 development](https://github.com/libretro/ps2)
