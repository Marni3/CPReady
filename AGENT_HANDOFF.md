# Agent Handoff: CPReady Audit, Fixes and Algorithm Refinement

**Written:** 28 October 2026, by the agent that did this work.
**Read first:** this file, then `ALGORITHM_REFINEMENT_REPORT.md`, then the parts of
`CPREADY_SYSTEM_AUDIT_AND_IMPROVEMENT_PLAN.md` you need. `LAB_MODE_ARCHITECTURE.md` is a
proposal awaiting the user's sign-off.

---

## 1. The project in one paragraph

CPReady is a low-cost CPR **training** vest worn over a manikin, built by a senior-high research
team. Dennis (the user) is the developer working for them.

- **Firmware:** `CPReady_Program/`, ESP32 Arduino via PlatformIO, Bluedroid BLE.
- **Hardware:** a classic ESP32 (`esp32dev`) reads two MPU-6050/6500-class accelerometers,
  chest and spine, behind a PCA9548A I2C multiplexer, and sends metrics over BLE.
- **App:** `FLUTTER/cpready/`, Android only, using flutter_blue_plus, sqflite and go_router.
  It shows live depth, rate, recoil and CCF and plays voice cues.
- **Research context:** results go into a research paper (`CPReady Research Proposal.pdf`:
  RQ 1.x accuracy of depth, rate, recoil and CCF; RQ 2.x response time, BLE reliability,
  logging completeness, algorithm accuracy).

**The user's stated main goal:** make the firmware and the app **reliable and properly
accurate**. The original request was a critical audit plus an improvement plan, aiming for
"as bug free as possible".

---

## 2. Decisions and preferences from the user (binding)

| Topic | Decision |
|---|---|
| Git | Work on branch **`for-finalization`** (they asked for "for finalization"; spaces are illegal in branch names). Commit as you go. Push only when asked (the branch was published on 28 Oct; see §3). Never touch `main` or force-push. |
| Hardware | **Ignore the KiCad schematic** (it is an unwired ESP32-S3 parts placement). The real hardware is a classic ESP32 with 2× MPU-6050 behind a PCA9548A. The firmware only has to work on an ESP32. |
| Force sensor | **No force sensor in the product** (hardware constraints; analog FSRs unreliable). Recoil stays "estimated". The **lab** build may optionally support an FSR402 or an RFP602. |
| RFP602 module | The user's photo shows the standard **analog** "thin-film pressure sensor voltage conversion module": VCC/GND/DO/AO pins, a potentiometer and an LM393 comparator. **It is not I2C.** Use AO → GPIO34 (ADC1), powered from **3.3 V** (at 5 V, AO can exceed the ESP32 ADC range). DO is a threshold on/off output set by the potentiometer. |
| iOS | **Not a target.** The harmless Info.plist edits stay. |
| Deleting | **Don't delete anything** (dead widgets, desktop and web scaffolds, the test-bench archive). |
| Protocol | The firmware and the app are always updated together. The 16-byte v2 packet breaks old app builds, and that is accepted. |
| `MyNotes.txt` | **Ignore it.** These are old notes, already addressed. |
| Flutter | The user asked to **pause running Flutter** for now. Don't run `flutter` unless they ask, or unless app code changes and verification is needed. If so, tell them first. |
| Working style | The user is often away. When blocked on something minor, proceed with the recommended approach. They want **questions answered before development continues**, and a **verification report before moving to the next stage**. |
| Lab mode | One **unified** app and one firmware. The user asked whether unifying is too complex; the recommendation was a hidden lab section, with firmware streaming off until the app enables it. Export as **CSV** (Excel/Sheets) via share; adding `share_plus` is OK. **No second person** during sessions: one person does CPR while the app records, and the app's guided script does the labelling. The manikin has its own Android app that shows realtime depth and a **session mean depth** and can be started and stopped per bout, so per-bout mean depth is the ground truth. |

