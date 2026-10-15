# RetroArch Lab library home

This Lab-only iPhone/iPad screen uses the existing RetroArch playlists, history, favorites, and installed cores. It is not a port of the Simple Launcher desktop application. Normal RetroArch and tvOS builds do not enable it.

## Using the screen

- Lab opens to the library when no game is running. Search titles or systems, use the system menu, or switch between All games, Recent (latest 10), and Favorites.
- Existing local box art is read from the configured thumbnails directory under `<database>/Named_Boxarts/<sanitized title>.png`. The original entry database name takes precedence, including for games found only in history or favorites; entries without it fall back to their playlist/system name. Missing art uses a controller placeholder. No online artwork service is contacted.
- Tap a game to use its explicitly assigned core. Assign missing cores through Advanced. Disc-image extensions never choose a console automatically.
- Advanced opens the regular RetroArch menu. Swipe down with **four fingers** to return to the library. Resume returns to the current game. Switching away from a running game asks for confirmation.
- Empty libraries can be populated using the existing Advanced > Import Content workflow. Recently played entries also appear in All games. This screen does not move, rename, import, or delete ROMs.

The screen checks readable content, a uniquely matching installed assigned core, and JIT for the Lab Dolphin and Play! cores. BIOS verification and core-specific runtime failures still use the existing RetroArch diagnostics. A queued launch is not proof of successful gameplay.

## Preservation and limits

Core revisions, patches, bundle ID, iCloud container, signing entitlements, save locations, and graphics configuration are unchanged. Existing favorite entries are displayed; adding or removing favorites still happens in Advanced. Native controller navigation, a dedicated console-tile screen, automatic artwork retrieval, in-screen core assignment, and detailed sync status are not part of this milestone.

Emulation frames are held while the native library is visible, while the normal task queue remains serviced. The display-link path resumes when the library is dismissed. Verify this lifecycle on hardware, especially during game switching, background/foreground transitions, and JIT activation.

## Validation

Run `python3 -m unittest discover -s pkg/apple/ipad-lab/tests -v` and `python3 pkg/apple/ipad-lab/build.py --check`.

On macOS with Xcode, run `bash pkg/apple/ipad-lab/tests/check_library.sh`. It executes the Foundation library-helper checks and type-checks the iOS screen against the iPhoneOS SDK. The Lab workflow runs these before compiling and packaging all six cores and the app.

Before installing a candidate, verify its workflow and packaged manifest. Check the IPA SHA-256, all six packaged core hashes, the source revision, bundle identifier, and iCloud container. Keep the previous working IPA. Do not treat a successful build as a completed hardware test.

### Test without replacing the working app

1. Close running content and complete any pending sync in the working app. Copy its saves, save states, playlists (including history and favorites), configuration, BIOS/system files, and thumbnails to a dated backup outside the app. Check that the copied files can be read. Keep the working IPA and signing details.
2. Prepare a separately signed **RetroArch Lab Library Test** copy with a distinct bundle identifier, for example `com.jamespauley.retroarchlab.librarytest`. In Sideloadly, use a custom bundle ID in Advanced Options. Check the identifier in the resulting signed IPA against the actual installed working app; automatic signing may have changed the working ID. Stop if they match or the installer proposes replacing it. Leave this repository's production identity unchanged.
3. Keep cloud sync disabled in the test app. Do not reuse the production iCloud entitlement/container for this first test. A different bundle ID alone does not isolate a shared iCloud container. If the signer cannot produce the required separate identity and entitlements, stop before installing.
4. Confirm both apps coexist. Copy a small disposable game set and the necessary BIOS/system files into the test app's own Documents directory. Use copies of saves, never the only originals. Update test playlist game paths to the test sandbox; paths inside the working app's sandbox are not accessible.
5. Test a Saturn entry with the legacy `mednafen_saturn_libretro_ios.dylib` assignment and no ordinary Saturn playlist. Check its cover from `thumbnails/Sega - Saturn/Named_Boxarts` in Recent and All games. Repeat with a favorites-only entry and its original database folder. Check multiple installed cores and a missing/ambiguous core assignment, which must be refused.
6. Complete the hardware checks below using disposable copies. Activate JIT for the test app when checking Dolphin and Play!; the working app's JIT session does not establish test-app readiness.
7. Test iCloud separately with an explicitly provisioned test-only container and disposable data, or leave that check pending. Only after the device checks pass and backups are verified should an in-place update of the working app be considered, using its existing signing account, identifier, and iCloud entitlements. Do not uninstall the working app.

A separately signed app verifies library behavior in its own sandbox. It does not prove an in-place upgrade or production iCloud synchronization has passed.

On both iPad and iPhone, check layout in portrait/landscape, search/filter/empty states, the complete favorites list, artwork reuse while scrolling, Advanced/Resume/four-finger return, unavailable files and cores, and missing JIT. Then verify GameCube gameplay and an in-game save/reload, the existing PS2 behavior without a renderer reset, and a no-JIT system. Confirm games and saves remain intact after backgrounding and reopening. Finally check existing iCloud sync separately after closing content.
