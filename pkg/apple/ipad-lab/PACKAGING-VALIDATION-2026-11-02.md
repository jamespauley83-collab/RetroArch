# iPad core packaging correction — November 2, 2026

PR: [#17](https://github.com/jamespauley83-collab/RetroArch/pull/17).
Published code fix: `163a859ee8bf5c4f4f2e4ec74cd8c769d87fadee`.
Locally built revision: `1c50624`; its complete Git tree matches the published
code commit (`d7f7288aec44313b54e37de51f92baa4403d2e18`).
This report does not claim physical PS3 gameplay acceptance.

## Root cause

[Run 41388765224](https://github.com/jamespauley83-collab/RetroArch/actions/runs/41388765224),
job `125095346413`, built the cores and the ARM64 app but failed final validation
with `ValueError: Packaged core is missing: fceumm`.

The archived FCEUmm compiler log contains its successful link command targeting
`fceumm_libretro_ios.dylib`. The build then passed its ARM64 check and
`shutil.copy2(binary, modules)`; either failure would have stopped before Xcode.
The expected staging path is `pkg/apple/iOS/modules/fceumm_libretro_ios.dylib`,
and the expected final path is
`RetroArch.app/Frameworks/fceumm.libretro.framework/fceumm.libretro`.
Neither naming nor destination needed correction.

In the uploaded `xcodebuild.log`, line 2258 reports:

> ./make-frameworks.sh: Permission denied

Line 2353 nevertheless reports `** BUILD SUCCEEDED **`.
Commit `73235fc` accidentally changed the script's Git mode from `100755`
to `100644`. Its direct invocation failed, so framework conversion never ran;
subsequent successful filter-copy commands masked that failure. FCEUmm is the
first core checked, not the only core affected. This is separate from the earlier
SDL download timeout, which the reported run had already passed.

## Correction

- Restore `pkg/apple/make-frameworks.sh` to executable mode `100755`.
- Propagate its failure immediately in the iOS and tvOS phases of
  `RetroArch_iOS13.xcodeproj`.
- Exercise the actual project build-phase text with an execution failure, a
  non-executable script, and successful iOS filter copies from paths with spaces.

No core recipes, versions, binary naming, app identities, runtime code or
`build.py` validation requirements were changed.

## Local verification

Performed on the user's M5 MacBook Air with Xcode 27.2 / iPhoneOS SDK 27.2.

- Reproduced the non-executable-script and masked-phase-failure defects before
  the fix. The focused tests pass after it.
- 20 build/packaging tests passed, including the three added tests and existing
  missing-core, identity, metadata and final-IPA hash checks.
- Six PS3 package tests passed, including isolated identity and input preservation.
- A fresh `git archive` of `1c50624` retained executable permission.
- One complete local ARM64 Release device app build passed using the same
  eight-core / iOS 26 configuration as the failed workflow, without StikJIT.
- The real framework phase embedded FCEUmm, Snes9x 2010, Opera, Dolphin, Play!,
  Beetle Saturn, Yabause and ARMSX2.
- `validate_app`, ARM64 checks, strict signatures for all eight core frameworks
  and MoltenVK, and `package_app` final-archive hash checks passed.
- The subsequent `package_eight_core_test.py` step passed, checking archive
  integrity, exact framework inventory, iOS deployment, dynamic dependencies,
  core metadata, isolation and unchanged executable bytes in the derivative.
- `git diff --check` passed.

The emulator cores were reused from the existing verified `0aee453` archive
after checking the original IPA and every core against its recorded SHA-256.
All seven locked cores match current source commits and patch hashes exactly.
Cached ARMSX2 has the same source commit and five runtime patches; the sole
difference is `0006-sdl-release-download.patch`, which changes only the SDL
download URL, preserving its version and checksum. The failed hosted run already
compiled ARMSX2 with that patch successfully. The local validation manifest
records this exception and marks the artifact `validation_only: true`.
This is not a claim that all cores were rebuilt at the current revision.

Validation IPA SHA-256:
`aa5387584e2f7a1e50424324b34ce8c9208e4b5610ea4a837077185e2e6685ef`.

Isolated eight-core test IPA SHA-256:
`62fce4d41fdc72990450a15331069d7156803e9eada3ca70abcf233ba682b040`.

Local artifacts and logs are under
`/Users/jamespauley/Developer/RetroArch-Packaging-20261102/.ipad-lab-build/local-packaging-validation-verified/`.
The verification driver and retrieved CI logs are under
`/tmp/retroarch-packaging-20261102/`.

## Release boundary

The packaging blocker is resolved and the skipped downstream eight-core
packaging validation has now passed locally. No GitHub Actions build was
dispatched or rerun; the correction commits use `[skip ci]`. The historical
failed run remains failed.

These are unsigned validation artifacts, not newly installed releases.
The local eight-core build uses the workflow's standard flags, not the optional
RPCS3 host flag. Prior native-bridge/simulator validation remains documented in
[VALIDATION-2026-11-01.md](rpcs3/VALIDATION-2026-11-01.md);
no new PS3 device acceptance is implied.

Keep PR #17 in draft. Full PS3 level gameplay, physical controller input and
in-game save/reload remain separate outstanding acceptance items. The user's
audio confirmation applies to installed bridge build 4. Existing Lab apps,
the separate PS3 bridge and standalone RPCS3, games, firmware and saves were
not modified by this work.
