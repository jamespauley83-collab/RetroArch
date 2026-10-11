# RetroArch Lab for iPad

A separate native iOS build for testing emulator-core changes. The first baseline
includes FCEUmm (NES/Famicom), Snes9x 2010 (SNES), Opera (3DO), Dolphin (GameCube/Wii),
and Play! (PlayStation 2),
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
4. Enable JIT for **RetroArch Lab** before loading a PS2 game. Play!'s iOS core
   checks the frontend's JIT capability and refuses to load when it is unavailable.
5. Load an extracted PS2 `.iso` or `.chd` from Lab's storage. Play! does not require
   a PS2 BIOS. Start at the native **1x** resolution and test graphics, audio,
   controller input, an in-game save, and loading that save after restarting.

Play! is experimental; compatibility and speed vary by game. Compilation and
packaging checks do not establish real iPad gameplay. Its memory cards and
configuration use the upstream `Play Data Files` directory in the app's Documents
folder. Back up that folder as well as RetroArch's saves; do not assume the cloud
Sync Saves option includes it.

References: [Play! source and iOS instructions](https://github.com/jpd002/Play-),
[Libretro Play! documentation](https://docs.libretro.com/library/play/).
