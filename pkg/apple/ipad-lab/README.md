# RetroArch Lab for iPad

A separate native iOS build for testing emulator-core changes. The first baseline
includes FCEUmm (NES/Famicom) and Snes9x 2010 (SNES), both compiled from source.
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
This build does not automatically enable JIT. The initial two cores do not depend
on JIT; adding demanding systems needs a separate compatibility assessment.

## Change a core

`cores.lock.json` pins each upstream repository to a full commit SHA. To test a
fix, update that SHA to a reviewed commit, or add ordered `.patch` files under
`patches/<core-name>/`. Patches apply to fresh pinned sources before compilation;
a patch that no longer applies stops the build. Commit and rebuild the complete
app, then sign/install it as an update to Lab.

The initial recipe supports cores with a root Makefile and an `ios-arm64` target
producing `<name>_libretro_ios.dylib`. Other cores may require different recipes,
submodules, dependencies, BIOS files, graphics support, or JIT. Add these explicitly
rather than assuming every core uses the same build command.

Retain a known-good IPA, manifest, source revision, and save backup. To roll back,
rebuild the earlier commit or re-sign the retained IPA using the same identity.
GitHub artifacts expire after 14 days; download any build you want to retain.
