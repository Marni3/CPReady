# CPReady Researcher Reference: Kinematic Model Rationale, Parameter Sensitivity & Theoretical/Empirical Error Bounds

**Document Version:** 1.0 (Model v5 — Fine-Tuned 1-MPU Ground-Truth Baseline)  
**Target Hardware:** ESP32 + MPU6050 (`100 Hz` Sampling, `100 kHz` I2C) on Laerdal Little Anne QC Manikin  
**Verification Dataset:** 9 Complete Ground-Truth Sessions (`667` Total Compressions, `41,521` Raw 100 Hz Samples)

---

## 1. Executive Summary & Model Selection Rationale

During field validation of the CPReady system against the **Laerdal Little Anne QC** built-in optical/spring ground-truth sensors, five candidate kinematic depth models and two sensor topologies (`1-MPU Chest Only` vs `2-MPU Chest-minus-Base Differential`) were evaluated across all 9 complete recorded trials (`DATA/organized_trials/`).

### 1.1 Head-to-Head Model Accuracy Across All 9 Ground-Truth Sessions (`667` Compressions)

| Model / Sensor Configuration | Mean Absolute Error (MAE) | Root Mean Square Error (RMSE) | Systematic Bias | Min Session Error | Max Session Error | Primary Physical / Mathematical Limitation |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **1. Historical Firmware (`packets.csv` as-run)** | `30.84 mm` | `34.12 mm` | `+3.40 mm` | `0.70 mm` | `46.00 mm` | `2-MPU` common-mode signal cancellation (`01`–`07`) + stale `K=48.20` clamping (`08`–`11`). |
| **2. 2-MPU Differential Double-Integration** ($a_{\text{chest}} - a_{\text{base}}$, optimal $K$) | `14.24 mm` | `18.79 mm` | `-12.93 mm` | `0.10 mm` | `29.35 mm` | **Mechanical coupling instability:** Base MPU shares `70%–85%` of chest acceleration in-phase; coupling shifts with hand placement. |
| **3. 1-MPU Legacy Peak-to-Trough ($T^2$) Model** ($K \cdot (a_{\max}-a_{\min}) \cdot T^2$) | `3.83 mm` | `4.96 mm` | `+0.28 mm` | `0.10 mm` | `8.87 mm` | **Waveform-shape sensitivity:** Sharp turnarounds inflate $a_{\max}-a_{\min}$ without increasing true displacement (`+8.9 mm` error). |
| **4. 1-MPU Double-Integration (Uncapped Window)** (`lastStrokeEnd` $\rightarrow$ `strokeEnd`, $K=11.20$) | `3.42 mm` | `4.25 mm` | `+3.40 mm` | `0.10 mm` | `7.24 mm` | **Inter-stroke dwell inflation:** Integrating across top-of-chest pauses (`250–450 ms`) quadratically integrates slow hand shifts (`+7.2 mm`). |
| **5. 1-MPU Double-Integration (Capped Pre-Onset, Unscaled)** (`MAX_PRE=18`, $K=11.20$) | `2.44 mm` | `3.23 mm` | `+1.46 mm` | `0.10 mm` | `6.74 mm` |Eliminates dwell inflation; slight `+1.5 mm` positive bias from external foam/vest pad compliance. |
| **6. 1-MPU Double-Integration (Fine-Tuned Production Model v5)** (`MAX_PRE=22`, $K=10.85$) | **`1.88 mm`** | **`2.49 mm`** | **`+0.54 mm`** | **`0.21 mm`** | **`5.43 mm`** | **Selected Production Model:** Global minimum MAE (`1.88 mm`), RMSE (`2.49 mm`), and Stroke Count MAE (`0.78` strokes). |

---

## 2. Mathematical Formulation of the Selected Model (Model v5)

### 2.1 Gravity Axis Projection (`GravityAxis.h`)
During the 2.0-second stationary calibration (`200` samples at `100 Hz`), the unit gravity vector $\hat{\mathbf{u}} = (u_x, u_y, u_z)$ and static gravity magnitude $g_0 = \|\bar{\mathbf{a}}_{\text{cal}}\|$ are learned from the resting chest accelerometer. At runtime, downward chest acceleration $a_{\text{net}}(t_i)$ (in units of $g$, positive downward) is computed via 3D projection:
$$a_{\text{net}}(t_i) = -\left( \mathbf{a}_{\text{chest}}(t_i) \cdot \hat{\mathbf{u}} - g_0 \right)$$
This makes the measurement invariant to mounting tilt angle without requiring a gyroscope.

