# Native tracker regression test

`tracker_regression.cpp` compiles the production `include/CompressionTracker.h`
on a PC (no ESP32 needed). It drives the tracker with chest-displacement waveforms
whose depth, rate and pauses are known, through the same 100 Hz EMA filter as
`SensorManager`. Run it after any change to the stroke detector or its constants.

## Build and run

From this folder:

```
g++ -std=c++17 -O2 -I shim -I ../include tracker_regression.cpp -o tracker_regression
./tracker_regression
```

The exit code is the number of failed checks, so 0 means everything passed.

On Windows with WinLibs MinGW installed under a path that contains a space, the
linker fails on `default-manifest.o`. Either install MinGW to a path without spaces,
or point gcc at a space-free junction with `-B<junction>/x86_64-w64-mingw32/lib/`.

## What it checks

| Area | Checks |
|---|---|
| Stroke detection and rate | Four stroke shapes (sinusoid, 40/60 duty cycle, 35/35/30 with a dwell at the top, dwell plus 2 mm spring bounce), at 80 / 100 / 120 / 150 cpm and 4.0 / 5.5 cm, on both profiles. Every stroke must be counted (±1) and the median rate must be within ±2 cpm. |
| Shallow strokes | 3 cm strokes are still counted. |
| Noise | 20 s of sensor noise with the hands still produces no strokes. |
| Pauses | The post-pause stroke reports no rate; session CCF and mean rate stay correct. |
| Live CCF | Live CCF decays during a pause instead of freezing. |
| PAUSE / RESUME | Paused time is excluded from elapsed time and duration; finalize ends the session. |
| Flags | The recoil-estimated flag is set, and the 16-bit stroke count is in the packet. |

A strong 4 mm / 8 Hz spring ring is printed as an INFO line, not asserted. At 80 cpm
it still double-counts; see the audit, finding C6 / Phase 2.

These are idealised, noise-added waveforms. They catch logic regressions, but they
do not replace validation against recorded manikin sessions (audit §6).
