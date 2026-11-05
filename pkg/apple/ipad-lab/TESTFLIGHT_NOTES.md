# TestFlight delivery notes

App record: [RetroArch Lab](https://appstoreconnect.apple.com/apps/6830930218/testflight)

Bundle ID: `com.jamespauley.retroarchlab.ps3bridge`

For each upload, save build-specific notes in App Store Connect's **What to Test**
field and reopen the build to verify them before making it available to testers.
App-level Test Information and pull request notes do not replace that field.

## Prepared notes: 1.22.2 (10)

These notes are prepared for the internal TestFlight package. Their presence here
does not confirm that Apple has processed or distributed the build.

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
