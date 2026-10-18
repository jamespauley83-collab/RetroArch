# RetroArch Lab for iPad

A separate native iOS build for testing emulator-core changes. The first baseline
includes FCEUmm (NES/Famicom), Snes9x 2010 (SNES), Opera (3DO), Dolphin (GameCube/Wii),
Play! (PlayStation 2), Beetle Saturn and Yabause (Sega Saturn),
all compiled from source. Opera includes a local startup diagnostic patch.
This is an initial development build, not a confirmed fix for any game.

## Build

Use the **RetroArch Lab iPad** GitHub Actions workflow. It builds on a hosted Mac;
a Windows PC can be used later for signing/sideloading. Fork workflows may need
to be enabled in the repository's Actions tab. Once this workflow is on the
default branch, it can also be launched with **Run workflow**, selecting the
branch or tag to build. The development branch builds on relevant pushes.

Alternatively, on a Mac with full Xcode and its iOS SDK installed:

```sh
python3 pkg/apple/ipad-lab/build.py --check
python3 -m unittest discover -s pkg/apple/ipad-lab/tests -v
python3 -u pkg/apple/ipad-lab/build.py
```

Commit changes before building. The script exports committed HEAD into a new
`.ipad-lab-build/` directory; it does not modify your checkout's Apple project,
assets, installed apps, or core files. Build logs remain in that directory if a
step fails. The existing committed assets bundle provides menus, touch overlays,
and core information. No ROMs or BIOS files are included.

The output artifact contains `RetroArch-Lab-unsigned.ipa`, exact core sources,
licenses, and a build manifest recording source commits, patches, Xcode/SDK
versions, and checksums. The frontend source is the manifest's `retroarch_commit`
in https://github.com/jamespauley83-collab/RetroArch.

Each core's `sha256` hashes the final framework executable at its `binary_path`
inside the unsigned IPA, after framework conversion and build-time signing.
The build checks those hashes against the completed IPA. The embedded
`retroarch-lab-build.json` records the same core paths and hashes; the external
`build-manifest.json` also includes `ipa_sha256` for the whole archive.
Verify these before device signing, which can change the executable bytes.

## ARMSX2 integration candidate

**For first physical-device testing, use the separate
[eight-core test copy](EIGHT-CORE-DEVICE-TEST.md).** The original
`RetroArch-Lab-unsigned.ipa` uses the working Lab identity and is an update, not
a side-by-side test install. The workflow now also produces an `eight-core-test`
subfolder with `RetroArch-Lab-8-Test-unsigned.ipa`, a separate identifier and no
widget. Sign it without cloud/app-group entitlements and use fresh local copies.
The standalone `package_eight_core_test.py` can derive it from an already
verified artifact without recompiling emulator code. Successful candidate cloud
sync is deferred to a dedicated-container build; do not authorize this test copy
to access the working Lab container.

ARMSX2 is the recommended PS2 core for the optional eight-core candidate. On
October 16, 2026, James reported that Need for Speed passed game boot, graphics,
sound, controls, in-game save/load, and reopening/reloading in **RetroArch PS2
Test**, and performed much better than Play!. The exact game edition, device/OS,
and installed build revision were not recorded. This is a user-reported result
for one game, not a benchmark or acceptance of every subsequent build.

On October 17, James also reported that a game now runs through ARMSX2 in
**RetroArch Lab 8 Test** after assigning `universal.js` to that app and retrying.
This records launch recovery in the combined app; its save/reload and
core-switching checks remain separate. See the
[launch investigation](PS2-LAUNCH-INVESTIGATION-2026-10-17.md) for the failure
stage, source comparison and evidence limits.

Pull requests run the eight-core candidate build. For a manual run, use
**RetroArch Lab iPad** with `with_armsx2` enabled on this integration branch.
The workflow builds the corrected ARMSX2 device-test core from the same revision
before adding it to the normal Lab app. For a local Mac build, prepare a fresh
`.armsx2-prototype/source` checkout at the pin in the experiment workflow, then:

```sh
bash pkg/apple/ipad-lab/experiments/armsx2/build.sh device-test
python3 pkg/apple/ipad-lab/build.py --check --with-armsx2
python3 -u pkg/apple/ipad-lab/build.py --with-armsx2
```

