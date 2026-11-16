# Performance recording

Open **Performance** in the native game library or PS3 screen. Start recording,
return to the game, and play the same section for 2–3 minutes. Tap the top-left overlay
when a slowdown is noticeable. Return to Performance, stop, and share the report.
Enable PS3 JIT saves and stops an active recording before StikDebug relaunches
the app. To record PS3 startup, start a new recording after returning from
StikDebug and before tapping Start PS3.

Recording is opt-in and never starts automatically. Reports are newline-delimited
JSON in `Documents/Performance`. Each row has elapsed seconds; the first row also
has UTC time, build, OS and device family. Game filenames and core names are
included, but game data, saves, pairing information and credentials are not.
Reports remain on-device unless shared. The recorder stops at ten minutes or
approximately 1.5 MB and retains the latest five recordings. An interrupted
recording may lack its final `end` row; earlier complete lines remain readable.

## Live overlay and RPCS3 console

**Live performance overlay** enables the top-left gray capsule without creating
or pruning a report. Recording also shows the capsule, with a red recording dot.
The overlay preference lasts for the current app session. Stopping recording
keeps live sampling only when the switch is enabled; switching both off stops
the sampler. The capsule respects the visible view's safe area and sits inside
the PS3 render surface during gameplay. On other native screens it follows the
visible controller, and it is hidden on the Performance/Log and sharing screens.

The FPS readout uses fresh valid PS3 emulator FPS, or libretro iteration cadence.
CPU is process CPU normalized across logical cores; RAM is app physical footprint
divided by physical device RAM. GPU≈ is the PS3 RSX estimate, not hardware GPU
utilization. Missing values show `—`, with an empty ring. The expanded summary
and VoiceOver value explain the sources. No PS3 frame/audio/GPU counters were added.

**Log** on the PS3 screen toggles a dark live console over the game surface,
with the most recent 300 lines, total line count and **Export**. Close it using
the X or the Log button again. The game controls remain outside this panel.
Before gameplay, on viewports shorter than 240 points, or from **RPCS3 Log** in
Performance, it opens a dedicated screen. Existing
RPCS3 callbacks feed all delivered severity levels, including verbose messages.
The console does not enable additional core logging or synthesize internal messages.
Its bounded in-memory ring retains up to 10,000 lines or 4 MiB for export; older
lines are evicted and counted. Each callback is bounded to 16 KiB and each decoded
message to 4,096 UTF-16 units. Oversized decoded messages are marked and counted.
Export includes all retained lines, not only the visible 300, and identifies
omitted lines, message truncations, build and export time. Before export, this
buffer creates no disk file. It resets on app termination. Logs can contain game
names and local paths. The console refreshes once per second and follows the
end only while the user is already at the end; it leaves manual scrolling alone.

## Reading a report

| Measurement | Meaning and limits |
| --- | --- |
| `libretro_fps` | Completed runloop iteration cadence; not unique displayed frames. Run-ahead/internal frame skipping can differ. |
| `frame_p95_ms`, `frame_max_ms` | Frame interval distribution. P95 rounds up to 1 ms buckets, capped at 500 ms; maximum is uncapped. |
| `slow_frames`, `worst_frame_at_s` | Intervals over 1.5 times the core's reported frame budget, and the time of the worst interval. Slow-frame counts are null without frame intervals. Pauses and speed changes reset cadence. |
| `core_work_*`, `core_inflight_ms` | Wall time inside the core/run-ahead call, including callbacks and synchronization. An unfinished call remains visible to the background sampler. |
| `video_submit_ms_total` | Time in frontend video submission, including waits; null without observed video callbacks. With threaded video this measures submission to the worker. It is not GPU execution time. |
| `audio_write_ms_total` | Time in device writes; null without observed audio writes. Blocking for audio pacing is expected. It does not include all resampling or worker wait time. |
| `audio_underruns_delta` | Dropouts from a supported driver's counter. The first sample, unavailable counters, and counter resets are null. |
| `process_cpu_percent_one_core` | Process user + system CPU time. 100% means one logical core; values can exceed 100%. |
| `process_cpu_percent_device` | The same CPU time divided by logical CPU count, used by the overlay gauge. |
| `memory_footprint_bytes` | Process physical footprint, not the iOS termination limit. |
| `memory_footprint_percent_physical` | App footprint divided by physical device RAM, used by the overlay gauge. |
| `thermal`, `low_power` | iOS thermal pressure and Low Power Mode. Memory warnings are timestamped events. |
| `main_thread_gap_s` | Time since the UI answered the recorder's heartbeat. Inactive/background time is not labeled a UI stall. |
| `ps3_fps`, `ps3_rsx_estimate_percent` | Optional RPCS3 ABI metrics. RSX utilization is an estimate, not a hardware GPU counter. Invalid or stale fields are null. |
| `event` rows | Manual slowdown marks, library/loading transitions, PS3 JIT probe, core initialization, LLVM check and boot stages. |

Signals identify correlations, not a proven bottleneck. For example, a long
video submission can be normal vsync, while slow frames plus thermal pressure
suggest a device constraint. Exact shader compilation, GPU execution, guest CPU
threads and file I/O attribution require core-specific instrumentation or an
external profiler. No fixed 60 FPS target is assumed for PS3.

The hot path uses bounded counters under a short lock, with no per-frame file
writes or allocations. A separate serial queue samples CPU/memory and writes once
per second. With recording and the live overlay both off, metric sampling and
its timer stop. The bounded RPCS3 callback log remains available independently. Actual
on-device overhead still needs an A/B comparison of the same game section with
recording disabled and enabled; the tests do not establish zero overhead.

## Local verification

No hosted CI is needed:

```sh
bash pkg/apple/ipad-lab/performance/check.sh
bash pkg/apple/ipad-lab/tests/check_library.sh
python3 -m unittest discover -s pkg/apple/ipad-lab/tests
xcodebuild -project pkg/apple/ipad-lab/performance/PerformanceTests.xcodeproj \
  -scheme BridgeTests -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath /tmp/retroarch-perf-tests CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO test
```

The `LabUITests` scheme tests recording, marking, stopping and report selection
against an already installed `com.jamespauley.retroarchlab.ps3bridge` app. Run it
on a physical iPad with development signing. It does not boot a game or establish
PS3 JIT correctness. Its separate test host/runner can be removed afterward.