---

## 3. Git state

Branch `for-finalization`, created from `main` at `3c086a5`. The remote is
`github.com/Marni3/CPReady`. The branch is **published as `origin/for-finalization`** and
tracks it. It was pushed on 28 October 2026 at the user's request, after they fixed a
first-attempt 403 permission error. A pull request can be opened at
`https://github.com/Marni3/CPReady/pull/new/for-finalization`; none has been opened. `main` is
untouched. Don't force-push, and push further work only when the user asks.

| Commit | Content |
|---|---|
| `15481f9` | fix(firmware): Phase 1 fixes (§4.1) |
| `a2c1f86` | fix(app): Phase 1 app fixes and protocol v2 (§4.2) |
| `3965701` | docs: audit and improvement plan, plus `audit_evidence/` |
| `97698e5` | docs: `LAB_MODE_ARCHITECTURE.md` proposal (not implemented) |
| `aa5c2a8` | feat(firmware): algorithm refinement (§4.3) |
| (last two) | docs: this handoff file and branch status in the report and audit |

Other state:

- **Untracked:** `ALGORITHM_RESEARCH.pdf` in the repo root. The user put it there; leave it
  alone and don't commit it.
- **Backup** of the project before any change:
  `C:\Users\Kloudtech Software\Desktop\Reyn\CPReady_backup_before_audit_fixes_2026-10-27.zip`.

---

## 4. What was done

### 4.1 Phase 1 firmware fixes (`15481f9`)

Audit IDs (C1, H3…) refer to `CPREADY_SYSTEM_AUDIT_AND_IMPROVEMENT_PLAN.md`.

- **C1 (BLE):** `BleManager.h`. Every `onDisconnect` clears the connection flag and restarts
  advertising. The library calls `onDisconnect` before decrementing its connected count, so
  the old count check never fired. Dropped commands are counted. Each notification is stamped
  with a uint16 sequence number.
- **C2/C3/C4 (stroke detector):** `CompressionTracker.h`.
  - The lockout is timed from stroke **onset** (300 ms) plus 80 ms after the previous end.
  - The recoil exit must be armed before the stroke can finish.
  - The start threshold adapts: 40 % of a decaying envelope, clamped between 0.12 g and the
    profile value.
- **M1/M2:**
  - live CCF is updated on every sample;
  - first and post-pause strokes carry no rate and are left out of averages;
  - PAUSE/RESUME shift timestamps by the paused time;
  - `endSession()` and `clearAudioPrompt()` were added, so each cue is announced once.
- **C5:** recoil is flagged `CADENCE_FLAG_RECOIL_ESTIMATED` (bit 3), and the
  "release fully" cue is disabled unless `RECOIL_MEASURED_BY_FORCE_SENSOR` or
  `ENABLE_ESTIMATED_RECOIL_PROMPT` is set.
- **H1/H2/M15 (sensors):** the vendored `lib/Adafruit_MPU6050` returns read status, caches
  scales, bounds `reset()`, and writes ACCEL_CONFIG2 (accelerometer low-pass) on
  MPU-6500-class chips. `SensorManager.h`:
  - fixed-rate sampling;
  - the fault latches after 5 failed reads or 50 identical samples, and `reinitialize()`
    recovers;
  - the EMA is reset at calibration;
  - **H8:** direct 0x68 + 0x69 wiring works as well as the multiplexer. The multiplexer path
    is the real one.
- **H3:** `src/main.cpp` follows a command state table:
  - START only from CALIBRATED_READY;
  - STOP during calibration cancels;
  - config commands are rejected during a session;
  - in FAULT, CALIBRATE re-initialises first;
  - a sensor fault abandons the session with `ERR_I2C_FAULT`;
  - `SET_TIME` accepts 0–3600 (0 = manual stop).
- **H6:** K is stored per profile only, with a one-time migration of the legacy `depth_k`.
  K bounds are 1–30, defined in config.
