# Pre-Defense Accuracy, Firmware v6 Specification & Thesis Delimitations Plan

> [!IMPORTANT]
> **Aligned Decisions (Incorporating User Feedback on Q19, Q5/Q31, Q27/Q28, Q44/Q45)**
> 1. **Q19 (Low-Risk Firmware Fixes)**: Proceed with **Firmware Model v6 (`Option A`)**, where every individual fix is explicitly planned with its exact C++ implementation and verified ablation impact before touching code.
> 2. **Q5 / Q31 (Option B Empirical Test on Existing Trial Dataset)**: We executed Option B's post-session refinement pass across all **10 Laerdal ground-truth sessions** and **4 Nov-5 Schema-2 sessions** (Section 2 below). Because firmware fixes `A + B` already eliminate the open-loop and pause-stretch spikes at the source (`10-GT MAE = 1.71 mm`, `9-GT MAE = 1.46 mm`), adding a post-session statistical refinement pass (`Option B`) yields only `0.03 mm` difference on `v5` (`1.81` $\rightarrow$ `1.78 mm`) and **worsens MAE on `v6` (`1.71` $\rightarrow$ `1.84 mm`)** by mistaking genuine shallow boundary strokes for outliers (e.g., pushing the `46.0 mm` shallow trial from `50.2 mm` to `53.2 mm`). Per your decision criterion, **we drop Option B and proceed with Firmware v6 (`Option A`) + Documentation & Delimitations**.
> 3. **Q27 / Q28 (Eliminating Open-Loop & Pause-Stretch Spikes at the Source)**: Rather than hiding spikes with post-hoc trimming, `Fix A` (closed-cycle `fromRestDepthCm`) and `Fix B` (`MAX_CYCLE_INTEGRATION_SAMPLES = 66`) prevent `78–100 mm` spikes from occurring in the first place.
> 4. **Q44 / Q45 (Well-Planned Bench Testing & Post-Trial Analysis Protocol)**: Section 4 defines the step-by-step bench procedure, trial matrix, data capture checklist, and automated post-trial validation pipeline.

---

## 1. Expanded 10-Session Ground-Truth Dataset (Discovery of `2928353c`)

Inspecting the 6 `.zip` files added to `DATA/` on Nov 6 revealed that **`DATA/2928353c-fe25-4d66-b75d-d45f5bd78f8b.zip`** (`ended_at: 2026-11-04T06:12:55Z` = **`2:12:55 PM PHT`**, `experiment: "10th test"`, `notes: "Single mpu balanced"`) is the exact capture for previously unpaired screenshot **`DATA/Single MPU/1MPU_Balanced2.jpg`** (`2:13 PM`, **75 strokes, 56 mm mean depth, 102 CPM, 95% good depth, 99% release**).

This expands our paired Laerdal ground-truth dataset from **9 to 10 complete sessions** (5 in 1-MPU, 5 in 2-MPU, totaling **742 compressions**), plus **4 Nov-5 Schema-2 sessions** (`3f74e948`, `af47d3f5`, `b6d1fe73`, `8f4e8e4c`) used to stress-test unsteady rhythm, post-pause behavior, and sampling stalls.

---

## 2. Empirical Test of Option B (Post-Session Refinement) on Current Dataset (`Q5 / Q31`)

Before deciding on Option B, we simulated both **Firmware v5 (current C++)** and **Firmware v6 (planned fixes)** with and without **Option B's post-session refinement pass** (which strips uncorroborated post-pause spikes `> 68 mm`, truncated final strokes `< 28 mm`, and isolated `> 3.5 MAD` outliers at `STOP`).

### 2.1 Per-Session Results Across All 10 Laerdal Ground-Truth Sessions

