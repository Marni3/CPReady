# CPReady Firmware Architectural Audit & Defect Analysis

**Audit Date**: October 2026  
**Auditor**: Antigravity Technical Consultation  
**Target Codebase**: `CPReady_Program` (ESP32 Dev Module, Dual MPU6050, BLE Telemetry)  
**Status**: Pending User Review (Pre-Implementation)

---

## Executive Summary

A comprehensive architectural and line-by-line audit of the CPReady firmware was performed across all subsystem modules (`include/`, `src/`, and `.ino`). While the modular design and single-threaded execution model provide a strong foundation, the audit surfaced **12 specific defects and vulnerabilities**, categorized by severity:

| Severity | Count | Summary of Key Areas |
| :--- | :---: | :--- |
| **Critical** | 4 | Stroke state machine latch-up, first-stroke calculation explosion, CCF pause freeze/drift, calibration underflow |
| **Major** | 4 | Incomplete `SESSION_PAUSED` state handling, lack of calibration motion rejection, audio coaching state contamination across pauses, BLE command race conditions |
| **Minor / Doc** | 4 | Documentation byte-size drift (8B vs 11B), stroke count clamp at 255, active vs. passive buzzer compatibility, entry point parity |

---

## Detailed Audit Findings

### 1. [CRITICAL] Stroke State Machine Dead-End / Latch-Up
- **Location**: [include/CompressionTracker.h:94-175](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/CompressionTracker.h#L94-L175)
- **Vulnerability**:
  In `StrokeState::COMPRESSING`, transition to `RECOILING` requires `netAccel < 0.0f`. If a trainee pushes down and then stops, hesitates mid-stroke, or rests hand weight without releasing dynamically, `netAccel` may settle near `0.0f` or remain positive ($> 0$).
  Similarly, in `StrokeState::RECOILING`, transition to stroke completion requires `netAccel >= CPReadyConfig::STROKE_FINISH_THRESHOLD_G` ($-0.05g$). If the rescuer leans continuously or hand rests heavily on the chest, net acceleration can remain depressed below $-0.05g$ (e.g. $-0.10g$).
- **Impact**: The state machine becomes permanently trapped in `COMPRESSING` or `RECOILING`. No future compressions are ever registered because `StrokeState::WAITING_FOR_DOWNSLICK` is never re-entered.
- **Root Cause**: Absence of an elapsed stroke watchdog / refractory timeout within the active compression states.
- **Recommended Fix**: Add a stroke timeout watchdog (e.g., if `currentMillis - strokeStartMillis > 1500 ms` while in `COMPRESSING` or `RECOILING`, automatically reset state to `WAITING_FOR_DOWNSLICK` and abort the incomplete stroke).

---

### 2. [CRITICAL] First-Stroke Cadence & Depth Math Corruption
- **Location**: [include/CompressionTracker.h:51, 122-143](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/CompressionTracker.h#L51)
- **Vulnerability**:
  In `reset()`, `lastStrokePeakMillis = 0`. When `startSession(currentMillis)` runs, `lastStrokePeakMillis` is left as `0`.
  Upon the completion of **Stroke #1**:
  ```cpp
  uint32_t cyclePeriodMs = currentMillis - lastStrokePeakMillis; // currentMillis - 0 = currentMillis!
  ```
  If the ESP32 has been booted for 45 seconds ($45,000\text{ ms}$), `cyclePeriodMs` is evaluated as $45,000\text{ ms}$ ($45.0\text{ s}$).
  1. `if (cyclePeriodMs > 0 && cyclePeriodMs < 2000)` fails, so `reading.rate_cpm` is left at `0.0` and `totalActiveCompressionMillis` is not updated.
  2. Depth is calculated as:
     $$D = K \cdot \Delta a \cdot T^2 = 11.2 \cdot (\Delta a) \cdot (45.0)^2 = 22,680 \cdot \Delta a \text{ cm}$$
     This astronomical depth instantly hits the clamp limit (`DEPTH_MAX_LIMIT_CM = 10.0 cm`).
  3. `cumulativeDepthSum += 10.0f` permanently skews the session average depth, while `cumulativeRateSum += 0.0f` skews the session average rate.
- **Recommended Fix**:
  In `startSession(currentMillis)`, initialize `lastStrokePeakMillis = currentMillis` (or check `if (totalStrokeCount == 0)` and derive the first period from downstroke-to-upstroke duration or sensible default).

---

### 3. [CRITICAL] Chest Compression Fraction (CCF) Freeze & Stale Summary
- **Location**: [include/CompressionTracker.h:149-153, 317](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/CompressionTracker.h#L149-L153)
- **Vulnerability**:
  CCF accumulation and percentage updates only occur inside `processSample()` upon stroke completion.
  1. If the trainee stops compressions to deliver rescue breaths or rests for 15 seconds, no strokes complete. During those 15 seconds, live BLE packets (sent at 5 Hz) continue broadcasting the old CCF percentage (e.g. $85\%$), misleading the instructor/app that active CCF is not decaying.
  2. In `finalizeSession(endMillis)`:
     ```cpp
     s.final_ccf_percent = reading.ccf_percentage;
     ```
     `finalizeSession` does not recalculate CCF using the actual total session duration (`endMillis - sessionStartMillis`). If a trainee compresses for 30 seconds ($100\%$ CCF) and rests for 90 seconds before pressing STOP, `finalizeSession` reports $100\%$ CCF instead of the actual $25\%$ ($30\text{s} / 120\text{s}$).
  3. `PAUSE_DETECTION_TIMEOUT_MS = 1500` is defined in `CPReadyConfig.h` and documented in research, but is never referenced anywhere in code.
- **Recommended Fix**:
  - Recompute CCF in `finalizeSession` using `totalActiveCompressionMillis / (endMillis - sessionStartMillis)`.
  - Add a lightweight tracker method `updateCCF(currentMillis)` callable from the periodic BLE broadcast loop so decaying CCF during pauses is accurately reflected in real-time telemetry.

---

### 4. [CRITICAL] Integer Underflow in Demo Mode Session Finalization
- **Location**: [src/main.cpp:36-37](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/src/main.cpp#L36-L37)
- **Vulnerability**:
  In `endAndFinalizeSession()` under `ENABLE_DEMO_MODE`:
  ```cpp
  summary.total_compressions = (uint16_t)((now - calibrationStartMillis - CPReadyConfig::CALIBRATION_DURATION_MS) / 550);
  summary.total_duration_sec = (uint16_t)((now - calibrationStartMillis - CPReadyConfig::CALIBRATION_DURATION_MS) / 1000);
  ```
  If an instructor clicks "STOP" during the 2-second calibration window or within 2 seconds of start, `now - calibrationStartMillis < CALIBRATION_DURATION_MS` ($2000\text{ ms}$).
  Because the operands are unsigned `uint32_t`, subtracting $2000$ causes an **integer underflow** to $\approx 4,294,965,000$.
  - `total_compressions` evaluates to $> 65,000$.
  - `total_duration_sec` evaluates to $> 65,000$.
- **Recommended Fix**: Add a guard checking `if (now > calibrationStartMillis + CALIBRATION_DURATION_MS)` before subtracting, defaulting to $0$ if stopped early.

---

### 5. [MAJOR] Broken `SESSION_PAUSED` State Machine Flow
- **Location**: [src/main.cpp:85-92, 129-241](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/src/main.cpp#L85-L92)
- **Vulnerability**:
  When mobile sends `"PAUSE"`, `state` changes to `DeviceState::SESSION_PAUSED`.
  1. In `loop()`, there is no branch for `SESSION_PAUSED`. Sensor sampling stops, but elapsed time tracking does not pause.
  2. If paused for 2 minutes and resumed via `"RESUME"`, `elapsed_seconds` jumps forward by 120 seconds.
  3. If `practiceDurationSec` is set (e.g. 120s), the session will instantly terminate upon `"RESUME"` because the pause time was treated as active training time.
  4. While paused, the app receives no status packets indicating that the vest is paused.
- **Recommended Fix**:
  Track `pauseStartMillis`. When `"RESUME"` is received, accumulate `totalPausedMillis += (now - pauseStartMillis)` and subtract paused duration from elapsed session time and CCF calculations.

---

### 6. [MAJOR] Calibration Stage Motion Vulnerability
- **Location**: [include/SensorManager.h:59-78](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/SensorManager.h#L59-L78), [src/main.cpp:153-187](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/src/main.cpp#L153-L187)
- **Vulnerability**:
  During the 2.0-second neutral baseline window (`CALIBRATING`), trainee hand acceleration is sampled and averaged into `chestGravityOffset` and `baseGravityOffset`.
  If the trainee is moving, adjusting the vest straps, or pressing down, `finalizeCalibration()` averages dynamic accelerations into the static 1g baseline.
  - The protocol specifies packet type `PKT_TYPE_ERROR = 5` (*"Calibration failed. Keep hands stationary"*), but the firmware never tests for excessive motion or signal variance during calibration and never emits packet type 5.
- **Recommended Fix**:
  Track max-min deviation during calibration. If $\Delta a > 0.25g$ during calibration, reject baseline, emit `PKT_TYPE_ERROR (5)`, and return to `STANDBY` or re-prompt.

---

### 7. [MAJOR] Audio Coaching Hysteresis Contamination Across Pauses
- **Location**: [include/CompressionTracker.h:189-234](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/CompressionTracker.h#L189-L234)
- **Vulnerability**:
  Streak counters (`shallowStreak`, `deepStreak`, `leaningStreak`, `slowRateStreak`, `fastRateStreak`) and start timestamps are only evaluated when compressions occur.
  If a trainee performed 5 shallow compressions, paused for 10 seconds to listen to an instructor, and then resumed with a single compression, `shallowStreak` is still 5 and `shallowStartTime` is 10 seconds in the past.
  The condition `isSustained()` immediately evaluates to `true` on the very first stroke after the pause, triggering a false `"Push harder"` prompt even if the student corrected their technique.
- **Recommended Fix**:
  If time since last stroke exceeds `PAUSE_DETECTION_TIMEOUT_MS` (s), reset all error streak counters and start times.

---

### 8. [MAJOR] BLE Command Dropping on Concurrent Writes
- **Location**: [include/BleManager.h:38-47, 101-105](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/BleManager.h#L38-L47)
- **Vulnerability**:
  In `BleManager::onWrite()`, if `hasCommandFlag == true`, any incoming command is silently dropped:
  ```cpp
  if (rxVal.length() > 0 && !hasCommandFlag) { ... }
  ```
  Mobile apps often issue setup commands in bursts (e.g. `"SET_TIME:60"` followed immediately by `"START"`). If the main loop is performing an I2C transaction when `"START"` arrives, `"START"` is permanently discarded.
- **Recommended Fix**: Implement a 4-slot ring buffer or circular queue for incoming BLE commands.

---

### 9. [MINOR] Documentation & Specification Drift (8 Bytes vs 11 Bytes)
- **Location**: [README.md:50](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/README.md#L50), [docs/ARCHITECTURE.md:45, 151-162](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/docs/ARCHITECTURE.md#L45)
- **Detail**: Commit `44786a1` updated the telemetry packet to 11 bytes (`CPRMetricsPacket`) with `packet_type` and `audio_prompt_code`. However, `README.md` and `docs/ARCHITECTURE.md` still state that an 8-byte packet is pushed.
- **Recommended Fix**: Update `README.md` and `ARCHITECTURE.md` to reflect the 11-byte packet layout.

---

### 10. [MINOR] Stroke Count uint8_t Saturation at 255
- **Location**: [include/BLEReadings.h:57, 85, 112](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/BLEReadings.h#L57)
- **Detail**: `total_compressions` in `CPRMetricsPacket` is a single byte (`uint8_t`), clamped at 255. Any session longer than 2.5 minutes ($\approx 300$ strokes) remains frozen at 255 in BLE telemetry.
- **Recommended Fix**: Document this protocol limit for mobile developers, or reserve a 2-byte field in future protocol revisions.

---

### 11. [MINOR] Active vs. Passive Buzzer Compatibility
- **Location**: [include/FeedbackController.h:40-44](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/include/FeedbackController.h#L40-L44)
- **Detail**: `FeedbackController` toggles GPIO 25 between digital `HIGH` and `LOW`. This works only with an active buzzer (integrated oscillator). If the student hardware prototype uses a passive piezo transducer, digital HIGH produces an inaudible DC click.
- **Recommended Fix**: Add a `#define USE_PWM_BUZZER` option in `CPReadyConfig.h` utilizing ESP32 LEDC PWM (`ledcWriteTone`) to support both active and passive piezo buzzers.

---

### 12. [MINOR] Arduino IDE Entry Point Parity (`CPReady_Program.ino`)
- **Location**: [CPReady_Program.ino](file:///c:/Users/reyna/CPready/CPReady/CPReady_Program/CPReady_Program.ino)
- **Detail**: `CPReady_Program.ino` mirrors `src/main.cpp`. Any logic fixes applied to `src/main.cpp` must be mirrored in `CPReady_Program.ino` so Arduino IDE users maintain exact feature parity.

---

## Prioritized Remediation Roadmap

1. **Phase 1 (Core Safety & Accuracy - Critical)**:
   - Fix 1: Stroke timeout watchdog in `CompressionTracker.h` to prevent state machine freeze.
   - Fix 2: Initialize `lastStrokePeakMillis` in `startSession` to eliminate first-stroke math explosion.
   - Fix 3: Real-time and final CCF calculation recalculation during pauses.
   - Fix 4: Guard against integer underflow on early STOP in demo mode.

2. **Phase 2 (Robustness & Protocol Integrity - Major)**:
   - Fix 5: Complete `SESSION_PAUSED` stopwatch compensation in `main.cpp`.
   - Fix 6: Calibration motion stability check and `PKT_TYPE_ERROR (5)` emission.
   - Fix 7: Reset audio coaching streak history when pauses exceed 1.5 seconds.
   - Fix 8: Ring buffer for BLE command mailbox to prevent dropped bursts.

3. **Phase 3 (Documentation & Parity - Minor)**:
   - Fix 9: Sync `ARCHITECTURE.md` and `README.md` to 11-byte packet specification.
   - Fix 10: Sync `CPReady_Program.ino` with `src/main.cpp`.
   - Fix 11: Add passive buzzer LEDC tone option.