- **M4/H10:** protocol v2, 16 bytes. Bytes 0–11 are unchanged; 12–13 are a uint16 stroke
  count; 14–15 are the sequence number (`BLEReadings.h`).
- **M12:** demo mode compiles.
- `src/simulation.cpp` mirrors these rules.
- `CPReady_Program.ino` is a byte-identical copy of `src/main.cpp`, kept for the Arduino IDE.
  **Keep it in sync**: `Copy-Item src\main.cpp CPReady_Program.ino`.

### 4.2 Phase 1 app fixes (`a2c1f86`)

All under `FLUTTER/cpready/lib/src/`:

- **Decoder:** `core/metrics/cpr_metrics.dart` and `config/ble.dart` accept 11-, 12- and
  16-byte packets and add `isRecoilEstimated`.
- **BLE:** `core/ble/ble_controller.dart` counts lost packets from sequence gaps (wrap-safe,
  gap ≤ 1000), subscribes before telemetry starts, makes `sendCommand` async, and makes
  `awaitPacketWhere` cancellable.
- **History:** schema v4 adds a `packets_lost` column, with a migration
  (`config/history.dart`, `core/history/session_repository.dart`, `session_record.dart`).
- **Live screen:** `screens/live_practice/live_practice_screen.dart`:
  - a cue plays only when its code changes;
  - only real-time packets satisfy the start watchdog;
  - `ERR_I2C_FAULT` ends the session with `SessionEndReason.sensorFault`, and nothing is
    saved;
  - recoil is shown as estimated;
  - `packetsLost` is saved;
  - the `cueClock` constructor parameter (`@visibleForTesting`) lets tests drive the cue
    gate's clock.
- **Grading:** `core/feedback/metric_feedback.dart` and `config/targets.dart` grade recoil
  good at ≥ 90 % (none when estimated) and add a CCF rating.
- **Summary, strings, settings:** the summary screen shows a sensor-fault reason; strings and
  comments are corrected (each profile keeps its own K); the guide no longer has a lay pulse
  check; template purple is replaced with brand blue; device settings refresh after a profile
  change.
- **Tests:** in `test/`, including the new `metric_feedback_test.dart` and
  `support/recording_voice_coach.dart`.
- **Last run:** `flutter test` 96/96 pass. `flutter analyze` reports no errors or warnings;
  its 93 infos are all the project's `///` file-header style plus one in the untouched
  `typography.dart`.

### 4.3 Algorithm refinement (`aa5c2a8`)

Full detail and numbers are in `ALGORITHM_REFINEMENT_REPORT.md`.

- **Depth:** `include/DepthEstimator.h` (new) integrates each stroke instead of using
  K·a_pp·T², which depended on stroke shape: a 5.5 cm push read 1.85–4.60 cm.
  - **Normal strokes:** a closed-cycle double integral between consecutive stroke ends, with
    the mean acceleration and mean velocity removed.
  - **First and post-pause strokes:** integrated from rest. If the 0.2 s before the push was
    not quiet (any deviation > 0.05 g), it returns "unknown", and the tracker keeps the
    previous depth and leaves the stroke out of averages and depth cues.
  - A 256-sample ring buffer (1 KB) holds the raw signal.
- **Tracker API:** `CompressionTracker::processSample(float filteredNet, float rawNet,
  uint32_t ms)`. Its other changes:
  - the filtered sample detects strokes and the raw sample is used for depth;
  - detections with under 1 cm of motion are discarded (`MIN_STROKE_DEPTH_CM`);
  - the live rate is the median of the last 3 periods;
  - the session rate is 60000 × count / sum of periods.
- **K:** now a correction factor: depth × K / profile default (11.2 manikin, 9.5 bench). The
  NVS key `depth_model` (= `DEPTH_MODEL_VERSION` 2) wipes old K values once on the first boot.
