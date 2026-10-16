# ARMSX2 iOS core prototype

This experiment has two explicit stages. The default **build probe** rejects
game loading. The **device test** enables experimental BIOS/game boot and
packages a separate unsigned RetroArch PS2 Test IPA. Neither stage establishes
working gameplay. Neither changes Lab's core lock or normal packaging.

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

For the device variant, use `build.sh device-test` on a fresh upstream checkout,
then run `python3 pkg/apple/ipad-lab/experiments/armsx2/package_device_app.py`.
The workflow builds and validates both variants separately. See
[DEVICE-TEST.md](DEVICE-TEST.md) for installation and device validation.

The artifact validator rejects simulator/macOS binaries, missing libretro
exports, non-libretro exports, non-system dynamic dependencies, or a missing
stage marker (or a marker belonging to the other stage). A successful run provides a dylib, source archive,
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
memory. Cache synchronization flushes the writable alias before invalidating the
executable alias. The frontend thread frees the arena after CPU/GS shutdown.

Patch 0004 gives the VM one exclusive code-arena borrow. Repeated/invalid
requests fail, and only the exact address and size can return the borrow.
Unmatched unmaps leave the active alias metadata intact. VM memory reset keeps
the reservation; matched unmap permits reuse, and frontend release refuses
outstanding borrows. The startup execution check returns its temporary borrow
before VM allocation.

Native tests check the ABI against Lab’s libretro header and cover rejected allocations, cleanup of malformed replies, exact
ownership, repeated allocation/release, pixel channel order, frame replacement,
invalid sizes, clearing and concurrent production/consumption. They do not
execute generated ARM64 code or exercise Metal. The Darwin map/unmap and
SysMemory reset tests compile those functions directly from the patched source,
with data-reset calls stubbed; full VM reset remains a device check.

Portable checks after applying all patches to the pinned source:

```sh
python3 pkg/apple/ipad-lab/experiments/armsx2/run_native_tests.py /path/to/ARMSX2 . /tmp/armsx2-tests
python3 -m unittest discover -s pkg/apple/ipad-lab/experiments/armsx2 -p 'test_*.py' -v
```

The initial Xcode build (Actions run 38837401507) compiled but failed linking
because CMake's object-library link inputs expected GS.o while Xcode emitted
distinct names for two GS.cpp files. The updated experiment uses Ninja and the
same iPhoneOS SDK. Latest-release patch downloads are disabled for reproducibility.

Run [38839234373](https://github.com/jamespauley83-collab/RetroArch/actions/runs/38839234373)
passed compilation and artifact inspection on 2026-10-16 at commit
`773057b1661f581367de3e4611203208799ea82f`. That run was gameplay-disabled and
contained no IPA.

Patch 0003 adds the explicit device variant: no-content BIOS boot, an ARM64
execute/patch/cache preflight, asynchronous boot-error reporting, and offscreen
Metal initialization without dispatching unnecessary UI work. Its test app uses
`com.jamespauley.retroarchlab.ps2test`, one core, and no iCloud feature flag or
entitlements. Packaging verifies app identity, URL scheme, core count and hashes. Both the
built app and final IPA must declare a minimum iOS version of at least 17.4;
missing, malformed or older values fail packaging.

## Remaining validation

1. Pass the iPhoneOS build and packaging checks for the device variant.
2. Validate JIT allocation, alias writes, instruction-cache flushing, branch
   reach, reset and teardown on a device. Unsupported frontend modes currently
   fail closed; there is no standalone allocator fallback.
3. Install the separate test app and verify its private settings/save paths.
   Do not overwrite Play! memory cards.
4. Test BIOS/game boot, graphics, input, audio, pause/resume, reset, in-game save,
   app restart and reload. Compare Play! at 1x in the same gameplay scene.

The default build-probe load gate remains enabled before configuration or VM
startup. Only the explicit device-test variant attempts boot. An unsigned IPA
is a test artifact, not evidence of playable PS2 emulation.

Source: https://github.com/ARMSX2/ARMSX2/tree/e58489d349cdcd635fc6264546087e347c84bf8c
