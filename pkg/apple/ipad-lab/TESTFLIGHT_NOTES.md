# TestFlight delivery notes

App record: [RetroArch Lab](https://appstoreconnect.apple.com/apps/6830930218/testflight)

Bundle ID: `com.jamespauley.retroarchlab.ps3bridge`

For each upload, save build-specific notes in App Store Connect's **What to Test**
field and reopen the build to verify them before making it available to testers.
App-level Test Information and pull request notes do not replace that field.

## Correct build reference — November 5, 2026

The owner identified the installed iPad app as the intended full RetroArch Lab
build. A fresh device inventory confirmed version 1.22.2 (8), development signed,
with the bundle ID above. Its installation path matched the build-8 install
receipt. The corresponding signed package includes ARMSX2 and Play! (PS2),
Dolphin (GameCube/Wii), the native RPCS3 bridge (PS3), and the existing NES,
SNES, 3DO and Saturn cores, plus Game Mode and the performance recorder.

Build 10 is a reduced distribution variant, not the replacement for that full
build. It reuses the same bundle ID and therefore must not be offered as the
owner's update. On November 5, 2026, build 10 was removed from Owner validation
with the owner's approval. App Store Connect confirmed the removal and displayed
**Groups (0)** on the build page. The build was not expired or deleted.

`archive_testflight.py` now refuses that full app identity before copying,
removing components, or signing. Any separately requested reduced TestFlight
variant requires its own provisioned base app and a different bundle ID. Do not
change the full app's identity or replace its installed package to work around
this check.

The signed build-8 reference was preserved on the build Mac with all 167 file
hashes matching the original installation artifact and deep signature
verification passing. Source tree: `06f85bcca841c84b2dc34a57bf49af84f2e5e415`.
Signed executable SHA-256:
`345c217e15be13dedf3100784114a1130c7af4ac3846a262d3ff1de212c64666`.
The device installation and its user data were not modified during this audit.
No new app build or hosted CI run was requested.

## Historical published notes: 1.22.2 (10)

Apple completed processing build 10 on November 5, 2026 (UTC), and marked it
Ready to Test. The following English (U.S.) notes were saved in What to Test,
then verified by leaving and reopening the build. The build was subsequently
added to Owner validation, with one internal tester.

[Build 10 in App Store Connect](https://appstoreconnect.apple.com/teams/624c8dce-c9b4-4f3d-9765-088e197cdb71/apps/6830930218/testflight/ios/c8f2932d-72a5-40da-8ce9-561952e0f668)

RetroArch Lab 1.22.2 (10) — Game Mode and performance recording

Distribution limitation: TestFlight signing does not allow the debugger-based JIT used by this Lab build. This package includes NES, SNES, 3DO and Saturn cores. PS2, PS3 and GameCube/Wii cores and developer JIT setup are excluded. Use the development installation for those systems. Installing this TestFlight build over the development app replaces its signing and removes that JIT access.

1. Start with NES, SNES, 3DO or Saturn. Open Library > Game Mode and confirm Hide routine popups starts enabled. Turn it off, close and reopen the app, and confirm your choice persists.
2. While a game is running, compare routine popups with the switch on and off. Warnings, errors, accessibility announcements, and messages in paused/menu states should remain available.
3. Set up Settings > Focus > Gaming with an App schedule for RetroArch Lab. Confirm silenced notifications do not display banners during play, and review allowed people/apps and time-sensitive exceptions. The app cannot turn Focus on itself.
4. Check Apple Game Mode in Control Center while playing full screen.
5. The performance recorder remains off until you start it. Record the same gameplay segment, mark a slowdown, stop and export the report. Confirm controller input, audio, save/load and returning to the library work normally. Do not assume an FPS improvement from the new setting alone.

Include device model, OS version, core/game, build number and reproduction steps in feedback.

## Packaging and delivery record

Build 8 was uploaded but rejected during Apple processing for development-only SecTask APIs and invalid Swift support packaging. It was not available in TestFlight.

Build 9 uses `TestFlight.xcconfig` to exclude the developer JIT and native PS3 integration. `archive_testflight.py` validates the host symbols, preserves the five supported cached cores, excludes the standalone PS3 dylib and JIT-dependent cores, and runs Xcode’s Swift runtime packager before signing. The development build retains those components.

Build 9 removed the private API issue but was rejected for an empty SwiftSupport folder (ITMS-90424). Build 10 uses the same compiled host and excludes that folder when Xcode finds no Swift runtime libraries to bundle.