- **Tilt:** `include/GravityAxis.h` (new) learns each sensor's gravity direction at
  calibration. `SensorManager` projects every sample onto it and returns
  `sample100Hz(filtered, raw, micros)`. The calibration acceptance checks are unchanged
  (z-based).
- **Bug fix:** `RECOIL_ARM_MIN_G` changed from 0.04 to **0.08**. With 0.04, the arm level sat
  above the finish level (−0.05), so weak strokes (peak below about 0.17 g) finished mid-way
  down.
- **Simulator:** `SyntheticVest.h` and `SimulationConfig.h` were rewritten to generate
  physical motion (push 35 %, release 35 %, rest 30 %) with its exact acceleration. The
  leaning phase was removed. `simulation.cpp` applies the same EMA and passes the raw sample.
- **Docs updated:**
  - `CPReady_Program/README.md`
  - `docs/CALIBRATION_AND_TUNING_GUIDE.md` §7
  - `docs/ALGORITHM_RESEARCH.md` (status note)
  - `docs/SOFTWARE_DEVELOPER_GUIDE.md` (`SET_K` entry)
  - `docs/NEW_FEATURES_AND_UI_FLOW_GUIDE.md`
  - the audit §9.7
- **Verification:**
  - `test_native/tracker_regression.cpp`: **233/233 pass**. The same test fails 80 on the
    Phase 1 tracker.
  - `test_native/simulation_scenario.cpp`: passes.
  - Mutation checks: disabling bump rejection, or restoring an arm level of 0.04, each fails
    its own test.
  - Both PlatformIO environments build: `esp32dev` flash 90.1 %, RAM 41 KB.
- **Evidence:** `audit_evidence/tracker_replay/results_*.txt`, listed in that folder's README.

### 4.4 Documents produced

| File | What it is |
|---|---|
| `CPREADY_SYSTEM_AUDIT_AND_IMPROVEMENT_PLAN.md` | The full audit: findings C1–C6, H1–H10, M1–M18, L1–L19 and D1–D9; plan Phases 0–5 (§5, with a status table at the top); validation protocol (§6); release checklist (§7); changes applied and verified (§9, §9.7). |
| `ALGORITHM_REFINEMENT_REPORT.md` | Before/after numbers, verification method, limits, and a **hardware checklist for the client** (§6). |
| `LAB_MODE_ARCHITECTURE.md` | Lab build proposal, **not updated yet** with the user's latest answers (§5 below). |
| `audit_evidence/tracker_replay/` | Offline replay harness (`replay.cpp`), Fourier depth prototype (`harmonic.cpp`), captured results. |
| `CPReady_Program/test_native/` | Native tests and their README. |

---

## 5. What's pending (in order)

1. **The user reviews `ALGORITHM_REFINEMENT_REPORT.md`.** Don't start lab work before they
   approve. Their client may run the report's §6 hardware checklist. Ask for:
   - the pairs of mean depths (CPReady versus the manikin app) at about 4, 5 and 6 cm;
   - the K value that Manikin Calibration produces;
   - the serial logs (tilt angle; the depth-model reset message on first boot).
2. **Update `LAB_MODE_ARCHITECTURE.md`** with the decisions in §2, then get sign-off:
   - **one app:** drop the separate "lab" flavour and use a hidden lab section, for example
     enabled from Device Settings;
   - **one firmware:** lab streaming compiled into production but off until the app enables
     it, using `LAB_STREAM:1`. Check flash headroom (90.1 % now). If it gets tight, consider
     the `huge_app.csv` partition (no OTA is used);
   - **force sensor:** the analog driver only (FSR402 or the RFP602 module's AO pin on GPIO34,
     3.3 V). Drop the I2C driver stub. Optionally read DO as a digital input;
   - **export:** CSV via `share_plus`;
   - **ground truth:** the manikin app's per-bout mean depth, entered after each bout;
   - **labelling:** the app's guided script labels everything; there is no observer.
