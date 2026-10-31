# CPReady Double-Integration, Calibration & I2C Bus Configuration Guide

## 1. Executive Summary

This reference guide documents the mathematical foundations, system architecture, protocol enhancements, and validation results for the **CPReady** CPR training system firmware and mobile application.

The primary engineering objectives addressed in this release:
1. **Accurate & Consistent Session Mean Depth (`avg_depth_cm`)**: The mobile app and firmware prioritize providing a reliable mean depth post-session across varied trainee cadences, pauses, and hand positioning.
2. **True $\Delta t$-Aware Double Integration**: Replaced fixed 10 ms assumptions with exact microsecond-timed Riemann integration ($\Delta t_i = (t_i - t_{i-1})$) to maintain precision during FreeRTOS scheduling jitter and BLE notification events.
3. **Drift-Free Double Integration**: Mathematical elimination of accelerometer DC bias, thermal drift, and gravity tilt leakage using cycle-bounded mean acceleration ($\bar{a}=0$) and mean velocity ($\bar{v}=0$) zeroing.
4. **Parity Between 15s Calibration and Live Practice Sessions**: Eliminated zero-depth drops following pauses caused by restrictive resting thresholds (`REST_LIMIT_G`), allowing natural trainee hand tremor without rejecting stillness.
5. **Guaranteed Calibration Reset on 15s Sessions**: Arming or starting a 15-second calibration trial automatically resets the depth calibration scalar $K$ to the default baseline ($11.20$), preventing corrupted or uncalibrated values from compounding.
6. **Dynamic I2C Bus Speed Configuration**: Added support for 100 kHz (standard mode) and 400 kHz (fast mode), configurable via BLE, persisted in NVS, followed by an automatic ESP32 hardware reset with user confirmation and warning.

---

## 2. Double Integration Kinematics & Drift Avoidance

### 2.1 The Classic Double Integration Problem
Integrating raw accelerometer data $a(t)$ over continuous time yields velocity $v(t) = \int a(t) dt$ and position $x(t) = \iint a(t) dt^2$. Any residual accelerometer bias $b$ or gravity leakage creates linear velocity drift $v_{err}(t) = b \cdot t$ and quadratic displacement drift $x_{err}(t) = \frac{1}{2} b \cdot t^2$. Over several seconds, this causes the estimated position to explode to infinity.

### 2.2 How CPReady Avoids Drift
CPReady prevents drift through three strict boundary principles:

#### 1. Cycle-Bounded Integration Window
Integration is **never continuous**. It only executes over a single compression cycle $[t_{onset}, t_{recoil\_end}]$, typically lasting $400\text{ ms to }650\text{ ms}$. At the end of each cycle, all internal velocity and position states reset to zero.

#### 2. Mean Acceleration Zeroing ($\bar{a} = 0$)
In cyclical chest compressions, the chest starts at the manikin surface and returns to the surface. By the Mean Value Theorem and Newton's laws:
$$\int_{t_1}^{t_2} a_{true}(t) \, dt = v(t_2) - v(t_1) = 0$$
Any non-zero average in the measured acceleration $\bar{a}_{meas} = \frac{1}{T} \sum a_i \Delta t_i$ consists entirely of sensor DC bias, thermal drift, and gravity tilt error. By subtracting $\bar{a}_{meas}$ from each sample:
$$a_{corr}(t_i) = a_{meas}(t_i) - \bar{a}_{meas}$$
all DC offset is completely removed before velocity integration.

#### 3. Mean Velocity Zeroing ($\bar{v} = 0$)
Similarly, because the chest begins and ends at the surface ($x(t_1) = 0, x(t_2) = 0$), the average velocity over the cycle must be zero:
$$\bar{v} = \frac{1}{T} \sum_{i=1}^{m} v_i \Delta t_i = 0$$
Subtracting $\bar{v}$ supplies the unknown initial boundary velocity $v_0$ without requiring an external velocity sensor:
$$v_{corr}(t_i) = v(t_i) - \bar{v}$$
Displacement is then integrated:
$$x(t_i) = \sum_{j=1}^{i} v_{corr}(t_j) \Delta t_j$$
The peak downward excursion $\max(x)$ represents the compression depth.

