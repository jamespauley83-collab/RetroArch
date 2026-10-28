# PS3 bridge validation — October 28, 2026

Runtime source: `0c5244a11ea2b2c8cddb542767f6758b42293caa` on
`codex/ipad-lab-rpcs3-bridge`, based on Lab's `45cd6246` built-in-JIT branch.
Later documentation commits do not change the tested native source.

## Completed

- Full ARM64 iOS Release build: Xcode 27.1, SDK 27.1, minimum iOS 26.0.
- Full ARM64 simulator Release build.
- 66 existing Lab Python tests passed.
- Six new packaging tests passed on Linux and macOS.
- Compiled C89-compatible API harness passed: ABI 29/31 and every missing
  required export fail atomically; ABI 30 resolves successfully.
- Six native simulator lifecycle tests passed against the actual controller
  with a fake ABI: enumeration copies callback data, duplicate boot, missing
  Universal, stop during boot, failed stop/retry, background pause and explicit
  resume. These do not run RPCS3 or validate PS3 sound, graphics, or speed.
- Full RetroArch UI simulator test passed: native library → PS3 → Start PS3 →
  recoverable missing-Universal message. This caught and fixed native-library
  presentation before the root view was visible under the current SDK.
- Native Lab Objective-C checks passed.
- Packager accepted the exact existing XITRIX 0.12 ARMv8.4-A IPA and core hashes.
  The candidate's host executable matches the final native build.

Native host SHA-256:
`fbb14a31f2871a37a7162edc0cfa4aa457f682a519b20cab5ca3681f2597b879`

XITRIX core SHA-256 (before development signing):
`64c942bc435d82627f7ad223ed091be76e1e2ba112c7f95d3596e68c31188237`

## Deployment status

**Not signed, not installed, and bridge gameplay not verified.**

The Mac has the Apple Development certificate, and both the M3 iPad Air and
phone were paired and available. Automatic provisioning for the separate
candidate identifier failed with **No Accounts: Add a new account in Accounts
settings**. The installed standalone RPCS3 profile authorizes the required
memory capabilities only for `com.jamespauley.rpcs3standalone`; the available
wildcard profile has neither Extended Virtual Addressing nor Increased Memory
Limit. Reusing the standalone identity would replace the user's working app,
so it was not used.

Reconnect the Apple account in Xcode Settings → Accounts, generate the candidate
profile, sign the candidate's nested code and host, then install only
`com.jamespauley.retroarchlab.ps3bridge`. Complete README's physical acceptance
checks before treating the bridge as playable.

No physical-device app was installed, uninstalled, replaced, or terminated.
No firmware, game, save, configuration, or pairing file was written to any
working app's container. The standalone gameplay result remains the baseline.

## Mac handoff

Work directory:
`/Users/jamespauley/Developer/RetroArch-PS3-Bridge-20261028`

Unsigned staged candidate:
`candidate-0c5244a/Payload/RetroArch.app`

Logs: `build-final.log`, `simulator-build2.log`, `tests-final.log`,
`ui-tests2.log`, `native-checks.log`, `signing-build.log`, and `package.log`.
The source worktree is `source`; `signing-template` is scoped to the candidate
and can be rebuilt after the Xcode account is reconnected. The accepted
standalone download/signing directory and all previous Lab source directories
were preserved.
