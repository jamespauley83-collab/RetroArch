# Development JIT restoration — build 15

Date: November 7, 2026 (America/New_York). Version: **1.22.2 (15)**.

## Delivery

The development JIT package was installed **in place** on both the iPhone 17 Pro
Max and iPad Air 11-inch (M3). Fresh device inventories confirm build 15 under
the established RetroArch Lab identifier. No app was uninstalled.

| Device | Previous build | Installed build | Documents entries retained | Save/configuration hashes matched |
| --- | --- | --- | --- | --- |
| iPhone | 14 | 15 | 45,573 of 45,573 | 21 of 21 |
| iPad | 13 | 15 | 6,139 of 6,139 | 78 of 78 |

The Documents comparison checks each recorded path, size and file/directory
type. It is not a full content hash of every game or firmware file. The smaller
recovery set hashes the selected saves, configuration and app metadata.
Copies were retained before installation. The broader initial recovery also
included iOS-managed launch snapshots; those can be regenerated during an app
update and are excluded from the save/configuration hash checks.

## Build and signature checks

- Full current development host compiled and linked with Lab.xcconfig,
  HAVE_RETROARCH_LAB_STIKJIT and HAVE_RETROARCH_LAB_RPCS3. Build succeeded.
- Native RPCS3 compiled and linked with WITH_LLVM=ON and
  RPCS3_IOS_JITLESS_ONLY=OFF. All 1,309 native build steps completed.
- Compilation records include the native JIT allocator, PPU LLVM translator,
  SPU LLVM recompiler and AArch64 JIT backend.
- The matching upstream iOS LLVM archive passed its published SHA-256 check.
- The microphone, logger-finalization and storage-capacity patches are retained.
- Packaged binaries include the JIT controls, LLVM execution self-test and
  sealed-arena build profile. The interpreter-only native build profile is absent.
- Eight preserved libretro cores plus native RPCS3 are present, including
  ARMSX2, Dolphin and Play!.
- The legitimate existing development profile authorizes the two devices,
  get-task-allow, Extended Virtual Addressing and Increased Memory Limit.
- Nested signing and deep strict signature validation passed.
- The focused physical-device UI-test runner built successfully.

The two production build commands ran locally. No hosted GitHub Actions build
was requested, and this change's commit includes [skip ci].

## Runtime acceptance blocked by device authorization

The iPhone UI test did **not** establish a successful JIT session. XCTest
timed out while enabling UI automation before the test body ran. A direct
device screenshot then showed Apple's **Enter iPhone Passcode for "XCTest" —
Enable UI Automation** prompt. The pending test session was stopped.

The iPad reported that its passcode was required, so its UI check was not
started. Installation and data verification completed despite that lock.

The owner must clear the iPhone's XCTest authorization prompt on the device
and unlock the iPad before the live checks can proceed. No passcode was read,
requested in chat or supplied by the automation.

The installed host restores the existing StikDebug launch workflow and requires
the actual LLVM execution self-test before enabling the PS3 library. However,
the Universal handshake, that self-test, a PS3 game boot and sustained gameplay
have **not yet been observed on build 15**. No FPS, audible-audio or full-speed
improvement is claimed.

## Artifact identities

| Artifact | SHA-256 |
| --- | --- |
| Unsigned host | 613895dbefc498787c5b763ea823739aa0170087df6e087ba1467bc4f37273cd |
| Unsigned native core | ccdae76a5be8e7c792687853d55bb73a8fa8b419bc072228e87f0f2966556389 |
| Signed native core | 43990496dd28ebc5a19df9a1d3f8f67e89aa1af977728e4aa7f6779e7613cf70 |

The host machine code uses build-14 source commit
088115472b5a2f88993709710e71f2b442580d5d with the development flags. This change
adds the packaging recipe, acceptance source and release record; it does not
change the already compiled host implementation.

Build commands, dependency manifests, logs, signed package and device recovery
copies are retained on the build Mac under
/Users/jamespauley/Developer/RetroArch-JIT-Build-20261108.
The prepared test names are StorageAcceptance/testRestoreJIT and
StorageAcceptance/testBootWithJIT. Start with the former after authorization.
Do not run the boot test until JIT initialization has succeeded.