### 2.3 Exact Microsecond Riemann Integration ($\Delta t$)
Rather than assuming a fixed $10\text{ ms}$ interval, `SensorManager` measures exact elapsed time using `micros()`:
$$\Delta t_i = \frac{t_{\mu s, i} - t_{\mu s, i-1}}{1\,000\,000.0}$$
Each sample in `DepthEstimator` stores its own $(a_{net}, \Delta t)$. The weighted sums:
$$\bar{a} = \frac{\sum a_i \Delta t_i}{\sum \Delta t_i}, \quad \bar{v} = \frac{\sum v_i \Delta t_i}{\sum \Delta t_i}, \quad x_k = \sum_{i=1}^{k} (v_i - \bar{v}) \Delta t_i$$
remain mathematically exact even if BLE transmissions or FreeRTOS scheduling cause timing jitter (e.g., 70 Hz to 130 Hz).

---

## 3. Discrepancy Resolution: 15s Trial vs. Live Practice Sessions

### 3.1 Observed Root Causes
1. **Resting Threshold Too Strict (`REST_LIMIT_G`)**:
   - In 15s sprints, compressions were continuous. Strokes were closed-cycle, using $\bar{a}=0, \bar{v}=0$ zeroing.
   - In live sessions, trainees paused. Post-pause strokes relied on `fromRestDepthCm()`, which required $|a| \le \text{REST_LIMIT_G}$.
   - The threshold was set to $0.05\text{g}$ ($50\text{ mg}$). Normal human hand tremor on the chest produces $40\text{ to }100\text{ mg}$ of vibration. As a result, the firmware declared the chest was "in motion" during rest, returning **Depth = 0.0 cm**.
2. **Quality Flag Exclusion**:
   - In `CompressionTracker.h`, strokes with `CADENCE_FLAG_FIRST_STROKE` (first stroke or post-pause stroke) were excluded from `validDepthSum` and `validStrokeCount`.
   - Trainees doing 30:2 CPR with frequent pauses had their post-pause strokes omitted from the mean depth calculation.
3. **Compounding Calibration Corruptions**:
   - If a 15s calibration was run while $K$ was already skewed (e.g. 25.0), the ratio scaled from the corrupted value, resulting in extreme $K$ values.

### 3.2 Implemented Fixes
1. **Relaxed `REST_LIMIT_G` to $0.15\text{g}$**: Accommodates natural human resting hand tremor without falsely rejecting rest.
2. **Inclusive Mean Depth Accumulation**:
   ```cpp
   if (r.depth_cm >= CPReadyConfig::MIN_STROKE_DEPTH_CM && depthKnown) {
       validDepthSum += r.depth_cm;
       validStrokeCount++;
   }
   ```
   Post-pause strokes with valid computed depth are now properly included in the session average.
3. **Automatic Calibration Reset**:
   - Sending `SET_TIME:15` or `RESET_K` resets $K$ to default ($11.20$).
   - Calibration factor updates enforce sanity bounds: ratios $<0.40$ or $>2.50$ are rejected with `ERR_NO_TRIAL_DATA`.

---

## 4. Dynamic I2C Bus Speed Switching

### 4.1 Motivation
MPU-6050 sensors connected via jumper wires can suffer from signal degradation and clock stretching at 400 kHz due to parasitic capacitance. 100 kHz (standard mode) provides high noise immunity and robust signal edges.

### 4.2 Protocol & Firmware Implementation
- **Commands**:
  - `SET_I2C:100` $\rightarrow$ sets clock speed to 100,000 Hz.
  - `SET_I2C:400` $\rightarrow$ sets clock speed to 400,000 Hz.
- **Firmware Response**:
  1. Validates speed (100 or 400 kHz).
  2. Saves setting to NVS namespace `"cpready"`, key `"i2c_speed"`.
  3. Sends BLE Type 3 Acknowledgement Packet.
  4. Delays 300 ms to ensure BLE packet is flushed.
  5. Executes `ESP.restart()`.
