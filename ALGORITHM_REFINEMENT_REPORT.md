# CPReady Algorithm Refinement: Change and Verification Report

**Date:** 27 October 2026
**Branch:** `for-finalization` (committed locally; the push to GitHub was refused for lack of write access, see `AGENT_HANDOFF.md` §3; `main` unchanged)
**Scope:** firmware measurement algorithm only. The Flutter app, the BLE protocol and the
command set are unchanged. A vest running this firmware works with the app already on this
branch.

---

## 1. Summary

The depth reading was the weakest part of the device. The old formula, depth = K × (peak-to-peak
acceleration) × T², is exact only for a perfect sine wave. Real compressions are not sine
waves, so the same 5.5 cm push read anywhere from **1.85 to 4.60 cm** depending on how it was
pushed. Calibrating K could not fix that, because the error changed with technique.

Depth is now measured by **integrating the chest's acceleration twice over each individual
stroke**. Your `ALGORITHM_RESEARCH.md` §3.3 describes this approach: each stroke is solved on
its own window, so drift cannot build up and no stroke shape is assumed.

On the same test waveforms, the new method reads a 5.5 cm push as **5.49–5.68 cm** for every
stroke shape and rate, and individual strokes of varying depth to within **0.2 cm** (median).
Four smaller reliability fixes came with it: tilt, rate smoothing, bump rejection, and a
weak-stroke bug.

**This is verified on synthetic, physically consistent motion, not yet on the vest.**
Section 6 is the checklist for confirming it on hardware.

---

## 2. What changed

### 2.1 Firmware files

| File | Change | Why |
|---|---|---|
| `include/DepthEstimator.h` (new) | Keeps the last 2.56 s of unfiltered acceleration and computes each stroke's depth by double integration. **Normal strokes:** over one full cycle (previous stroke end → this stroke end), with the mean acceleration and mean velocity removed, because the chest ends a cycle where it started. **First stroke / first after a pause:** integrated from rest. If the chest was not actually still before the push, it reports "unknown" instead of a wrong number. | Removes the stroke-shape error (audit C6). Removing the means also cancels sensor offset and leftover tilt. |
| `include/CompressionTracker.h` | `processSample()` now takes the filtered sample (to detect strokes) **and** the raw sample (for depth). Changes: depth from `DepthEstimator`; detections with under 1 cm of motion are discarded; live rate is the median of the last 3 periods; session rate is strokes per minute of steady compressing; an unknown depth keeps the previous value and stays out of averages and coaching. The K·a·T² code and its clamps were removed. | Accuracy (depth), reliability (no phantom strokes, steadier rate and coaching). |
| `include/GravityAxis.h` (new) | Learns each sensor's "up" direction from its resting reading at calibration. Each sample is then projected onto it. | A pad tilted 30° read 13 % short on the z axis alone, and K silently absorbed it. |
| `include/SensorManager.h` | Reads all three axes, which it already received from the sensor. Calibration learns the gravity directions and logs the tilt angle. `sample100Hz()` returns both the filtered and the raw vertical acceleration. The calibration acceptance checks are **unchanged**. | Feeds the two items above. |
| `include/CPReadyConfig.h` | K is documented as a correction factor (reported depth = integrated depth × K / default). New `DEPTH_MODEL_VERSION`, `MIN_STROKE_DEPTH_CM` (1.0) and `RATE_MEDIAN_STROKES` (3). `RECOIL_ARM_MIN_G` goes from 0.04 to **0.08**. Unused period clamps removed. | The 0.08 change fixes the bug in §2.2. |
| `src/main.cpp` (+ its `.ino` copy) | Passes the raw sample to the tracker. On the first boot of this firmware, K values saved by older firmware are discarded once (NVS key `depth_model`), and the log says so. | Old K values were fitted to the old formula and would mis-scale the new depth. |
| `include/SyntheticVest.h`, `include/SimulationConfig.h`, `src/simulation.cpp` | The simulator now generates real chest motion (push, release, rest at the top) and its exact acceleration, through the same filter as the sensor build. The "leaning" phase was removed, because the device cannot detect leaning and no longer gives that cue. | The old simulated signal was shaped to fool the old formula and was not physical motion, so the new depth method would have read it wrongly. |

### 2.2 A bug found and fixed along the way

In the Phase 1 fixes, the recoil phase "armed" at −0.04 g but finished at −0.05 g. For
gentle strokes (peak acceleration under about 0.17 g), the arm level sat above the finish
level, so a stroke could finish on its way **down**. That is the same truncation bug as audit
finding C3. Stroke counting still came out right, which is why the earlier test missed it.
The new depth method needs accurate stroke boundaries, and exposed it: the slow, gentle test
case lost 6 of 40 strokes. The arm minimum is now 0.08 g, well below the finish level.

### 2.3 What did not change

- The stroke **detection** logic, apart from the two items above: adaptive threshold,
  lockouts and pause rules are as before.
- The **app**, the **BLE packet** (16 bytes, protocol v2), the **commands**, Manikin
  Calibration (`CALIBRATE_TARGET`) and `SET_K`. They behave exactly as before, with K now a
  correction around the default.
