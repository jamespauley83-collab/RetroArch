# RetroArch Lab interpreter TestFlight build

Candidate: **1.22.2 (11)**, bundle `com.jamespauley.retroarchlab.ps3bridge`.

This configuration retains the native library, Game Mode, performance recorder,
PS2, GameCube/Wii and the native PS3 screen. It replaces the development
debugger-dependent execution paths with existing interpreter backends.

## Runtime configuration

| System | Backend | Distribution execution |
| --- | --- | --- |
| NES | FCEUmm | Existing core |
| SNES | Snes9x 2010 | Existing core |
| 3DO | Opera | Existing core |
| Saturn | Mednafen Saturn and Yabause | Existing cores |
| PS2 | ARMSX2 | EE, IOP, VU0 and VU1 interpreters; fastmem and MTVU disabled |
| GameCube / Wii | Dolphin | CPU interpreter, DSP HLE and software vertex loader |
| PS3 | RPCS3 | Native PPU/SPU static interpreters; LLVM and JIT allocator absent |

Play! is omitted because its general execution path requires generated native
code. PS2 remains available through ARMSX2 and requires the user's PS2 BIOS.
Play!-assigned playlists receive specific guidance to select ARMSX2; existing
playlist assignments and save data are not rewritten.

`TestFlightPolicy.h` enforces Dolphin's five interpreter options on every
libretro query, including after saved or per-game configuration changes. Those
fixed options are hidden from the core menu. The host always reports JIT
unavailable and refuses executable-memory requests.

`JITSupport.m` has a distribution-only implementation that contains no debugger
service, private debugger API or executable allocator. The development
implementation remains unchanged behind the other compile-time branch.

The native RPCS3 controller sets interpreter mode before loading
`RPCS3Core.framework/RPCS3Core`. Initialization errors, imports, firmware/game
management, display/input/audio and pause/resume/stop remain active.

## Native core sources

ARMSX2 uses `ARMSX2/ARMSX2` at
`e58489d349cdcd635fc6264546087e347c84bf8c`, the existing patches in
`../experiments/armsx2/patches`, and `armsx2-no-jit.patch`. Configure the existing
iOS Lab bridge with `RETROARCH_LAB_ARMSX2_NO_JIT=ON`; the build-probe gate must
remain off.

RPCS3 uses `XITRIX/rpcs3` at
`f88bff947b83730c0cf8a3949f59338b992b3ca0` and
`rpcs3-interpreter-only.patch`. Configure with
`RPCS3_FRONTEND=IOS`, `RPCS3_IOS_JITLESS_ONLY=ON` and `WITH_LLVM=OFF`.
The patch selects the permanently disabled code-generation allocator and fixes
two LLVM-free build dependencies. It preserves ABI 30, including the exported
LLVM self-test function, which reports JIT unavailable in interpreter mode.

Build dependencies were official MoltenVK 1.4.2 and FFmpeg 8.1.1. Pins and
unsigned binary hashes are in `native-core-manifest.json`. The original
development core and the clean rebuild do not claim byte-for-byte identity.

Keep the app's legitimate Extended Virtual Addressing and Increased Memory
Limit entitlements. Interpreter mode removes generated native code; it does
not remove the native PS3 guest virtual-address reservation.

## Packaging

Compile the host with `../TestFlight.xcconfig`, including a fresh JITSupport
object. Use `../archive_testflight_interpreter.py` with the preserved full app
as the resource base and the two newly built native cores.

The packager requires all eight emulator backends plus MoltenVK, validates the
interpreter markers and checked private API imports, wraps RPCS3 in a proper
iOS framework, signs nested code, preserves Game Mode, and omits empty
SwiftSupport directories. It refuses the old reduced package shape.

The older `../archive_testflight.py` remains guarded against replacing the
canonical full app with its reduced-core variant.

The local acceptance archive omits the debugger entitlement. App Store export
must apply the distribution profile and be checked for
`get-task-allow=false` and `beta-reports-active=true` before upload.

## Validation and delivery

All builds were performed locally on the existing Mac. No hosted CI build was
requested. See `DEVICE-VALIDATION.md` for the actual device results and their
scope.

Build 11 is built, signed for local device acceptance, and installed on the
iPhone. The preserved iPad build 8 was not changed.

**RetroArch Lab 1.22.2 (11) is available in TestFlight under Owner validation.**

The preserved archive was exported successfully on November 5, 2026, uploaded,
and processed by App Store Connect. The build-specific What to Test notes were
saved and reopened, and its Owner validation assignment was verified.
Build 10 remains withdrawn from that group.

[App Store Connect build 11](https://appstoreconnect.apple.com/teams/624c8dce-c9b4-4f3d-9765-088e197cdb71/apps/6830930218/testflight/ios/ad2ea1d3-5278-459e-b434-11502ef98962)

The documented physical-device checks used local acceptance signatures before
distribution export. They were not tests of a TestFlight-installed app;
their compatibility and performance limits remain unchanged.
