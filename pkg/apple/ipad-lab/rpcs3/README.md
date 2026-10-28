# Native XITRIX RPCS3 bridge

This optional RetroArch Lab destination hosts the XITRIX Preview 0.12 native
ABI 30 core. It is a private experimental build for the M3 iPad Air, not a
libretro core. The user's standalone RPCS3 0.12 has verified JIT, firmware and
gameplay; that does not establish gameplay in this new host.

## Isolation and behavior

- Candidate identity: `com.jamespauley.retroarchlab.ps3bridge`, display name
  **RetroArch PS3 Bridge**, URL scheme `retroarchlabps3bridge`.
- PS3 data is private to this candidate at `Documents/PS3/Data`; its disposable
  cache is `Documents/PS3/Cache`. No working-app container is opened or migrated.
- Import firmware PUP, decrypted ISO, PKG, RAP, or an extracted game folder.
  Security-scoped sources stay readable for the whole coordinated import and
  are never deleted. This prototype does not import encrypted ISOs with a
  separate key, ZIPs, saves or savestates through its UI.
- **Enable PS3 JIT** opens StikDebug for this running bundle and `universal.js`.
  Return to the bridge and tap **Start PS3**. It checks the development profile,
  takes Lab's activation lease, probes Universal without detaching, then loads
  the core. RPCS3 prepares its own arena and runs its LLVM execution self-test.
  Lab's built-in helper is not used for PS3 in this candidate.
- The core stays loaded for the lifetime of the process. Initialization failure
  after loading requires restart. Stop permits another PS3 game; switching
  back to other Lab systems requires restarting the candidate.
- Boot/import/stop/pause work is serialized off the UI thread. The main-thread
  callback is dispatched asynchronously; Metal resize, input and boot-progress
  callbacks use upstream's independently synchronized interfaces.
- Backgrounding releases inputs and queues pause, including during boot.
  Returning to the foreground does not resume play automatically. A failed
  stop retains the surface and permits retry. The surface is detached only
  after a successful stop; the dylib is never unloaded.
- Up to seven extended controllers are polled. Touch provides digital buttons;
  a physical controller provides analog sticks. Rumble, RetroArch savestates,
  shaders, rewind and other libretro-only controls are not integrated.

## Build on the Mac

Use Xcode with its Metal Toolchain installed. From the repository root:

```sh
xcodebuild -project pkg/apple/RetroArch_iOS13.xcodeproj \
  -scheme 'RetroArch iOS Release' -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath /absolute/work/DerivedData \
  -xcconfig pkg/apple/ipad-lab/Lab.xcconfig \
  IOS_BUNDLE_IDENTIFIER=com.jamespauley.retroarchlab.ps3bridge \
  LAB_JIT_FLAGS=-DHAVE_RETROARCH_LAB_STIKJIT \
  LAB_RPCS3_FLAGS=-DHAVE_RETROARCH_LAB_RPCS3 \
  LAB_ICLOUD_CONTAINER=iCloud.com.jamespauley.retroarchlab.ps3bridge \
  RA_IPHONEOS_DEPLOYMENT_TARGET=26.0 ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= APPSTORE_BUILD= build

python3 pkg/apple/ipad-lab/rpcs3/package.py \
  --host-app /absolute/work/DerivedData/Build/Products/Release-iphoneos/RetroArch.app \
  --xitrix-ipa /absolute/path/RPCS3-ios-arm64-armv8.4-a-unsigned.ipa \
  --output /absolute/work/new-candidate
```

The packager verifies both release IPA and native-core SHA-256, checks the host
identity and bridge class, writes a new output directory, removes unrelated
extension/provisioning material, and preserves its inputs. It does not download,
sign, install, or publish a binary. Other Lab cores are packaged by the existing
Lab recipes; they are not downloaded by this PS3 recipe. Keep the working
multi-core app for other systems until combined-process behavior is accepted.

Signing requires a **new profile for the candidate identifier** authorizing
Extended Virtual Addressing, Increased Memory Limit and `get-task-allow`.
The successful standalone profile also uses Sustained Execution. Sign embedded
code before the outer app. Do not reuse the standalone bundle identifier or
install over any existing Lab identity. See NOTICE.md for binary redistribution
limitations; this repository contains bridge source and the interface, not the
combined emulator binary.

## Tests

```sh
python3 -m unittest discover -s pkg/apple/ipad-lab/tests -p 'test_*.py'
python3 -m unittest discover -s pkg/apple/ipad-lab/rpcs3 -p 'test_*.py'
cc -std=gnu89 -Wall -Wextra -Werror pkg/apple/ipad-lab/rpcs3/api_test.c -o /tmp/ps3-api-test
/tmp/ps3-api-test
bash pkg/apple/ipad-lab/tests/check_library.sh
cd pkg/apple/ipad-lab/rpcs3
xcodegen generate --spec tests.yml
xcodebuild -project RPCS3BridgeTests.xcodeproj -scheme BridgeTests \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' test
```

The six native lifecycle tests inject a fake ABI into the actual bridge
controller. They cover callback data ownership, duplicate boot rejection,
stop during boot, stop failure/retry, pause across background/foreground, and
missing JIT. They do not execute the device RPCS3 binary. The API harness rejects
ABI 29/31 and each missing required symbol without exposing a partial API.
The six packager tests cover identity, input preservation, tampering and output
collision.

For the full UI test, build the Lab host for the simulator with the same flags,
install it under the candidate identifier using `simctl`, then run the
`LabUITests` scheme. It verifies native-library startup, PS3 navigation and
recoverable missing-JIT behavior in the full RetroArch application.

## Physical acceptance still required

1. Provision and install only the candidate. Verify all working app identities
   remain installed. Do not terminate a working gameplay session to run tests.
2. Attach Universal to the candidate and start PS3. Verify ABI loading and LLVM
   self-test. Missing JIT must remain recoverable without loading the core.
3. Import a copy of firmware and a game into the candidate. Confirm the source
   files and standalone library remain unchanged.
4. Verify image, sound, analog/digital input, rotation, pause/resume, app switch
   and reconnect behavior. Save in-game, stop, reboot the title and verify save
   reload. Repeat after candidate process restart.
5. Check stop during compilation, stop failure handling, and repeated PS3 title
   changes. Compare behavior with the accepted standalone baseline.

Do not mark physical gameplay accepted or merge this candidate on the strength
of simulator tests alone.
