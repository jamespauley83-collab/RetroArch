# RetroArch Lab library home

This Lab-only iPhone/iPad screen uses the existing RetroArch playlists, history, favorites, and installed cores. It is not a port of the Simple Launcher desktop application. Normal RetroArch and tvOS builds do not enable it.

## Using the screen

- Lab opens to the library when no game is running. Search titles or systems, use the system menu, or switch between All games, Recent (latest 10), and Favorites.
- Existing local box art is read from the configured thumbnails directory under `<system>/Named_Boxarts/<sanitized title>.png`. Missing art uses a controller placeholder. No online artwork service is contacted.
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

Before installing a candidate, verify its workflow and packaged manifest. Keep the previous working IPA. Update using the existing Apple signing account, Lab identifier, and iCloud entitlements; do not uninstall Lab. Do not treat a successful build as a completed hardware test.

On both iPad and iPhone, check layout in portrait/landscape, search/filter/empty states, the complete favorites list, artwork reuse while scrolling, Advanced/Resume/four-finger return, unavailable files and cores, and missing JIT. Then verify GameCube gameplay and an in-game save/reload, the existing PS2 behavior without a renderer reset, and a no-JIT system. Confirm games and saves remain intact after backgrounding and reopening. Finally check existing iCloud sync separately after closing content.