| Session ID | Mode & Preset | Laerdal GT Depth (Count) | C++ Model v5 Mean (`Max`) | v5 + Option B Mean | Planned Model v6 Mean (`Max`) | v6 + Option B Mean |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `01_2MPU_Balanced1_a4dc7413` | 2-MPU `BALANCED` | **46.0 mm** (52) | 51.5 mm (`100.0 mm`) | 53.0 mm | **50.2 mm** (`73.4 mm`) | 53.2 mm |
| `04_2MPU_Strict1_7c5ea2c3` | 2-MPU `STRICT` | **54.0 mm** (103) | 54.7 mm (`65.1 mm`) | 55.9 mm | **54.9 mm** (`65.1 mm`) | 56.2 mm |
| `05_2MPU_Strict2_f501e7c8` | 2-MPU `STRICT` | **57.0 mm** (69) | 57.8 mm (`69.6 mm`) | 57.8 mm | **57.8 mm** (`69.6 mm`) | 58.1 mm |
| `06_2MPU_High1_343540cf` | 2-MPU `HIGH` | **60.0 mm** (82) | 59.5 mm (`69.5 mm`) | 60.3 mm | **59.3 mm** (`69.5 mm`) | 60.3 mm |
| `07_2MPU_High2_e5c4ad3a` | 2-MPU `HIGH` | **59.0 mm** (69) | 57.8 mm (`67.4 mm`) | 57.8 mm | **57.0 mm** (`67.4 mm`) | 57.7 mm |
| `08_1MPU_Strict1_6ee8938f` | 1-MPU `STRICT` | **54.0 mm** (71) | 55.2 mm (`66.9 mm`) | 55.2 mm | **54.9 mm** (`66.9 mm`) | 55.2 mm |
| `09_1MPU_Strict2_848e796c` | 1-MPU `STRICT` | **57.0 mm** (71) | 53.9 mm (`66.6 mm`) | 55.8 mm | **54.3 mm** (`66.6 mm`) | 56.4 mm |
| `10_1MPU_Balanced1_48011a51` | 1-MPU `BALANCED` | **58.0 mm** (70) | 57.9 mm (`100.0 mm`) | 58.0 mm | **57.3 mm** (`69.5 mm`) | 58.2 mm |
| `11_1MPU_High2_44c2e739` | 1-MPU `HIGH` | **51.0 mm** (80) | 52.3 mm (`100.0 mm`) | 52.6 mm | **50.9 mm** (`80.5 mm`) | 53.0 mm |
| `10_1MPU_Balanced2_2928353c` | 1-MPU `BALANCED` | **56.0 mm** (75) | 52.3 mm (`100.0 mm`) | 53.6 mm | **52.0 mm** (`72.0 mm`) | 53.6 mm |
| **9-Session GT MAE (Original 9)** | — | — | **1.60 mm** | 1.62 mm | **1.46 mm** | 1.78 mm |
| **10-Session GT MAE (All 10)** | — | — | **1.81 mm** | 1.78 mm | **1.71 mm** | 1.84 mm |
| **1-MPU 5-Session GT MAE** | **1-MPU Only** | — | **1.87 mm** | 1.38 mm | **1.69 mm** | 1.33 mm |

### 2.2 Why Option B Is Rejected in Favor of Firmware v6 + Delimitations
1. **Firmware v6 already removes the `100.0 mm` and `78.2 mm` spikes directly in live estimation**: Across all 10 GT sessions, Model v6 lowers the 9-session MAE from `1.60 mm` to **`1.46 mm`** and the 10-session MAE from `1.81 mm` to **`1.71 mm`** while eliminating every `100.0 mm` clamp event.
2. **Option B hurts shallow-stroke sessions**: On `01_2MPU_Balanced1` (`GT = 46.0 mm`) and `11_1MPU_High2` (`GT = 51.0 mm`), Option B trims legitimate shallower boundary strokes (`28–38 mm`), artificially inflating the session mean from `50.2 mm` $\rightarrow$ `53.2 mm` (`+7.15 mm` error) and `50.9 mm` $\rightarrow$ `53.0 mm` (`+2.01 mm` error). Since your client specifically flagged **upward mean-depth inflation from discarding shallow strokes** as a primary concern, avoiding post-session stroke trimming and keeping live and summary numbers 100% identical is the right engineering decision.

---

## 3. Explicit Specification & Ablation Impact of Each Firmware v6 Fix (`Q19`, `Q27/Q28`)

We ran a cumulative ablation of the proposed firmware changes across all 10 GT sessions and 4 Nov-5 Schema-2 sessions.

### 3.1 Cumulative Ablation Summary

| Configuration Step | 9-GT Depth MAE | 10-GT Depth MAE | Count MAE | Max Single Stroke (10 GT) | Max Single Stroke (`af47d3f5`) | Dropped (`0.0 mm`) Strokes (10 GT) | Decision |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Baseline C++ Model v5** | `1.60 mm` | `1.81 mm` | `1.20` | `100.0 mm` | `78.2 mm` | `4` | Baseline |
| **`+ Fix A` (Closed-Cycle `fromRestDepthCm`)** | `1.63 mm` | `1.85 mm` | `1.20` | `100.0 mm` | **`61.1 mm`** | **`1`** | **KEEP** |
| **`+ Fix B` (Max Cycle Window Cap `= 66`)** | **`1.43 mm`** | **`1.70 mm`** | `1.20` | **`80.5 mm`** | **`61.1 mm`** | **`1`** | **KEEP** |
| **`+ Fix C` (Period-Scaled Pre-Onset `S2`)** | **`1.44 mm`** | **`1.69 mm`** | `1.20` | **`80.5 mm`** | **`61.1 mm`** | **`1`** | **KEEP** |
| **`+ Fix E` (Stall Guard `>50ms` + `190ms` Min Dur)** | **`1.46 mm`** | **`1.71 mm`** | `1.20` | **`80.5 mm`** | **`61.1 mm`** | **`1`** | **KEEP** |
| *(Rejected)* `Fix D` (Lower Envelope Cap `0.24g` / Positive-Only) | `1.88 mm` | `2.05 mm` | `1.10`–`2.90` | `80.5 mm` | `61.1 mm` | `1` | **REJECT** |

> [!WARNING]
> **Why `Fix D` (Altering `signalEnvelopeG` Tracking/Ceiling) Was Rejected After Ablation**
> When we tested positive-only envelope tracking (`if (netAccel > signalEnvelopeG)`) or lowering `MAX_START_THRESHOLD_G` from `0.28g` to `0.24g`, `9-GT MAE` degraded from `1.44 mm` to `1.87–2.37 mm`. Why? Because after upward recoil completes on the Laerdal spring, there is a `+0.15g` to `+0.25g` post-recoil spring bounce `80–120 ms` after zero-crossing. `signalEnvelopeG` tracking `fabsf(netAccel)` up to `0.28g` is what prevents the detector from re-triggering early on that post-recoil bounce during normal compressions. Instead of weakening the bounce guard globally, we add a **targeted envelope release when no stroke has triggered for `> 650 ms`** (`Fix E3` below) so transitioning from deep to shallow strokes recovers immediately without disturbing steady-state threshold rejection.