3. **Implement the lab build**, once it is approved. Steps L1–L5 are in the lab document.
   Keep the production behaviour unchanged when lab mode is off, and add tests (byte fixtures
   shared between the C++ packer and the Dart decoder).
4. **Remaining plan items:**
   - P0.1: tag `3c086a5` as `audit-baseline`, if the user wants it;
   - P0.4: app CI;
   - P2.5: CCF pause definition;
   - the bench half of P2.8;
   - P3.2–P3.8 (status heartbeat, command ACK, session ID, disconnect grace, unique device
     names, flash headroom, task watchdog and battery);
   - P4.1–P4.4 (live display smoothing and paused state, summary, per-stroke table and CSV);
   - Phase 5 docs.
   Several of these overlap with lab mode (per-stroke data, raw logging), so plan them
   together.
5. **Clean up temporary artifacts at the very end.** Section 6 lists them.

### Known limits to keep in mind

- **Synthetic only.** Accuracy is proven only on synthetic motion; real vest data is the next
  evidence.
- **Small bias at some rates.** At 110 cpm (54.5 samples per stroke) cycle windows alternate
  between 54 and 55 samples, which gives about +0.1 cm. Moving the window boundaries to the top
  of the stroke (zero velocity) would remove it and reduce the error when depth changes
  between strokes, at the cost of reporting depth one stroke late. Decide with lab data.
- **Spring ringing.** A strong 4 mm, 8 Hz ring still double-counts at 80 cpm (synthetic).
- **Leaning.** It is undetectable without a force sensor. A cycle in which leaning starts
  or stops gives a small depth error on that one stroke.
- **Base sensor.** The base sensor must track the manikin's back, because depth is measured
  relative to it.

---

## 6. Environment and how to run things (Windows, PowerShell 5.1)

### Firmware build

```powershell
& "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -e esp32dev -e simulation
```

Run it from `CPReady_Program/`. It creates `CPReady_Program/.pio/`, which is gitignored; it
did not exist before this work.

### Native C++ tests

The compiler is WinLibs GCC 16.2 (via winget), at:

```
C:\Users\Kloudtech Software\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64
```

Its linker fails on paths that contain a space (`default-manifest.o`). The workaround is a
space-free junction plus `-B` flags:

```powershell
$j = "C:\Users\KLOUDT~1\AppData\Local\Temp\cpr_mingw"   # junction -> the mingw64 folder above
# create if missing:
# New-Item -ItemType Junction -Path $j -Target "<mingw64 path above>"
$env:PATH = "$j\bin;$env:PATH"
$inc = "C:\Users\Kloudtech Software\Desktop\Reyn\CPReady\CPReady_Program"
& "$j\bin\g++.exe" -std=c++17 -O2 -Wall -Wextra "-B$j/x86_64-w64-mingw32/lib/" "-B$j/lib/gcc/x86_64-w64-mingw32/16.2.0/" "-L$j/x86_64-w64-mingw32/lib" -I "$inc\test_native\shim" -I "$inc\include" "$inc\test_native\tracker_regression.cpp" -o "<scratch>\tracker_regression.exe"
& "<scratch>\tracker_regression.exe"   # exit code = number of failures
```

Build `simulation_scenario.cpp` the same way. `audit_evidence/tracker_replay/replay.cpp`
uses `-I shim -I ../../CPReady_Program/include` from its own folder. The shim
(`test_native/shim/Arduino.h`) provides `String`, a by-value `min`, and `PI`.
`<random>` is broken in this MinGW, so the tests use their own random-number generator.

### Flutter (paused at the user's request)

The SDK (Flutter 3.47.8, Dart 3.13.7) was downloaded into the **previous session's**
scratchpad:

```
C:\Users\Kloudtech Software\AppData\Local\Temp\claude\c--Users-Kloudtech-Software-Desktop-Reyn\5ca2a9b2-58a4-4738-909d-e2e00519c359\scratchpad\flutter_sdk\flutter
```

