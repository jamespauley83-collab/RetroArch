# RetroArch PS2 Test

This unsigned IPA enables experimental ARMSX2 boot. A successful build proves
compilation and packaging only. Graphics, audio, input, saves and sustained
gameplay have not been validated on an iPhone or iPad.

## Install and prepare

1. Download the `ARMSX2-iOS-device-test` artifact from the successful workflow.
   Extract `RetroArch-PS2-Test-unsigned.ipa` and `ARMSX2-system-files.zip`.
2. Sign and install the IPA with your existing sideloading setup. Keep its
   distinct bundle ID, `com.jamespauley.retroarchlab.ps2test`, and display name,
   **RetroArch PS2 Test**. It has its own settings and saves and contains only
   ARMSX2. It does not enable Lab's iCloud integration.
3. Launch once. In **Settings > Directory > System/BIOS**, note this app's system
   directory. Extract the system-files ZIP there, preserving the `pcsx2` folder.
   The result must include `pcsx2/resources/fonts/Roboto-Regular.ttf`.
4. Copy your own PS2 BIOS into `pcsx2/bios` beneath that system directory. BIOS
   files and games are not included. Close and relaunch after copying the BIOS.
5. Enable JIT for **RetroArch PS2 Test** with your existing device setup before
   starting the core. Enabling it for the normal Lab app does not enable it for
   this separate process. This bridge requires a frontend RWX or dual-map arena;
   unsupported allocation modes produce an error before emulator startup.
6. Enable **Settings > Logging > Logging Verbosity** and **Log to File** before
   the first boot. Note the log location under **Settings > Directory > Logs**.

## First test: BIOS

Choose **Load Core > Sony - PlayStation 2 (ARMSX2 Lab Test)**, then **Start Core**
without loading a game. Use the default renderer and 1x resolution. The expected
log message before boot is:

```text
ARMSX2 Lab device test: experimental boot; JIT execute/patch test passed.
```

This checks executing a small ARM64 function, changing it through the writable
mapping, and observing the changed result through the executable mapping. It
does not prove the emulator's complete recompiler works. Invalid executable
permissions can crash the process during this check; capture the device crash
report if that happens.

Record whether the BIOS menu appears, responds to controls, and has sound.
Close content, start it again, and test reset. A boot error should be reported
instead of leaving an unexplained black screen. If the app exits or stays blank,
save the log and crash report before retrying.

## Then test one game

Load one of your own game images at 1x. Check picture orientation and colors,
controls, audio, pause/resume, reset, and an in-game memory-card save. Quit the
app, re-enable JIT if needed, reopen, and confirm the save loads. Keep test saves
inside this app; do not replace existing Play! memory cards.

Report the device model, iOS version, JIT method, build commit from
`build-manifest.json`, BIOS region, game/title ID, first failing step, and logs.
Frame pacing and Metal CPU readback performance remain development work.
