# CPReady Minimum Viable Product (MVP) Release Notes

**Date:** November 4, 2026
**Scope:** Firmware (`CPReady_Program`), Mobile Application (`FLUTTER/cpready`), and Raw Telemetry Schema (`v2`)

---

## 1. Root Causes Resolved from Field Testing (`ANALYSIS.md`)

### 1.1 Common-Mode Cancellation in 2-MPU Differential Mode (`RC-1`, `§9.1`)
- **Problem:** In all 6 Dual-MPU field sessions recorded on the Laerdal Little Anne QC manikin, the base accelerometer moved in near-unity lockstep with the chest accelerometer ($r = 0.978\text{–}0.995$, base/chest gain $0.95\text{–}0.99$) because the manikin torso and backboard flex together under compression force. Subtracting `-(aChestG - aBaseG)` cancelled **80–90%** of the real compression signal, causing 0–61% stroke detection and `1.3–1.8 cm` raw depths.
- **Fix:**
  - Added runtime sensor mode selection (`SET_MPU:1` for **1-MPU Chest Only**, `SET_MPU:2` for **2-MPU Differential**), persisted in NVS (`dual_mpu`) and exposed in the Flutter **Device Settings** screen.
  - Set `DEFAULT_USE_DUAL_MPU = false` so the firmware defaults to **1-MPU (Chest Only)** (`rawNet = -aChestG`) out of the box for reliable compression detection and depth measurement.
  - When two MPUs are physically connected, `SensorManager` continues reading `baseSensor` into `raw.csv` (`base_x/y/z_mg`) even in 1-MPU mode so field recordings still capture both sensors for research, while ignoring base-sensor faults or disconnects during 1-MPU operation (`RC-7`, `§9.6`).

### 1.2 Depth Calibration Scalar `K` Restoration & Summary Clamping (`RC-2`, `§9.3`, `§9.4`)
- **Problem:**
  1. The `K = 48.20` ($4.30\times$) default was calibrated during 2-MPU mode to compensate for common-mode signal cancellation. When used in 1-MPU mode (`-aChestG`), where unscaled `K = 11.20` ($1.0\times$) already produces `5.2–6.5 cm` depth, `K = 48.20` multiplied depths to `22–26 cm` and saturated **86–100%** of strokes at the `10.0 cm` display ceiling.
  2. `CompressionTracker.h` excluded strokes with `reading.depth_cm >= 10.0f` from `validDepthSum`. When 69 of 70 strokes saturated at `10.0 cm` (e.g., session `48011a51`), the final summary reported `4.00 cm` from the single non-clamped stroke.
- **Fix:**
  - Restored `DEPTH_CALIBRATION_K = 11.2f` ($1.0\times$, matching `NOMINAL_INTEGRATOR_K = 11.2f`) and bumped `DEPTH_MODEL_VERSION = 4` so devices with `48.20` saved in NVS automatically reset once to `11.20`.
  - Removed `< CPReadyConfig::DEPTH_MAX_LIMIT_CM` from `validDepthSum` accumulation so clamped strokes are included in the session mean depth.
  - Added `unclamped_depth_mm` (`uint8_t`, 0–255 mm) to byte 15 (`header.reserved`) of `TelemetryFrames::Header` and `raw.csv` so offline analysis always has the exact pre-clamp depth.

### 1.3 Post-Pause Unmeasured Depth & 3-Axis Gravity Plausibility (`RC-4`, `RC-5`)
- **Fix (`RC-4`):** In `CompressionTracker::processSample()`, if `depthKnown` is `false` on a post-pause stroke, `reading.depth_cm` is explicitly set to `0.0f` instead of carrying over the pre-pause stroke's depth.
- **Fix (`RC-5`):** In `SensorManager::isCalibrationStable()`, gravity plausibility (`0.65g–1.35g`) is checked against the 3-axis vector magnitude `chestAxis.magnitude()` rather than `chest.z` alone, preventing false calibration rejections on tilted pads, and base-sensor stability checks run only when `useDualMpu && baseSensorOnline`.

### 1.4 Telemetry `IOSink.flush()` Race Condition & Schema `v2` (`RC-6`, `§7.1`, `§7.4`, `§9.5`)
- **Problem:** `TelemetryRecorder._maybeFlush()` called `unawaited(_flushSinks())` (`await _raw?.flush()`) every 1 second while 100 Hz BLE notifications were arriving. In `dart:io`, calling `IOSink.writeln()` while `IOSink.flush()` is awaiting throws `StateError: StreamSink is bound to a stream`, which dropped 10-sample frames mid-flush (`7c5ea2c3`, `e5c4ad3a`) and caused `sample_count`, `frame_count`, and `missing_samples` in `session.json` to be off by 1.
- **Fix:**
  - Removed periodic mid-stream `_maybeFlush()` calls so `IOSink` is flushed only at `start()` and `stop()`.
  - Bumped `AppTelemetry.schemaVersion = 2`:
    - Added `recoil_status` to `packets.csv`.
    - Added `unclamped_depth_mm` to `raw.csv`.
    - Added `device_config`, `stroke`, `device_error`, `final_summary`, and `recording_stopped`/`interrupted` events to `events.csv` and `session.json`.
  - Updated `supabase/DATA_FORMAT.md` to match the exact wire and CSV contracts.

