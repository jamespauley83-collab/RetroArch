# PS3 bridge audio correction — October 29, 2026

Runtime source: `85efa585784bb84e954af6b966e92e4e10176fe7`.
Candidate: `com.jamespauley.retroarchlab.ps3bridge`, build 4.

The user reported silent PS3 gameplay. Candidate configuration had Master Volume
100 and the default system audio device. The pinned XITRIX native backend starts
with its audio-session flag false and deliberately does not start RemoteIO until
its wrapper posts `RPCS3AudioSessionDidActivate`. The old bridge never posted it.
The matching source contract and both strings in the bundled binary were checked.

The bridge now activates AVAudioSession playback before boot/explicit Resume,
then posts the native activation notification. Backgrounding and interruptions
post WillDeactivate. Interrupted startup pauses once the native state is RUNNING.
Audio activation failure prevents boot/resume and displays the error. Foreground
and interruption end do not automatically resume a game. System volume and route
are preserved.

Validation completed before installation:
- ARM64 Release device build succeeded (`build-audio.log`).
- 13 native-controller/fake-ABI tests passed (`tests-audio.log`), including three
  new audio tests for notification lifecycle, activation failure and interruption.
- Six packaging tests passed; 65 library checks and iOS type-check passed.
- Candidate profile and strict recursive development-signature checks passed.
- Existing bridge saves copied to `saves-before-audio-build4` on the Mac before
  updating only the candidate. Original working app IDs were not installed over.

Mac artifacts: `/Users/jamespauley/Developer/RetroArch-PS3-Bridge-20261028/`.
Signed app: `signed-candidate-85efa58/Payload/RetroArch.app`.
Physical validation: `ipad-audio-build4.log`.

Audible output must be confirmed on the iPad; automated lifecycle checks do not
establish what the user hears or audio quality.

Physical follow-up:
- Build 4 installed successfully; StikDebug handoff/core initialization passed.
- Full game lifecycle run did not complete: the UI test runner exited during
  startup at approximately 87 seconds and its supervisor stalled. The supervisor
  was interrupted; this run is not a passing gameplay/lifecycle result.
- A separate UI inspection succeeded at 07:28 EDT. The same candidate process
  remained alive, displaying “Starting game” with Pause disabled. Boot had passed
  AVAudioSession activation (an activation error would prevent the boot call).
  No successful build-4 pause/resume or audible-output result is claimed.
- All four original app records compared exactly equal before/after the update.
  Final candidate inventory reports build 4. Temporary test runner removed.