- **Recoil:** still an estimate, flagged, not graded, no voice cue. Leaning remains
  undetectable without a force sensor; the replay confirms this (table B in
  `audit_evidence/tracker_replay/results_refined_algorithm.txt`).

---

## 3. Results: before and after

All numbers come from the same native test program run against both versions of the
firmware headers. Waveforms are physically consistent chest motion with 5 mg of sensor noise,
fed through the firmware's own 100 Hz filter.

### 3.1 Depth at a true 5.5 cm, by stroke shape (80–150 cpm, both profiles)

| Stroke shape | Before: reads | Before: error range | After: reads | After: error range |
|---|---|---|---|---|
| Sine (no pause at top) | 1.85–2.39 cm | −3.65 to −2.31 cm | 5.49–5.51 cm | ±0.01 cm |
| 40 % push / 60 % release | 2.25–3.26 cm | −3.25 to −1.63 cm | 5.50–5.52 cm | 0 to +0.02 cm |
| Push / release / rest at top | 2.94–4.50 cm | −2.56 to −0.73 cm | 5.51–5.53 cm | +0.01 to +0.03 cm |
| Same, plus 2 mm spring bounce | 2.94–4.60 cm | −2.56 to −0.48 cm | 5.49–5.68 cm | −0.01 to +0.18 cm* |

\*The bounce is real extra chest movement, so reading slightly deeper is physically correct.

### 3.2 Other depth checks

| Check | Before | After |
|---|---|---|
| 3 / 4 / 5 / 6 / 7 cm strokes at 110 cpm (median) | 2.12 / 2.84 / 3.54 / 4.24 / 4.93 | 3.04 / 4.12 / 5.11 / 6.11 / 7.11 |
| 80 strokes, each a different depth (4–7 cm) and period (±10 %): median per-stroke error | 1.52 cm (dwell), 2.40 cm (40/60) | 0.17 cm, 0.19 cm |
| Same: 90th-percentile per-stroke error | 2.33 cm, 3.16 cm | 0.54 cm, 0.39 cm |
| First stroke of the session (true 5.5) | 3.93 | 5.41 |
| First stroke after a pause (true 5.5) | 3.91 | 5.81 |
| 30 mg sensor offset left after calibration (true 5.5) | 3.92 | 5.70 |
| 20 mg noise, 4× a real MPU-6050 (true 5.5) | 3.86 | 5.63 |
| K set to 2× default doubles a 2.5 cm stroke to 5.0 | 3.49 | 5.02 |
| Session mean depth (true 5.5, with a pause) | 3.85 | 5.59 |

At 110 cpm a stroke lasts 54.5 samples, so cycle windows alternate 54/55 samples. That
causes a small consistent over-read of about +0.1 cm (2 %). K calibration removes any
constant bias of this kind.

### 3.3 Reliability checks

| Check | Before | After |
|---|---|---|
| A 3 mm knock on the vest during a pause | counted as a compression | **not counted** |
| The same pulse at 3 cm (a real push) | counted | counted |
| Gentle 4 cm sine strokes at 80 cpm (stroke boundaries) | ended mid-downstroke (§2.2) | correct; all strokes measured within ±0.1 cm |
| Detection and median rate across all shapes, rates and depths | pass | pass (unchanged) |
| 20 s of noise with hands still | 0 strokes | 0 strokes |
| CCF, pause/resume, flags, 16-bit count | pass | pass (unchanged) |
| Tilted sensor (30°): vertical acceleration | z-only reads 13 % short | exact (projection) |

**Totals:** the extended test has 233 checks. The refined firmware passes all 233. The
Phase 1 firmware fails 80 of them, almost all depth.

### 3.4 Simulator

The simulation firmware's cue drill, played through the production tracker:

| Phase | Measured depth | Measured rate |
|---|---|---|
| warm-up | 5.58 cm (5.5) | 109 cpm (110) |
| shallow | 4.14 cm (4.0) | 109 cpm |
| deep | 7.10 cm (7.0) | 109 cpm |
| slow | 5.64 cm (5.5) | 86 cpm (85) |
| fast | 5.62 cm (5.5) | 146 cpm (145) |
| good | 5.60 cm (5.5) | 109 cpm |

Every cue fired in its own phase, in order: push harder, push less, speed up, slow down,
good job. "Good job" fired twice, 15 s apart, as designed. No "release fully" cue was
issued.

---

## 4. How this was verified

1. **Native tests on a PC.** These compile the exact firmware headers with a minimal Arduino
   shim.
   - `CPReady_Program/test_native/tracker_regression.cpp`: 233 checks, all pass.
   - `CPReady_Program/test_native/simulation_scenario.cpp`: all pass.
   - Outputs are saved in `audit_evidence/tracker_replay/`:
     - `results_regression_refined.txt`
     - `results_simulation_scenario.txt`
     - `results_refined_algorithm.txt`