This candidate requires **iOS 26.0+ with working JIT access**. Pre-26 frontend
WX-toggle allocations are rejected; see the [compatibility rationale](experiments/armsx2/README.md#ios-compatibility).
The ordinary seven-core build without ARMSX2 retains its existing minimum OS. It retains the seven baseline cores, library,
Lab identity and iCloud configuration, adding ARMSX2 and its source provenance.
The ordinary build without this option retains the seven-core/iOS 15 baseline.
The combined app still needs its own build and device validation; the separate
PS2 Test app result does not validate combined-app lifecycle or iCloud behavior.

For isolated testing, extract the supplied `ARMSX2-system-files.zip` into
**RetroArch Lab 8 Test**'s configured System/BIOS directory and copy your PS2 BIOS
into its `pcsx2/bios` subfolder. Enable JIT for that exact app,
`com.jamespauley.retroarchlab.eightcoretest`, with its assigned `universal.js`;
activation for working Lab or PS2 Test does not activate this process.
In Advanced, choose **Sony - PlayStation 2 (ARMSX2 Lab - Recommended)** and assign
it to the local test games you want to use from the library. Existing Play!
assignments are not rewritten; Play! remains a fallback.

The current source delegates ARMSX2 validation to its own mode 2/4 arena check
for both launch routes; Dolphin and Play! retain the generic Library JIT gate.
The existing Files-Fix IPA predates this correction and the new failure
diagnostics. A targeted iPhoneOS build is still required to validate those source
changes; the reported launch recovery is not a test of that unbuilt code.

Keep the working PS2 Test app and its saves. This build does not migrate its
sandbox, convert Play! memory cards, or establish ARMSX2 iCloud save coverage.
Use copied test data first and verify saving/reloading and switching between
ARMSX2 and a non-PS2 core in the combined app.

## Install and test

The IPA is **not device-signed and cannot be installed directly**. Its embedded
frameworks have only build-time ad-hoc signatures. A signing/sideloading tool must
sign the app, its extension, and all embedded frameworks using your Apple account.
Keep Apple credentials and certificates out of this repository and CI.

Use `com.jamespauley.retroarchlab` consistently for this app; the widget uses its
own suffix. The display name is **RetroArch Lab** and its URL scheme is
`retroarchlab`. This identity is separate from the official app. Sideloading tools
may add account-specific identifiers: keep the same signing account and identity
for later updates. Do not uninstall the original RetroArch app.

Before testing, export copies of saves, save states, configuration, and playlists
from the original app. Import copies into Lab using Files; each app has its own
sandbox. A save state from another core/version may not load; keep in-game saves
as well. Test one game at a time, including touch/controller input, audio, graphics,
in-game saving, restarting, and loading that save.

Device signing, installation, and real iPad gameplay must still be verified.
This build does not automatically enable JIT. Dolphin needs a separate JIT setup
for practical performance, and Play! requires it to start a game; see below.

## Yabause Saturn option

Yabause is included at upstream revision
`8926b0c6c347f8c5c755911ddb0ac695420ffbf8`, using the upstream ARM64 iOS Makefile
with both dynamic recompilers disabled and the app's deployment target. It uses
software rendering and does not require StikDebug/JIT. James requested Yabause
as his preferred Saturn option; performance in this Lab build is still pending
physical-device comparison. Beetle Saturn remains installed and existing Saturn
playlist assignments stay unchanged.

1. Put a copy of your Saturn BIOS in Lab's System/BIOS directory named
   `saturn_bios.bin`. Preserve the originals used by Beetle Saturn. A real BIOS
   is recommended and is required for multi-disc `.m3u` playback.
2. In Advanced, choose **Load Core > Sega - Saturn (Yabause)** and load a `.chd`
   or `.cue` with all referenced binary tracks. Assign Yabause explicitly to the
   desired playlist entries to launch them from the native library.
3. Use separate per-core save/state folders for comparison. Yabause writes its
   own `<content-name>.srm` in the configured Save directory; Beetle uses its
   own formats. Do not rename or convert Beetle saves or reuse its save states.
4. Test graphics, audio, input, pause/resume, normal content close, and an in-game
   save followed by app restart/reload. Compare the same game/scene against
   Beetle. Keep normal close-content in the test: Yabause owns backup-RAM file
   writes rather than exposing SRAM through RetroArch's memory callbacks.

No BIOS or game files are included. See the
[upstream Yabause documentation](https://docs.libretro.com/library/yabause/).

## Sega Saturn setup

This build includes **Sega - Saturn (Beetle Saturn)**, compiled from the pinned
`mednafen_saturn` source. Its iOS ARM64 implementation uses the interpreter;
StikDebug/JIT is not required for this core. Game performance still needs to be
checked on the device. Start with the core defaults and leave experimental JIT
options alone; the pinned core's JIT backends do not support iOS ARM64.

1. Install this IPA as an update using the same Lab identity, signing account,
   and custom iCloud entitlements as the existing app. Keep your saves backed up.
2. In Lab, check **Settings > Directory > System/BIOS**. Copy your BIOS files
   directly into that directory using Files. Lab has its own sandbox; BIOS files
   in the original RetroArch app are not automatically available here.

   | Region | Filename | MD5 |
   | --- | --- | --- |
   | North America / Europe | `mpr-17933.bin` | `3240872c70984b6cbfda1586cab68dbe` |
   | Japan | `sega_101.bin` | `85ec9ca47d8f6807718151cbcca8b964` |

3. Select **Load Core > Sega - Saturn (Beetle Saturn)**, then check
   **Information > Core Information** for the required firmware. The extra
   cartridge ROMs listed there are only needed for their named games.
4. Use **Load Content** to open a `.chd`, or a `.cue` stored alongside all of
   its referenced `.bin` tracks. Extract ZIP/7z archives first. Select the `.cue`,
   not an individual `.bin` track. `.m3u`, `.ccd`, and `.toc` are also supported.
5. Test one game with the existing video driver and default core settings.
   Check picture, audio and controls, then make an in-game save. Close the
   content normally, reopen Lab, and confirm the save loads. Report the game,
   region and FPS if it runs slowly before changing global settings.

No BIOS or game files are supplied. The ordinary Saturn saves (`.bkr`, `.bcr`,
`.smpc`) use RetroArch's configured Save directory; save states use its State
directory. Verify any desired cloud sync separately.

Reference: [Libretro Beetle Saturn documentation](https://docs.libretro.com/library/beetle_saturn/).

## Change a core

`cores.lock.json` pins each upstream repository to a full commit SHA. To test a
fix, update that SHA to a reviewed commit, or add ordered `.patch` files under
`patches/<core-name>/`. Patches apply to fresh pinned sources before compilation;
a patch that no longer applies stops the build. Commit and rebuild the complete
app, then sign/install it as an update to Lab.

The Makefile recipe supports cores with a root Makefile and an `ios-arm64` target
producing `<name>_libretro_ios.dylib`. Dolphin uses its upstream iOS CMake recipe
and pinned recursive submodules, excluding the Windows Qt and FFmpeg SDKs.
Play! uses its upstream iOS Xcode/CMake recipe and pinned recursive submodules,
excluding the standalone app's AltKit dependency.
Other cores may require different recipes,
submodules, dependencies, BIOS files, graphics support, or JIT. Add these explicitly
rather than assuming every core uses the same build command.

Retain a known-good IPA, manifest, source revision, and save backup. To roll back,
rebuild the earlier commit or re-sign the retained IPA using the same identity.
GitHub artifacts expire after 14 days; download any build you want to retain.

## Opera diagnostics

Opera writes `opera-lab-diagnostic.log` directly into the frontend's configured
Save directory. The log records the exact BIOS paths checked, the selected BIOS,
ROM read sizes, the content path, disc-open results, and startup/frame milestones.
It also shows a ten-second notification if no BIOS was loaded. The log appends
across launches and records local paths; inspect it before sharing.

Copy your existing BIOS and one game into Lab's own storage before reproducing
the issue. This app cannot read the original app's private sandbox. Check Lab's
System/BIOS and Save directories to locate the files and the diagnostic log.
After reproducing the black screen, export the log using Files or Apple Devices
file sharing. This is an instrumented build, not a verified fix for the game.

Opera is pinned to upstream `ea60917d7f8f79a19b46e1d8ecc6eca7be589b6a`.
Its core information is copied from libretro-core-info blob
`d8447c579efd7425edc06b6e03697abfeebee062` and overlaid only in the exported
build tree. The committed shared assets bundle is unchanged.

## iCloud Drive sync

Lab includes the `icloud_drive` backend at **Settings > Saving > Cloud Sync >
Cloud Sync Backend**. It uses `iCloud.com.jamespauley.retroarchlab`, separate
from the official RetroArch app's container. Lab installations on your iPhone
and iPad can share this container when signed by the same developer team and
used with the same iCloud account. It cannot access the official app's cloud saves.

The unsigned artifact includes `RetroArch-Lab-iCloud.entitlements`. Enabling the
menu option alone is not sufficient: the signed app and its provisioning profile
must both authorize that exact container and the `CloudDocuments` service.

1. In Apple Developer Certificates, Identifiers & Profiles, register the iCloud
   container `iCloud.com.jamespauley.retroarchlab` under your developer team.
2. Enable iCloud Documents on the **existing installed Lab app's explicit App ID**,
   associate that container, and regenerate its development provisioning profile.
   Preserve the existing signing team and installed bundle identity when updating.
3. Re-sign the IPA with that profile and the supplied iCloud entitlements, preserving
   the normal signing entitlements supplied by your signer. Use a signing tool that
   retains custom entitlements. Sideloadly documents this as a Patreon feature for
   Apple Developer Program members; ordinary sideloading may strip them.
4. Install as an update to Lab, keeping a backup of its saves. On each device,
   enable iCloud Drive in iOS Settings, then enable Cloud Sync in Lab, choose
   `icloud_drive`, enable Sync Saves, and leave Destructive Cloud Sync off.
5. Save the configuration and restart Lab. Verify successful sync with one test
   save on the first device before testing a download on the second device.

The build records the container in `build-manifest.json`. CI verifies compilation,
packaging and driver behavior with a simulated container; a real two-device sync
requires device signing and cannot be established by the unsigned build.

References: [Apple iCloud setup](https://developer.apple.com/documentation/xcode/configuring-icloud-services),
[Sideloadly changelog](https://sideloadly.io/changelog.html).

## Dolphin (GameCube / Wii)

Install the new IPA as an update to **RetroArch Lab**, using the same signing
account and bundle identity as before. Keep a copy of Lab's saves first.
The build preserves the existing three cores and adds `dolphin.libretro.framework`.
Dolphin is built from the revision in `cores.lock.json`; its submodule revisions
and final packaged executable checksum are recorded in the build manifest.
Core metadata is from libretro-core-info revision
`5a74858ab2f7a50cebb5a6330895bc38899531c0`.

1. Extract the accompanying `Dolphin-system-files.zip`. Copy its `dolphin-emu`
   folder into Lab's **Settings > Directory > System/BIOS** location. Confirm
   `dolphin-emu/Sys/codehandler.bin` exists there. These are Dolphin's support
   files from the same source revision; games and Nintendo BIOS dumps are not included.
2. In Lab, run **Online Updater > Update Core Info Files** if upgrading an existing
   installation, then restart. Choose **Load Core > Nintendo - GameCube / Wii (Dolphin)**.
3. Use **Settings > Drivers > Video > vulkan**, save the configuration and restart
   Lab before loading a game. The frontend already bundles MoltenVK; Dolphin's
   libretro hardware renderer does not use RetroArch's `metal` driver directly.
4. Enable JIT for **RetroArch Lab** through your compatible signing/debugging setup
   before loading a game. Installing this IPA does not enable JIT. Without JIT,
   Dolphin may fall back to its slower interpreter.
5. Load one GameCube game copied into Lab's own storage. Start at native resolution
   and verify graphics, audio, controller input, an in-game save, and loading that save.

Compilation and package validation do not establish device compatibility or game
performance. Those checks require the signed build running on the iPad.

## Play! (PlayStation 2)

See [PS2 development](PS2-DEVELOPMENT.md) for the audio-buffer refinement,
PCSX2-derived ARM64 candidates, and the device comparison procedure.

The Lab build includes `play.libretro.framework`, compiled from the pinned Play!
revision in `cores.lock.json`. Its source and dependency revisions are included
in the build artifact and manifest. Core metadata is from libretro-core-info blob
`b91e6d04d33a86694d1e14ed8f3cddd962805f33`.

1. Sign and install the new IPA as an update to Lab using the same account, bundle
   identity, and custom iCloud entitlements used for the previous build.
2. Run **Online Updater > Update Core Info Files** on an existing installation,
   then restart. Choose **Load Core > Sony - PlayStation 2 (Play!)**.
3. Select **Settings > Drivers > Video > gl**, save the configuration, and restart
   Lab. This core uses OpenGL ES on iOS. Dolphin uses `vulkan`, so change the driver
   and restart when switching between these two cores.
4. Enable JIT for **RetroArch Lab** before loading a PS2 game. The Lab patch uses
   RetroArch's executable-memory API on iOS 26 and newer, including separate
   executable and writable mappings. Earlier iOS versions retain the legacy JIT
   path. VM initialization is deferred until this check succeeds; if JIT is not
   ready, enable it and retry the game.
5. Load an extracted PS2 `.iso` or `.chd` from Lab's storage. Play! does not require
   a PS2 BIOS. Start at the native **1x** resolution and test graphics, audio,
   controller input, an in-game save, and loading that save after restarting.

Play! is experimental; compatibility and speed vary by game. Compilation and
packaging checks do not establish real iPad gameplay. Its memory cards and
configuration use the upstream `Play Data Files` directory in the app's Documents
folder. Back up that folder as well as RetroArch's saves; do not assume the cloud
Sync Saves option includes it.

The Lab-only Play! patch also routes block linking and cloning through the writable
mapping and recycles freed code within a frontend-owned arena. The build runs a
host regression harness against the patched CodeGen sources before compiling iOS.
This covers separate read/write mappings, block edits, clone/move ownership,
exhaustion, free-space reuse, concurrency, unavailable JIT, retry, and cleanup.
Linux x86-64 additionally executes generated and patched code in the harness.

References: [Play! source and iOS instructions](https://github.com/jpd002/Play-),
[Libretro Play! documentation](https://docs.libretro.com/library/play/).

