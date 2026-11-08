# Restore the development JIT build

The interpreter distribution recorded about 7.9 FPS during the owner's
20.1-second active PS3 sample from build 14. This recipe returns the established
RetroArch Lab app to its development configuration while retaining the PS3
microphone, logger and import-storage corrections.

## Build inputs

- Host source: build-14 commit 088115472b5a2f88993709710e71f2b442580d5d.
- Native core: XITRIX/rpcs3 f88bff947b83730c0cf8a3949f59338b992b3ca0.
- LLVM: XITRIX/LLVM-On-iOS release llvm-ios15-ca7933e47d3a3451-ec81b2304bcb.
- LLVM source revision: ca7933e47d3a3451d81e72ac174dcb5aa28b59d1.
- LLVM archive SHA-256:
  138446dbbd497f1c18a741aab85b27982ec62099f13e39f81abfbdc901160583.
- Existing MoltenVK 1.4.2 and FFmpeg 8.1.1 dependencies.
- Preserved full development build 8 for the eight libretro cores and the
  legitimate development provisioning profile.
- Build 14 resource app, preserving the current icon, resources and metadata.

Download the LLVM archive and its JSON/checksum companions from the exact
[upstream release](https://github.com/XITRIX/LLVM-On-iOS/releases/tag/llvm-ios15-ca7933e47d3a3451-ec81b2304bcb).
Verify the checksum before extraction. The manifest records the matching source
revision and the AArch64 GHC emergency-spill patch.

## Native core

Apply these existing patches to the pinned native source, in order:

1. ../testflight-interpreters/rpcs3-interpreter-only.patch
2. ../rpcs3-playback/native-core.patch
3. ../rpcs3-storage/native-core.patch

The first patch introduces a conditional build option. For this development
build, configure it **OFF**:

~~~sh
cmake -S /path/to/native-source -B /path/to/native-build -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=/path/to/iPhoneOS.sdk \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DRPCS3_FRONTEND=IOS \
  -DRPCS3_IOS_JITLESS_ONLY=OFF \
  -DWITH_LLVM=ON -DBUILD_LLVM=OFF -DUSE_LTO=OFF \
  -DLLVM_DIR=/path/to/LLVM-iOS15-arm64/lib/cmake/llvm \
  -DRPCS3_MOLTENVK_ROOT=/path/to/MoltenVK \
  -DRPCS3_FFMPEG_ROOT=/path/to/ffmpeg-ios-arm64 \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build /path/to/native-build --target RPCS3Core --parallel 3
~~~

This compiles JITIOS.cpp, PPU LLVM translation, SPU LLVM recompilation and
the AArch64 backend. It does not compile the interpreter-only allocator.

## Host and packaging

Use Lab.xcconfig, LAB_JIT_FLAGS=-DHAVE_RETROARCH_LAB_STIKJIT and
LAB_RPCS3_FLAGS=-DHAVE_RETROARCH_LAB_RPCS3. Keep the established
com.jamespauley.retroarchlab.ps3bridge identifier, iOS deployment target 26,
and the existing Lab iCloud-container build setting. The complete host command
is documented in ../rpcs3/README.md. Do not use TestFlight.xcconfig.

~~~sh
python3 package_development.py \
  --resource-app /path/to/build-14/RetroArch.app \
  --development-app /path/to/preserved-build-8/RetroArch.app \
  --host-app /path/to/HostDerivedData/Build/Products/Release-iphoneos/RetroArch.app \
  --native-core /path/to/native-build/rpcs3/libRPCS3Core.dylib \
  --output /path/to/new-development-package \
  --build 15 \
  --signing-identity DEVELOPMENT_SIGNING_IDENTITY
~~~

The packager requires the established identity, native JIT controls, the host's
LLVM execution self-test, a non-interpreter native core, and the existing
development profile's debugger and memory entitlements. It restores the
preserved JIT-capable libretro cores, including ARMSX2 and Play!, retains the
storage privacy declarations, signs nested code and verifies the complete
signature. It writes to a new directory and does not install or upload the app.

Before updating a device in place, inventory its Documents and retain save and
configuration recovery copies. Verify those files again after installation.
iOS-managed launch snapshots can change during installation; they are not
save-data preservation checks. Never uninstall the app as part of this update.

## Runtime acceptance

A build or a JIT button alone is insufficient. On a physical device:

1. Open **PS3 → Enable PS3 JIT**.
2. In StikDebug, approve **Enable and Run Script** for the established Lab
   identifier and its assigned universal.js.
3. Return to **PS3 → Start PS3**.
4. The existing host must complete the Universal handshake, initialize the
   native core and execute the LLVM self-test, which returns 22 for input 5.
   It enables Import only after those checks succeed.
5. Verify the game retains both PPU and SPU LLVM decoder settings and inspect
   the native runtime log after boot. Compare a repeatable gameplay scene
   with the earlier interpreter recording before claiming a performance gain.

This is a development installation. The interpreter TestFlight variant does
not contain this JIT execution path. Reinstalling that variant replaces this
development build.

See VALIDATION.md for actual build and device results. All work uses local
builds; publication commits include [skip ci].