---

### 3.2 Detailed Implementation Plan for Each Approved Firmware Fix

#### Fix A: Replace Open-Loop Integration in `DepthEstimator::fromRestDepthCm` with Closed-Cycle Zero-Mean Velocity Closure
- **Target File**: [`DepthEstimator.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/DepthEstimator.h#L109-L157)
- **Root Cause**: In C++, `fromRestDepthCm` currently requires 20 quiet samples (`REST_SAMPLES = 20`) and integrates `(s.rawNetG - baseline)` **open-loop** without subtracting `meanV`. On `af47d3f5` stroke #1, a tiny `0.02g` baseline tilt offset passes the check and integrates open-loop to **`78.2 mm`**. Conversely, on `2928353c` stroke #1, `3f74e948` stroke #1, and `8f4e8e4c` stroke #1, normal pre-push hand settling exceeds `0.15g` during the 20-sample (`200 ms`) lead-in, causing `fromRestDepthCm` to fail and emit **`0.0 mm`**.
- **Exact Implementation**:
  1. Change `PRE_ONSET_SAMPLES` from `20` to `8` and `REST_SAMPLES` from `20` to `8` (`80 ms` stillness check).
  2. Check that the peak-to-peak spread `(restMax - restMin) <= REST_LIMIT_G` (`0.15g`) over `[restFrom, start)`, and then delegate the depth calculation to **`closedCycleDepthCm(start, to, outCm)`** so mean acceleration and mean velocity are both zeroed over the stroke window.
  3. In [`CompressionTracker.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/CompressionTracker.h#L467-L470), if `fromRestDepthCm` returns `false` on the **very first stroke of a session** (`totalStrokeCount == 0`), fall back to `depthEstimator.closedCycleDepthCm(onsetSampleIndex >= 8 ? onsetSampleIndex - 8 : 0, strokeEndIndex, physicalDepthCm)` so stroke #1 is never lost as `0.0 mm`.
- **Verified Impact**:
  - Eliminates the `78.2 mm` open-loop spike on stroke #1 of `af47d3f5` (`78.2 mm` $\rightarrow$ `61.1 mm`).
  - Reduces `0.0 mm` dropped post-pause/first strokes across the 10 GT sessions from `4` to `1` and across the 4 Schema-2 sessions from `10` to `3` (where the remaining 3 are genuine non-compression hand bumps during pauses).

#### Fix B: Cap Maximum Closed-Cycle Integration Span (`MAX_CYCLE_INTEGRATION_SAMPLES = 66`)
- **Target Files**: [`CPReadyConfig.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/CPReadyConfig.h#L165-L185) and [`CompressionTracker.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/CompressionTracker.h#L456-L466)
- **Root Cause**: Every single **`100.0 mm` (`10.0 cm` clamp)** spike across the entire 14-session dataset (`01_2MPU_Balanced1` strokes #7 & #11, `10_1MPU_Balanced1` stroke #3, `11_1MPU_High2` strokes #25, #29, #34, #69, `2928353c` stroke #14, and `3f74e948` stroke #24) occurs when `isPostPause == false` (`rawPeriodMs` between `850 ms` and `1120 ms`), where the detector triggered early on the previous stroke's post-recoil bounce and the user hesitated at the top of the chest before pushing. The resulting window `[cycleStartIndex, strokeEndIndex]` spans `75–85 samples` (`750–850 ms`), and because double-integration drift scales with $T^2$, integrating across `800+ ms` inflates the depth to `85–100 mm`.
- **Exact Implementation**:
  - Define `static constexpr uint32_t MAX_CYCLE_INTEGRATION_SAMPLES = 66;` (`0.66 s` at `100 Hz`, sufficient for any true active compression + recoil cycle down to `65 CPM`) in `CPReadyConfig.h`.
  - In `CompressionTracker.h` (line 463), immediately after applying the pre-onset cap to `cycleStartIndex`, bound the total integration span:
    ```cpp
    if (strokeEndIndex > cycleStartIndex + CPReadyConfig::MAX_CYCLE_INTEGRATION_SAMPLES) {
        cycleStartIndex = strokeEndIndex - CPReadyConfig::MAX_CYCLE_INTEGRATION_SAMPLES;
    }
    ```
- **Verified Impact**:
  - **Eliminates every `100.0 mm` spike across all 10 GT sessions and 4 Schema-2 sessions** (reducing max stroke from `100.0 mm` to `80.5 mm`).
  - Improves **9-GT Depth MAE from `1.63 mm` $\rightarrow$ `1.43 mm`** and **10-GT Depth MAE from `1.85 mm` $\rightarrow$ `1.70 mm`**.
  - Specifically improves the shallow trial `01_2MPU_Balanced1` (`GT = 46.0 mm`) from `51.5 mm` (`+5.52 mm` error) to **`50.2 mm` (`+4.25 mm` error)** and `11_1MPU_High2` (`GT = 51.0 mm`) from `52.3 mm` (`+1.34 mm` error) to **`50.9 mm` (`-0.12 mm` error)**.

#### Fix C: Period-Proportional Pre-Onset Lookback Window (`S2`)
- **Target File**: [`CompressionTracker.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/CompressionTracker.h#L457-L464)
- **Root Cause**: Fixed `MAX_PRE_ONSET_INTEGRATION_SAMPLES = 22` is calibrated for `105–115 CPM` (`~550 ms` period), but slightly over-integrates high-cadence bursts (`> 125 CPM`) and under-integrates slower steady cadence (`90–100 CPM`).
- **Exact Implementation**:
  - When `periodHistoryCount > 0`, compute the adaptive pre-onset sample cap from `medianRecentPeriodMs()`:
    ```cpp
    uint32_t maxPreSamples = CPReadyConfig::MAX_PRE_ONSET_INTEGRATION_SAMPLES; // 22 default
    if (periodHistoryCount > 0) {
        int32_t scaledPre = (int32_t)lroundf(0.40f * (medianRecentPeriodMs() / 10.0f));
        if (scaledPre < 16) scaledPre = 16;
        if (scaledPre > 26) scaledPre = 26;
        maxPreSamples = (uint32_t)scaledPre;
    }
    ```
- **Verified Impact**:
  - Improves 10-GT Depth MAE from `1.70 mm` to **`1.69 mm`** and adapts pre-onset lookback smoothly across `80–140 CPM`.

#### Fix E: Sampling Stall Guard (`dtSeconds > 0.050f`), Minimum Stroke Duration (`>= 190 ms`), and Sub-Threshold Shallow-Transition Envelope Release
- **Target File**: [`CompressionTracker.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/CompressionTracker.h#L375-L450)
- **Root Causes**:
  1. **Sampling stall (`b6d1fe73`)**: A `1.013 s` jump in `t_us` (`sample_index` increments by 1) is currently clamped to `dt = 0.01f` in `DepthEstimator::push`, integrating across a 1-second gap as if no time passed.
  2. **Mid-stroke split (`3f74e948` strokes 23–24)**: A hesitant double-pump push dips below `-recoilArmLevel()` and crosses `-0.02g` after `< 180 ms`, splitting one stroke into a `11.6 mm` fragment + `81.0 mm` second half.
  3. **Deep-to-shallow transition masking**: If a trainee switches abruptly from deep (`55 mm`, `env ~ 0.9g`) to very shallow (`35 mm`, peak `0.15g`) compressions, `startThreshold()` stays above `0.18g` for `~600 ms`, potentially missing the first shallow stroke.
- **Exact Implementation**:
  1. **Stall reset (`processSample` entry)**: If `dtSeconds > 0.050f`, reset `state = StrokeState::WAITING_FOR_DOWNSLICK`, `depthEstimator.reset()`, `recoilArmed = false`, and `forcePostPause = true`.
  2. **Minimum stroke duration (`StrokeState::RECOILING`)**: Require `(currentMillis - strokeStartMillis) >= 190` (`190 ms`) before allowing stroke completion at `netAccel >= STROKE_FINISH_THRESHOLD_G`.
  3. **Shallow-transition envelope release (`StrokeState::WAITING_FOR_DOWNSLICK`)**: If `state == WAITING_FOR_DOWNSLICK` and `(currentMillis - lastStrokePeakMillis) > 650` (`> 650 ms` without triggering a new downstroke while `signalEnvelopeG` is still elevated), accelerate envelope decay (`signalEnvelopeG *= 0.960f;`) so a sudden drop to shallow compressions immediately unmasks `startThreshold()` down to `baseStartThreshold` (`0.06g–0.08g`) without affecting normal `100–120 CPM` post-recoil bounce rejection (`80–250 ms` after completion).
- **Verified Impact**:
  - Preserves **`1.46 mm` 9-GT MAE** and **`1.71 mm` 10-GT MAE** (zero regression on steady-state bounce rejection) while guaranteeing that any missed shallow transition unmasks within `< 150 ms` after `650 ms` elapsed, blocking `< 190 ms` split strokes, and resetting cleanly across `> 50 ms` RTOS/BLE stalls.

---

## 4. Well-Planned Bench Testing & Post-Trial Validation Protocol (`Q44 / Q45`)

To validate Firmware v6 on the two client-priority edge cases (**shallow strokes** and **unsteady rhythm**) before the Nov 20 defense without consuming excessive lab time, we use a structured **9-Trial Verification Protocol (~35 minutes total)**.

```mermaid
flowchart LR
    Prep["1. Setup & Flash v6<br/>(Enable Raw Sample Export)"] --> Block1["2. Block A (3 Trials)<br/>Shallow Compressions<br/>(38–44 mm, Steady ~105 CPM)"]
    Block1 --> Block2["3. Block B (3 Trials)<br/>Deep-to-Shallow Transitions<br/>(15 Deep 55mm ↔ 15 Shallow 40mm)"]
    Block2 --> Block3["4. Block C (3 Trials)<br/>Unsteady Rhythm & Pauses<br/>(80–130 CPM + two 2s pauses)"]
    Block3 --> Analyze["5. Automated Post-Trial Script<br/>(Match Zips ↔ QC Screenshots)"]
```

### 4.1 Pre-Test Setup Checklist
1. **Firmware & App Configuration**:
   - Flash `Model v6` (`DEPTH_MODEL_VERSION = 6`) to the ESP32.
   - Open the CPReady Flutter app on the test tablet/phone:
     - Set **Sensor Mode**: `1-MPU (Chest Only)`.
     - Set **Sensitivity Preset**: `BALANCED` (default) for all 9 core trials.
     - Enable **Save Raw Sensor Samples (`raw.csv`)** in the app workspace settings so every trial exports a complete `.zip` bundle (`session.json`, `metrics.csv`, `raw.csv`, `events.jsonl`).
2. **Manikin & Vest Placement**:
   - Place the **Laerdal Little Anne QC** on a rigid, non-flexing surface (floor or solid lab bench).
   - Secure the CPReady sensor pouch firmly at the center of the sternum (`MPU1`) and verify the cable does not tug during recoil.
3. **Calibration Discipline (Critical Observation from `2928353c`)**:
   - When pressing `START` in the CPReady app, **keep hands completely off the chest (or motionless) during the 2-second `CALIBRATING` banner** until the status switches to `ACTIVE` before starting the first compression on the Laerdal manikin.
4. **Synchronized Start/Stop & Ground-Truth Logging**:
   - Start a fresh session on the **Laerdal QC app** simultaneously with the CPReady session.
   - At the end of each trial, stop both apps immediately, take a **screenshot of the Laerdal QC summary screen** (showing Mean Depth `mm`, Mean Rate `CPM`, Total Compressions, Good Depth `%`, Complete Release `%`), and name the screenshot `BlockA_Run1_QC.jpg`, etc., matching the session notes entered in the CPReady app.

### 4.2 The 9-Trial Verification Matrix

| Block | Purpose | Runs | Target Strokes / Duration | Execution Instructions | Primary Acceptance Criteria |
| :--- | :--- | :---: | :---: | :--- | :--- |
| **Block A: Pure Shallow Compressions** | Verify client feedback that shallow strokes (`35–44 mm`) are detected and not omitted (no artificial upward mean-depth inflation). | **3 runs** (`A1`, `A2`, `A3`) | `50–60 strokes` (~30 s each) | Compress intentionally below the Laerdal 50 mm clicker (`~38–44 mm` on the QC live gauge) at a steady `100–110 CPM`. | 1. **Stroke Capture Rate**: `|Count_CPReady - Count_QC| <= 2` (`>= 96%` capture).<br>2. **Session Mean Depth Error**: `|MeanDepth_CPReady - MeanDepth_QC| <= 3.0 mm`.<br>3. **No Upward Inflation**: CPReady mean depth must correctly read `< 46 mm` (`0%` false `> 55 mm` spikes). |
| **Block B: Deep-to-Shallow Transitions** | Verify that adaptive envelope decay (`Fix E3`) unmasks shallow strokes immediately after deep strokes. | **3 runs** (`B1`, `B2`, `B3`) | `60 strokes` (~35 s each) | Perform **15 normal/deep strokes (`53–58 mm`)**, transition immediately without pausing into **15 shallow strokes (`38–42 mm`)**, repeat once (`15 deep` $\rightarrow$ `15 shallow`). | 1. **Transition Dropout Count**: `<= 1` missed stroke across both deep$\rightarrow$shallow transitions (`|Count_CPReady - Count_QC| <= 2`).<br>2. **Session Mean Depth Error**: `|MeanDepth_CPReady - MeanDepth_QC| <= 2.5 mm`.<br>3. **Bimodal Stroke Distribution**: `metrics.csv` clearly shows two depth clusters (`~55 mm` and `~40 mm`). |
| **Block C: Unsteady Rhythm & Pauses** | Verify `Fixes A, B, C, E` under erratic cadence, hesitation at top of chest, and deliberate hands-off pauses. | **3 runs** (`C1`, `C2`, `C3`) | `60 strokes` (~45 s each) | Start at **slow cadence (`80–85 CPM`, 15 strokes)** $\rightarrow$ **2-second pause** $\rightarrow$ **fast cadence (`120–130 CPM`, 20 strokes)** $\rightarrow$ **2-second pause** $\rightarrow$ **hesitant/alternating cadence (`90–115 CPM`, 25 strokes)**. | 1. **Zero Open-Loop / Pause-Stretch Spikes**: Max single-stroke depth in `metrics.csv` `< 72 mm` (no `78–100 mm` explosions on stroke #1 or post-pause strokes).<br>2. **Zero Dropped Post-Pause Strokes**: `0` strokes with `depth = 0.0 mm`.<br>3. **Session Mean Depth Error**: `|MeanDepth_CPReady - MeanDepth_QC| <= 3.0 mm`. |

### 4.3 Automated Post-Trial Validation & Analysis Workflow
Once the 9 `.zip` exports and 9 Laerdal screenshots are placed in `DATA/v6_validation_trials/`:
1. **Automated Ingestion & Pairing**:
   - Run `CPReady_Program/test_native/ground_truth_verification_suite.py` (extended to ingest `DATA/v6_validation_trials/`).
   - For each trial, extract:
     - **Firmware Live Summary** (`session.json` $\rightarrow$ `mean_depth_mm`, `compression_count`, `mean_rate_cpm`).
     - **Per-Stroke Distribution** (`metrics.csv` $\rightarrow$ min, P5, median, mean, P95, max depth, `0.0 mm` count, and post-pause stroke depths).
     - **Bit-Accurate Python Replay Verification** on `raw.csv` (confirming live firmware telemetry matches offline C++ replay within `±0.1 mm`).
2. **Statistical Metrics Computed Automatically**:
   - **Per-Block and Overall Mean Absolute Error (MAE)**, **Root Mean Squared Error (RMSE)**, **Signed Bias (Mean Error)**, and **Bland-Altman 95% Limits of Agreement (`Bias ± 1.96 SD`)** for:
     - Session Mean Depth (`mm`)
     - Total Compression Count (`strokes`)
     - Session Mean Rate (`CPM`)
   - **Shallow-Stroke Capture Sensitivity (%)** on Blocks A & B (`Detected Shallow Strokes / Laerdal Total Compressions`).
   - **Leave-One-Session-Out Cross-Validation (LOOCV) MAE** across the combined 19-session corpus (`10 historical GT + 9 new v6 validation trials`).
3. **Auto-Generated Defense Tables & Plots**:
   - Update [`RESEARCHER_ERROR_BOUNDS_AND_TUNING_GUIDE.md`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/RESEARCHER_ERROR_BOUNDS_AND_TUNING_GUIDE.md) and regenerate [`RESEARCHER_ERROR_BOUNDS_AND_TUNING_GUIDE.pdf`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/RESEARCHER_ERROR_BOUNDS_AND_TUNING_GUIDE.pdf) with the empirical validation tables.

---

## 5. Thesis Scope, Delimitations & Recommendations for Future Researchers

This section is structured so it can be lifted directly into Chapters 1/5 of the manuscript and defense slides:

### 5.1 Scope and Delimitations of the Present System
1. **Single-Manikin Reference Standard & Display Granularity**:
   - Accuracy benchmarking was conducted against a single **Laerdal Little Anne QC** training manikin. Because the Little Anne QC reports **session-level summary statistics only** (rounded to the nearest `1 mm` and `1 CPM`, with an internal optical sensor tolerance of `±1–2 mm`) and does not export per-stroke displacement waveforms, per-stroke errors are bounded analytically and via cycle-closure invariants rather than against a per-stroke optical/potentiometer trace.
2. **Single-MPU Operational Posture on Rigid-Sternum Manikins**:
   - Empirical correlation analysis of dual-IMU recordings on the Laerdal Little Anne QC demonstrated that the chest pad (`MPU1`) and secondary reference (`MPU2`) vertical accelerations correlate at `r > 0.99` due to the rigid mechanical hinge of the manikin torso. Consequently, the production system operates in a **1-MPU (chest-only)** configuration, which achieves equal or superior depth accuracy (`1.69 mm` MAE across 5 single-MPU sessions) while halving I2C bus contention and eliminating dual-sensor wiring failure modes.
3. **Physical Error Floor of Single-IMU Double Integration (`~1.5–2.5 mm` Session MAE)**:
   - Because an accelerometer measures $\ddot{x}(t)$ rather than absolute position $x(t)$, closed-cycle double integration ($\Delta x \propto \iint a \, dt^2$) is fundamentally bounded by three physical factors that no scalar calibration constant $K$ can eliminate below `~1.5 mm`:
     - **Vest/Pouch Fabric Compliance (`±2.0–3.0 mm`)**: Slight variations in strap tension and hand placement on the soft sensor pouch alter high-frequency impact coupling between trials (`E3`).
     - **Quasi-Periodic Cycle-Closure Assumption**: Closed-cycle zero-mean velocity subtraction assumes each compression starts and ends at the same chest elevation. During highly erratic rhythm or incomplete chest release (leaning), the true net displacement over a single cycle is non-zero ($\Delta x_{\text{net}} \neq 0$), introducing a bounded per-stroke variance (`±3–5 mm`) that averages out over the session summary.
     - **100 Hz I2C Sampling & Gravity Projection Drift**: Dynamic sternal rocking (`3°–5°`) during forceful compressions projects a small horizontal acceleration component onto the calibrated resting gravity axis (`~0.5–1.5 mm` equivalent).

### 5.2 Recommendations for Future Researchers
1. **Hardware Recommendation 1 — Thin Contact / Force Switch on the Compression Pad (`S14`, Highest Impact)**:
   - Integrating a low-profile Force-Sensitive Resistor (FSR) or mechanical dome switch beneath the palm pad provides an exact binary contact/release boundary ($v(t_{\text{contact}}) = 0$, $x(t_{\text{release}}) = 0$). This directly measures **leaning / incomplete chest recoil** (which an accelerometer alone cannot distinguish from constant-velocity rest) and provides exact zero-velocity updates (ZUPT) for unsteady rhythm.
2. **Hardware Recommendation 2 — 6-Axis SPI IMU (`ICM-42688-P` or `BMI270`) at `200–400 Hz` (`S11`, `S13`)**:
   - Replacing the legacy I2C `MPU6050` at `100 Hz` with a modern SPI 6-axis IMU at `200–400 Hz` and fusing the 3-axis gyroscope via a complementary/Madgwick orientation filter will track dynamic sternal tilt (`3°–5°`) during each stroke and eliminate I2C bus stalls.
3. **Hardware Recommendation 3 — Linear Potentiometer / Optical Draw-Wire Reference Rig (`S9`)**:
   - Future cohorts calibrating CPR wearables should instrument the training manikin with an internal linear potentiometer or draw-wire encoder sampled by the same microcontroller so per-stroke ground-truth displacement $x_{\text{ref}}(t)$ is captured alongside `raw.csv`.
4. **Software Recommendation — Offline Zero-Phase (`filtfilt`) Waveform Reconstruction in Companion App (`S1`)**:
   - While real-time coaching on the ESP32 must remain causal, future versions of the mobile companion app can apply a forward-backward zero-phase 4th-order Butterworth high-pass filter (`fc = 0.45 Hz`) to the completed `raw.csv` recording to render a continuous displacement waveform $x(t)$ for visual post-session debriefing.


---

## 6. App-Side Unsteady Rhythm Retroactive Refinement (`R3 + Zero-Phase filtfilt`) & Dynamic Voice Coaching Engine (v1)

Following client feedback that **shallow stroke detection is now performing well** under Firmware Model v6 and that the **remaining accuracy bottleneck is unsteady rhythm**, we implemented a two-layer solution in the Flutter companion app (`FLUTTER/cpready`) supported by diagnostic bitmask extensions in the ESP32 firmware:

### 6.1 Extended Per-Stroke Segmentation Diagnostics in `Byte 11` (`quality_flags`)
Bits `4..7` of `Byte 11` in the 16-byte BLE real-time telemetry packet ([`BLEReadings.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/BLEReadings.h), [`CompressionTracker.h`](file:///c:/Users/reynq/OneDrive/Documents/CPReady/CPReady_Program/include/CompressionTracker.h), [`ble.dart`](file:///C:/Users/reynq/OneDrive/Documents/CPReady/FLUTTER/cpready/lib/src/config/ble.dart), [`cpr_metrics.dart`](file:///C:/Users/reynq/OneDrive/Documents/CPReady/FLUTTER/cpready/lib/src/core/metrics/cpr_metrics.dart)) now report per-stroke causal segmentation diagnostics:

| Bit | Mask | Constant | Diagnostic Meaning |
| :---: | :---: | :--- | :--- |
| `Bit 0` | `0x01` | `CADENCE_FLAG_FIRST_STROKE` | First stroke of session or first stroke after a $> 1.5\text{ s}$ hands-off pause |
| `Bit 1` | `0x02` | `CADENCE_FLAG_STEADY` | Rolling 4-stroke period mean absolute deviation $\le 25\%$ |
| `Bit 2` | `0x04` | `CADENCE_FLAG_BENCH_MODE` | Single-MPU bench mode active (`MPU2` absent) |
| `Bit 3` | `0x08` | `CADENCE_FLAG_RECOIL_ESTIMATED` | Recoil estimated from chest accelerometer proxy |
| `Bit 4` | `0x10` | `CADENCE_FLAG_SUB_PERIOD_BOUNCE` | Raw stroke-to-stroke interval $\Delta t < 300\text{ ms}$ (`rate_cpm = 0` bounce/split candidate) |
| `Bit 5` | `0x20` | `CADENCE_FLAG_WINDOW_CLAMPED` | Closed-cycle integration window hit the `MAX_CYCLE_INTEGRATION_SAMPLES = 66` (`660 ms`) cap |
| `Bit 6` | `0x40` | `CADENCE_FLAG_HESITATION_ONSET` | Onset-to-peak acceleration exceeded `12 samples` (`> 120 ms` hesitation/double-pump push) |
| `Bit 7` | `0x80` | `CADENCE_FLAG_ENVELOPE_UNMASKED` | Adaptive threshold envelope decay (`0.960`) triggered after $> 650\text{ ms}$ idle wait |

### 6.2 Four-Stage Hybrid Retroactive Refinement Engine (`SessionRefinementEngine`)
During every `LivePracticeScreen` and `ManikinCalibrationScreen` session, the app streams the 100 Hz raw accelerometer frames (`TELEM:1`) into a lightweight in-memory ring buffer (`_inMemoryRawSamples`, only writing CSV files to disk when the researcher's *"Record raw sensor data"* toggle is enabled). At session end (`STOP`), [`SessionRefinementEngine.refineSession`](file:///C:/Users/reynq/OneDrive/Documents/CPReady/FLUTTER/cpready/lib/src/core/metrics/session_refinement_engine.dart) executes a 4-stage hybrid pass:

1. **Stage 0 — Self-Calibrated Zero-Phase Forward-Backward (`filtfilt`) Trajectory for Unsteady Strokes**:
   - Pure continuous `filtfilt` integration (`2.11 mm` MAE on its own) suffers from frequency-dependent high-pass filter attenuation across different compression rates (`85–135 CPM`), whereas causal closed-cycle integration (`closedCycleDepthCm`) has flat gain on steady strokes (`1.62 mm` MAE) but suffers from boundary-velocity mismatch ($\Delta v \neq 0$) on unsteady transitions.
   - Stage 0 computes a 2nd-order Butterworth forward-backward zero-phase high-pass ($f_c = 0.55\text{ Hz}$) displacement trajectory $x_{\text{ff}}(t)$, self-calibrates its session gain against the session's steady closed-cycle strokes ($\alpha_{\text{session}} = \text{median}_{k \in \text{steady}}(d_{\text{closed},k} / d_{\text{ff},k})$), and blends `60%` self-calibrated `filtfilt` + `40%` closed-cycle **only on unsteady, window-clamped, or hesitation strokes**.
2. **Stage 1 — Case A (True Split Stroke Merge) vs. Case B (Premature-Cut + Carryover Rebalance)**:
   - **Case A (True Split Stroke)**: When a hesitant release splits one physical compression into two detections with combined period $\Delta t_i + \Delta t_{i+1} \le \max(700\text{ ms}, 1.30\,T_{\text{median}})$, merges them into 1 stroke via full-window closed-cycle re-integration (or root-sum-of-squares energy conservation $\sqrt{d_i^2 + d_{i+1}^2}$).
   - **Case B (Boundary-Shifted Pair)**: When stroke $i$ terminates early ($\Delta t_i < 320\text{ ms}$) and stroke $i+1$ absorbs the carryover ($\Delta t_{i+1} > 700\text{ ms}$, $\Delta t_i + \Delta t_{i+1} \ge 1.55\,T_{\text{median}}$), re-balances both strokes to $\frac{1}{2}(d_i + d_{i+1})$ while preserving the true 2-stroke count.
3. **Stage 2 — 100 Hz Gap Stroke Recovery**:
   - Scans inter-stroke gaps $> 720\text{ ms}$ in the 100 Hz waveform to recover any shallow or hesitant stroke that fell below the causal trigger threshold.
4. **Stage 3 — Local Steady-Median Winsorization**:
   - Clamps any remaining unsteady transition outliers to within $\pm 5.0\text{ mm}$ of the local 5-stroke steady median depth.

#### Benchmark Results Across All 10 Laerdal Ground-Truth Sessions

| Metric | Firmware Model v6 (Causal Live) | Stage 1–3 (`R3` Only) | **4-Stage Hybrid (`R3 + Self-Calibrated filtfilt`)** |
| :--- | :---: | :---: | :---: |
| **10-Session Mean Depth MAE** | `1.62 mm` | `1.36 mm` | **`1.21 mm`** |
| **10-Session Mean Depth RMSE** | `2.16 mm` | `1.88 mm` | **`1.75 mm`** |
| **10-Session Max Depth Error** | `4.95 mm` | `4.34 mm` | **`4.34 mm`** |
| **10-Session Stroke Count MAE** | `1.20 strokes` | `0.50 strokes` | **`0.50 strokes` (`10/10` within `±1`)** |
| **9-Session Mean Rate MAE** | `1.08 CPM` | `0.94 CPM` | **`0.94 CPM`** |

Both `final_summary` (raw ESP32 firmware summary) and `refined_final_summary` (plus `refinement_diagnostics`) are written to `session.json` by [`TelemetryRecorder`](file:///C:/Users/reynq/OneDrive/Documents/CPReady/FLUTTER/cpready/lib/src/core/telemetry/telemetry_recorder.dart) so researchers have complete auditability.

### 6.3 Live Unsteady-Rhythm Banner &App-Side Dynamic Voice Coaching (`LiveCoachingController` v1)
1. **Live Display Notice & Hysteresis**:
   - When 2 consecutive unsteady strokes occur (`AppDurations.liveCadenceWarningPackets = 2`), `LivePracticeScreen` displays:
     > *"Rhythm unsteady — realtime readings may be inaccurate. Accuracy is maintained once session is finalized."*
   - The notice clears after 3 consecutive steady strokes (`AppDurations.liveCadenceClearPackets = 3`), and [`LiveDepthStabilizer`](file:///C:/Users/reynq/OneDrive/Documents/CPReady/FLUTTER/cpready/lib/src/core/metrics/session_refinement_engine.dart) applies a 3-stroke rolling median to the live Depth capsule while unsteady.
2. **App-Side Dynamic Voice Coaching Engine ([`LiveCoachingController`](file:///C:/Users/reynq/OneDrive/Documents/CPReady/FLUTTER/cpready/lib/src/core/audio/live_coaching_controller.dart))**:
   - Coaching cue selection is now performed dynamically in the Flutter app (`CPReadyConfig::ENABLE_AUDIO_COACHING_PROMPTS = false` on the ESP32).
   - **Unsteady-Rhythm Depth Cue Suppression**: Whenever cadence is unsteady, depth cues (`"Compression too shallow"` / `"Compression too deep"`) are suppressed so the trainee is never misled by a single unsteady transition stroke; rate cues (`"Compress faster"` / `"Slow down"`) remain active to stabilize rhythm first.
   - **Note for Future Researchers**: `LiveCoachingController` is designed as a modular v1 baseline with documented constants (`minCorrectiveInterval`, `sameCueRepeatInterval`, `consecutiveFaultThreshold`, `goodStrokeStreakTarget`) ready for human-factors tuning in future studies.