2. **Same test, previous algorithm.** The extended test was compiled against the Phase 1
   headers from git, with a 1-line adapter for the new function signature. It reports 80
   failures (`results_regression_before_refinement.txt`). This shows the new checks really
   measure the improvement.
3. **Mutation checks.** On scratch copies (the project files were not touched), each new
   protection was reverted to confirm its test catches it:
   - bump rejection disabled → the knock test fails;
   - arm level back to 0.04 g → the gentle-stroke detection tests fail.
4. **Harness check.** One test initially passed for the wrong reason. My test harness cut a
   compression segment mid-stroke, which made the simulated chest jump back to the top in one
   sample: an impossible acceleration spike that saturated the detector threshold. The harness
   now ends segments on whole strokes. After that, the knock test was confirmed to fail when
   rejection is disabled (step 3).
5. **Firmware builds.** `pio run -e esp32dev -e simulation`: both succeed with no warnings
   from project code.
   - Flash: 90.1 % on `esp32dev` (was 89.9 %).
   - RAM: 41 KB of 320 KB. The depth buffer is 1 KB.
6. **Not run:** the Flutter app tests, which you asked me to pause. No app file changed in
   this step, so nothing new there needs re-running.

To re-run the native tests (any g++ with C++17), from `CPReady_Program/test_native`:

```
g++ -std=c++17 -O2 -I shim -I ../include tracker_regression.cpp -o tracker_regression && ./tracker_regression
g++ -std=c++17 -O2 -I shim -I ../include simulation_scenario.cpp -o simulation_scenario && ./simulation_scenario
```

---

## 5. Limits and risks

1. **Synthetic, not real.** Real signals include things the tests do not model:
   - vest and foam compliance;
   - the base sensor not sitting perfectly still;
   - sensor scale error (MPU-6050 clones are about ±3 %);
   - hand slip.

   The method is sound, but its accuracy on the vest is unproven until it is compared with a
   reference (§6, and the lab build).
2. **Depth needs both sensors to track the manikin.** The depth is the chest's motion
   relative to the base sensor. If the base sensor is not coupled to the manikin's back (for
   example it slides on a mat), the error goes straight into the depth.
3. **Leaning between strokes.** Each cycle is assumed to end where it started. When a
   rescuer starts or stops leaning, that cycle does not close, and roughly a quarter of the
   change shows up as a depth error on that one stroke. Leaning itself remains undetectable.
4. **Strong spring ringing.** A 4 mm, 8 Hz bounce after every stroke still double-counts at
   80 cpm (synthetic; unchanged from before). Real data will show whether manikins do this.
5. **First stroke.** It is measured only if the hands were still before it. Otherwise its
   depth is reported as unknown, and the display keeps the previous value.
6. **K values reset once.** Every vest loses its saved calibration on the first boot of this
   firmware, by design. Re-run Manikin Calibration.

---

## 6. Hardware checklist for your client

Flash `esp32dev` from this branch. Install the app from this branch too; older app builds
reject the 16-byte packet.

| # | Do this | Expect |
|---|---|---|
| 1 | Boot with the serial monitor open (115200) | `[NVS] Depth model changed: saved K values reset...` once. It does not appear on the next boot. |
| 2 | Calibrate on the manikin | `[CALIB] Sensor tilt from vertical: chest X deg, base Y deg`. A few degrees is normal; above about 30° means the pad is mounted crooked. |
| 3 | Practice at about 5 cm with the manikin's app running in parallel. Start and stop both together; 30 s per run. | The CPReady mean depth is close to the manikin app's mean depth **before** any calibration. Note both numbers. |
| 4 | Repeat at shallow (~4 cm) and deep (~6 cm) | The CPReady mean tracks the manikin's mean across all three. A constant offset is fine (calibration fixes it); a gap that changes with depth is worth reporting. |
| 5 | Run Manikin Calibration | The new K is within about ±15 % of 11.2. Much further suggests a sensor or mounting problem. |
| 6 | Push at 100 and 120 cpm with a metronome | The live rate shows 100 / 120 ± 2 and does not jump from stroke to stroke. |
| 7 | Stop for 5 s and tap or shift your hands without pushing | The count does not increase. |
| 8 | Push very gently and slowly (about 3 cm at 80 cpm) | Every push is counted; "push harder" plays. |
| 9 | Disconnect and reconnect from the app 10 times; unplug a sensor mid-session | Reconnects each time; "sensor fault" result within about 0.5 s. These are the Phase 1 checks. |

Steps 3–5 give the first real accuracy numbers. Please send the pairs of means (CPReady
versus manikin app), plus the K from step 5. They decide whether anything needs tuning
before the lab build.

---

## 7. Reviewing or reverting

This step is one commit on `for-finalization`, titled
"feat(firmware): integrate depth per stroke, tilt projection, median rate".

- Find it: `git log --oneline --grep "integrate depth per stroke"`.
- See exactly what changed: `git show <that commit>`.
- Revert only this step: `git revert <that commit>`. The Phase 1 fixes stay.
- Backup of the project before any audit work:
  `..\CPReady_backup_before_audit_fixes_2026-10-27.zip`.
