# CPReady: System Audit and Improvement Implementation Plan

**Date:** 27 October 2026 (revision 2, same day)
**Scope:** ESP32 firmware (`CPReady_Program`), simulation build, test bench
(`CPReady_Test_Bench`), Flutter app (`FLUTTER/cpready`), KiCad schematic, and all project
documentation, including the research proposal, the planning documents and Reyn's feedback.
**Goal:** make readings trustworthy and the system as bug-free as possible.

**Revision 2:**

- Every file in the repository has now been read; §3 lists them.
- The Phase 1 fixes have been **applied to the working tree**. They are uncommitted and on
  `main`, so `git diff` shows them. They are verified by:
  - both firmware builds;
  - the native stroke-detector regression test (0 failures);
  - the Flutter test suite (§9).
- New findings from the second pass are H9–H10, M16–M18 and L13–L19.
- §9 lists every change, how it was verified, and what still needs hardware testing.

---

## 0. Summary for the impatient

The code is tidy and well commented, and the Flutter app is carefully engineered. Several
defects made the **readings untrustworthy** and the **device unreliable in use**. The six
that mattered most, and where they stand after this pass:

| # | Problem | Consequence during training | Status |
|---|---|---|---|
| **C1** | Disconnects are never detected: the BLE callback checks the client count before the library decrements it. | After the phone disconnects once (including the app's own "Tap to reconnect"), the vest **stops advertising** until it is power-cycled. | **Fixed** (P1.1); needs a hardware check |
| **C2** | The stroke lockout is timed from the *end* of a stroke, not its start. | At fast cadences **every other compression is dropped**. Rate reads about half the true value, so a trainee who is **too fast is told "Speed up"**. | **Fixed** (P1.2); regression-tested |
| **C3** | The recoil phase can end on the first sample after it starts. | Smooth strokes are cut in half. Depth reads about ½ and every stroke is flagged as leaning, so the trainee hears **"Release chest completely"** for correct compressions. | **Fixed** (P1.3); regression-tested |
| **C4** | A fixed 0.45 g start threshold is applied after a low-pass filter. | Shallow strokes (≤ 4–4.5 cm) and smooth strokes are **not counted at all**. "Push harder" can never fire for the most common novice error, and averages are biased upward. | **Fixed** with an adaptive threshold (P1.4); regression-tested |
| **C5** | The "recoil" flag measures how hard the chest decelerates at the **bottom** of the stroke, not whether it returns at the top. | **Leaning is invisible** (shown in the replay). The recoil metric, the recoil percentage and the highest-priority voice cue are not valid measures of recoil. | **Mitigated** (P1.5): flagged as an estimate, no cue, not graded. A real fix needs the FSR (P2.6). |
| **C6** | Depth = K·a_pp·T² depends on the *shape* of the stroke, not just its depth. | The same 5.5 cm compression reads anywhere from 1.9 cm to 4.2 cm depending on technique. One K calibration cannot fix this. | **Open**: needs the Phase 2 estimator and recorded data |

C2–C6 were demonstrated by compiling the **unmodified** `CompressionTracker.h` on a PC and
replaying physically consistent strokes through it (Appendix A, `audit_evidence/`). C1 was
confirmed against the installed Arduino-ESP32 2.0.17 BLE source.

**After flashing the fixed firmware, re-run Manikin Calibration** (or send `RESET_CONFIG`
first). Any K saved before was fitted to the old detector's miscounted strokes.

**Timing note.** The roadmap in `CPReady_Hardware_Consultation_Guide.md` schedules BLS
instructor evaluation trials for 26–31 October 2026, which is now. Data recorded with the
firmware as committed (`3c086a5`) should **not** be used for depth or recoil accuracy claims.
If trials cannot move:

- flash the working-tree firmware, which contains P1.1–P1.4 (§9), and re-run Manikin
  Calibration;
- power-cycle the vest if it ever stops advertising, and report it, because the C1 fix has
  not been tried on hardware;
- still treat depth as provisional (C6) and recoil as not measured (C5);
- log raw sensor data (P0.3) so the sessions can be re-scored later.

The plan in §5 runs in six phases:

| Phase | Content |
|---|---|
| 0 | Version control, tests and data logging |
| 1 | Surgical fixes for the critical and high-severity bugs |
| 2 | Replace the depth/recoil measurement with validated methods: the harmonic estimator from the paper in Reyn's notes, plus an FSR for recoil |
| 3 | Protocol v2 and connection robustness |
| 4 | App polish |
| 5 | Documentation and research methodology |

---

## 1. Purpose, aims and constraints

**What CPReady is.** A low-cost CPR *training* aid. It is a vest worn over a manikin, with an
ESP32, two MPU-6050-class accelerometers (chest and spine) and a phone app. It gives live
feedback on the four AHA indicators (depth 5–6 cm, rate 100–120 cpm, full recoil, CCF ≥ 60 %)
plus spoken coaching. It is built by a senior-high-school research team on a short timeline.

**Constraints that shape every recommendation:**

- **Cheap sensors.** MPU-6050 or MPU-6500 clones. The calibration guide's own boot log shows
  WHO_AM_I = 0x70 (MPU-6500 class). Expect ±3 % scale error, ±50–80 mg offsets and
  temperature drift.
- **An accelerometer only measures changes in motion.** Displacement must be inferred. Static
  quantities such as **leaning (incomplete recoil) cannot be observed** by an accelerometer;
  that needs a force sensor (the FSR in the hardware guide).
- **Mechanics.** A soft vest over a manikin means foam, strap slip and pad tilt. A sensor pad
  that is not flat under-reads by cos(tilt).
- **Team.** Student developers. Simple, testable, single-threaded code is the right call, and
  the existing architecture respects it.
- **Research use.** The numbers will appear in a paper. Every reported metric needs a
  ground-truth comparison and honest limitations.

**Realistic accuracy goals for a training device.** These are achievable with the plan below.

| Metric | Goal | Notes |
|---|---|---|
| Rate | ±2 cpm | The paper in Reyn's notes reports 0.9 cpm median error. |
| Depth | ±5 mm mean absolute error, 95 % limits ±10 mm | The paper reports 2.1 mm median with two accelerometers and spectral analysis. |
| Stroke detection | ≥ 98 % sensitivity and precision | Across 80–150 cpm and 3–7 cm. |
| Recoil | Valid only with a force sensor | Otherwise report "not measured". |
| CCF | Exact, by definition | Once pauses are defined consistently. |

---

## 2. What is already good

These are worth keeping as they are:

- **Firmware**
  - Clear module split: `SensorManager`, `CompressionTracker`, `BleManager`.
  - Non-blocking loop.
  - A FreeRTOS queue bridges BLE writes to the main loop.
  - Calibration has four checks: sample count, motion spread, gravity bounds and alignment.
  - Flash (NVS) persistence of settings.
  - A stroke watchdog and fixes for most items in the earlier `FIRMWARE_AUDIT.md`.
- **App**
  - Every visual value lives in `lib/src/config`.
  - The command queue paces BLE writes.
  - Packets are decoded defensively, with plausibility limits.
  - STOP has a GET_RESULTS recovery path.
  - Interrupted sessions are never saved.
  - The history schema migrates additively.
  - Widget tests cover the main end-of-session paths.
- **Simulation build.** A hardware-free way to drive the app. It needs a more physical signal
  model (M13).

---

## 3. Method and evidence

1. Read every file in the repository. The first pass skimmed some; revision 2 opened all of
   them:
   - firmware headers and sources, all of the vendored MPU-6050 library, and the simulation
     build;
   - the test bench, its `platformio.ini` and all of `archive/`;
   - every Dart file under `lib/` and `test/`, including the splash, home, history and guide
     screens, every widget and every config file;
   - Android, iOS, web and desktop configuration;
   - all Markdown documentation, the consultant notes, and the Word documents (research
     proposal, hardware plans, app plans and Reyn's consultation scope);
   - the KiCad schematic and PCB.
2. **Built the firmware.** Both PlatformIO environments (`esp32dev`, `simulation`) build
   successfully, before and after the fixes. Flash use was 87.6 % of the app partition at
   `3c086a5` and is 89.9 % with the fixes (M14).
3. **Checked library behaviour against its source.** Arduino-ESP32 2.0.17 is installed at
   `~/.platformio/packages/framework-arduinoespressif32` (`BLEServer.cpp`); Adafruit BusIO
   comes in via `lib_deps`.
4. **Replayed the production tracker offline.** `audit_evidence/tracker_replay/` compiles the
   unmodified `CompressionTracker.h` with a 20-line Arduino shim. It feeds the tracker
   accelerations computed from known displacement waveforms (sinusoid, 40/60 duty cycle,
   35/35/30 with a dwell at the top) at 80–150 cpm, 3–7 cm depth, and with or without leaning.
   A copy with the P1.2 and P1.3 fixes and a prototype harmonic estimator were run on the same
   inputs.
5. **Read the reference paper** in Reyn's notes (PMC5143701): Ruiz de Gauna et al.,
   "A Feasibility Study for Measuring Accurate Chest Compression Depth and Rate on Soft
   Surfaces Using Two Accelerometers and Spectral Analysis", *Biomed Res Int* 2016.

6. **Applied the Phase 1 fixes and tested them** (revision 2):
   - turned the replay into an assertion-based regression test
     (`CPReady_Program/test_native/`);
   - installed a Flutter SDK temporarily and ran `flutter analyze` and `flutter test` (§9).

**Not done:**

- No physical hardware test. Every firmware change has been compiled and the stroke detector
  has been tested natively, but BLE, I2C and NVS behaviour have only been reviewed against
  library source.
- iOS was not built or run.

Findings marked "by inspection" should be confirmed on hardware.

**Severity scale:**

| Severity | Meaning |
|---|---|
| **Critical** | Wrong training feedback, or the device is unusable in normal use. |
| **High** | Silent wrong data, or a broken flow under plausible conditions. |
| **Medium** | Degraded accuracy, robustness or UX. |
| **Low** | Polish and maintainability. |

---

## 4. Findings

### 4.1 Critical

#### C1: Disconnects are never detected, and the vest stops advertising after the first one

- **Where:** [BleManager.h:41-64](CPReady_Program/include/BleManager.h#L41-L64). Library:
  `framework-arduinoespressif32/libraries/BLE/src/BLEServer.cpp:207-220`.
- **What:** Both `onDisconnect` overloads only act if `pServer->getConnectedCount() == 0`. The
  library calls these callbacks **before** it decrements `m_connectedCount` (lines 209–219), so
  the count is still 1. Every normal disconnect takes the "stale disconnect … 1 client(s)
  still connected" branch. As a result:
  - advertising is never restarted;
  - `hasDisconnectedFlag` is never set, so an active session is not aborted;
  - `isClientConnected` stays true.
- **Impact:**
  - After any disconnect the vest is invisible to scans until it is reset. That includes app
    swipe-away, walking out of range, an Android BLE glitch, and the app's own reconnect path:
    `BleController.connect()` disconnects first, see
    [ble_controller.dart:140-145](FLUTTER/cpready/lib/src/core/ble/ble_controller.dart#L140-L145).
  - A session in progress keeps running to its 120 s auto-stop and sends its summary to nobody.
  - `SOFTWARE_DEVELOPER_GUIDE.md` §2.1 promises the opposite.
- **How to confirm on hardware:** connect with the app, then disconnect. The serial monitor
  prints `Stale disconnect … 1 client(s) still connected`, and the device no longer appears in
  scans.
- **Fix:** P1.1.

#### C2: The refractory lockout is timed from stroke *end*, so fast compressions are halved

- **Where:** [CompressionTracker.h:205-213](CPReady_Program/include/CompressionTracker.h#L205-L213)
  (lockout check), [line 233](CPReady_Program/include/CompressionTracker.h#L233) (where the
  reference time is set).
- **What:** A stroke "ends" at the mid-upstroke zero crossing. The next downstroke's
  acceleration peak arrives about T/4 later (≈ 125 ms at 120 cpm). It is rejected because it
  falls inside `REFRACTORY_LOCKOUT_MS` = 250 ms measured **from the end**. By the time the
  lockout expires the peak has passed, so only every second compression is counted. The
  simulator's waveform was deliberately shaped to avoid this
  ([SyntheticVest.h:12-16](CPReady_Program/include/SyntheticVest.h#L12-L16): "every other
  stroke would be rejected").
- **Evidence (Appendix A, table A):**
  - Sinusoid at 130–150 cpm: 49–51 % detected, rate reported 65–75 cpm, depth 7.6–8.7 cm.
  - 40/60 duty strokes are halved even at 110–120 cpm.
  - Dwell strokes at 140–150 cpm read 70–75 cpm and 10.0 cm (clamped).
- **Impact:** **Feedback inversion.** A trainee going too fast sees a red low rate, hears
  "Speed up", and their depth is inflated to the 10 cm clamp ("Push shallower"). Session
  averages and CCF are wrong too.
- **Fix:** P1.2. With an onset-to-onset lockout, detection is 98–100 % at 120–150 cpm and
  rates are exact (Appendix A, table A′).

#### C3: The recoil phase can end on the first sample, truncating smooth strokes

- **Where:** [CompressionTracker.h:220-231](CPReady_Program/include/CompressionTracker.h#L220-L231).
- **What:** The tracker enters `RECOILING` when `netAccel < 0`. It finishes the stroke when
  `netAccel ≥ STROKE_FINISH_THRESHOLD_G` (−0.05 g). Any first negative sample between −0.05
  and 0 therefore ends the stroke **immediately**, at mid-downstroke, and the trough is never
  measured.
- **Evidence:** trace of a 5.5 cm, 100 cpm sinusoid on the bench profile:
  - at t = 1380 ms the filtered value is −0.004 g, so the tracker enters RECOILING;
  - at t = 1390 ms the filtered value is −0.035 g, so the stroke completes;
  - reported depth 1.11 cm (true 5.5 cm), recoil "incomplete" on 100 % of strokes (table D).
- **Impact:** Smooth or gentle strokes, which are typical on the bench profile and on soft
  manikins, are reported at about half depth. Every stroke is flagged as leaning, which
  triggers the top-priority cue "Release chest completely" for correct technique.
- **Fix:** P1.3. With an armed exit, the same case reports 1.98 cm with recoil 100 %. The
  remaining depth error is C6.

#### C4: A fixed 0.45 g start threshold after the EMA misses shallow and smooth compressions

- **Where:** [CPReadyConfig.h:44](CPReady_Program/include/CPReadyConfig.h#L44),
  [CompressionTracker.h:206](CPReady_Program/include/CompressionTracker.h#L206), filter at
  [SensorManager.h:525-528](CPReady_Program/include/SensorManager.h#L525-L528).
- **What:** A 5.5 cm sinusoidal compression at 110 cpm peaks at (D/2)·ω² = 0.37 g, below the
  0.45 g threshold. The 4.5 Hz EMA further reduces sharp peaks. Detection therefore depends on
  how *impulsive* the push is, not on whether a compression happened.
- **Evidence (tables A–C):**
  - Sinusoidal strokes at 80–120 cpm and 40/60 strokes at 80–100 cpm: **0 %** detected.
  - Strokes of 3.0–4.0 cm: 0–1 of 58 detected, even with sharp pushes.
- **Impact:** The most common novice error, compressing too shallow, produces **no stroke at
  all**. There is no depth reading and no "Push harder". The counter freezes and CCF drops.
  The session mean depth only averages the strokes that crossed the threshold, so it is biased
  **upward**.
- **Fix:** P1.4 now (an adaptive threshold), P2.3 later.

#### C5: The "recoil" flag does not measure recoil, and leaning is invisible

- **Where:** [CompressionTracker.h:317](CPReady_Program/include/CompressionTracker.h#L317),
  cue priority at [lines 434-440](CPReady_Program/include/CompressionTracker.h#L434-L440).
- **What:** `recoil_complete = troughAccel < −0.35 g`. The trough is the upward acceleration
  at the **bottom** of the stroke, when the chest reverses. It scales with depth × rate², not
  with release at the top. Leaning is a constant offset in displacement, which produces zero
  acceleration. The hardware consultation guide says exactly this (Pitfall 2, "Retain the FSR"),
  but there is no FSR or ADC code in the firmware.
- **Evidence (table B):** strokes with **1.5 cm and 2.0 cm of leaning** are reported as
  "full recoil" on 100 % of strokes. Conversely, C3 flags correct smooth strokes as leaning on
  100 % of strokes.
- **Impact:** None of these are valid measures of recoil:
  - the live "Full/Partial" capsule;
  - the summary's "recoil compliance %";
  - the History record;
  - the top-priority voice cue.

  Because the flag is coupled to amplitude, shallow strokes are told to "release" instead of
  "push harder". For the research paper this is the most serious validity problem.
- **Fix:** P1.5 now (stop presenting it as recoil), P2.6 later (add the FSR).

#### C6: The depth model depends on stroke shape, so one K cannot calibrate it

- **Where:** [CompressionTracker.h:281-306](CPReady_Program/include/CompressionTracker.h#L281-L306);
  derivation in `docs/ALGORITHM_RESEARCH.md` §4.3.
- **What:** D = K·(a_max − a_min)·T² holds for a pure sinusoid, where K would be 24.8. Real
  strokes contain harmonics, so the acceleration peak-to-peak for the *same* depth changes with
  push speed, dwell and duty cycle. K = 11.2 is justified in the research doc by "viscoelastic
  damping attenuates amplitude to 45 %". That is physically backwards: impulsive strokes have
  *larger* acceleration peaks than a sinusoid of the same depth. K has no measured basis.

  Other weaknesses:
  - Because depth goes with T², a 10 % period error becomes a 21 % depth error.
  - The 0.38–0.85 s period clamps and the 0.55 s fallback add bias at slow rates and after
    pauses.
  - The test-bench K is not comparable to production (H7).
- **Evidence (tables A′, C, D):** with C2 and C3 already fixed, a true 5.5 cm stroke reads:
  - 2.2 / 2.9 / 3.9 cm for the three shapes (manikin profile);
  - 1.9 / 2.5 / 3.5 cm (bench profile).

  Within one shape the reading is proportional (5.0 → 3.5, 7.0 → 4.9), so K can fix *one
  trainee's style* but not the next trainee's.
- **Impact:** Depth feedback is not trustworthy across trainees. A claim of "±2–3 mm agreement
  with the clicker" (calibration guide §10) is not supported.
- **Fix:** P2.2. The prototype harmonic (Fourier-series) estimator from the cited paper
  recovers depth to within **±0.22 cm** across all three shapes, 80–150 cpm and 4–7 cm, with
  **no K**, and rate to within 0.3 cpm (Appendix A, table H). Real signals will be noisier;
  the paper reports 2.1 mm median error on a manikin.

### 4.2 High

#### H1: Sensor I/O errors are ignored, so a loose wire produces silent garbage

- **Where:**
  - Vendored library [Adafruit_MPU6050.cpp:638-690](CPReady_Program/lib/Adafruit_MPU6050/Adafruit_MPU6050.cpp#L638-L690)
    and [707-717](CPReady_Program/lib/Adafruit_MPU6050/Adafruit_MPU6050.cpp#L707-L717).
  - [SensorManager.h:408-431, 510-523](CPReady_Program/include/SensorManager.h#L408-L431).
  - [main.cpp:241-247](CPReady_Program/src/main.cpp#L241-L247).
- **What:**
  - `_read()` ignores the result of the I2C read and decodes an **uninitialised** 14-byte
    stack buffer. `getEvent()` always returns `true`.
  - Every sample also re-reads the range registers ([658](CPReady_Program/lib/Adafruit_MPU6050/Adafruit_MPU6050.cpp#L658),
    [675](CPReady_Program/lib/Adafruit_MPU6050/Adafruit_MPU6050.cpp#L675)). That is 2 extra
    transactions per sensor per sample, and if one fails the scale falls back to 1, turning
    raw counts into "g".
  - `ERR_I2C_FAULT` is defined, and the app handles it, but the firmware never sends it.
  - `FAULT_ERROR` set at boot is not enforced: CALIBRATE and START still run, reading sensors
    that were never initialised.
  - `reset()` loops forever if the bus returns 0xFF
    ([157-160](CPReady_Program/lib/Adafruit_MPU6050/Adafruit_MPU6050.cpp#L157-L160)).
- **Impact:** Cables flexing at 110 cpm (hardware guide, Pitfall 4) cause phantom strokes,
  frozen values or nonsense depth, with no error shown to the trainee or instructor.
- **Fix:** P1.7.

#### H2: The accelerometer on MPU-6500-class chips has no anti-alias filter

- **Where:** WHO_AM_I acceptance at [Adafruit_MPU6050.cpp:92-96](CPReady_Program/lib/Adafruit_MPU6050/Adafruit_MPU6050.cpp#L92-L96);
  `setFilterBandwidth(MPU6050_BAND_44_HZ)` at [SensorManager.h:340, 352](CPReady_Program/include/SensorManager.h#L340).
- **What:** The library was patched to accept chips reporting 0x70/0x72, and the team's
  sensors report 0x70 (see the calibration guide's boot log). On MPU-6500-class chips, CONFIG
  (0x1A) `DLPF_CFG` filters only the gyro and temperature sensor. The accelerometer's
  bandwidth is set in **ACCEL_CONFIG2 (0x1D)**, which defaults to about 218 Hz at a 1 kHz
  internal rate. The 44 Hz setting therefore leaves the accelerometer unfiltered. Reading it at
  about 100 Hz folds impact ringing and foam vibration (50–218 Hz) into the 0–50 Hz band, where
  the EMA cannot remove it. *Verify against the MPU-6500 register map before shipping.*
- **Fix:** In P1.7, when WHO_AM_I ≠ 0x68, write ACCEL_CONFIG2 with A_DLPF_CFG = 3 (≈ 45 Hz)
  or 4 (≈ 21 Hz).

#### H3: The firmware command state machine has holes

- **Where:** [main.cpp:62-207](CPReady_Program/src/main.cpp#L62-L207).
- **What:**
  - **START from any state other than `CALIBRATED_READY`** silently re-runs calibration
    ([96-106](CPReady_Program/src/main.cpp#L96-L106)). That includes `ACTIVE_SESSION`, so a
    retried or duplicate START aborts a running session with no summary.
  - **PAUSE is accepted in any state, and RESUME always goes to `ACTIVE_SESSION`**
    ([121-128](CPReady_Program/src/main.cpp#L121-L128)). The tracker keeps `sessionStartMillis`
    after a session ends. A RESUME in `STANDBY` therefore "continues" the finished session,
    immediately exceeds the duration, and broadcasts a FINAL_SUMMARY with the previous
    session's numbers but a new duration and CCF. Paused time is still counted as session
    time (earlier audit item #5 is still open). This is latent today: the app does not send
    PAUSE or RESUME.
  - **STOP during `CALIBRATING`** ([108-111](CPReady_Program/src/main.cpp#L108-L111)) calls
    `finalizeSession` on the *previous* session's state. It broadcasts a corrupted summary and
    overwrites `lastFinalSummary`, which GET_RESULTS and CALIBRATE_TARGET then use.
  - CALIBRATE is accepted in `SESSION_PAUSED` (abandons the session silently) and in
    `FAULT_ERROR` (see H1).
  - SET_PROFILE, SET_K, RESET_CONFIG, CALIBRATE_TARGET and SET_TIME are accepted **during an
    active session**. Thresholds and K can change mid-session, and the summary then mixes two
    profiles.
  - If the 8-slot command queue is full, `xQueueSend(…, 0)` drops the command silently
    ([BleManager.h:74](CPReady_Program/include/BleManager.h#L74)).
- **Fix:** P1.6, an explicit transition table (Appendix B.3).

#### H4: The same voice cue repeats every second during pauses and very slow compressions

- **Where:**
  - Firmware keeps the cue in `reading` until the next stroke
    ([CompressionTracker.h:349-350](CPReady_Program/include/CompressionTracker.h#L349-L350)).
  - The 5 Hz heartbeat re-sends it ([main.cpp:370-376](CPReady_Program/src/main.cpp#L370-L376));
    the simulation acknowledges this at [simulation.cpp:538-539](CPReady_Program/src/simulation.cpp#L538-L539).
  - The app's gate is time-based: the same cue is blocked for only 1 s
    ([voice_cue_gate.dart:27-30](FLUTTER/cpready/lib/src/core/audio/voice_cue_gate.dart#L27-L30),
    [durations.dart:93](FLUTTER/cpready/lib/src/config/durations.dart#L93)).
- **Impact:** Whenever the next stroke is more than 1 s away, the cue plays again about every
  second until compressions resume. That happens when the trainee stops to listen, compresses
  slower than 60 cpm, or at session end.
- **Fix:** P1.8. Make the firmware send each cue once, and make the app trigger on a *change*
  of cue code.

#### H5: The app's start watchdog is satisfied by calibration packets

- **Where:** [live_practice_screen.dart:103-110](FLUTTER/cpready/lib/src/screens/live_practice/live_practice_screen.dart#L103-L110)
  and [183-193](FLUTTER/cpready/lib/src/screens/live_practice/live_practice_screen.dart#L183-L193).
- **What:** The watchdog aborts only if `_latest == null`, but `_latest` is set by *every*
  non-error packet, including type 2 (calibrating) and type 3 (calibration done). If START
  reaches a device that is not `CALIBRATED_READY` (for example after a brownout reset), the
  firmware re-calibrates (H3) and sends type 2 and 3 packets. The watchdog is satisfied, so the
  app shows a running "live" session. The firmware sits in `CALIBRATED_READY` waiting for a
  START that never comes, and no compression is ever counted.
- **Fix:** P1.9.

#### H6: The legacy flash key corrupts K across reboots, and K bounds disagree

- **Where:** [main.cpp:141-142, 161-162](CPReady_Program/src/main.cpp#L141-L142) (writes),
  [221-227](CPReady_Program/src/main.cpp#L221-L227) (reads and bounds),
  [CompressionTracker.h:125](CPReady_Program/include/CompressionTracker.h#L125).
- **What:** Every K write also writes the legacy `depth_k` key. At boot, `depth_k` is the
  fallback for `k_manikin`. So on a fresh device: switch to BENCH, send `SET_K:9.0`, reboot,
  and the **manikin K becomes 9.0** instead of 11.2, a silent 20 % depth error.
  Separately, runtime accepts K in 1–30 but boot accepts only 2–25, so a K of 1.5 or 28 is
  acknowledged now and silently reverted after the next reboot.
- **Fix:** P1.10.

#### H7: The test bench runs a different algorithm on different hardware

- **Where:** [CPReady_Test_Bench.ino](CPReady_Test_Bench/CPReady_Test_Bench.ino).
- **What:** It has its own tracker copy, which:
  - has **no EMA filter** ([541-570](CPReady_Test_Bench/CPReady_Test_Bench.ino#L541-L570));
  - has no first-stroke initialisation ([256-260](CPReady_Test_Bench/CPReady_Test_Bench.ino#L256-L260)):
    the first period is "time since boot", which clamps depth to 10 cm and puts 0 cpm into the
    averages;
  - has no watchdog and no calibration checks.

  The hardware setup differs as well:
  - It uses a **±2 g range** ([579-583](CPReady_Test_Bench/CPReady_Test_Bench.ino#L579-L583)),
    so upward peaks above +1 g of dynamic acceleration clip.
  - Wiring is direct at 0x68/0x69 instead of through the multiplexer.
  - It uses a different MPU library.

  Its "paper export" ([1373-1377](CPReady_Test_Bench/CPReady_Test_Bench.ino#L1373-L1377))
  produces K and threshold values that do not mean the same thing in production, because
  unfiltered and filtered peak-to-peak values differ.
- **Impact:** Parameters tuned or reported from the bench do not transfer to the vest.
- **Fix:** P2.8.

#### H8: The documented wiring does not work with the production firmware

- **Where:** Hardware guide §4 and Test Bench README §2 (both MPUs on one bus at 0x68/0x69);
  [SensorManager.h:358-361](CPReady_Program/include/SensorManager.h#L358-L361);
  [CPReadyConfig.h:95](CPReady_Program/include/CPReadyConfig.h#L95).
- **What:** In dual-MPU mode the firmware *requires* a PCA9548A multiplexer and rejects
  direct 0x68 + 0x69 wiring with `FAULT_ERROR`. Only the developer guide documents the
  multiplexer.
- **Fix:** P1.12. Support both topologies (probe 0x68 + 0x69 on the main bus first), and keep
  one wiring document.

#### H9: The KiCad schematic is a parts placement for a different MCU, and the PCB is empty

*Added in revision 2.* **Team decision (27 Oct 2026): out of scope.** The schematic is not
used. The hardware is a classic ESP32 with two MPU-6050s behind a PCA9548A multiplexer, which
is what the firmware targets. The finding is kept for reference only.

- **Where:** [CPReady_Electronics.kicad_sch](Schematic%20and%20PCB/CPReady_Electronics/CPReady_Electronics.kicad_sch),
  [CPReady_Electronics.kicad_pcb](Schematic%20and%20PCB/CPReady_Electronics/CPReady_Electronics.kicad_pcb).
- **What:**
  - The schematic places 7 symbols: TP4056, MT3608, a switch, two cells, `MCU_Espressif:ESP32-S3`
    and **one** `module_mpu6050`. It has **no wires, labels or junctions**, so it defines no
    circuit.
  - The PCB file is an empty 79-byte header.
  - The MCU is the **bare ESP32-S3 chip**. A bare chip needs flash (unless it is an FN8
    part), a 40 MHz crystal, RF matching and an antenna, decoupling, and a USB or UART
    programming path. A module such as ESP32-S3-WROOM-1 provides all of these.
  - The firmware is built for the **classic ESP32** (`board = esp32dev`) and uses I2C on
    GPIO21/22. **GPIO22 does not exist on the ESP32-S3.** The hardware guide's FSR on GPIO34
    is an ADC pin on the classic ESP32 but **not on the S3**, where the ADC pins are GPIO1–20.
  - The schematic has a single MPU-6050 and no multiplexer, yet depth needs both
    accelerometers (chest minus spine). It has no FSR either, though C5 needs one.
  - Two cells with a single-cell TP4056 charger only work if the cells are in parallel (1S).
    Nothing in the file says which.
- **Impact:**
  - No board can be made from these files.
  - If the board is drawn around the S3 as placed, the firmware will not run on it without
    changes to the board target, the pins and possibly the BLE configuration.
- **Fix:** P5.2. Pick the MCU first. The least-risk choice is to keep the classic ESP32 as a
  WROOM-32 module, matching `esp32dev`. If the S3 is wanted, use an S3 *module* and add an
  `esp32-s3-devkitc-1` environment with new pin constants. Then draw:
  - both MPUs, at 0x68/0x69 or behind the PCA9548A;
  - the FSR divider on an ADC1 pin;
  - battery sensing;
  - the charger and boost wiring.
  Run ERC before laying out the PCB.

#### H10: The research questions need data the system does not record

*Added in revision 2.*

- **Where:** `CPReady Research Proposal.pdf` (RQ 1.1–1.4, 2.1–2.4); the History schema; the
  BLE protocol.
- **What:** The proposal promises the following measures, each reported as mean, SD and MAE
  against a comparison system, video and a BLS instructor.

  | Proposal item | What the system recorded at `3c086a5` |
  |---|---|
  | RQ 1.1–1.4: accuracy of depth, rate, recoil and CCF | Only the session summary. Per-stroke values were thrown away (L6), so nothing can be paired stroke by stroke with the reference. Recoil is not measurable (C5). |
  | RQ 2.1: response time | Nothing. No packet carries a device timestamp and the app does not log arrival times, so the stroke-to-feedback latency cannot be computed. |
  | RQ 2.2: Bluetooth reliability | Nothing. Packets had no sequence number, so losses were invisible. |
  | RQ 2.3: logging completeness | Only whether the summary was saved. There is no count of expected versus stored strokes. |
  | RQ 2.4: firmware algorithmic accuracy | Nothing re-scorable. No raw sensor data is kept (P0.3). |
- **Impact:** Half of the research questions cannot be answered from the data the device
  produces, whatever its accuracy.
- **Fix:**
  - **Done in this pass:** protocol v2 adds a 16-bit sequence number, and the app stores
    `packets_lost` per session. That answers RQ 2.2.
  - **Still to do:**
    - P0.3: raw logging, for RQ 2.4.
    - P4.4: a per-stroke table and CSV export, for RQ 1.x and 2.3.
    - P3.8: add a device millisecond timestamp to each packet and log the app's receive time,
      for RQ 2.1.

### 4.3 Medium

| ID | Finding | Where | Fix |
|---|---|---|---|
| **M1** | **CCF is stale and inconsistent.** Live CCF is recomputed only when a stroke completes, so it freezes during pauses. Gaps under 2 s count as active time, but the pause rule is 1.5 s. The START→first-stroke interval is also credited as active. | [CompressionTracker.h:276-279, 319-324](CPReady_Program/include/CompressionTracker.h#L276-L279) | P2.5 |
| **M2** | **Rate averages include bad values.** The first stroke's "rate" is 60000 ÷ (time since START). Gaps of 2 s or more keep and re-add the previous stroke's rate. Post-pause strokes at 1.5–2 s add 30–40 cpm. All of these go into `avg_rate_cpm`. | [CompressionTracker.h:276-279, 333](CPReady_Program/include/CompressionTracker.h#L276-L279), [499](CPReady_Program/include/CompressionTracker.h#L499) | P2.4 |
| **M3** | **Only the z axis is used, against a fixed baseline.** Calibration accepts a z-gravity of 0.65–1.35 g, i.e. tilts up to about 49°. Compression is then under-read by cos θ: 13 % at 30°, 34 % at 49°. K silently absorbs vest-specific tilt. A pad that shifts mid-session is never re-baselined. | [SensorManager.h:411, 513-520](CPReady_Program/include/SensorManager.h#L411); [CPReadyConfig.h:70-72](CPReady_Program/include/CPReadyConfig.h#L70-L72) | P2.1 |
| **M4** | **The compression count saturates at 255** (it is a `uint8`). A 2-minute session above about 128 cpm exceeds it. The live counter circle then turns "idle" because the count stops rising, and History stores 255. | [BLEReadings.h:73, 130, 166](CPReady_Program/include/BLEReadings.h#L73); [live_practice_screen.dart:152-158, 185-188](FLUTTER/cpready/lib/src/screens/live_practice/live_practice_screen.dart#L152-L158) | P3.1 |
| **M5** | **Recoil grading.** `recoilRating(0)` returns `null`, so a "Partial" stroke and a 0 % summary are drawn in neutral grey instead of red. The summary needs exactly 100 %, so 98 % compliance shows a red "Partial". | [metric_feedback.dart:37-43](FLUTTER/cpready/lib/src/core/feedback/metric_feedback.dart#L37-L43); [targets.dart:26](FLUTTER/cpready/lib/src/config/targets.dart#L26) | P1.11 / P4.3 |
| **M6** | **A dropped link loses the session.** A disconnect wipes the session and summary ([main.cpp:278-287](CPReady_Program/src/main.cpp#L278-L287)), there is no session ID to match GET_RESULTS to the right session, and the app never auto-reconnects. One Android BLE hiccup loses a 2-minute session. | firmware and app | P3.4, P3.5 |
| **M7** | **Several vests look identical.** Every vest advertises "CPReady", and the app connects to the last match seen. In a class with several vests it can connect to a neighbour's. Device settings are a single row. | [CPReadyConfig.h:34](CPReady_Program/include/CPReadyConfig.h#L34); [ble.dart:72-83](FLUTTER/cpready/lib/src/core/ble/ble.dart#L72-L83) | P3.6 |
| **M8** | **The app wrongly believes SET_PROFILE resets K.** It clears its known K and tells users to recalibrate. The firmware actually keeps a separate K per profile. | [kinematic_profile.dart:1-4](FLUTTER/cpready/lib/src/core/ble/kinematic_profile.dart#L1-L4); [device_settings_screen.dart:291-309](FLUTTER/cpready/lib/src/screens/device_settings/device_settings_screen.dart#L291-L309); [practice_setup_screen.dart:113-118](FLUTTER/cpready/lib/src/screens/setup/practice_setup_screen.dart#L113-L118); [strings.dart:203-204](FLUTTER/cpready/lib/src/config/strings.dart#L203-L204); [CompressionTracker.h:176-187](CPReady_Program/include/CompressionTracker.h#L176-L187) | P4.5 |
| **M9** | **Type 3 means two things.** `CALIB_SUCCESS` is reused as the acknowledgement for CALIBRATE_TARGET, so an unrelated type 3 can be mistaken for "K saved". | [main.cpp:164](CPReady_Program/src/main.cpp#L164) | P3.3 |
| **M10** | **Live values go stale.** After a pause the last stroke's values stay on screen indefinitely. Per-stroke values jump from stroke to stroke. There is no live CCF and no "paused" indicator. | live screen | P4.1 |
| **M11** | **iOS will crash on Bluetooth use.** `Info.plist` has no `NSBluetoothAlwaysUsageDescription`, so iOS terminates the app on first Bluetooth access (if iOS is a target). | `ios/Runner/Info.plist` | P4.7 |
| **M12** | **Build hygiene.** Demo mode does not compile: `DEMO_CCF_PERCENT` is undefined ([main.cpp:37, 349](CPReady_Program/src/main.cpp#L37)). `CPReady_Program.ino` duplicates `src/main.cpp`. PlatformIO ignores it, while the Arduino IDE would compile both (duplicate `setup`/`loop`) and cannot see `include/`. README Option B tells users to install the Electronic Cats library, but the firmware uses the vendored Adafruit one. | firmware root | P0.5 |
| **M13** | **The simulator cannot validate the algorithm.** Its waveform is non-physical: peak ≠ −trough, so velocity does not return to zero each cycle. It is shaped around C2. Its behaviour also differs from `main.cpp`: STOP when idle re-sends the summary ([simulation.cpp:258-261](CPReady_Program/src/simulation.cpp#L258-L261)), SET_K persists only the legacy key ([284-290](CPReady_Program/src/simulation.cpp#L284-L290)), and there are no gravity or alignment checks. App behaviour tested against the simulator can differ on hardware. | simulation build | P0.2, P2.8 |
| **M14** | **Little flash headroom.** The `esp32dev` image used 87.6 % of the 1.25 MB app partition at `3c086a5`, and 89.9 % with this pass's fixes. Most of it is the Bluedroid BLE stack. That leaves little room for Phase 2 or OTA updates. | build output | P3.7 |
| **M15** | **Sampling details.** `lastSampleMicros = currentMicros` accumulates loop jitter, so the effective rate is a little under 100 Hz and not exactly known. The EMA state is not reset at calibration. Each sample makes 3 I2C transactions per sensor at 100 kHz, about 5 ms of the 10 ms budget. | [SensorManager.h:505-508, 527](CPReady_Program/include/SensorManager.h#L505-L508) | P1.7, P2.1 |
| **M16** | **The test bench is not a reliable instrument** *(rev. 2)*. Beyond H7: (a) its `platformio.ini` reports "Nothing to build", because the sketch is not under `src/`, so it only builds in the Arduino IDE. (b) It runs an **open** Wi-Fi access point (`softAP(ssid, nullptr)`), so anyone nearby can join and send `/api/action` commands. (c) The page polls `/api/metrics` 10 times a second ([1385](CPReady_Test_Bench/CPReady_Test_Bench.ino#L1385)), and `server.handleClient()` runs in the same loop as sampling ([1640-1648](CPReady_Test_Bench/CPReady_Test_Bench.ino#L1640-L1648)). A slow request delays samples, which the catch-up scheduler then takes in a burst; this is by inspection. (d) `archive/` holds two more algorithm variants that differ again: un-negated sign, an EMA, ±4 g range, and a WPA2 AP. Three detectors in one repo make it unclear which one produced any reported number. | `CPReady_Test_Bench/` | P2.8 |
| **M17** | **The guide told lay rescuers to check for a pulse** *(rev. 2)*. Step 3 said to check breathing "and check for a pulse simultaneously". AHA guidance for lay rescuers is to check breathing only; the pulse check is for healthcare providers, and it delays CPR. | [guide_steps.dart:30-34](FLUTTER/cpready/lib/src/config/guide_steps.dart#L30-L34) | Fixed in this pass |
| **M18** | **The Android build is not releasable** *(rev. 2)*. `applicationId` is `com.example.cpready`, which Google Play rejects, and the release build type signs with the **debug** key. Any APK given to testers can be replaced by anyone holding the public debug key, and it cannot later be upgraded in place by a properly signed build. | [build.gradle.kts:18, 30](FLUTTER/cpready/android/app/build.gradle.kts#L18) | P4.7 |

### 4.4 Low and polish

| ID | Finding | Where |
|---|---|---|
| L1 | `awaitPacketWhere` leaves its `firstWhere` subscription alive after a timeout (`Future.timeout` does not cancel it). | [ble_controller.dart:219-227](FLUTTER/cpready/lib/src/core/ble/ble_controller.dart#L219-L227) |
| L2 | Packets arriving between `setNotifyValue(true)` and `listen()` are dropped because the stream controller is created lazily. | [ble.dart:160-191](FLUTTER/cpready/lib/src/core/ble/ble.dart#L160-L191) |
| L3 | `BleController.sendCommand` throws *synchronously*; it should return a failed `Future`. Callers that don't `await` inside `try` would crash. | [ble_controller.dart:208-213](FLUTTER/cpready/lib/src/core/ble/ble_controller.dart#L208-L213) |
| L4 | The calibration screen's ERR_WRONG_STATE retry can never succeed if the device is stuck in a session. Offer "Stop running session" (send STOP). | [calibration_screen.dart:154-156](FLUTTER/cpready/lib/src/screens/calibration/calibration_screen.dart#L154-L156) |
| L5 | `TextScaler.noScaling` disables the OS font-size setting app-wide. This is a deliberate design choice: `layout_matrix_test.dart` asserts it, so the fixed layouts are guaranteed not to overflow. It is still an accessibility trade-off. If it is revisited, clamp instead (`textScaler.clamp(maxScaleFactor: 1.3)`) and add 1.3× cases to the layout matrix. | [main.dart:143-149](FLUTTER/cpready/lib/main.dart#L143-L149) |
| L6 | Per-stroke packets are recorded but thrown away; only the summary is stored. Research needs per-stroke export. | [live_practice_screen.dart:303, 393-408](FLUTTER/cpready/lib/src/screens/live_practice/live_practice_screen.dart#L303) |
| L7 | The firmware version is never reported, so History's `firmware_version` is always null. | protocol |
| L8 | Comments say the firmware does not answer GET_CONFIG; it does now. | [config/ble.dart:69-71](FLUTTER/cpready/lib/src/config/ble.dart#L69-L71), [device_config.dart:13](FLUTTER/cpready/lib/src/core/ble/device_config.dart#L13), [ble_controller.dart:231-233](FLUTTER/cpready/lib/src/core/ble/ble_controller.dart#L231-L233) |
| L9 | A per-stroke `Serial.println` runs inside the 100 Hz loop and can block when the UART FIFO fills. Add a log level. | [main.cpp:378-380](CPReady_Program/src/main.cpp#L378-L380) |
| L10 | No battery monitoring, no task watchdog, and the brownout or reset reason is not reported. | firmware |
| L11 | `CPReady_Test_Bench/archive/` holds 127 KB of older sketches that are easy to flash by mistake. | test bench |
| L12 | `pubspec.yaml` still says "A new Flutter project." | app |
| L13 | **Dead widgets** *(rev. 2)*. These are referenced by nothing except their own files and the `widgets.dart` barrel: `ConnectionStatusChip`, `ConnectButton`, `MetricsCard`, the public `MetricRow` (the summary uses its own private `_MetricRow`), `HoldToConfirmButton`, `HeartbeatIcon`, and every class under `widgets/base/`. They still have to compile and be read. Delete them, or move them to an example. | [widgets.dart](FLUTTER/cpready/lib/src/widgets/widgets.dart) |
| L14 | **Splash navigation in `initState`** *(rev. 2)*. With `showSplash = false`, the splash screen calls `context.go` from `initState`, which navigates during the first build. It works today only because the flag is true; switch to `addPostFrameCallback` or a router `redirect`. | [splash_screen.dart:24-35](FLUTTER/cpready/lib/src/screens/splash/splash_screen.dart#L24-L35) |
| L15 | **History dates use chained `replaceAll`** *(rev. 2)*. Each token replacement also matches letters inserted by earlier replacements. The current English data happens to be safe, but a month name containing a lowercase "d" (e.g. a localised "dic") would be corrupted, as would any literal word containing "d", "h" or "A" in either pattern. Use `intl`'s `DateFormat`. | [history_format.dart:13-27](FLUTTER/cpready/lib/src/core/history/history_format.dart#L13-L27) |
| L16 | **Template colours** *(rev. 2)*. `brandPrimary`, `brandSecondary` and `brandSurface` were the Flutter template's purple (`0xFF6200EE`, `0xFFEADDFF`). They seed the Material `ColorScheme`, so dialog buttons and progress indicators were purple in an otherwise blue app. Fixed in this pass. | [colors.dart:16-24](FLUTTER/cpready/lib/src/config/colors.dart#L16-L24) |
| L17 | **Platforms** *(rev. 2)*. The iPhone build allowed landscape, though every screen is laid out for portrait (now portrait only). The `web/`, `windows/`, `linux/` and `macos/` scaffolds remain, but `flutter_blue_plus` has no BLE on most of them, so they build an app that cannot connect. Remove them or document them as unsupported. | `ios/Runner/Info.plist`; platform folders |
| L18 | **Home gates calibration on the local profile** *(rev. 2)*. The Manikin Calibration button reads the profile from the phone's settings row, whose comment says the firmware "has no read-back". The firmware now answers GET_CONFIG, so if the vest was switched from another phone or by RESET_CONFIG, the gate can be wrong. Ask the device instead. | [home_screen.dart:383-425](FLUTTER/cpready/lib/src/screens/home/home_screen.dart#L383-L425) |
| L19 | **Firmware and app must be updated together** *(rev. 2)*. App builds from `3c086a5` reject any packet that is not 11 or 12 bytes, so they discard every 16-byte v2 packet from the new firmware. The new app still decodes 11- and 12-byte packets from old firmware. | protocol |

### 4.5 Documentation drift

| ID | Drift |
|---|---|
| D1 | Packet size is given as 8 bytes in `README.md`, `ARCHITECTURE.md` and `CPReady_Firmware_Program_Flow.md`, and as "11-byte" in `BleManager.h` comments. The actual size is **12**. |
| D2 | The error-code table in `SOFTWARE_DEVELOPER_GUIDE.md` §3 does not match `BLEReadings.h:36-43`. For example, the guide says 1 = NOT_READY; the firmware says 1 = MOTION_UNSTABLE. The app follows the firmware. The config-packet column also does not match `CPRConfigPacket`. |
| D3 | Documented but not implemented: `SET_K_MANIKIN`, `SET_K_BENCH`, `SET_TIME:0` meaning "indefinite", PAUSE "pauses timer and CCF", audio cue 7 "Maintain a steady rhythm", and a "trimmed mean" depth (the code uses a qualified mean). |
| D4 | The developer guide §2.1 and its sequence diagram say advertising resumes after a disconnect. It does not (C1). |
| D5 | The developer guide §6 demo-mode instructions fail to compile (M12). |
| D6 | `ALGORITHM_RESEARCH.md` makes three errors: it says the EMA has no phase lag (it has about 30 ms of group delay); it derives K by "damping" (C6); and it still describes an "8-byte" packet. Some 2025–2026 citations could not be verified. **Check every DOI before citing.** The paper in Reyn's notes (Ruiz de Gauna 2016) is the right primary reference for the method. |
| D7 | The hardware guide specifies an FSR on GPIO34, a buzzer on GPIO25, 0x69 for the second MPU and 400 kHz I2C. None of these are in the production firmware (C5, H8). |
| D8 | The calibration guide compares the vest against a **separate** reference run (§5, Step 1), so K absorbs run-to-run variation. A clicker only signals "≥ 5 cm"; it does not give a mean depth. The "±2–3 mm" expectation is unsupported (C6). |
| D9 | `FIRMWARE_AUDIT.md` is not marked as partly resolved (see 4.6). |

### 4.6 Status of the earlier `FIRMWARE_AUDIT.md`

| # | Item | Status now |
|---|---|---|
| 1 | Stroke state latch-up | **Fixed** (2 s watchdog) |
| 2 | First-stroke explosion | **Fixed** (seeded at START, 0.55 s fallback period) |
| 3 | CCF freeze / stale summary | **Partly fixed:** the final CCF is recomputed, but live CCF still freezes during pauses (M1) |
| 4 | Demo-mode underflow | Guarded, but demo mode no longer compiles (M12) |
| 5 | PAUSE handling | **Open**, and worse (H3) |
| 6 | Calibration motion rejection | **Fixed** |
| 7 | Coaching streaks across pauses | **Fixed** |
| 8 | Dropped BLE commands | **Fixed** (8-slot queue); a full queue still drops silently |
| 9 | Doc drift | **Open** (D1–D9) |
| 10 | 255 count saturation | **Open** (M4) |
| 11 | `.ino` parity | The files are identical, but the Arduino IDE build path is broken (M12) |

---

## 5. Improvement implementation plan

Effort sizes: **S** is up to half a day, **M** is 1–2 days, **L** is 3–5 days. Every task
lists the findings it closes and how to show it is done. Phases 0 and 1 are the minimum before
any data is collected for the paper.

**Status after revision 2** (details and evidence in §9):

| Status | Tasks |
|---|---|
| Done in the working tree; verified in software | P1.2, P1.3, P1.4 (interim adaptive threshold), P1.5 (a–c), P1.6, P1.8, P1.9, P1.10, P1.11, P0.5 (demo mode compiles; README fixed), parts of P3.1 (uint16 count and sequence number, as a 16-byte v2), P4.5, P4.6 (except "Stop running session"), the iOS half of P4.7 |
| Done; needs a hardware check | P1.1 (BLE disconnect), P1.7 (sensor fault handling; saturation detection and bus recovery not done), P1.12 (direct 0x68/0x69 wiring) |
| Partly done | P0.2: a native regression test exists (`CPReady_Program/test_native/`), but not yet as `pio test -e native`, and the command state machine still lives in `main.cpp` and is untested |
| Open | P0.1 tag and branch, P0.3, P0.4, all of Phase 2, P3.2–P3.8, P4.1–P4.4, P4.8 (partly covered), Phase 5 |

### Phase 0: Foundations (do first)

| Task | What | Done when | Effort |
|---|---|---|---|
| **P0.1** Version control | *Corrected in revision 2:* the first revision said this folder was not a git repository. That was wrong; I had checked the parent folder. `CPReady/` is a clone of `github.com/Marni3/CPReady` on `main`, and the audit baseline is commit `3c086a5`. Remaining work: tag `3c086a5` as `audit-baseline`, commit this pass's changes on a branch (they are uncommitted in the working tree), and use one branch and one PR per later task. `.pio/` and `.dart_tool/` are already ignored. | The tag exists; every later change is a reviewable diff. | S |
| **P0.2** Firmware unit tests | Add `[env:native]` (`platform = native`, Unity). Make `CompressionTracker.h` and its configuration build without `Arduino.h`, using a tiny `Platform.h` the way `audit_evidence/tracker_replay/shim` does. Turn the replay scenarios into assertions in `test/test_tracker/`: detection ≥ 98 %, rate error ≤ 2 cpm, and no recoil-from-leaning claims. Add a table-driven test of every (state, command) pair for P1.6, which needs the command dispatcher moved out of `main.cpp` into a testable `SessionController`. **These tests will fail today; that is the point.** | `pio test -e native` runs on any PC. | M |
| **P0.3** Raw data logging | Add a `CPREADY_RAW_LOG` build flag. During `ACTIVE_SESSION` it streams `t_us,cx,cy,cz,bx,by,bz` as CSV at 100 Hz over Serial (921600 baud), plus a small Python capture script. Use it to record ≥ 10 real manikin sessions **with ground truth** (§6): target, shallow, deep, fast, slow and leaning bouts. These recordings feed the Phase 2 work and become regression fixtures. | Fixtures checked in under `test/data/`. | M |
| **P0.4** App CI | Pin the Flutter version and run `flutter analyze` and `flutter test` on every push (GitHub Actions or a script). | Green CI. | S |
| **P0.5** Build hygiene (M12) | Delete demo mode; the `simulation` environment replaces it. Delete or regenerate `CPReady_Program.ino`. Fix README Option B and the library name. | Both PlatformIO environments build, and the docs match. | S |

### Phase 1: Critical and high-severity fixes (surgical, about one week)

These are small and testable, and they should land before any further trials.

| Task | Change | Closes | Done when | Effort |
|---|---|---|---|---|
| **P1.1** Disconnect handling | In `BleManager`, treat every `onDisconnect` as the disconnect: set the flags and call `BLEDevice::startAdvertising()` **without** the connected-count check. Keep one overload for logging only. See Appendix B.1. | C1 | 20 connect/disconnect cycles from the app without a power cycle; the app reconnects within 5 s each time. A disconnect during a session aborts it (or follows P3.5). | S |
| **P1.2** Onset-based lockout | Measure the lockout from **stroke onset**: `strokeStartMillis == 0 \|\| now − strokeStartMillis > MIN_ONSET_INTERVAL_MS` (300 ms ≈ 200 cpm). Also require `now − lastStrokeEnd > 80 ms`, or use an adaptive `0.6 × median recent period`. The patched replay showed four double counts at 100 cpm with a strong top-deceleration lobe (bench profile), so a pure 300 ms onset lockout is not enough on its own. | C2 | Native tests: 80–150 cpm at ≥ 98 % sensitivity **and** ≥ 98 % precision; rate within ±2 cpm. | S |
| **P1.3** Armed recoil exit | Add `recoilArmed`, set once `netAccel < RECOIL_ARM_G` (−0.10 g, or half the recoil threshold for the bench profile). Finish the stroke only when armed **and** ≥ −0.05 g. See Appendix B.2. | C3 | Bench sinusoid at 100 cpm: trough captured, no stroke ends within 40 ms of entering RECOILING. | S |
| **P1.4** Adaptive start threshold (interim) | `threshold = clamp(0.35 × median(a_pp of last 4 strokes), 0.12 g, profile threshold)`, with hysteresis (re-arm below 0.5 × threshold). Seed it at the profile value. | C4 | 3–7 cm strokes at 90–140 cpm, all three shapes: ≥ 95 % detected. Full redesign in P2.3. | M |
| **P1.5** Honest recoil (interim) | Until an FSR exists: (a) the firmware stops issuing `PROMPT_RELEASE_FULLY` from the acceleration proxy; (b) a new `quality_flags` bit 3 `RECOIL_ESTIMATED` is set; (c) the app shows recoil as "—", or as "Estimated" in grey, and leaves it out of scoring and History grading; (d) the docs and paper describe it as not measured. *Team decision; this is the recommended option.* | C5 | No recoil cue without an FSR; the UI labels it. | S |
| **P1.6** Command state machine | Implement the transition table in Appendix B.3. START only from `CALIBRATED_READY`, which removes the legacy auto-calibrate. STOP during calibration aborts without a summary. PAUSE and RESUME are guarded with paused-time compensation, or removed until the app needs them. Configuration commands are rejected during a session. Add `tracker.endSession()` to clear `sessionStartMillis`. Every rejection returns `ERR_WRONG_STATE`. | H3 | Table-driven native test of every (state, command) pair. | M |
| **P1.7** Sensor health | Patch the vendored library: `_read()` returns `bool`, zero-initialises the buffer, caches the range scale, reads only the 6 accel bytes on the fast path, puts a 100 ms bound on the `reset()` loop, and writes ACCEL_CONFIG2 for WHO_AM_I ≠ 0x68 (H2). In `SensorManager`: propagate failures; after 5 consecutive failures (50 ms), send `ERR_I2C_FAULT`, enter `FAULT_ERROR`, then run `recoverI2CBus()` and re-init. Detect stuck values (identical raw values for 50 samples) and saturation (\|a\| ≥ 3.9 g). In `FAULT_ERROR`, CALIBRATE first tries a re-init and otherwise answers `ERR_I2C_FAULT`. Use `lastSampleMicros += interval` with a catch-up guard, and reset the EMA at calibration (M15). | H1, H2, M15 | Unplugging the chest sensor mid-session shows a sensor-fault message within 0.5 s with no phantom strokes; re-plugging and calibrating recovers. | M |
| **P1.8** One cue, once | Firmware: clear `audio_prompt_code` after the first packet that carries it (`tracker.clearAudioPrompt()` after `sendPacket`). App: play only when the code *changes* from the previous real-time packet. Keep `VoiceCueGate` for overlap protection. See Appendix B.4. | H4 | Widget test: a cue code repeated in 10 packets over 3 s plays once. Hardware: a 5 s pause after a cue gives one playback. | S |
| **P1.9** Start watchdog | Only real-time packets set `_latest` and cancel the watchdog. A type 2 packet on the live screen means the device re-calibrated, so show the start-failure dialog. See Appendix B.5. | H5 | Widget test: type 2 and 3 packets then silence give the failure dialog at 3 s. | S |
| **P1.10** K storage | Stop writing `depth_k`. On boot, migrate it to `k_manikin` once, only if `k_manikin` is missing **and** the saved profile was MANIKIN, then delete `depth_k`. Define `K_MIN`/`K_MAX` once in `CPReadyConfig.h` and use them for runtime, boot and the app's `AppBleConfig.depthKMin/Max`. | H6 | Reboot test: bench K never leaks into manikin K. | S |
| **P1.11** App grading fixes | `recoilRating`: `null` only for a `null` value. Grade summary recoil compliance as ≥ 90 % good, below that poor, and show the percentage. Grade CCF as ≥ 80 % good, 60–79 % fair, < 60 % poor. | M5 | Unit tests for 0, 89, 90 and 100. | S |
| **P1.12** Both wirings | `SensorManager::begin()` first probes 0x68 **and** 0x69 on the main bus; if both are present, use direct dual mode. Otherwise fall back to the multiplexer path. Log which topology was found. | H8 | Both wirings boot into dual mode. | S |

### Phase 2: Measurement validity (2–3 weeks; needs the P0.3 recordings)

The goal is to make the numbers defensible in the paper. Keep the old estimator behind a
compile flag so the old and new versions can be compared on the same recordings.

**P2.1 Signal conditioning** (closes M3, M15; effort M)
- During calibration, record the full gravity **vector** (x, y, z) for each sensor. Project
  every sample onto that unit vector, so dynamic acceleration along gravity no longer depends on
  tilt.
- Reject a tilt above about 20° with a new error code (`ERR_TILT`), and report the tilt.
- Remove baseline drift with a 0.3 Hz high-pass filter, or by removing the mean of each window
  in P2.2.
- Split the filtering: a 5 Hz low-pass for *detection*, and the raw (44 Hz hardware-filtered)
  signal for *estimation*.
- Optional: sample on the MPU's data-ready interrupt (INT → GPIO19, as in the hardware guide)
  for jitter-free 100 Hz.

**P2.2 Harmonic depth and rate estimator** (closes C6; effort L)

This follows Ruiz de Gauna et al. 2016 (PMC5143701).
- Keep a ring buffer of the last 3 s × 100 Hz for the chest and base signals. That is
  2 × 300 floats, 2.4 KB.
- On each detected stroke, or every 0.5 s:
  1. Find the fundamental period T from the autocorrelation over 0.3–1.5 s lags, with
     parabolic refinement, or from the median stroke period.
  2. Compute Fourier coefficients for k = 1…6 over a whole number of periods.
  3. Reconstruct displacement as x(t) = −Σ a_k / (kω)².
  4. Report depth = peak-to-peak of (x_chest − x_base).
- **Quality gate:** if the normalised autocorrelation peak is below about 0.6 (rhythm not
  periodic), hold the last value and set `STEADY = 0`.
- K becomes `DEPTH_SCALE`, default 1.0, for small sensor-scale corrections.
- Cost: about 25 k multiply-accumulates per update, under 1 ms on the ESP32.
- The prototype is in `audit_evidence/tracker_replay/harmonic.cpp`.
- **Done when:** on the recorded fixtures, depth error is ≤ 5 mm MAE and rate error ≤ 2 cpm
  (§6 targets). On the synthetic set, ≤ 3 % error across shapes, which the prototype already
  meets.

**P2.3 Stroke detection redesign** (closes C4, C2; effort M)
- Count strokes from the conditioned signal using an adaptive threshold with hysteresis, or
  from the minima of the reconstructed displacement.
- Cross-check: the count over a window should be about f₀ × window.
- **Done when:** detection sensitivity and precision are ≥ 98 % on the fixtures, including
  shallow and fast bouts.

**P2.4 Rate and session statistics** (closes M2; effort S)
- Take the live rate from the median of the last 3–5 onset intervals, or from f₀.
- Leave first and post-pause strokes out of every average.
- Summary: median and interquartile range for depth and rate, % of strokes in the depth band,
  % in the rate band, number of pauses and longest pause. These match how commercial
  QCPR-style feedback scores sessions.

**P2.5 CCF** (closes M1; effort S)
- Define a pause as no stroke for ≥ 2.0 s (one constant, documented).
- Accumulate hands-off time in real time and send CCF in **every** packet. Finalise with the
  same rule.

**P2.6 Recoil with an FSR** (closes C5; effort L, includes hardware)

*Team decision (27 Oct 2026): the product will not get a force sensor, because of hardware
constraints and the unreliability of analog FSRs. The lab build (`LAB_MODE_ARCHITECTURE.md`)
records an optional FSR402 or RFP602 module and accelerometer release features against
labelled leaning bouts. That data decides whether any recoil indication is defensible. Until
then recoil stays "estimated" (P1.5). The steps below apply only if a force sensor is adopted
later.*

- Add the FSR 406 with a 10 kΩ divider on GPIO34 (ADC1), as the hardware guide already
  specifies. Sample it at 100 Hz with a 4× oversampled average.
- Calibrate per session: hands-off baseline, then hands-resting baseline.
- Per stroke: take the **minimum force in the release window** between strokes. Recoil is
  complete if that minimum is below the threshold.
- Convert the threshold to newtons with known weights. *Literature commonly defines leaning as
  ≥ 2.5 kg (about 25 N) of residual force; the hardware guide says "2.5 N". Settle the units
  before implementing.*
- Re-enable `PROMPT_RELEASE_FULLY` only on FSR evidence.
- **Done when:** leaning bouts are detected with ≥ 85 % sensitivity and ≥ 85 % specificity
  against ground truth.

**P2.7 Retire the heuristics** (effort S)
- Once P2.2 is validated, remove the T clamps, the 0.55 s fallback period, the 10 cm clamp
  workaround and the old K profiles.

**P2.8 Converge the bench and the simulator** (closes H7, M13; effort M)
- Rebuild the test bench on the shared `SensorManager.h` and `CompressionTracker.h` (Wi-Fi UI
  only), or retire it for tuning.
- Replace `SyntheticVest` with the physical displacement model (x(t) → a = x″) plus replay of
  the recorded fixtures.
- Make the simulation's command handling call the same `SessionController` as `main.cpp`.

### Phase 3: Protocol v2 and robustness (1–2 weeks; can overlap with Phase 2)

**P3.1 Packet v2** (closes M4, H4, L7; effort M)
- Grow the packet to 20 bytes. That still fits the default ATT MTU of 23.

  | Bytes | Field |
  |---|---|
  | 0 | type |
  | 1 | protocol version |
  | 2–3 | session ID |
  | 4 | sequence number |
  | 5 | device state |
  | 6–7 | stroke count (uint16) |
  | 8–9 | rate × 10 |
  | 10–11 | depth in 0.1 mm |
  | 12 | CCF |
  | 13 | recoil (flag or %) |
  | 14 | cue code |
  | 15 | cue sequence number |
  | 16–17 | elapsed seconds |
  | 18 | quality and fault flags |
  | 19 | reserved |

- Negotiate the version through GET_CONFIG; the app keeps its 12-byte decoder for v1.

**P3.2 Status heartbeat** (effort S)
- Send a 1 Hz status packet when no session is active: state, fault flags, battery mV,
  firmware version, last reset reason.
- Add a GET_STATUS command.

**P3.3 Command acknowledgements** (closes M9; effort S)
- Add a new type 7 `CMD_ACK` packet: command ID, result, error code. Stop using type 3 as an
  acknowledgement.

**P3.4 Session identity** (closes M6; effort S)
- Make the session ID a uint16 incremented in flash.
- Cache the summary per ID, and add `GET_RESULTS:<id>`. The app only saves a summary whose ID
  matches the session it started.

**P3.5 Disconnect grace period** (closes M6; effort M)
- On disconnect during a session, keep sampling for up to 30 s, so the trainee's compressions
  still count.
- The app shows a banner and reconnects automatically: scan for the remembered `remoteId` and
  retry with backoff.
- On reconnect, the app sends GET_STATUS and then either resumes or fetches the summary.
- If no reconnect happens within 30 s, the firmware finalises and caches the summary.
- The developer guide's "drop means interrupted" policy can remain as the fallback.

**P3.6 One vest per phone** (closes M7; effort M)
- Advertise as `CPReady-XXXX`, using the last two MAC bytes.
- The app shows a device picker the first time, remembers the `remoteId`, and keeps settings
  per device.

**P3.7 Flash headroom** (closes M14; effort M)
- Migrate to NimBLE-Arduino, which roughly halves the BLE flash cost and is API-similar, or set
  `board_build.partitions = huge_app.csv` as a stop-gap.

**P3.8 Resilience** (closes L10; effort S–M)
- Enable the task watchdog (`esp_task_wdt`) on the loop.
- Report `esp_reset_reason()` in the status packet.
- Measure battery voltage through a divider on an ADC1 pin and warn below 3.5 V; the
  hardware guide's brownout trap is relevant here.

### Phase 4: App polish (can run in parallel with Phase 3)

| Task | What | Closes | Effort |
|---|---|---|---|
| **P4.1** Live display | Show the rolling median of the last 3–5 strokes. After 2 s with no stroke, show "Paused – resume compressions" and grey out the values. Add a live CCF chip. Add colour hysteresis so values near a boundary do not flicker. | M10 | M |
| **P4.2** Recoil UI | Follow the P1.5 / P2.6 outcome. | C5 | S |
| **P4.3** Summary | Show medians, % of strokes in target, pauses, the graded CCF and the recoil percentage. | M5 | M |
| **P4.4** Per-stroke data | Schema v4: a `session_strokes` table (time, depth, rate, recoil, flags), plus CSV export through the share sheet. This is essential for the paper. | L6 | M |
| **P4.5** Config truth | After any SET_PROFILE, SET_K or RESET_CONFIG, re-read GET_CONFIG and show what the device reports. Remove the "K resets on profile change" wording and update the stale comments. | M8, L8 | S |
| **P4.6** BLE layer | Cancellable `awaitPacketWhere` (copy the `requestConfig` pattern); create the telemetry controller before `setNotifyValue`; make `sendCommand` `async`; offer a "Stop running session" recovery. | L1–L4 | S |
| **P4.7** Platforms and accessibility | Add the iOS `NSBluetoothAlwaysUsageDescription` (if iOS is in scope). Allow text scaling with a clamp (`textScaler.clamp(maxScaleFactor: 1.3)`) instead of disabling it. | M11, L5 | S |
| **P4.8** Tests to add | Cue played once over repeated codes; watchdog with calibration packets; counter past 255 (with v2); `recoilRating(0)`; stale-value indicator; v1/v2 decoder parity against byte fixtures produced by the native C++ tests from the real structs. | | M |

### Phase 5: Documentation, hardware and research methodology

| Task | What | Closes |
|---|---|---|
| **P5.1** One protocol spec | Write `docs/PROTOCOL.md` and have tests check it: native tests emit byte fixtures and the Dart tests decode the same fixtures. Delete the protocol tables duplicated in the other guides and link to it. | D1–D5 |
| **P5.2** Hardware guide | Describe the real wiring (multiplexer or 0x68/0x69), the FSR decision, battery sensing and the buzzer (remove it if unused). | D7, H8 |
| **P5.3** Algorithm document | Rewrite it around the harmonic method. Correct the physics (C6, EMA lag). Verify every DOI. | D6 |
| **P5.4** Calibration guide | Use simultaneous ground truth (§6) instead of a separate reference run. Use a train/test split for any scale calibration. Explain that the clicker is a 5 cm threshold indicator. | D8 |
| **P5.5** Earlier audit | Mark the items in `FIRMWARE_AUDIT.md` as resolved or open, and link to this plan. | D9 |
| **P5.6** Paper limitations | State that this is a training aid, not clinical use; that it was tested on one manikin model; the vest and foam effects; and that recoil needs the FSR. | |

---

## 6. Validation protocol (for the research claims)

**Ground truth.** In order of preference:

1. **A linear or draw-wire potentiometer** (100–150 mm stroke) mounted between the chest plate
   and the base, read by the *same* ESP32 in a validation build. This gives sample-synchronous
   true displacement, so depth, rate and recoil (return to zero) all come for free, at low
   cost.
2. The manikin's own feedback (QCPR or similar) recorded **during the same compressions**.
3. Side-on video at 60–120 fps with a millimetre scale, digitised with free tools such as
   *Tracker*.

**Design:**

- At least 10 participants with mixed experience.
- Each does six randomised 30 s bouts: target (5–6 cm, 110 cpm), shallow (about 4 cm), deep
  (about 6.5 cm), fast (about 140 cpm), slow (about 90 cpm) and deliberate leaning.
- Use two surfaces (floor and mattress) to test the two-sensor subtraction.

**Analysis:**

- Per-stroke and per-session mean absolute error and bias.
- **Bland–Altman** 95 % limits of agreement for depth and rate.
- Cohen's κ for in-band versus out-of-band classification.
- Stroke-detection sensitivity and precision.
- Recoil sensitivity and specificity (with the FSR).
- Fit any scale calibration on a held-out subset of participants and **never** report
  accuracy on the data used to calibrate.

**Acceptance targets (training grade):**

| Metric | Target |
|---|---|
| Depth mean absolute error | ≤ 5 mm |
| Depth 95 % limits of agreement | within ±10 mm |
| Rate mean absolute error | ≤ 2 cpm |
| Stroke detection, sensitivity and precision | ≥ 98 % |
| Band classification κ | ≥ 0.8 |
| Recoil sensitivity and specificity (FSR) | ≥ 85 % |

---

## 7. Release checklist (definition of done for every firmware or app release)

1. `pio test -e native` and `flutter test` are green; `flutter analyze` is clean.
2. Errors on the replay fixtures are within the §6 targets.
3. Hardware smoke test:
   - 20 connect/disconnect cycles;
   - unplug a sensor mid-session, then replug and recalibrate;
   - brownout: drop the supply and confirm the reset reason is reported;
   - 2-minute sessions at 100, 120 and 140 cpm;
   - shallow and deep bouts;
   - a 5 s pause, which gives exactly one cue;
   - STOP, auto-stop and GET_RESULTS;
   - manikin calibration, profile switch, and reboot persistence of K;
   - two vests in the same room.
4. Protocol version bumped if the packet layout changed; `docs/PROTOCOL.md` updated.
5. The firmware version shown in the app matches the build.

## 8. Suggested schedule

| Milestone | Contents | Exit criterion |
|---|---|---|
| **M1: Stable baseline** (week 1) | P0.1, P0.2, P0.4, P0.5, P1.1–P1.3, P1.6, P1.8–P1.11 | Native tests for C1–C3 and H3–H6 pass |
| **M2: Trustworthy sensing** (week 2) | P1.4, P1.5, P1.7, P1.12, P0.3 recordings collected | Fault handling demonstrated; ≥ 10 recorded sessions with ground truth |
| **M3: Validated measurement** (weeks 3–4) | P2.1–P2.5, P2.7, validation round 1 | §6 targets met for depth, rate, CCF and detection |
| **M4: Robust product** (weeks 4–5) | Phase 3, P4.1–P4.8, P2.6 (FSR), P2.8 | Recoil validated with the FSR; reconnect grace works |
| **M5: Publishable** | Phase 5, validation round 2 | Documentation consistent; paper limitations written |

---

## 9. Changes applied in this pass (revision 2)

Baseline: commit `3c086a5` on `main`. The changes are committed on the local branch
`for-finalization` and have not been pushed.

### 9.1 Firmware (`CPReady_Program/`)

| File | Change | Closes |
|---|---|---|
| `include/BleManager.h` | Every `onDisconnect` clears the connection flag and restarts advertising; the overload with parameters only logs the reason. A full command queue is counted and logged instead of dropping silently. Each notification is stamped with a 16-bit sequence number. | C1, H10 |
| `include/CompressionTracker.h` | Lockout timed from stroke **onset** (300 ms), plus 80 ms from the previous stroke's end. Recoil exit fires only after the trough has armed it. The start threshold adapts: 40 % of a decaying signal envelope, clamped between 0.12 g and the profile value. Live CCF updates on every sample. Post-pause and first strokes report no rate and are left out of the average. PAUSE/RESUME shift timestamps by the paused time. `endSession()` stops processing after the summary. The recoil cue is not issued without a force sensor, and the recoil-estimated flag is set. A cue is cleared after it has been sent once. | C2, C3, C4, C5 (interim), M1, M2, H3, H4 |
| `include/SensorManager.h` | Fixed-rate sampling clock with a catch-up guard. Sensor faults latch after 5 failed reads or 50 identical samples; `reinitialize()` recovers. The EMA is reset at calibration. Direct 0x68 + 0x69 wiring is supported as well as the multiplexer. | H1, M15, H8 |
| `lib/Adafruit_MPU6050/` | Reads return success or failure on a zeroed buffer, with cached scales. The `reset()` loop is bounded. ACCEL_CONFIG2 (accelerometer low-pass) is written on MPU-6500-class chips. | H1, H2 |
| `include/BLEReadings.h` | Protocol v2, 16 bytes: bytes 0–11 are unchanged, 12–13 hold a uint16 stroke count, 14–15 a sequence number. Quality flag bit 3 is `RECOIL_ESTIMATED`. | M4, H10 |
| `include/CPReadyConfig.h` | One place for K bounds, detector constants, fault limits and the recoil-source switch. Defines `DEMO_CCF_PERCENT`, so demo mode compiles. | H6, M12 |
| `src/main.cpp`, `CPReady_Program.ino` | Command handling follows the state table: START only when calibrated; STOP during calibration cancels; config changes are rejected during a session. In FAULT, CALIBRATE re-initialises the sensors first. K is stored per profile only, with a one-time migration of the legacy key. A sensor fault during calibration or a session abandons it (no summary, because the data is suspect), enters `FAULT_ERROR` and reports `ERR_I2C_FAULT`. | H3, H6, H1 |
| `src/simulation.cpp` | Same command rules as `main.cpp`; per-profile K; cue cleared after sending. | M13 (partly) |

### 9.2 App (`FLUTTER/cpready/`)

| Area | Change | Closes |
|---|---|---|
| Decoder (`cpr_metrics.dart`, `config/ble.dart`) | Accepts 11-, 12- and 16-byte packets; reads the uint16 count and the sequence number; adds an `isRecoilEstimated` getter. | M4 |
| BLE (`ble_controller.dart`) | Counts lost packets from sequence gaps, handling wrap-around and firmware restarts. Subscribes before starting telemetry. `sendCommand` returns a failed Future instead of throwing. `awaitPacketWhere` cancels its subscription on both match and timeout. | H10, L1–L3 |
| Live screen | A cue plays only when the code changes. Only real-time packets satisfy the start watchdog. `ERR_I2C_FAULT` ends the session with a "sensor fault" result and nothing is saved. Recoil is labelled as estimated. Lost-packet count is saved with the session. | H4, H5, H1, C5 |
| Summary and grading | Recoil compliance is graded at ≥ 90 % and not graded at all when estimated. CCF is graded at ≥ 80 % good, 60–79 % fair. | M5 |
| History | Schema v4 adds `packets_lost`, with a v3→v4 migration. | H10 |
| Settings | Wording and comments corrected (each profile keeps its own K); the screen refreshes after a profile switch. | M8, L8 |
| Content | Guide no longer tells lay rescuers to check a pulse. Template purple replaced with the brand blue. | M17, L16 |
| Platforms | iOS Bluetooth usage string and portrait-only orientation (harmless; iOS is not a target). | M11 |

### 9.3 Verification

| Check | Result |
|---|---|
| `pio run -e esp32dev -e simulation` | Both succeed with no warnings from project code. Flash use is 89.9 % (`esp32dev`) and 87.7 % (`simulation`). |
| `test_native/tracker_regression.cpp` (new) | **144 of 144 checks pass**: detection ±1 stroke and median rate ±2 cpm for 4 stroke shapes × 4 cadences × 2 depths × 2 profiles, shallow strokes, no phantom strokes from noise, pause/CCF/rate handling, PAUSE/RESUME timing, flags and the 16-bit count. Output is in `audit_evidence/tracker_replay/results_regression_test.txt`. |
| Replay after the fixes | Detection is 100 % (102 % where the reference count is floored) for every shape at 80–150 cpm, and rates are exact (`results_after_fixes.txt`). |
| `flutter test` (Flutter 3.47.8, Dart 3.13.7) | **96 of 96 tests pass**. One new test first failed because it relied on wall-clock time; the cue gate now takes an injectable clock. The test was then shown to fail when the cue fix is removed, so it guards the fix. |
| `flutter analyze` | No errors or warnings. 93 info-level notes: 92 are the project's `///` file-header convention (`dangling_library_doc_comments`, present in untouched files too) and 1 is in the untouched `typography.dart`. |

### 9.4 Not verified, and needs the vest

1. **BLE reconnect:** 20 connect/disconnect cycles without a power cycle (C1).
2. **Sensor fault:** unplug a sensor mid-session; expect "sensor fault" within about 0.5 s; replug, calibrate, and confirm it recovers.
3. **Wiring detection:** boot with the multiplexer wiring and check the serial log reports the multiplexer path.
4. **Re-calibrate K:** after flashing, run Manikin Calibration. Any K saved before was fitted to the old detector.
5. **One cue per pause:** a 5 s pause after a cue gives one playback.
6. **Firmware and app together:** install both. App builds from before this pass reject 16-byte packets (L19).

### 9.5 Limits that remain after this pass

- **Depth (C6).** At the default K, a 5.5 cm push now reads 2.2–4.5 cm depending on stroke
  shape (`results_after_fixes.txt`, section A). Re-calibrating K centres one shape but cannot
  remove the spread. Depth must not be reported as validated until P2.2 is done and checked
  against recorded data.
- **Recoil (C5).** Leaning is still invisible; recoil is shown as estimated and is not graded.
- **Strong spring ringing.** A synthetic 4 mm, 8 Hz bounce after every stroke still
  double-counts at 80 cpm. Real manikin data will show whether this happens.
- **Bumps during pauses.** The adaptive threshold falls to 0.12 g during a pause, so a hand
  repositioning harder than that can count as a stroke.

### 9.6 How to review or revert

- Review: `git diff main..for-finalization`, or one file at a time.
- Revert a file: `git checkout main -- <path>`.
- Full backup taken before any change:
  `..\CPReady_backup_before_audit_fixes_2026-10-27.zip` (next to the `CPReady` folder).

---

## Appendix A: Replay results (production `CompressionTracker.h`, unmodified)

Full outputs are in `audit_evidence/tracker_replay/results_*.txt`. True depth is 5.5 cm unless
stated. Each run is 30 s with 5 mg of sensor noise and the production EMA.

**Table A: manikin profile, original tracker**

| Shape | cpm | detected / true | rate reported | depth reported |
|---|---|---|---|---|
| sinusoid | 80–120 | **0 %** | – | – |
| sinusoid | 130 / 140 / 150 | 49 / 50 / 51 % | **65 / 70 / 75** | 7.6 / 8.7 / 8.7 cm |
| 40/60 duty | 80–100 | **0 %** | – | – |
| 40/60 duty | 110 / 120 | 40 / 52 % | **55 / 60** | 7.4 / 8.4 cm |
| 40/60 duty | 140 / 150 | 50 / 51 % | **70 / 75** | **10.0 (clamped)** |
| 35/35/30 dwell | 100 | 49 % | **50** | 8.3 cm |
| 35/35/30 dwell | 110 / 120 / 130 | ≈ 100 % | 109 / 120 / 130 | 3.9 / 3.7 / 3.3 cm |
| 35/35/30 dwell | 140 / 150 | 50 / 51 % | **70 / 75** | **10.0 (clamped)** |

**Table A′: the same runs with P1.2 and P1.3 applied** (scratch copy, not committed)

| Shape | cpm | detected | rate | depth |
|---|---|---|---|---|
| sinusoid | 130 / 140 / 150 | 98–100 % | 130 / 140 / 150 | 2.2 cm |
| 40/60 duty | 120–150 | 100 % | exact | 2.6–2.9 cm |
| 35/35/30 dwell | 100–150 | 98–100 % | exact | 3.5–4.2 cm |
| sinusoid, 40/60 duty | ≤ 110 | still ≈ 0 % (C4 remains) | | |

**Table B: recoil versus actual leaning** (dwell, 120 cpm, manikin profile)

| Case | detected | depth | "full recoil" |
|---|---|---|---|
| 3.5 cm, full release | 0 / 58 | – | – |
| 4.0 cm, full release | 1 / 58 | – | – |
| 5.5 cm, full release | 59 / 58 | 3.74 | 100 % |
| **5.5 cm, 1.5 cm leaning** | 59 / 58 | 3.74 | **100 %** |
| **6.0 cm, 2.0 cm leaning** | 59 / 58 | 4.08 | **100 %** |

**Table C: depth linearity** (dwell, 120 cpm)

True 3.0 / 4.0 cm: not detected. True 5.0 / 5.5 / 6.0 / 7.0 cm reads 3.40 / 3.74 / 4.08 /
4.76 cm. The reading is proportional within one shape, but the proportion depends on the shape
(table A′).

**Table D: bench profile (0.25 g), original tracker, sinusoid at 100 cpm**

Depth reads **1.11 cm** with recoil **0 %**, caused by C3. With P1.2 and P1.3 applied: 1.98 cm
with recoil 100 %. The remaining error is C6.

**Table H: harmonic estimator prototype** (3 s window, N = 6, autocorrelation f₀, with lean)

| Shapes | Rates | True depths | Result |
|---|---|---|---|
| sinusoid, 40/60, dwell | 80, 100, 120, 150 cpm | 4.0 / 5.5 / 7.0 cm | estimated depth within **−0.09 … +0.22 cm** in all 36 cases; rate within 0.3 cpm |

The estimator is unaffected by a 1.5 cm lean. It measures depth correctly but cannot detect
the lean, which confirms that recoil needs the FSR.

---

## Appendix B: Code sketches

These are illustrative and match the existing style; adapt during implementation.

### B.1 BLE disconnect (P1.1), `BleManager.h`

```cpp
// Arduino-ESP32 2.0.x runs this before decrementing the connected count, so
// getConnectedCount() still includes the departing client here. CPReady only
// ever has one client, so every disconnect is the disconnect.
void onDisconnect(BLEServer* pServer) override {
    isClientConnected = false;
    hasDisconnectedFlag = true;
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Client disconnected. Advertising resumed.");
}

void onDisconnect(BLEServer* pServer, esp_ble_gatts_cb_param_t *param) override {
    Serial.printf("[BLE] Disconnect reason 0x%02X\n", param->disconnect.reason);
}
```

### B.2 Stroke state machine (P1.2, P1.3), `CompressionTracker.h`

```cpp
case StrokeState::WAITING_FOR_DOWNSLICK:
    if (netAccel > compressionStartThresholdG &&
        (strokeStartMillis == 0 ||
         currentMillis - strokeStartMillis > CPReadyConfig::MIN_ONSET_INTERVAL_MS) &&
        currentMillis - lastStrokePeakMillis > CPReadyConfig::MIN_END_TO_ONSET_MS) {
        state = StrokeState::COMPRESSING;
        strokeStartMillis = currentMillis;
        peakAccel = netAccel;
        troughAccel = netAccel;
    }
    break;

case StrokeState::COMPRESSING:
    if (netAccel > peakAccel) peakAccel = netAccel;
    if (netAccel < 0.0f) {
        state = StrokeState::RECOILING;
        troughAccel = netAccel;
        recoilArmed = false;
    }
    break;

case StrokeState::RECOILING:
    if (netAccel < troughAccel) troughAccel = netAccel;
    // Only a real upward swing arms the exit; otherwise a gentle zero crossing
    // would end the stroke on the very next sample.
    if (netAccel < CPReadyConfig::RECOIL_ARM_G) recoilArmed = true;
    if (recoilArmed && netAccel >= CPReadyConfig::STROKE_FINISH_THRESHOLD_G) {
        // ... existing stroke completion ...
    }
    break;
```

### B.3 Command and state transition table (P1.6)

| Command \ State | STANDBY | CALIBRATING | CAL_READY | ACTIVE | PAUSED | FAULT |
|---|---|---|---|---|---|---|
| CALIBRATE | start calibration | restart | restart | ERR_WRONG_STATE | ERR_WRONG_STATE | re-init sensors → calibrate, else ERR_I2C_FAULT |
| START | ERR_WRONG_STATE | ERR_WRONG_STATE | **start session** | ignore (ACK) | ERR_WRONG_STATE | ERR_I2C_FAULT |
| STOP | ignore (ACK) | abort → STANDBY, no summary | → STANDBY, no summary | finalise + summary | finalise + summary | ignore |
| PAUSE | ERR | ERR | ERR | → PAUSED (note the time) | ignore | ERR |
| RESUME | ERR | ERR | ERR | ignore | → ACTIVE (+ paused time) | ERR |
| SET_* / RESET_CONFIG / CALIBRATE_TARGET | OK | ERR | OK | **ERR** | **ERR** | OK |
| GET_CONFIG / GET_RESULTS / GET_STATUS | OK | OK | OK | OK | OK | OK |

### B.4 Cue played once (P1.8)

Firmware, `main.cpp`, after a real-time packet is sent:

```cpp
ble.sendPacket(packet);
tracker.clearAudioPrompt();   // reading.audio_prompt_code = PROMPT_NONE
```

App, `live_practice_screen.dart`:

```dart
/// Cue code of the previous real-time packet. Older firmware repeats a cue in
/// every packet until the next stroke, so only a change of code is a new cue.
int _previousCueCode = 0;

// in _onPacket, for real-time packets:
final int cue = metrics.audioPromptCode;
final bool newCue = cue != _previousCueCode;
_previousCueCode = cue;
if (newCue && !_muted && !_ending && !_finished && _cueGate.allows(cue)) {
  unawaited(_coach?.play(cue));
}
```

### B.5 Start watchdog (P1.9), `live_practice_screen.dart`

```dart
// Calibration packets mean START reached a device that was not ready and it is
// re-running its baseline; they must not count as the session going live.
if (metrics.packetType != AppBleConfig.packetRealtime &&
    metrics.packetType != AppBleConfig.packetFinalSummary) {
  return;
}
```

### B.6 Recoil grading (P1.11), `metric_feedback.dart`

```dart
MetricRating? recoilRating(int? percent) {
  if (percent == null) return null;
  return percent >= AppTargets.recoilGoodPercent
      ? MetricRating.good
      : MetricRating.poor;
}
```
