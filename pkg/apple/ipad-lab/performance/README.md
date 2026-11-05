# Performance recording

Open **Performance** in the native game library or PS3 screen. Start recording,
return to the game, and play the same section for 2–3 minutes. Tap the red badge
when a slowdown is noticeable. Return to Performance, stop, and share the report.
For startup failures, start recording before Enable PS3 JIT / Start PS3.

Recording is opt-in and never starts automatically. Reports are newline-delimited
JSON in `Documents/Performance`. Each row has elapsed seconds; the first row also
has UTC time, build, OS and device family. Game filenames and core names are
included, but game data, saves, pairing information and credentials are not.
Reports remain on-device unless shared. The recorder stops at ten minutes or
approximately 1.5 MB and retains the latest five recordings. An interrupted
recording may lack its final `end` row; earlier complete lines remain readable.

## Reading a report

| Measurement | Meaning and limits |
| --- | --- |
| `libretro_fps` | Completed runloop iteration cadence; not unique displayed frames. Run-ahead/internal frame skipping can differ. |
| `frame_p95_ms`, `frame_max_ms` | Frame interval distribution. P95 rounds up to 1 ms buckets, capped at 500 ms; maximum is uncapped. |
| `slow_frames`, `worst_frame_at_s` | Intervals over 1.5 times the core's reported frame budget, and the time of the worst interval. Pauses and speed changes reset cadence. |
| `core_work_*`, `core_inflight_ms` | Wall time inside the core/run-ahead call, including callbacks and synchronization. An unfinished call remains visible to the background sampler. |
| `video_submit_ms_total` | Time in frontend video submission, including waits. With threaded video this measures submission to the worker. It is not GPU execution time. |
| `audio_write_ms_total` | Time in device writes; blocking for audio pacing is expected. It does not include all resampling or worker wait time. |
| `audio_underruns_delta` | Dropouts from a supported driver's counter. The first sample, unavailable counters, and counter resets are null. |
| `process_cpu_percent_one_core` | Process user + system CPU time. 100% means one logical core; values can exceed 100%. |
| `memory_footprint_bytes` | Process physical footprint, not the iOS termination limit. |
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
per second. Disabled recording skips the timers and metric collection. Actual
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
