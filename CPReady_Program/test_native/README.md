# Native tests (no ESP32 needed)

Two programs compile the production headers on a PC against `shim/Arduino.h`:

| Program | What it covers |
|---|---|
| `tracker_regression.cpp` | `CompressionTracker.h`, `DepthEstimator.h` and `GravityAxis.h`. It drives the tracker with chest-displacement waveforms whose depth, rate and pauses are known, through the same 100 Hz low-pass filter as `SensorManager`. |
| `simulation_scenario.cpp` | The `simulation` firmware's scenario (`SyntheticVest.h`). It checks that every phase is measured at its own depth and rate and that each coaching cue fires, in order. |

Run both after any change to the stroke detector, the depth estimator, the detector
constants or the simulator.

## Build and run

From this folder:

```
g++ -std=c++17 -O2 -I shim -I ../include tracker_regression.cpp -o tracker_regression
./tracker_regression
g++ -std=c++17 -O2 -I shim -I ../include simulation_scenario.cpp -o simulation_scenario
./simulation_scenario
```

The exit code is the number of failed checks, so 0 means everything passed.

On Windows with WinLibs MinGW installed under a path that contains a space, the
linker fails on `default-manifest.o`. Either install MinGW to a path without spaces,
or point gcc at a space-free junction with `-B<junction>/x86_64-w64-mingw32/lib/`.

## What `tracker_regression` checks

| Area | Checks |
|---|---|
| Detection, rate, depth | Four stroke shapes (sinusoid, 40/60 duty cycle, 35/35/30 with a dwell at the top, dwell plus 2 mm spring bounce), at 80 / 100 / 120 / 150 cpm and 4.0 / 5.5 cm, on both profiles. Every stroke must be counted (±1), the median rate must be within ±2 cpm, and the median depth within ±0.25 cm. |
| Depth range | 3–7 cm strokes at 110 cpm, median depth within ±0.25 cm. |
| Per-stroke depth | 80 strokes, each with its own depth (4–7 cm) and period (±10 %), on two shapes. Median per-stroke error ≤ 0.30 cm, 90th percentile ≤ 0.60 cm. |
| First strokes | The first stroke of a session and the first after a pause are measured from rest, within ±0.5 cm. |
| Robustness | A 30 mg offset left after calibration, and 20 mg noise: detection and depth still correct. |
| K | K still scales depth proportionally (Manikin Calibration and SET_K). |
| Shallow strokes | 3 cm strokes are still counted. |
| Noise | 20 s of sensor noise with the hands still produces no strokes. |
| Knock during a pause | A 3 mm knock is not counted. The same pulse at 3 cm is counted, which shows the knock reaches the detector and is rejected on its depth. |
| Pauses | The post-pause stroke reports no rate; session CCF, mean rate and mean depth stay correct. |
| Live CCF | Live CCF decays during a pause instead of freezing. |
| PAUSE / RESUME | Paused time is excluded from elapsed time and duration; finalize ends the session. |
| Flags | The recoil-estimated flag is set, and the 16-bit stroke count is in the packet. |
| Tilt | A sensor tilted 30° learns its vertical, and the projected acceleration is exact (the z-only value read 13 % short). |

A strong 4 mm / 8 Hz spring ring is printed as an INFO line, not asserted. At 80 cpm
it still double-counts; see the audit, finding C6 / Phase 2.

The waveforms are generated so that the chest never jumps: a compression segment ends
on a whole stroke. A jump would be an unphysical acceleration spike.

These are idealised, noise-added waveforms. They catch logic regressions and prove the
method on known motion, but they do not replace validation against recorded manikin
sessions (audit §6, `LAB_MODE_ARCHITECTURE.md`).
