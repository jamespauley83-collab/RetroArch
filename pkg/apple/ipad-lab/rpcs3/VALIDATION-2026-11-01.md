# PS3 bridge pause and controller follow-up — November 1, 2026

Baseline: `5aa5570dfcda66f9eb734531e64ebae28d70038f` on PR #17.
Candidate identity remains `com.jamespauley.retroarchlab.ps3bridge`.

The user confirmed sound worked in installed build 4 on October 29. This closes
the audible-output question in the October 29 handoff for that build. It does not
establish physical controller, full level gameplay or save/reload acceptance.

## Corrections

- Remember a background/audio-interruption pause request even if the app becomes
  active again before asynchronous startup completes.
- Preserve an interruption arriving during Resume, including one that ends before
  the native resume operation returns. Pause again and require explicit Resume.
- Keep controller/touch snapshots neutral while interrupted, pausing or paused.
- Restore display-link input polling when Stop fails, retaining the display and
  permitting another Stop attempt and honoring background pauses received during Stop.
- Quote the iOS filter-copy paths in the Xcode build phase so the host builds
  from a project directory containing spaces.

## Verification

Before the corrections, four regression scenarios failed: brief background and
audio interruptions during boot, input returning while paused/interrupted, and
polling not restarting after Stop failure. Thirteen other scenarios passed.

After the corrections, all 19 native bridge tests passed on an iPad Air simulator
running iOS 27.2. These execute the real Objective-C bridge with a fake RPCS3 ABI.
The controller snapshot test also checks two players, button mapping, both
sticks, mixed analog/touch triggers and disconnect clearing. It does not test
Bluetooth connectivity or a real controller.

Additional passing checks: 66 Lab tests, six packaging tests, the ABI/missing-export
harness, 65 native-library checks and iOS library/JIT/PS3 type-checks.

Xcode's Metal 27.2 component was installed to match the updated Xcode version.
The full ARM64 simulator host then compiled, linked and installed successfully.
The device shell build could not resolve the Metal component in its restricted
environment; no successful full device build is claimed for this revision.

The full-app navigation test did not pass: the simulator showed a blank startup
screen and the PS3 button was absent. The same symptom occurred on iOS 27.2 and
the previously used iOS 27.0 simulator. The isolated bridge tests above pass, but
this full-host startup issue must be resolved before installing this revision.

## Review findings

- Xcode 27.2's resolved `OTHER_CFLAGS` includes all Lab library, iCloud, StikJIT
  and RPCS3 defines, including the separate candidate iCloud container. The raw
  configuration-file summary only shows the final assignment; the resolved
  target setting includes the inherited assignments. No flag change was needed.
- The pinned upstream initialization copies both paths into `std::string` storage
  and repoints its retained config at those strings before returning. See
  [RPCS3IOS.cpp at the pinned commit](https://github.com/XITRIX/rpcs3/blob/f88bff947b83730c0cf8a3949f59338b992b3ca0/rpcs3/ios/RPCS3IOS.cpp).
  No process-lifetime duplicate allocation was needed in the bridge.
- Data backup exclusions were not changed. Excluding all `PS3/Data` would also
  exclude saves; separating replaceable content from saves needs its own policy.

## Build-service failure

The previous head's iPad workflow passed. Linux i686 run `40866009265` failed
before compilation, at checkout, because its container could not resolve
`github.com`. A retry reproduced the same DNS failure. This is not evidence of a
Linux source compilation failure, and that check is not marked passing.

## Device acceptance

This follow-up has not been installed on the iPad. Existing installed apps, games
and saves were not modified. Keep PR #17 in draft pending a complete candidate
build and physical gameplay/controller/save-reload acceptance.
