# Built-in StikJIT candidate

This optional build adds a native Library JIT Setup screen and a classic helper
extension. Launching ARMSX2, Dolphin or Play! from the Library requests activation
before queuing content. ARMSX2 retains its own arena validation; ordinary cores
remain usable without activation. Advanced launch paths still require JIT to have
been enabled first (use JIT Setup > Enable JIT now).

The default is Built-in StikJIT. StikDebug and Wait for debugger remain explicit
fallback choices. An unsuccessful method never silently switches to another.

## Initial setup

1. Sign the isolated Lab 8 Test IPA, its `JITHelper` extension and all frameworks.
   Keep extensions in the sideloader. Both app identifiers must be unique to the
   test app. Keep the host's `get-task-allow`; do not add cloud, app-group or shared
   keychain permissions. Check the exported signed package before installation.
2. Open the test app normally. Choose Settings > JIT Setup > Import pairing file
   and import the pairing plist for this device. Developer Mode must be enabled.
   JIT Setup is the first entry in the ordinary Settings list. The native Library
   toolbar also provides it, but the Library screen and gesture are not required.
3. Connect LocalDevVPN. Check setup can verify connectivity and mount the developer
   disk image. Its first run may download files. Then launch a PS2 game from Library.
4. If the helper is unavailable, explicitly choose StikDebug. The app sends its
   actual installed bundle identifier, PID and universal.js in the handoff.

Pairing bytes are stored in the host's default private Keychain access group,
WhenUnlockedThisDeviceOnly. They are not copied to Documents or iCloud. The helper
receives them through its extension request, temporarily writes them under its
private, backup-excluded Library directory, and deletes them on completion and on
the next non-reset request after interruption. The framework's DDI cache stays in
the helper. No App Group is required.

## Focused new acceptance

Do not repeat the previously completed eight-core tests merely to reconfirm them.
This new build requires its own JIT activation checks:

- Confirm actual host/helper identifiers, profile coverage, executable signatures,
  get-task-allow and no-cloud/scoped-keychain entitlements before device use.
- From the ordinary XMB Settings list, open JIT Setup and verify that Import
  pairing file and Check setup are reachable without opening the native Library.
- Open the test app from its own icon; launch the known PS2 game via Library and
  confirm built-in activation, game start and existing save availability.
- Close and relaunch the test app, then verify built-in activation for the new process.
- Cancel the wait and confirm that no game launches later. A running helper is
  allowed to finish; if it stalls, close/reopen the test app before retrying.
- With VPN disconnected, verify an actionable error and no game launch; reconnect
  and retry. Check missing pairing, unavailable helper, and StikDebug fallback.
- With an available LAN bless helper, verify StikDebug and Wait for debugger can
  still activate. Select Built-in StikJIT and confirm that a new activation or
  Check setup does not start LAN discovery; verify external activation again
  after switching back.
- Cancel an external activation while its LAN helper is connecting or waiting
  for a reply, then select Built-in. Verify the app requests a retry instead of
  starting both helpers.
- With a sent LAN request receiving no definite reply, confirm the `result is
  unknown` message and that repeated Built-in retries remain blocked without a
  late game launch. Close and reopen the test app; verify Built-in activation
  can be attempted again in the new process.
- Confirm Saturn still opens without JIT, and working Lab remains intact.

Activation completion requires a prepared executable-memory pool. A helper success
response or URL-open success alone is insufficient. A 180-second wait stops automatic
launch; late completion cannot start content. A stuck helper blocks overlapping
attempts until it exits or the app is restarted.

Compilation and package checks are separate from signing and physical-device
acceptance. Do not merge or replace working Lab based on compilation alone.

## Build verification — October 19, 2026

[CI run 39180567671](https://github.com/jamespauley83-collab/RetroArch/actions/runs/39180567671)
successfully built runtime commit `dbe80de88a5dd0535b76f8a7a6a0a2577c6fc013`
with Xcode 26.3. All 61 Lab and 12 ARMSX2 tests passed, along with native iOS
type checks, helper/framework compilation, the complete app build, and isolated
package validation. The test IPA SHA-256 is
`abe1136bf671c843f7d60d53f06e8fcae47fcfe547eb6638e826c3b1acbb0ba1`.
It is unsigned and has not passed physical-device JIT acceptance. Keep the PR draft.
