# PS3 ISO import storage capacity

Status: source correction and focused checks completed on November 7, 2026.
No updated emulator binary has been built, installed or uploaded from this package.
The failing iPhone import has not yet been repeated with this correction.

## Observed problem

The submitted iPhone screenshots show a 6.71 GB ISO in iCloud Drive, approximately
43 GB available in Settings, and an RPCS3 ISO-import error requesting another
3.95 GiB. Those rounded values imply that the import check saw roughly 2.47 GB
available, if the screenshots represent the same storage state.

The pinned importer compares the ISO and optional key size with
`fs::statfs(...).avail_free`. On this platform that field comes from
`statvfs` free blocks. Apple recommends
`NSURLVolumeAvailableCapacityForImportantUsageKey` for storage requested by the
user. A difference between raw free blocks and capacity available for important
usage is a plausible explanation. We have not measured both values on the
affected iPhone, so this is not a confirmed device-level root cause.

## Changes

- Query important-usage capacity on the destination volume through Foundation.
  Use the filesystem reading only when the Apple query is unavailable or invalid.
- Treat a valid zero capacity as authoritative. Preserve 64-bit sizes and the
  optional key's contribution to required space.
- Report ISO size, available capacity and additional space needed in the error.
  The existing PS3 diagnostic console receives the selected capacity, its source
  and the raw filesystem reading.
- Preserve the existing copy, validation, temporary-directory cleanup and source
  preservation behavior. This patch does not delete a source ISO, games or saves.
- The existing interpreter archive packager merges disk-space API reasons
  `E174.1`, `85F4.1` and `7D9E.1` into the app's privacy manifest. Existing
  declarations are preserved. The reasons cover import decisions, displayed
  capacity and storage information in the user's optional diagnostic export.

An estimated capacity is not a reservation. The existing copy error and cleanup
paths remain necessary if a write fails or free space changes during import.

## Apply and build

Use XITRIX/rpcs3 at `f88bff947b83730c0cf8a3949f59338b992b3ca0`.

1. Apply `../testflight-interpreters/rpcs3-interpreter-only.patch`.
2. Apply `../rpcs3-playback/native-core.patch`.
3. Apply this directory's `native-core.patch`.
4. Rebuild the existing iOS native core with `RPCS3_FRONTEND=IOS`,
   `RPCS3_IOS_JITLESS_ONLY=ON` and `WITH_LLVM=OFF`.
5. Package with the updated `../archive_testflight_interpreter.py`, preserving the
   current full host, eight emulator backends, signing identity and app identity.

Run `git apply --check` before applying each patch. The storage patch changes
only `rpcs3/ios/GameLibrary.cpp`, `RPCS3IOSPlatform.h` and `RPCS3IOSPlatform.mm`.
These files do not overlap the earlier two patches.

## Focused validation

Run on a Mac with Xcode, preserving a baseline source copy:

```sh
python3 tests/test_import_storage.py \
  --baseline /path/to/baseline/rpcs3/ios/GameLibrary.cpp \
  --patched /path/to/patched/rpcs3/ios/GameLibrary.cpp \
  --platform /path/to/patched/rpcs3/ios/RPCS3IOSPlatform.mm
```

Results:

| Check | Result |
| --- | --- |
| Production preflight decision body | 13 checks passed |
| Unchanged preflight negative control | 7 of the same 13 checks failed |
| Production Foundation capacity helper | 9 checks passed |
| Capacity helper against iOS arm64 SDK, minimum iOS 16 | Compilation check passed |
| Native patch against the pinned source | Application check passed |
| Archive privacy metadata | Creation, existing-field preservation, category merge and idempotence verified |

The preflight harness extracts the production decision body and substitutes
filesystem/query inputs, logging and formatting. The Foundation harness executes
the production helper and temporarily replaces NSURL's resource-query method in
the test process. It checks the requested key and destination path, positive and
zero values, missing/wrong-type/negative values, query failure and 64-bit capacity.

These checks do not compile the complete emulator, exercise actual iOS storage
reclamation, copy a game, or establish hardware import success. The full native
build/link, signed archive and physical iPhone acceptance remain pending. No
hosted CI build was requested.

## Device acceptance

Import the same 6.71 GB ISO from iCloud Drive. Verify the original remains
available and the game appears in the PS3 library. Inspect the new storage line
in the PS3 log; if copying still fails, retain that log and the exact error.
Separately confirm that a genuine shortage still produces a recoverable error.
Check that existing firmware, games and saves remain accessible.

## Sources

- [Apple: Checking Volume Storage Capacity](https://developer.apple.com/documentation/foundation/checking-volume-storage-capacity)
- [Apple: required disk-space API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Pinned ISO installer](https://github.com/XITRIX/rpcs3/blob/f88bff947b83730c0cf8a3949f59338b992b3ca0/rpcs3/ios/GameLibrary.cpp)
- [Pinned filesystem capacity implementation](https://github.com/XITRIX/rpcs3/blob/f88bff947b83730c0cf8a3949f59338b992b3ca0/Utilities/File.cpp)