- **Bootloader Initialization**:
  On startup in `setup()`:
  ```cpp
  uint32_t savedSpeed = prefs.getUInt("i2c_speed", CPReadyConfig::I2C_CLOCK_SPEED_HZ);
  sensors.begin(savedSpeed);
  ```

### 4.3 Flutter App UI & Warning Dialog
In `lib/src/screens/device_settings/device_settings_screen.dart`:
- Added `_I2CSpeedPanel` with buttons for 100 kHz (Standard - Recommended) and 400 kHz (Fast Mode).
- Tapping either speed displays a confirmation dialog:
  > **Change I2C Speed & Reset?**  
  > *"Changing this option will reset the ESP32 and need reconnection. Do you want to proceed?"*
- Upon confirmation, Flutter sends `SET_I2C:100` or `SET_I2C:400` and alerts the user to reconnect.

---

## 5. Verification & Test Suite Results

### 5.1 PlatformIO Firmware Compilation
- **`esp32dev` (Sensor Target)**: `SUCCESS` (Flash: 36.7%, RAM: 12.5%).
- **`simulation` (Synthetic Vest Target)**: `SUCCESS` (Compiles `simulation.cpp` cleanly).

### 5.2 Python Kinematic Simulation Suite (`simulation_test_suite.py`)
Eighteen automated regression test cases were executed across diverse physiological and noise conditions:

| Test Group | Condition | Target | Measured / Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **1. Sampling Rate ($\Delta t$)** | 70 Hz with 5% timing jitter | 5.20 cm | 5.23 cm ($\Delta = 0.03$ cm) | **PASS** |
| | 85 Hz with 5% timing jitter | 5.20 cm | 5.21 cm ($\Delta = 0.01$ cm) | **PASS** |
| | 100 Hz with 5% timing jitter | 5.20 cm | 5.20 cm ($\Delta = 0.00$ cm) | **PASS** |
| | 115 Hz with 5% timing jitter | 5.20 cm | 5.20 cm ($\Delta = 0.00$ cm) | **PASS** |
| | 130 Hz with 5% timing jitter | 5.20 cm | 5.20 cm ($\Delta = 0.00$ cm) | **PASS** |
| **2. DC Bias Drift Cancellation** | $+0.00\text{g}$ DC tilt offset | 5.00 cm | 5.01 cm ($\Delta = 0.01$ cm) | **PASS** |
| | $+0.02\text{g}$ DC tilt offset | 5.00 cm | 5.01 cm ($\Delta = 0.01$ cm) | **PASS** |
| | $+0.05\text{g}$ DC tilt offset | 5.00 cm | 5.01 cm ($\Delta = 0.01$ cm) | **PASS** |
| | $+0.10\text{g}$ DC tilt offset | 5.00 cm | 5.01 cm ($\Delta = 0.01$ cm) | **PASS** |
| **3. Post-Pause Tremor Recovery** | 20 mg hand tremor | 5.50 cm | 5.34 cm ($\Delta = 0.16$ cm) | **PASS** |
| | 50 mg hand tremor | 5.50 cm | 5.32 cm ($\Delta = 0.18$ cm) | **PASS** |
| | 80 mg hand tremor | 5.50 cm | 5.36 cm ($\Delta = 0.14$ cm) | **PASS** |
| | 110 mg hand tremor | 5.50 cm | 5.38 cm ($\Delta = 0.12$ cm) | **PASS** |
| **4. Multi-Burst Session** | 60 strokes with 5s pause | 60 strokes | All 60 valid depths | **PASS** |
| | Session Mean Depth (`avg_depth_cm`)| 5.40 cm | 5.39 cm ($\Delta = 0.01$ cm) | **PASS** |
| **5. Calibration & Safety** | `RESET_K` on 15s session | $K=11.20$ | Restores default 11.20 | **PASS** |
| | Out-of-bounds ratio rejection | $<0.40$ | Cleanly rejected (`ERR_NO_TRIAL_DATA`) | **PASS** |
| | Out-of-bounds ratio rejection | $>2.50$ | Cleanly rejected (`ERR_NO_TRIAL_DATA`) | **PASS** |

**Total Suite Result**: **18 PASSED, 0 FAILED**.