There is a junction `C:\Users\KLOUDT~1\AppData\Local\Temp\cpr_flutter` pointing at it. The
long scratchpad path broke `flutter analyze` (paths over 260 characters), so run Flutter
through the junction.

```powershell
$j = "C:\Users\KLOUDT~1\AppData\Local\Temp\cpr_flutter"
$env:PUB_CACHE = "<that scratchpad>\pub_cache"; $env:CI = "true"
cd FLUTTER\cpready
& "$j\bin\flutter.bat" pub get --suppress-analytics      # updates pubspec.lock (see below)
& "$j\bin\flutter.bat" analyze --no-pub --suppress-analytics lib test
& "$j\bin\flutter.bat" test --no-pub --suppress-analytics
git checkout -- FLUTTER/cpready/pubspec.lock             # restore afterwards
```

- `pub get` exits 1 on "Building with plugins requires symlink support" (Windows Developer
  Mode is off). Dependency resolution still succeeds. **Do not change system settings**; use
  `--no-pub` for analyze and test.
- The committed `pubspec.lock` came from a different SDK (master channel; `test_api` 0.7.14
  and `listen`), so `pub get` modifies it. Restore it with git afterwards.
- `.dart_tool/` and `build/` in `FLUTTER/cpready` were created by this work. They are
  gitignored.
- If the scratchpad is gone, re-download the SDK (about 1.9 GB) with `curl.exe` from
  `storage.googleapis.com/flutter_infra_release/releases/stable/windows/` and extract it with
  `tar.exe`.

### Other quirks

- `Stop-Process` on another process was blocked by the permission classifier. Use TaskStop for
  your own background tasks.
- `Invoke-WebRequest` stalls for big downloads; `curl.exe` works.
- PowerShell `git commit -F -` does not read a here-string. Write the message to a file and
  use `git commit -F <file>`.
- Line endings: `core.autocrlf=true`, and firmware files are CRLF in the working tree. New
  files written with an editor tool come out LF; convert them for consistency (git normalises
  either way).

---

## 7. Cleanup checklist (when the work is finished)

Remove only what this work created:

- [ ] `CPReady_Program/.pio/` (build output)
- [ ] `FLUTTER/cpready/.dart_tool/` and `FLUTTER/cpready/build/`
- [ ] The junctions `C:\Users\KLOUDT~1\AppData\Local\Temp\cpr_mingw` and `...\cpr_flutter`.
      Remove **the junction only**, with `[System.IO.Directory]::Delete($path)`. Never delete
      recursively through it.
- [ ] Optionally, the Flutter SDK and pub cache in the old scratchpad.
- [ ] **Keep** the backup zip and `ALGORITHM_RESEARCH.pdf` (user files).

---

## 8. Key source map

| Area | Files |
|---|---|
| Firmware config | `CPReady_Program/include/CPReadyConfig.h` (all constants) |
| Stroke detection, rate, CCF, coaching | `include/CompressionTracker.h` |
| Depth | `include/DepthEstimator.h` |
| Sensors, calibration, tilt | `include/SensorManager.h`, `include/GravityAxis.h`, `lib/Adafruit_MPU6050/` |
| BLE | `include/BleManager.h`; packet structs in `include/BLEReadings.h` |
| Command and state machine | `src/main.cpp` (sensor build), `src/simulation.cpp` (simulator) |
| Simulator signal | `include/SyntheticVest.h`, `include/SimulationConfig.h` |
| App BLE and decoding | `lib/src/core/ble/`, `lib/src/core/metrics/cpr_metrics.dart`, `lib/src/config/ble.dart` |
| App live session | `lib/src/screens/live_practice/live_practice_screen.dart` |
| App history | `lib/src/core/history/`, `lib/src/config/history.dart` |
| Test bench (separate, older algorithm; audit H7/M16) | `CPReady_Test_Bench/` |
