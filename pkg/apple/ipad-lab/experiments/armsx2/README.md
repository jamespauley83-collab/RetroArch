# ARMSX2 iOS core prototype

This is an isolated **build probe**, not a playable PS2 core or installable IPA.
The core deliberately rejects game loading with an explanation. It is not
added to Lab's core lock, normal packaging, or game assignments.

## Reproduce

Open the `ARMSX2 iOS core prototype` PR workflow. It checks out ARMSX2 revision
`e58489d349cdcd635fc6264546087e347c84bf8c`, applies only this directory's patches,
builds the upstream checksum-verified static iOS dependencies, and compiles the
root `pcsx2-libretro` target for ARM64/iPhoneOS 17.4. No Apple credentials or
provisioning profiles are used. A fresh source checkout is required per run.

On a Mac with Xcode, check out the same pinned upstream revision at
`.armsx2-prototype/source` under the Lab repository and run:

```sh
bash pkg/apple/ipad-lab/experiments/armsx2/build.sh
```

The artifact validator rejects simulator/macOS binaries, missing libretro
exports, non-libretro exports, non-system dynamic dependencies, or a missing
prototype load gate. A successful run provides a dylib, source archive,
dependency source archives/checksums, patches, GPL license, inspection report
and manifest. Apply the included patches in numeric order to the pinned source archive to
reconstruct the modified source. Read the manifest's stage and validation
fields; compilation does not establish runtime compatibility.

## Implemented bridge (runtime unvalidated)

Patch 0002 selects Metal without a frontend GL/Vulkan context. It captures the
GS output through the existing snapshot/download path at 640x448, converts
RGBA8 to libretro XRGB8888, and hands off the latest complete frame under a
mutex. The mailbox holds one frame and never blocks the GS thread during a
frontend pause. CPU readback is a correctness baseline; it is not a performance
solution or a claim of synchronized frame pacing.

The build compiles and embeds its own iOS Metal library. It never loads
RetroArch's default Metal shaders. Surfaceless pipeline creation gets an
explicit pixel format. This still needs a device test for orientation, aspect,
colors, blank frames and sustained rendering.

The JIT bridge requests the full upstream code arena (305 MiB) using RetroArch's
executable-memory ABI v1. Only RWX and dual-map allocations are accepted. Missing
callbacks, unsupported modes, undersized arenas and invalid aliases fail before
VM startup. Darwin's allocator borrows this arena and uses the existing writable
alias translation. It does not independently map, protect or unmap frontend
memory. The frontend thread frees the arena after CPU/GS shutdown.

Native tests cover rejected allocations, cleanup of malformed replies, exact
ownership, repeated allocation/release, pixel channel order, frame replacement,
invalid sizes, clearing and concurrent production/consumption. They do not
execute generated ARM64 code or exercise Metal.

The initial Xcode build (Actions run 38837401507) compiled but failed linking
because CMake's object-library link inputs expected GS.o while Xcode emitted
distinct names for two GS.cpp files. The updated experiment uses Ninja and the
same iPhoneOS SDK. Latest-release patch downloads are disabled for reproducibility.

## Remaining validation

1. Pass the iPhoneOS build and artifact inspection with both bridges compiled.
2. Validate JIT allocation, alias writes, instruction-cache flushing, branch
   reach, reset and teardown on a device. Unsupported frontend modes currently
   fail closed; there is no standalone allocator fallback.
3. Package a separately identified test app with distinct save/config paths and
   no shared production iCloud container. Do not overwrite Play! memory cards.
4. Test BIOS/game boot, graphics, input, audio, pause/resume, reset, in-game save,
   app restart and reload. Compare Play! at 1x in the same gameplay scene.

The build-probe load gate remains enabled before configuration or VM startup.
Neither an installable IPA nor a playable core is supplied by this experiment.

Source: https://github.com/ARMSX2/ARMSX2/tree/e58489d349cdcd635fc6264546087e347c84bf8c