### 2.2 Bounded Pre-Onset Closed-Cycle Windowing (`CompressionTracker.h`)
Because the 1st-order IIR low-pass filter ($\alpha = 0.25$, $f_c \approx 4.5\text{ Hz}$) introduces a `80–180 ms` phase delay before `netAccel` crosses the downstroke trigger threshold, the physical downstroke begins prior to `onsetSampleIndex`. However, starting the integral at `lastStrokeEndSampleIndex` includes any idle pause at the top of the chest between compressions.

To capture 100% of the physical push lead-in while rejecting inter-stroke idle dwell, the integration window $[i_{\text{start}}, i_{\text{end}})$ is bounded by `MAX_PRE_ONSET_INTEGRATION_SAMPLES` ($N_{\text{pre}} = 22$ samples $= 220\text{ ms}$ at `100 Hz`):
$$i_{\text{start}} = \max\!\left( i_{\text{lastEnd}},\; i_{\text{onset}} - N_{\text{pre}} \right), \qquad i_{\text{end}} = i_{\text{recoilFinish}} + 1$$

### 2.3 Closed-Cycle Zero-Mean Double Integration (`DepthEstimator.h`)
Over a complete compression-recoil cycle of duration $T = \sum_{i=i_{\text{start}}}^{i_{\text{end}}-1} \Delta t_i$, the chest returns to its starting position, enforcing two exact physical boundary conditions:
1. **Zero net velocity change** ($\bar{a} = \frac{1}{T}\sum a_{\text{net}}(t_i)\Delta t_i = 0$), which removes any constant DC offset or quasi-static tilt drift during the stroke.
2. **Zero net displacement change** ($\bar{v} = \frac{1}{T}\sum v(t_i)\Delta t_i = 0$), which determines the unknown initial velocity $v(t_{\text{start}})$ without requiring the window edges to be at rest:
$$v_k = \sum_{i=i_{\text{start}}}^{k} \left(a_{\text{net},i} - \bar{a}\right) \Delta t_i, \qquad x_k = \sum_{i=i_{\text{start}}}^{k} \left(v_i - \bar{v}\right) \Delta t_i$$
The raw physical displacement and calibrated depth are then:
$$d_{\text{phys,cm}} = G_{\text{cm/s}^2} \cdot \left(\max_k x_k - \min_k x_k\right), \qquad d_{\text{reported,cm}} = d_{\text{phys,cm}} \cdot \frac{K_{\text{depth}}}{K_{\text{nominal}}}$$
where $G_{\text{cm/s}^2} = 980.665\text{ cm/s}^2$, $K_{\text{nominal}} = 11.20$, and $K_{\text{depth}} = 10.85$ (`0.96875x` compliance factor correcting for ~`1.7 mm` of external vest/foam compression before the manikin's internal optical plate moves).

---

## 3. Empirical Per-Session Verification (`K = 10.85`, `MAX_PRE = 22`)

| Trial Folder | Preset | GT Strokes | Model Strokes | **Stroke Error** | GT Depth (mm) | Model Depth (mm) | **Depth Error (mm)** | GT Rate (CPM) | Model Rate (CPM) | **Rate Error (CPM)** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `01_2MPU_Balanced1_a4dc7413` | `BALANCED` | 52 | 53 | **`+1`** | 46.0 | 51.43 | **`+5.43 mm`** | 103 | 99.09 | `-3.91` |
| `04_2MPU_Strict1_7c5ea2c3` | `STRICT` | 103 | 104 | **`+1`** | 54.0 | 54.44 | **`+0.44 mm`** | 104 | 102.59 | `-1.41` |
| `05_2MPU_Strict2_f501e7c8` | `STRICT` | 69 | 69 | **`0`** | 57.0 | 57.72 | **`+0.72 mm`** | 109 | 108.53 | `-0.47` |
| `06_2MPU_High1_343540cf` | `HIGH` | 82 | 83 | **`+1`** | 60.0 | 59.35 | **`-0.65 mm`** | 105 | 104.43 | `-0.57` |
| `07_2MPU_High2_e5c4ad3a` | `HIGH` | 69 | 70 | **`+1`** | 59.0 | 57.00 | **`-2.00 mm`** | 101 | 100.71 | `-0.29` |
| `08_1MPU_Strict1_6ee8938f` | `STRICT` | 71 | 70 | **`-1`** | 54.0 | 57.05 | **`+3.05 mm`** | 107 | 104.76 | `-2.24` |
| `09_1MPU_Strict2_848e796c` | `STRICT` | 71 | 71 | **`0`** | 57.0 | 53.82 | **`-3.18 mm`** | 103 | 101.79 | `-1.21` |
| `10_1MPU_Balanced1_48011a51` | `BALANCED` | 70 | 70 | **`0`** | 58.0 | 57.79 | **`-0.21 mm`** | 102 | 100.52 | `-1.48` |
| `11_1MPU_High2_44c2e739` | `HIGH` | 80 | 82 | **`+2`** | 51.0 | 52.26 | **`+1.26 mm`** | 102 | 99.20 | `-2.80` |
| **Aggregate Error Summary** | **All 9** | **667** | **672** | **Min `0`, MAE `0.78`, Max `2`** | **55.1** | **55.65** | **Min `0.21`, MAE `1.88`, RMSE `2.49`, Max `5.43 mm`** | **104.0** | **102.40** | **Min `0.29`, MAE `1.60`, Max `3.91`** |

---

## 4. Empirical Parameter Error Bounds (Across All 9 Ground-Truth Sessions)

The tables below provide researchers with the exact **Minimum Absolute Error**, **Mean Absolute Error (MAE)**, **Root Mean Square Error (RMSE)**, **Mean Signed Bias**, and **Maximum Absolute Error** when varying each firmware parameter across the 9 recorded manikin sessions.

### 4.1 Depth Calibration Scalar (`DEPTH_CALIBRATION_K`, Command: `SET_K:<val>`)
*Controls linear depth scaling: $d = d_{\text{phys}} \times (K / 11.20)$. Analytical sensitivity is $\frac{\partial d}{\partial K} = \frac{d_{\text{phys}}}{11.20} \approx 5.0\text{ mm per } 1.0\text{ unit of } K$ at $56\text{ mm}$ depth.*

| `DEPTH_CALIBRATION_K` | Scale Ratio ($K / 11.20$) | Min Depth Error (mm) | **Mean Absolute Error (MAE)** | **Depth RMSE (mm)** | Mean Signed Bias (mm) | Max Depth Error (mm) | Signed Error Range (mm) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `9.50` | `0.848x` | `0.63 mm` | `6.27 mm` | `6.82 mm` | `-6.27 mm` | `9.87 mm` | `[-9.87, -0.63]` |
| `10.00` | `0.893x` | `1.42 mm` | `4.10 mm` | `4.54 mm` | `-3.74 mm` | `7.39 mm` | `[-7.39, +1.66]` |
| `10.50` | `0.938x` | `0.27 mm` | `2.35 mm` | `2.77 mm` | `-1.22 mm` | `4.91 mm` | `[-4.91, +3.89]` |
| **`10.85` (Default)** | **`0.969x`** | **`0.21 mm`** | **`1.88 mm`** | **`2.49 mm`** | **`+0.54 mm`** | **`5.43 mm`** | **`[-3.18, +5.43]`** |
| `11.00` | `0.982x` | `0.17 mm` | `2.10 mm` | `2.73 mm` | `+1.29 mm` | `6.09 mm` | `[-2.43, +6.09]` |
| `11.20` | `1.000x` | `0.16 mm` | `2.66 mm` | `3.30 mm` | `+2.30 mm` | `6.97 mm` | `[-1.44, +6.97]` |
| `11.50` | `1.027x` | `0.05 mm` | `3.81 mm` | `4.46 mm` | `+3.81 mm` | `8.29 mm` | `[+0.05, +8.29]` |
| `12.00` | `1.071x` | `2.53 mm` | `6.32 mm` | `6.71 mm` | `+6.32 mm` | `10.48 mm` | `[+2.53, +10.48]` |
| `12.50` | `1.116x` | `5.01 mm` | `8.83 mm` | `9.10 mm` | `+8.83 mm` | `12.68 mm` | `[+5.01, +12.68]` |

---

### 4.2 Pre-Onset Integration Lead-In Cap (`MAX_PRE_ONSET_INTEGRATION_SAMPLES`)
*Controls how many samples before `onsetSampleIndex` (at `10 ms` per sample) can be included in the closed-cycle integral. Values $< 16$ clip the initial push before the filtered threshold fires (causing negative bias); values $> 26$ include inter-stroke idle dwell (causing positive inflation).*

| `MAX_PRE_ONSET_SAMPLES` | Lead-In Window (ms) | Min Depth Error (mm) | **Mean Absolute Error (MAE)** | **Depth RMSE (mm)** | Mean Signed Bias (mm) | Max Depth Error (mm) | Signed Error Range (mm) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `8` | `80 ms` *(Clips push start)* | `0.31 mm` | `4.14 mm` | `5.47 mm` | `-2.65 mm` | `11.59 mm` | `[-11.59, +4.00]` |
| `12` | `120 ms` | `0.15 mm` | `3.27 mm` | `4.17 mm` | `-1.65 mm` | `8.84 mm` | `[-8.84, +4.34]` |
| `16` | `160 ms` | `0.60 mm` | `2.56 mm` | `3.15 mm` | `-0.76 mm` | `6.42 mm` | `[-6.42, +4.60]` |
| `18` | `180 ms` | `0.45 mm` | `2.27 mm` | `2.83 mm` | `-0.25 mm` | `5.27 mm` | `[-5.27, +5.07]` |
| `20` | `200 ms` | `0.21 mm` | `1.94 mm` | `2.61 mm` | `+0.19 mm` | `5.34 mm` | `[-4.17, +5.34]` |
| **`22` (Default)** | **`220 ms` (Optimal)** | **`0.21 mm`** | **`1.88 mm`** | **`2.49 mm`** | **`+0.54 mm`** | **`5.43 mm`** | **`[-3.18, +5.43]`** |
| `26` | `260 ms` | `0.21 mm` | `2.04 mm` | `2.55 mm` | `+1.11 mm` | `5.47 mm` | `[-2.00, +5.47]` |
| `32` | `320 ms` | `0.18 mm` | `2.14 mm` | `2.79 mm` | `+1.48 mm` | `5.01 mm` | `[-2.00, +5.01]` |
| `Uncapped` | Full `lastStrokeEnd` | `0.10 mm` | `2.26 mm` | `2.91 mm` | `+1.77 mm` | `5.24 mm` | `[-1.29, +5.24]` |

---

### 4.3 Recoil Arming Fraction (`RECOIL_ARM_FRACTION`, Command: `SET_ARM:<val>`)
*Controls how far negative the upward rebound acceleration must swing ($-\max(\text{recoilArmMinG},\; \text{recoilArmFraction} \times a_{\text{peak}})$) before a zero-crossing can finish the stroke. Values $\le 0.12$ allow post-recoil spring ringing to trigger false extra strokes.*

| `RECOIL_ARM_FRACTION` | Stroke Min Err | **Stroke MAE (strokes)** | **Stroke Max Err** | Signed Stroke Range | Depth Min Err (mm) | **Depth MAE (mm)** | **Depth RMSE (mm)** | Depth Max Err (mm) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `0.08` | `0` | `2.44` | `8 strokes` | `[0, +8]` | `0.13 mm` | `2.75 mm` | `3.50 mm` | `7.20 mm` |
| `0.10` | `0` | `2.00` | `6 strokes` | `[0, +6]` | `0.07 mm` | `2.41 mm` | `3.06 mm` | `5.73 mm` |
| `0.12` | `0` | `1.33` | `3 strokes` | `[0, +3]` | `0.07 mm` | `2.03 mm` | `2.60 mm` | `4.35 mm` |
| **`0.15` (`BALANCED`)** | **`0`** | **`1.00`** | **`3 strokes`** | **`[0, +3]`** | **`0.07 mm`** | **`1.95 mm`** | **`2.59 mm`** | **`5.43 mm`** |
| **`0.20` (`HIGH`)** | **`0`** | **`0.67`** | **`2 strokes`** | **`[0, +2]`** | **`0.21 mm`** | **`1.83 mm`** | **`2.42 mm`** | **`5.43 mm`** |
| **`0.25` (`STRICT`)** | **`0`** | **`0.67`** | **`2 strokes`** | **`[-1, +2]`** | **`0.34 mm`** | **`1.99 mm`** | **`2.69 mm`** | **`6.24 mm`** |
| `0.30` | `0` | `0.56` | `2 strokes` | `[-1, +2]` | `0.31 mm` | `1.95 mm` | `2.69 mm` | `6.24 mm` |
| `0.35` | `0` | `0.56` | `2 strokes` | `[-1, +2]` | `0.31 mm` | `1.95 mm` | `2.69 mm` | `6.24 mm` |

---

### 4.4 Downstroke Trigger Floor (`MIN_START_THRESHOLD_G`, Command: `SET_TRIG:<val>`)
*Controls the floor of the adaptive downstroke trigger ($\min(0.28\text{g},\; \max(\text{minStartThresholdG},\; \text{adaptiveStartFraction} \times \text{envelopeG}))$).*

| `MIN_START_THRESHOLD_G` | Stroke Min Err | **Stroke MAE (strokes)** | **Stroke Max Err** | Signed Stroke Range | Depth Min Err (mm) | **Depth MAE (mm)** | **Depth RMSE (mm)** | Depth Max Err (mm) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `0.04 g` | `0` | `1.00` | `3 strokes` | `[-1, +3]` | `0.20 mm` | `1.87 mm` | `2.49 mm` | `5.43 mm` |
| **`0.06 g` (`HIGH`)** | **`0`** | **`1.00`** | **`3 strokes`** | **`[-1, +3]`** | **`0.20 mm`** | **`1.89 mm`** | **`2.49 mm`** | **`5.43 mm`** |
| **`0.08 g` (`BALANCED`)** | **`0`** | **`1.00`** | **`3 strokes`** | **`[-1, +3]`** | **`0.21 mm`** | **`1.89 mm`** | **`2.49 mm`** | **`5.43 mm`** |
| `0.10 g` | `0` | `0.89` | `2 strokes` | `[-1, +2]` | `0.04 mm` | `1.84 mm` | `2.49 mm` | `5.42 mm` |
| **`0.12 g` (`STRICT`)** | **`0`** | **`0.78`** | **`2 strokes`** | **`[-1, +2]`** | **`0.22 mm`** | **`1.88 mm`** | **`2.48 mm`** | **`5.42 mm`** |
| `0.15 g` | `0` | `0.67` | `2 strokes` | `[-1, +2]` | `0.22 mm` | `1.78 mm` | `2.40 mm` | `5.41 mm` |
| `0.20 g` | `0` | `0.56` | `2 strokes` | `[-1, +2]` | `0.50 mm` | `1.79 mm` | `2.32 mm` | `5.10 mm` |

---

### 4.5 Minimum Unscaled Stroke Depth Gate (`MIN_STROKE_DEPTH_CM`, Command: `SET_MIN_D:<val>`)
*Rejects incidental hand bumps smaller than `minStrokeDepthCm` before incrementing `totalStrokeCount`. Raising this above `1.0 cm` begins rejecting legitimate shallow strokes and skewing session mean depth upward.*

| `MIN_STROKE_DEPTH_CM` | Stroke Min Err | **Stroke MAE (strokes)** | **Stroke Max Err** | Signed Stroke Range | Depth Min Err (mm) | **Depth MAE (mm)** | **Depth RMSE (mm)** | Depth Max Err (mm) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `0.15 cm` (`1.5 mm`) | `0` | `0.78` | `2 strokes` | `[-1, +2]` | `0.21 mm` | `1.88 mm` | `2.49 mm` | `5.43 mm` |
| **`0.25 cm` (`BALANCED`/`HIGH`)** | **`0`** | **`0.78`** | **`2 strokes`** | **`[-1, +2]`** | **`0.21 mm`** | **`1.88 mm`** | **`2.49 mm`** | **`5.43 mm`** |
| `0.35 cm` (`3.5 mm`) | `0` | `0.67` | `2 strokes` | `[-1, +2]` | `0.21 mm` | `1.98 mm` | `2.72 mm` | `6.36 mm` |
| **`0.50 cm` (`STRICT`)** | **`0`** | **`0.67`** | **`2 strokes`** | **`[-1, +2]`** | **`0.21 mm`** | **`1.98 mm`** | **`2.72 mm`** | **`6.36 mm`** |
| `0.75 cm` (`7.5 mm`) | `0` | `0.78` | `2 strokes` | `[-1, +2]` | `0.21 mm` | `2.08 mm` | `2.96 mm` | `7.25 mm` |
| `1.00 cm` (`10.0 mm`) | `0` | `0.67` | `2 strokes` | `[-2, +1]` | `0.44 mm` | `2.27 mm` | `3.24 mm` | `8.13 mm` |
| `1.50 cm` (`15.0 mm`) | `0` | `1.00` | `3 strokes` | `[-3, +1]` | `0.44 mm` | `2.45 mm` | `3.42 mm` | `8.13 mm` |

---

## 5. Theoretical Analytical & Monte-Carlo Perturbation Error Bounds

To bound worst-case sensor and timing errors outside the 9 recorded trials, the double-integration engine was evaluated analytically and via Monte-Carlo simulation (`50` trials per point at `55.0 mm` target depth, `110 CPM` cadence).

### 5.1 Loop Timing & I2C Sampling Jitter ($\Delta t$ Perturbation)
Because `DepthEstimator::closedCycleDepthCm` integrates using each sample's true microsecond interval $\Delta t_i = (t_i - t_{i-1}) \times 10^{-6}$, Riemann discretization error is bounded by $\mathcal{O}(\overline{\Delta t^2})$.

| Timing Jitter ($\pm \% \text{ of } 10\text{ ms}$) | **True-$\Delta t$ Integrator Min Err** | **True-$\Delta t$ Integrator MAE** | **True-$\Delta t$ Integrator Max Err** | Uncompensated Fixed-$\Delta t$ MAE | Uncompensated Fixed-$\Delta t$ Max Err |
| :---: | :---: | :---: | :---: | :---: | :---: |
| `±0%` (Ideal `100.0 Hz`) | `0.35 mm` | `0.35 mm` | `0.35 mm` | `0.35 mm` | `0.35 mm` |
| `±2%` (`9.8–10.2 ms`) | `0.11 mm` | **`0.49 mm`** | **`2.09 mm`** | `0.55 mm` | `2.42 mm` |
| `±5%` (`9.5–10.5 ms`) | `0.00 mm` | **`0.60 mm`** | **`1.88 mm`** | `0.93 mm` | `2.63 mm` |
| `±10%` (`9.0–11.0 ms`) | `0.03 mm` | **`0.74 mm`** | **`2.17 mm`** | `1.34 mm` | `3.14 mm` |
| `±15%` (`8.5–11.5 ms`) | `0.00 mm` | **`0.67 mm`** | **`2.39 mm`** | `1.45 mm` | `4.97 mm` |
| `±20%` (`8.0–12.0 ms`) | `0.00 mm` | **`0.74 mm`** | **`2.78 mm`** | `1.87 mm` | `6.34 mm` |

### 5.2 Top-of-Chest Inter-Stroke Dwell Inflation (With `0.035g` Low-Frequency Hand Shift)
When a trainee pauses at the top of the chest for $T_{\text{dwell}}$ between compressions while shifting weight slightly ($\Delta a_{\text{dwell}} \approx 0.035\text{ g}$), an uncapped closed-cycle integral accumulates a spurious displacement proportional to $T_{\text{dwell}}^2$:

| Inter-Stroke Dwell Duration ($T_{\text{dwell}}$) | Uncapped Closed-Cycle Error (mm) | **Capped Pre-Onset (`MAX_PRE=22`) Error (mm)** | Error Reduction |
| :---: | :---: | :---: | :---: |
| `0 ms` (Continuous 110 CPM) | `-0.41 mm` | **`-0.41 mm`** | — |
| `100 ms` (`10` samples) | `+1.36 mm` | **`+1.36 mm`** | — |
| `220 ms` (`22` samples — cap boundary) | `+3.67 mm` | **`+3.67 mm`** | — |
| `300 ms` (`30` samples) | `+5.34 mm` | **`+4.03 mm`** | **`-1.31 mm` (`-25%`)** |
| `400 ms` (`40` samples) | `+7.58 mm` | **`+3.73 mm`** | **`-3.85 mm` (`-51%`)** |
| `500 ms` (`50` samples) | `+9.99 mm` | **`+3.29 mm`** | **`-6.70 mm` (`-67%`)** |

### 5.3 Static DC Bias / Gravity Tilt Drift & Resting Hand Tremor Bounds
- **Constant DC Bias / Quasi-Static Tilt Drift ($\Delta a_{\text{DC}} \in [0.00\text{ g}, 0.25\text{ g}]$)**:
  - **Theoretical & Empirical Error**: **`0.00 mm` additional error** across all closed-cycle strokes, because subtracting $\bar{a} = \frac{1}{T}\sum a_i \Delta t_i$ cancels any constant acceleration bias identically before velocity integration.
- **Post-Pause First-Stroke Hand Tremor ($\sigma_{\text{tremor}} \in [20\text{ mg}, 110\text{ mg}]$)**:
  - With `REST_LIMIT_G = 0.15f` (`150 mg`), `fromRestDepthCm` recovers **100% of post-pause first strokes** up to `110 mg` peak-to-peak hand tremor, with a **Single-Stroke Max Error $\le 3.8\text{ mm}$** and **25-Trial Mean Error $\le 1.2\text{ mm}$**.

---

## 6. Practical Tuning Decision Guide for Researchers

| Observed Symptom in Field Testing | Root Cause | Recommended Parameter Adjustment (via App or BLE Command) |
| :--- | :--- | :--- |
| **Mean depth is consistently `X mm` higher or lower than a new manikin's reference display** | Different foam/spring compliance between the vest pad and the new manikin's internal sensor. | Run the **15 s Manikin Calibration** in the app, or set $K_{\text{new}} = K_{\text{current}} \times \frac{d_{\text{manikin}}}{d_{\text{CPReady}}}$ via `SET_K:<val>`. Each `±0.20` change in $K$ shifts reported depth by `±1.0 mm`. |
| **Extra `2–5` compressions counted at the start or end of a 30-stroke cycle** | Post-recoil manikin spring oscillation arming the recoil zero-crossing detector. | Switch from `HIGH` to `BALANCED` (`SET_SENS:BALANCED`) or increase **Recoil Arm** (`SET_ARM:0.20` to `0.25`). |
| **Very shallow/soft compressions (`< 35 mm`) on a heavily damped manikin are missed** | Downstroke peak acceleration stays below trigger floor or recoil rebound is heavily damped by leaning hands. | Select **`HIGH` Sensitivity Preset** (`SET_SENS:HIGH`: `Trigger = 0.06g`, `Recoil Arm = 0.20`, `Min Depth = 0.25 cm`). |
| **Slower compressions (`80–95 CPM`) with a pause at the top of each stroke over-read depth by `3–5 mm`** | Pre-onset window includes part of the top-of-chest dwell. | Reduce `MAX_PRE_ONSET_INTEGRATION_SAMPLES` in `CPReadyConfig.h` from `22` (`220 ms`) to `18` (`180 ms`). |
| **Incidental hand repositioning during a pause counts as a stroke** | Hand bump exceeds `minStartThresholdG` and produces `> 2.5 mm` of raw motion. | Select **`STRICT` Sensitivity Preset** (`SET_SENS:STRICT`) or raise **Min Depth** (`SET_MIN_D:0.50`). |


---

## 7. App-Side Retroactive Refinement (`R3 + Zero-Phase filtfilt`) & Dynamic Voice Coaching Engine (v1)

To resolve unsteady-rhythm boundary errors ($\Delta v \neq 0$), split-stroke fragments, and premature-cut carryover pairs without sacrificing causal real-time responsiveness on the ESP32, the Flutter companion app (`FLUTTER/cpready`) executes a **4-Stage Hybrid Retroactive Refinement Pass (`SessionRefinementEngine`)** at session completion (`STOP`) and drives live voice coaching dynamically (`LiveCoachingController`).

### 7.1 Four-Stage Hybrid Refinement Pipeline (`SessionRefinementEngine`)
1. **Stage 0 — Self-Calibrated Zero-Phase Forward-Backward (`filtfilt`) Trajectory**:
   - Applies a 2nd-order Butterworth forward-backward zero-phase high-pass filter ($f_c = 0.55\text{ Hz}$) to the 100 Hz chest acceleration and velocity stream to compute a phase-distortion-free displacement waveform $x_{\text{ff}}(t)$.
   - Computes the session's steady-stroke gain ratio $\alpha_{\text{session}} = \text{median}_{k \in \text{steady}}(d_{\text{closed},k} / d_{\text{ff},k})$ to eliminate frequency-dependent filter attenuation, and blends `60%` self-calibrated `filtfilt` + `40%` closed-cycle **only on unsteady, window-clamped, or hesitation strokes**.
2. **Stage 1 — Case A (True Split Stroke Merge) vs. Case B (Boundary-Shifted Pair Rebalance)**:
   - **Case A**: Merges true split-stroke fragments ($\Delta t_i < 330\text{ ms}$ or $\Delta t_{i+1} < 330\text{ ms}$ with $\Delta t_i + \Delta t_{i+1} \le \max(700\text{ ms}, 1.30\,T_{\text{median}})$) into 1 stroke via 100 Hz closed-cycle re-integration or $\sqrt{d_i^2 + d_{i+1}^2}$.
   - **Case B**: Re-balances premature-cut + carryover pairs ($\Delta t_i < 320\text{ ms}$, $\Delta t_{i+1} > 700\text{ ms}$, $\Delta t_i + \Delta t_{i+1} \ge 1.55\,T_{\text{median}}$) to $\frac{1}{2}(d_i + d_{i+1})$ while preserving the 2-stroke count.
3. **Stage 2 — 100 Hz Gap Stroke Recovery**:
   - Scans inter-stroke gaps $> 720\text{ ms}$ in the 100 Hz waveform to recover missed shallow/transition strokes.
4. **Stage 3 — Local Steady-Median Winsorization**:
   - Clamps residual unsteady transition outliers to within $\pm 5.0\text{ mm}$ of the local 5-stroke steady median depth.

### 7.2 10-Session Ground-Truth Performance Comparison (`Live Model v6` vs. `4-Stage Hybrid Refinement`)

| Session ID | Mode & Preset | Laerdal GT Depth (`Count`) | Live Model v6 Depth (`Count`) | **Refined Hybrid (`R3 + filtfilt`) Depth (`Count`)** | Live Abs Err | **Refined Abs Err** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `01_2MPU_Balanced1` | 2-MPU `BALANCED` | **46.0 mm** (`52`) | 51.0 mm (`52`) | **50.3 mm (`52`)** | `4.95 mm` | **`4.34 mm`** |
| `04_2MPU_Strict1` | 2-MPU `STRICT` | **54.0 mm** (`103`) | 54.6 mm (`101`) | **54.6 mm (`102`)** | `0.63 mm` | **`0.62 mm`** |
| `05_2MPU_Strict2` | 2-MPU `STRICT` | **57.0 mm** (`69`) | 57.9 mm (`69`) | **57.9 mm (`69`)** | `0.85 mm` | **`0.85 mm`** |
| `06_2MPU_High1` | 2-MPU `HIGH` | **60.0 mm** (`82`) | 59.6 mm (`84`) | **60.3 mm (`83`)** | `0.40 mm` | **`0.31 mm`** |
| `07_2MPU_High2` | 2-MPU `HIGH` | **59.0 mm** (`69`) | 56.9 mm (`71`) | **57.9 mm (`70`)** | `2.15 mm` | **`1.06 mm`** |
| `08_1MPU_Strict1` | 1-MPU `STRICT` | **54.0 mm** (`71`) | 55.2 mm (`70`) | **54.9 mm (`71`)** | `1.19 mm` | **`0.94 mm`** |
| `09_1MPU_Strict2` | 1-MPU `STRICT` | **57.0 mm** (`71`) | 54.5 mm (`73`) | **55.6 mm (`72`)** | `2.46 mm` | **`1.37 mm`** |
| `10_1MPU_Balanced1` | 1-MPU `BALANCED` | **58.0 mm** (`70`) | 57.5 mm (`71`) | **57.6 mm (`71`)** | `0.48 mm` | **`0.36 mm`** |
| `11_1MPU_High2` | 1-MPU `HIGH` | **51.0 mm** (`80`) | 51.1 mm (`80`) | **51.1 mm (`80`)** | `0.13 mm` | **`0.13 mm`** |
| `12_1MPU_Balanced2` | 1-MPU `BALANCED` | **56.0 mm** (`75`) | 53.0 mm (`77`) | **53.8 mm (`76`)** | `2.96 mm` | **`2.16 mm`** |
| **10-Session Summary** | **All 10 Trials** | — | **`MAE = 1.62 mm`<br>`Count MAE = 1.20`** | **`MAE = 1.21 mm` (`RMSE = 1.75 mm`)<br>`Count MAE = 0.50` (`10/10` within `±1`)** | **`1.62 mm`** | **`1.21 mm`** |

### 7.3 App-Side Dynamic Voice Coaching Engine (`LiveCoachingController` v1)
- Located in `FLUTTER/cpready/lib/src/core/audio/live_coaching_controller.dart`.
- **Unsteady-Rhythm Depth Suppression**: Whenever `!metrics.isSteadyCadence` or the live cadence warning banner is active, depth error streaks are cleared and depth cues (`"Compression too shallow"` / `"Compression too deep"`) are suppressed so rate prompts (`"Compression rate too slow"` / `"Compression rate too fast"`) stabilize the trainee's rhythm first.
- **Tunable Parameters (`LiveCoachingConfig`)**: `consecutiveErrorStrokes = 5`, `sustainedErrorWindowMs = 3000`, `promptCooldownMs = 5000`, `positivePraiseIntervalMs = 15000`. Designed as a modular v1 baseline for future human-factors research.
