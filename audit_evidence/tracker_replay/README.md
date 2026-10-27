# Tracker replay harness (audit evidence)

Offline tests that back the algorithm findings in
`../../CPREADY_SYSTEM_AUDIT_AND_IMPROVEMENT_PLAN.md` (findings C2, C3, C4, C5, C6).

- `replay.cpp` compiles `CPReady_Program/include/CompressionTracker.h` natively. It feeds the tracker 100 Hz net acceleration computed from a known chest
  displacement, so every stroke has a true depth, rate and lean. The samples go through
  the same EMA (alpha 0.25) as `SensorManager::sample100Hz`.
- `harmonic.cpp` is a prototype of the windowed Fourier-series depth estimator from
  Ruiz de Gauna et al., *Biomed Res Int* 2016 (PMC5143701). It runs on the same waveforms.
- `shim/Arduino.h` is just enough of Arduino for the header to compile on a PC.
- Captured outputs (27 Oct 2026):

  | File | Contents |
  |---|---|
  | `results_original_tracker.txt` | The tracker as committed at `3c086a5` (before any fixes) |
  | `results_patched_tracker.txt` | A scratch copy with only the lockout and recoil-exit fixes |
  | `results_after_fixes.txt` | The tracker after the Phase 1 fixes in this working tree |
  | `results_harmonic_estimator.txt` | The Fourier-series depth prototype |
  | `results_regression_test.txt` | `CPReady_Program/test_native/tracker_regression.cpp` after the Phase 1 fixes (144 checks) |
  | `results_refined_algorithm.txt` | `replay.cpp` after the algorithm refinement (integrated depth, tilt projection, median rate) |
  | `results_regression_refined.txt` | The extended regression test (233 checks) on the refined algorithm: all pass |
  | `results_regression_before_refinement.txt` | The same extended test run against the Phase 1 tracker (K·a·T² depth): 80 failures, almost all depth |
  | `results_simulation_scenario.txt` | `CPReady_Program/test_native/simulation_scenario.cpp`: the simulator's cue drill |

  `replay.cpp` always compiles whatever `CompressionTracker.h` is in the tree. To
  reproduce the original numbers, check out `3c086a5` first. Since the refinement,
  `processSample` also takes the unfiltered sample; `replay.cpp` passes it.

## Build and run (any g++ with C++17)

From this folder:

```
g++ -std=c++17 -O2 -I shim -I ../../CPReady_Program/include replay.cpp -o replay
./replay
g++ -std=c++17 -O2 harmonic.cpp -o harmonic
./harmonic
```

On this PC, the WinLibs MinGW install sits under a path that contains a space, and its
linker fails on `default-manifest.o`. Either install MinGW to a path without spaces or
add `-B<space-free junction to mingw64>/x86_64-w64-mingw32/lib/`.

## Waveforms

| Name | Shape of one cycle |
|---|---|
| `sine` | x = D/2·(1 − cos 2πt/T); smooth, no pause at the top |
| `40/60 duty` | half-cosine push in 40 % of the cycle, half-cosine release in 60 % |
| `35/35/30 dwell` | push 35 %, release 35 %, hands still at the top for 30 % |

`lean` adds a constant offset, so the chest never returns to the starting height.

## Caveats

These are idealised, perfectly periodic strokes with 5 mg of noise. Real manikin
signals contain more harmonics, vary from stroke to stroke, and pick up tilt and
sensor scale error. The *structural* findings do not depend on waveform details and
will reproduce on real data:

- refractory anchored to stroke end;
- recoil exit firing immediately;
- leaning being invisible to the accelerometer.

The exact percentages will differ on real data. Confirm the size of the depth-model
errors with recorded sessions (Phase 0 of the plan).

A "true" count can be exceeded by one stroke ("102 %"). That is an edge effect of how
the reference count is floored, not a double count.
