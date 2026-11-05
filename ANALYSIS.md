# CPReady Field Data Analysis

**Analysis date:** 2026-11-04 (baseline); **Revision 2:** 2026-11-05  
**Data set:** 12 recorded sessions in `DATA/` — 11 baseline sessions (10 complete, 1 interrupted) plus the new `ce67d9d5` capture (2.56 s, interrupted, no compressions)  
**Scope:** diagnose missed compressions, unexpectedly low depth readings, and the new complaint that irregular rhythm makes depth less accurate and more variable  
**Change policy:** analysis only. No firmware, Flutter, Supabase, or configuration source file was modified. This report is the only file changed.

---

## 0. Executive Summary

The original two symptoms have different but connected causes, and Revision 2 adds a third — rhythm-dependent fluctuation:

1. **Missed compressions are overwhelmingly a dual-sensor problem.** In every dual-MPU session the base accelerometer moves almost exactly like the chest accelerometer (`r = 0.978–0.995`, base/chest gain `0.95–0.99`). Firmware subtracts the two signals (`rawNet = -(chest − base)`), so it cancels **roughly 80–90% of the real compression signal**. The remaining differential is mostly noise and is *negatively* correlated with chest motion (`r = −0.13 to −0.25`). Detection therefore falls to 1–65% of the chest-only reference, depending on preset.

2. **The “1.5” reading is 1.58 cm, not 1.5 mm.** `depth_tenths_mm = 158` means 15.8 mm = 1.58 cm. The repeated low value is `158` (12 packets in `343540cf`, 3 in `e5c4ad3a`). Other sessions contain genuine 1.4–1.7 cm values, but none contains a 1.5 mm value. The app conversion is correct; the UI shows `1.58 cm / 15.8 mm`.

3. **Depth behaves badly in both directions.**
   - Dual mode under-reads because the real signal is subtracted away. `343540cf` reports a final 1.80 cm and repeats 1.58 cm for seconds at a time.
   - Single mode drives the depth estimate into the 10.0 cm ceiling. `6ee8938f` clamps on **70 of 70** strokes and reports 10.00 cm; `48011a51` clamps on 69 of 70 and reports 4.00 cm from the one remaining stroke.

4. **The final depth average is not the average of what the user saw.** `validDepthSum` deliberately excludes every stroke at exactly `10.0 cm` (`CompressionTracker.h:532`). If some strokes clamp and some do not, the summary is the mean of only the non-clamped minority. Examples:
   - `848e796c`: 71 of 73 strokes clamp; final 6.59 cm is the mean of the two survivors (`725` and `593`).
   - `48011a51`: 69 of 70 clamp; final 4.00 cm is one stroke.
   - `44c2e739`: 74 of 86 clamp; final 4.22 cm is the mean of 12 strokes.
   - `6ee8938f`: all 70 clamp; the fallback reports 10.00 cm.

5. **Sensitivity presets cannot rescue a cancelled signal.** HIGH is the only dual preset that detects materially above 20% (`49/75`, `53/88`). BALANCED and STRICT fall to 1–38%. STRICT is worst overall because its start floor (`0.12 g`) and recoil-arm floor (`0.07 g`) are at or above the standard deviation of the already-cancelled net signal (`0.054–0.085 g`).

6. **A second, independent depth problem exists even in single mode.** The double integrator plus the default manikin scale (`48.2 / 11.2 = 4.30×`) produces 4–10 cm from normal chest motion, frequently saturating. The runtime `K` is not recorded in any upload, so the relative contribution of `K`, integration boundary conditions, and sensor gain cannot be separated from these files alone.

7. **The upload pipeline hides the evidence needed to diagnose this.** `packets.csv` omits `recoil_status`, no session contains a type-6 config report (`K`, mode, preset, duration), `events.csv` contains only `recording_started`, and `DATA_FORMAT.md` documents the packet types incorrectly.

8. **One session is a separate hardware fault.** `f71deb5f` stopped after 2.73 s with packet type 5, error code 7 (`ERR_I2C_FAULT`). It is not evidence about the detection algorithm.

9. **Revision 2 (2026-11-05): the rhythm complaint is real, and it is a windowing problem.** The new `ce67d9d5` file is only a 2.56 s idle capture with zero compressions, so it cannot validate depth. In a replay of the nine ground-truth sessions through the current tuned model, strokes whose cycle interval is within ±10% of the session median deviate from the session median depth by **3.4 mm on average**; strokes whose interval is ≥20% off deviate by **26.1 mm** — a **7.7× increase in fluctuation**. The mechanism is analysed in §13: irregular cycles change the integration window, the pre-onset dwell included in it, and whether a pause is treated as a pause or as a continuous cycle. The new file does show a much-improved static baseline (chest **0.996 g**, base **1.000 g** versus 1.07–1.15 g / 0.83–0.89 g before), but it contains no compression data.

---

## 1. Data Inventory

The 11 baseline zip archives plus the new 2026-11-05 `ce67d9d5` archive were extracted to `/tmp/opencode/`; the repository `DATA/` directory was left untouched. Each short session ID below corresponds to `DATA/<session-id>-<uuid>.zip`. Each archive contains exactly:

- `raw.csv` — 100 Hz chest/base accelerometer samples
- `packets.csv` — firmware metrics packets
- `events.csv` — app lifecycle events
- `session.json` — metadata and upload counters

### 1.1 Session inventory

| Session | Participant | Experiment | Notes (free text) | Inferred mode / preset | Started (UTC) | Duration | Status |
|---|---|---|---|---|---|---:|---|
| `343540cf` | P005 | 5th test | Dual mpu high | dual / HIGH | 2026-11-04 05:54:49 | 51.83 s | complete |
| `44c2e739` | P012 | 12th test | Single mpu high | single / HIGH | 2026-11-04 06:17:25 | 48.33 s | complete |
| `48011a51` | P009 | 9th test | Single mpu balanced | single / BALANCED | 2026-11-04 06:09:21 | 44.82 s | complete |
| `6ee8938f` | P007 | 7th test | Single mpu strict | single / STRICT | 2026-11-04 06:03:08 | 44.06 s | complete |
| `7c5ea2c3` | P003 | 3rd test | Dual mpu strict | dual / STRICT | 2026-11-04 05:49:19 | 66.02 s | complete |
| `848e796c` | P008 | 8th test | Single mpu strict | single / STRICT | 2026-11-04 06:06:00 | 44.36 s | complete |
| `a4dc7413` | P001 | 1st test | Balanced dual mpu | dual / BALANCED | 2026-11-03 07:35:21 | 38.88 s | complete |
| `e5c4ad3a` | P006 | 6 test | Dual mpu high | dual / HIGH | 2026-11-04 05:57:41 | 48.51 s | complete |
| `e5e68774` | P002 | 2nd test | Dual mpu balanced | dual / BALANCED | 2026-11-03 07:37:32 | 62.66 s | complete |
| `f501e7c8` | P004 | 4th test | Dual mpu strict | dual / STRICT | 2026-11-04 05:52:02 | 44.91 s | complete |
| `f71deb5f` | P003 | 3rd test | Dual mpu balanced | dual / BALANCED | 2026-11-03 07:39:39 | 2.73 s | interrupted |
| `ce67d9d5` | P001 | practice | *(blank)* | single / unknown (base constant 1000 mg) | 2026-11-05 08:50:13 | 2.56 s | interrupted |

Mode and preset are **inferred from the free-text `notes` field**, because no type-6 config report was uploaded. `P003` has two sessions both labelled “3rd test”: `7c5ea2c3` (complete, strict) and `f71deb5f` (interrupted, balanced). The new `ce67d9d5` session has no notes and no config report; it is identified from its raw stream only.

### 1.2 Sampling health

| Session | Raw rows | Sample index range | Median dt | p99 dt | Max dt |
|---|---:|---|---:|---:|---:|
| `343540cf` | 5,184 | 0–5183 | 10.00 ms | 10.0 ms | 11 ms |
| `44c2e739` | 4,834 | 0–4833 | 10.00 ms | 11.0 ms | 11 ms |
| `48011a51` | 4,483 | 0–4482 | 10.00 ms | 10.0 ms | 10 ms |
| `6ee8938f` | 4,407 | 0–4406 | 10.00 ms | 10.0 ms | 10 ms |
| `7c5ea2c3` | 6,592 | 0–6601 | 10.00 ms | 11.0 ms | 109 ms |
| `848e796c` | 4,437 | 0–4436 | 10.00 ms | 10.0 ms | 10 ms |
| `a4dc7413` | 3,889 | 0–3888 | 10.00 ms | 10.0 ms | 10 ms |
| `e5c4ad3a` | 4,842 | 0–4851 | 10.00 ms | 10.0 ms | 110 ms |
| `e5e68774` | 6,267 | 0–6266 | 10.00 ms | 11.0 ms | 11 ms |
| `f501e7c8` | 4,492 | 0–4491 | 10.00 ms | 11.0 ms | 11 ms |
| `f71deb5f` | 264 | 0–263 | 10.00 ms | 40.0 ms | 50 ms |
| `ce67d9d5` | 257 | 0–256 | 10.00 ms | 10.0 ms | 10 ms |

**The 100 Hz sampling loop is healthy.** The only 100+ ms gaps are the two 10-sample dropouts discussed in §7.1. The new 2.56 s session is clean at exactly 10.00 ms. There is no evidence of systematic BLE loss, CPU starvation, or sampling-rate collapse.

### 1.3 The new `ce67d9d5` session (2026-11-05)

This archive is not a compression trial. It is a **2.56 s idle capture** that ends with a zeroed final summary. Its purpose in this revision is to check whether the static/calibration problem improved, not to evaluate rhythm or depth accuracy.

| Property | Value |
|---|---:|
| Raw rows | 257 (indices 0–256) |
| Duration | 2.561 s |
| Frames | 26 |
| Packets | 13 × type 1 (realtime), 1 × type 4 (final summary) |
| Packet sequence | 7–20, no gaps |
| Event log | only `recording_started` |
| Status | `interrupted` (the app rejects a `completed` session with 0 compressions) |
| Final summary | rate 0, depth 0, CCF 0, compressions 0, quality flags 9 |
| Chest static magnitude | **0.996 g** |
| Base static magnitude | **1.000 g** |
| Chest dynamic SD | 0.028 g |
| Base dynamic SD | 0.000 g |

The chest stream contains a small, highly periodic 33 Hz dither (z alternates 968 / 996 / 1037 mg; x alternates −16 / −2 / 18 mg). The base stream is constant at 1000 mg on all three axes. This is not physiological compression motion. It is either a stationary device with a high-frequency sensor/board artifact or a synthetic idle test. The dither amplitude is below every preset’s start threshold, so **zero detections is the correct outcome**.

The positive finding is that the static magnitudes are now very close to 1 g, versus 1.07–1.15 g on the chest and 0.83–0.89 g on the base in the baseline data. That is consistent with a calibration/gain fix. The negative finding is that the file contains **no compression, no depth, no recoil, and no config report**, so it cannot support the claim that depth or rhythm tracking is now better. It also still uses `schema_version: 1` and the old `raw.csv` header without `unclamped_depth_mm`, `recoil_status`, or a type-6 config packet.

---

## 2. Method

Because the true calibration baseline (`K`, profile, preset) was not uploaded, the firmware pipeline was reconstructed offline from `raw.csv`:

1. Parse `raw.csv` at 100 Hz.
2. Compute each sensor’s static vector and dynamic vertical signal by projecting onto its resting gravity direction, matching `GravityAxis::dynamicG`.
3. Low-pass filter the net signal with `alpha = 0.25`, matching `SensorManager.h`.
4. Re-implement the `CompressionTracker` state machine: adaptive start threshold, refractory lockout, RECOILING arm, finish threshold, 2 s watchdog, pause timeout, and depth gate.
5. Re-implement `DepthEstimator::closedCycleDepthCm` / `fromRestDepthCm`: mean removal, double Riemann integration with true `dt`, and `×980.665` to centimetres.
6. Apply the same preset constants used by `applySensitivityPreset`.
7. Compare the reconstructed counts/depths with the recorded packets and final summary.

The reconstruction scripts were scratch-only under `/tmp/opencode/` and were deliberately not added to the repository, consistent with the analysis-only constraint.

**Important limitations**

- The “chest-only replay” used as a reference is the *same detector* run on chest motion with the base contribution removed. It is not an independent ground truth. It is a best-case reference showing what the detector can see when the signal is not cancelled.
- Per-stroke depth was inferred from the first live packet carrying a new `total_compressions` value. If that stroke had no measurable depth (`depthKnown == false`), the packet repeats the previous `reading.depth_cm`; those values are stale rather than that stroke’s depth. This affects a small number of strokes and is itself evidence for §4.4.
- Runtime `K` is unknown. Values in this report are consistent with the default `DEPTH_CALIBRATION_K = 48.2` and `NOMINAL_INTEGRATOR_K = 11.2` (4.30×), but the absence of a config packet means a different calibrated `K` cannot be ruled out.

---

## 3. Headline Results

### 3.1 Missed compressions

“Chest-only replay” is the number of strokes the same detector finds when the base signal is replaced by zero. “Retained” is recorded strokes divided by that reference.

| Session | Mode / preset | Firmware strokes | Chest-only replay | Retained | Median detected interval | Gaps > 1.5 s | Actual average rate* | Reported final rate |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `343540cf` | dual / HIGH | 53 | 88 | **60%** | 0.60 s | 7 | 67.5 cpm | 82 cpm |
| `e5c4ad3a` | dual / HIGH | 49 | 75 | **65%** | 0.70 s | 3 | 70.8 cpm | 78 cpm |
| `a4dc7413` | dual / BALANCED | 20 | 53 | **38%** | 0.90 s | 6 | 45.2 cpm | 80 cpm |
| `e5e68774` | dual / BALANCED | 1 | 97 | **1%** | — | 0 | 0 cpm | 0 cpm |
| `7c5ea2c3` | dual / STRICT | 5 | 102 | **5%** | 4.50 s | 4 | 6.0 cpm | 0 cpm |
| `f501e7c8` | dual / STRICT | 8 | 69 | **12%** | 1.80 s | 6 | 16.9 cpm | 52 cpm |
| `44c2e739` | single / HIGH | 86 | 103 | 83% | 0.60 s | 0 | 107.8 cpm | 99 cpm |
| `48011a51` | single / BALANCED | 70 | 73 | 96% | 0.60 s | 0 | 101.2 cpm | 101 cpm |
| `6ee8938f` | single / STRICT | 70 | 70 | 100% | 0.60 s | 0 | 104.5 cpm | 105 cpm |
| `848e796c` | single / STRICT | 73 | 71 | 103% | 0.60 s | 0 | 104.6 cpm | 104 cpm |
| `f71deb5f` | dual / BALANCED | 2 | 4 | (too short) | 1.17 s | 0 | 51.3 cpm | none |

\* Average of detected intervals only; missed strokes bias this upward or downward depending on which strokes survive. The chest-only replay is a plausibility reference and may itself overcount noise, especially in single mode.

**Key observations**

- **Single mode detects normally.** 70–86 strokes in 44–48 s at ~100–108 cpm, with no gaps over 1.5 s. Preset choice barely matters.
- **Dual mode detects a preset-dependent fraction.** HIGH retains 60–65%, BALANCED 1–38%, STRICT 5–12%.
- **Across the six complete dual sessions, only 136 of 484 chest-only reference strokes were retained (28%).** The four single sessions retained 299 of 317 (94%) by the same reference.
- **The failure is not a global detector failure.** The same detector sees 53–102 strokes in the same dual recordings when the base term is removed. Those counts imply 82–102 cpm across all six complete dual sessions — physiologically consistent with the 100–108 cpm seen in the single sessions, whereas the recorded dual rates of 0–71 cpm are not.
- **The retained dual strokes are not a random sample.** Detection favours the largest residual artifacts, so the surviving strokes have unstable depths (§3.2).

### 3.2 Depth

Final summary values are the type-4 packet `depth_tenths_mm`; 100 units = 1.00 cm = 10.0 mm.

| Session | Final raw value | Final cm | Final mm | Strokes at 10.0 cm ceiling | Median non-clamped stroke | Basis of final average |
|---|---:|---:|---:|---:|---:|---|
| `343540cf` | 180 | **1.80 cm** | 18.0 mm | 2 / 53 | 1.44 cm | mean of 51 non-clamped (179.6) |
| `44c2e739` | 422 | 4.22 cm | 42.2 mm | 74 / 86 | 4.09 cm | mean of 12 non-clamped (421.7) |
| `48011a51` | 400 | 4.00 cm | 40.0 mm | 69 / 70 | 4.00 cm | one non-clamped stroke |
| `6ee8938f` | 1000 | **10.00 cm** | 100.0 mm | 70 / 70 | none | fallback cumulative mean (10.0) |
| `7c5ea2c3` | 315 | 3.15 cm | 31.5 mm | 2 / 5 | 2.67 cm | mean of 3 non-clamped (314.7) |
| `848e796c` | 659 | 6.59 cm | 65.9 mm | 71 / 73 | 6.59 cm | mean of 2 survivors (725, 593) |
| `a4dc7413` | 302 | 3.02 cm | 30.2 mm | 0 / 20 | 2.56 cm | 19-stroke subset (first excluded) |
| `e5c4ad3a` | 224 | 2.24 cm | 22.4 mm | 0 / 49 | 1.70 cm | all 49 strokes (224.1) |
| `e5e68774` | 439 | 4.39 cm | 43.9 mm | 0 / 1 | 4.39 cm | single detected stroke |
| `f501e7c8` | 331 | 3.31 cm | 33.1 mm | 3 / 8 | 2.91 cm | 4-stroke subset |
| `f71deb5f` | none | — | — | 1 live packet | — | no final summary |

**Depth is not a single bug.** The dual sessions under-read; the single sessions run into the 10 cm ceiling. Both are explained by the signal path, not by a unit conversion.

### 3.3 What the user sees live vs at the end

Live packets repeat the most recent `reading.depth_cm` at 5 Hz; they are not independent per-stroke means. Counts below are packets, not strokes.

| Session | Live packets | Packets showing 10.00 cm | Share |
|---|---:|---:|---:|
| `343540cf` | 280 | 7 | 2.5% |
| `44c2e739` | 274 | 225 | 82.1% |
| `48011a51` | 253 | 245 | 96.8% |
| `6ee8938f` | 247 | 244 | 98.8% |
| `7c5ea2c3` | 333 | 126 | 37.8% |
| `848e796c` | 250 | 242 | 96.8% |
| `a4dc7413` | 203 | 0 | 0% |
| `e5c4ad3a` | 264 | 0 | 0% |
| `e5e68774` | 311 | 0 | 0% |
| `f501e7c8` | 228 | 56 | 24.6% |
| `f71deb5f` | 15 | 1 | 6.7% |

This table is the direct explanation for “the summary says 4.22 cm but the live screen was mostly 10.0 cm.”

---

## 4. Root Causes

**Ranking for the reported symptoms**

| Rank | Cause | Explains |
|---|---|---|
| 1 | RC-1 dual subtraction cancels the chest signal | Missed strokes in every dual session; 1.5–3 cm dual depth |
| 2 | RC-3 preset thresholds exceed the cancelled signal | Why STRICT/BALANCED miss more than HIGH |
| 3 | RC-2 clamp + valid-depth selection | Erratic final averages and 10.00 cm summaries |
| 4 | RC-5 invalid static calibration / co-moving base | Enables RC-1; gain and tilt error |
| 5 | RC-4 stale depth + cm/mm display | The specific “1.5” observation and lingering values |
| 6 | RC-6 telemetry/doc gaps | Prevents verification; not a measurement cause |
| 7 | RC-7 I2C fault | One interrupted session only |

### RC-1 — Dual-sensor differential subtraction cancels the real compression signal (primary)

**Where:** `SensorManager.h:703–710`

```cpp
float aChestG = chestAxis.dynamicG(chest);
float aBaseG  = baseAxis.dynamicG(base);
float rawNet  = -(aChestG - aBaseG);
```

This is correct only if the base sensor is a *stationary reference*. In these recordings it is not. It moves with the chest.

**Evidence — dual sessions**

| Session | Chest SD (g) | Base SD (g) | Net SD (g) | Net / chest | Chest–base correlation | Base/chest gain | Net–chest correlation |
|---|---:|---:|---:|---:|---:|---:|---:|
| `343540cf` | 0.583 | 0.578 | 0.060 | **10.2%** | 0.995 | 0.987 | −0.13 |
| `7c5ea2c3` | 0.515 | 0.505 | 0.070 | **13.6%** | 0.991 | 0.972 | −0.21 |
| `a4dc7413` | 0.413 | 0.408 | 0.085 | **20.7%** | 0.978 | 0.966 | −0.16 |
| `e5c4ad3a` | 0.465 | 0.458 | 0.054 | **11.7%** | 0.993 | 0.978 | −0.19 |
| `e5e68774` | 0.333 | 0.323 | 0.062 | **18.7%** | 0.982 | 0.954 | −0.25 |
| `f501e7c8` | 0.641 | 0.626 | 0.085 | **13.2%** | 0.991 | 0.969 | −0.24 |
| `f71deb5f` | 0.480 | 0.474 | 0.083 | **17.2%** | 0.985 | 0.973 | −0.16 |

The base signal is not merely correlated; it is nearly a scaled copy of the chest signal. Subtracting it removes most of the motion. The residual is only 10–21% of chest SD and is *negatively* correlated with chest motion, so it is not a usable depth signal.

**Why this explains both symptoms**

- The detector sees a signal roughly 5–10× smaller than the real chest motion, so start/recoil thresholds are crossed rarely or erratically.
- The depth integrator sees the same small residual. Even after the 4.30× default scale, `343540cf` lands at 1.80 cm instead of a plausible 5 cm.
- The stronger strokes survive preferentially, so the retained subset is biased toward high-amplitude artifacts. That is why dual averages are not simply 10–20% of the chest-only average.

**Hardware interpretation:** the base MPU is probably mounted on the same moving pad/backboard, or the “base” fixture flexes with the chest. A backboard reference must be mechanically independent of the compressing surface. This is a mounting/placement issue first and a firmware issue second.

### RC-2 — Depth clamps at 10 cm, then the summary excludes the clamped strokes

**Where:** `CompressionTracker.h:496–501`, `:532–537`, `:747–750`

```cpp
reading.depth_cm = physicalDepthCm * depthScale();
if (reading.depth_cm > CPReadyConfig::DEPTH_MAX_LIMIT_CM) {
    reading.depth_cm = CPReadyConfig::DEPTH_MAX_LIMIT_CM;
}
...
if (depthKnown && reading.depth_cm < CPReadyConfig::DEPTH_MAX_LIMIT_CM) {
    validDepthSum += reading.depth_cm;
    validStrokeCount++;
}
...
s.avg_depth_cm = (validStrokeCount > 0) ? (validDepthSum / validStrokeCount)
               : (cumulativeDepthCount > 0) ? (cumulativeDepthSum / cumulativeDepthCount)
               : 0.0f;
```

Two distinct failures follow:

1. **Saturation:** any per-cycle estimate above 10 cm is silently replaced by 10 cm. The user cannot tell a true 10 cm from a 15 cm artifact.
2. **Selection bias:** exactly-10.0 values are then excluded from `validDepthSum`. The final average is computed over the non-clamped minority. If *every* stroke clamps, the fallback uses `cumulativeDepthSum`, which contains the clamped values, and reports 10.00 cm.

**Exact examples**

- `848e796c`: 71 of 73 strokes clamp. The two survivors are `725` (7.25 cm) and `593` (5.93 cm). Final = `(725 + 593) / 2 = 659` → 6.59 cm. The user performed ~70 compressions; the summary describes two.
- `48011a51`: 69 of 70 clamp. The only survivor is `400`; final = 4.00 cm. One stroke defines the session average.
- `44c2e739`: 74 of 86 clamp. The 12 survivors average 421.7 → 4.22 cm.
- `6ee8938f`: 70 of 70 clamp. `validStrokeCount == 0`, so the fallback reports 10.00 cm.
- `343540cf`: only 2 of 53 clamp; final 1.80 cm is a genuine average of 51 low values, not a clamp artifact.

This is a **reporting bug**, not a detector bug, but it makes the depth output look erratic and untrustworthy.

### RC-3 — Preset thresholds are large relative to the cancelled net signal

**Where:** `CompressionTracker.h:302–325`, `:591–601`

| Preset | Start floor | Adaptive fraction | Recoil-arm fraction | Recoil-arm floor | Min stroke depth |
|---|---:|---:|---:|---:|---:|
| HIGH | 0.05 g | 0.22 | 0.10 | 0.025 g | 0.15 cm |
| BALANCED | 0.08 g | 0.30 | 0.15 | 0.040 g | 0.25 cm |
| STRICT | 0.12 g | 0.40 | 0.25 | 0.070 g | 0.50 cm |

The dual net signal has SD **0.054–0.085 g**. In STRICT:

- the start floor `0.12 g` is **1.4–1.7 SD** above the mean, so only the extreme tail triggers;
- the recoil-arm floor `0.07 g` is at or above the net SD in `7c5ea2c3` (0.070) and `e5e68774` (0.062), so the RECOILING state often never arms;
- without arming, the stroke times out after 2 s, and no depth is recorded.

This quantitatively explains the STRICT counts (`5/102`, `8/69`) without needing any additional bug. HIGH lowers the start floor to `0.05 g` and the arm floor to `0.025 g`, which is why it is the only dual preset that reaches 60–65%.

**Preset is a modifier, not the root cause.** Even HIGH loses 35–40% of dual strokes. Removing the base subtraction should raise all presets together.

### RC-4 — Stale depth and the cm/mm display make 1.58 cm look like “1.5 mm”

**Where:** `CompressionTracker.h:494–503`, `cpr_metrics.dart:145–146`, `metrics_card.dart:31–35`

```dart
depthCm: depthTenths / 100.0,
depthMm: depthTenths / 10.0,
```

The conversions are correct:

- `158` → `1.58 cm` and `15.8 mm`
- `180` → `1.80 cm` and `18.0 mm`
- `1000` → `10.00 cm` and `100.0 mm`

The UI displays both units side by side: `1.58 cm / 15.8 mm`. The “1.5 mm” phrasing almost certainly comes from reading the mm field as the primary value or from truncating `1.58` to `1.5`.

**Where the 1.5-range values occur**

- `343540cf` (dual HIGH): `158` appears 12 times. Per-stroke values include stroke 2 = 158 and stroke 29 = 158. Final 1.80 cm. Neighbouring values (141–156) are also present.
- `e5c4ad3a` (dual HIGH): `158` appears 3 times at the first stroke. Final 2.24 cm. Values 140–170 occur throughout.
- `a4dc7413` (dual BALANCED): values 146–154 occur, final 3.02 cm.
- Single sessions do not contain 15.x values; their non-clamped depths are 283–725.
- Minimum non-clamped depth in the entire corpus is `76` → **7.6 mm = 0.76 cm**. There is no 1.5 mm sample.

**Why it lingers:** `reading.depth_cm` is only updated when `depthKnown == true`. There is no `else` that resets it. When a stroke is detected but has no measurable depth, the next 5 Hz packets keep repeating the previous value. Combined with missed detections, the display can sit at `158` for seconds. This is a display/staleness issue, not a second source of low depth.

### RC-5 — Static sensor vectors are outside the expected 1 g range, and the alignment check is too weak

Median static magnitudes across the recordings:

| Session | Chest static magnitude | Base static magnitude |
|---|---:|---:|
| `343540cf` | 1.086 g | 0.862 g |
| `7c5ea2c3` | 1.082 g | 0.852 g |
| `a4dc7413` | 1.129 g | 0.887 g |
| `e5c4ad3a` | 1.100 g | 0.868 g |
| `e5e68774` | 1.121 g | 0.880 g |
| `f501e7c8` | 1.120 g | 0.888 g |
| `f71deb5f` | 1.127 g | 0.888 g |
| Single sessions | 1.070–1.103 g | 0 (unused) |

Both sensors should read ~1.000 g at rest. The chest is 7–13% high; the base is 11–15% low. This points to accelerometer bias/scale error, mounting pre-load, or an incorrect static calibration window. It also explains why a simple scalar-z alignment check is not sufficient:

- `isCalibrationStable()` compares `fabs(chestGravityOffset − baseGravityOffset)` against `0.35 g` (`SensorManager.h:655–659`).
- The observed difference is ~0.21–0.24 g, so it passes.
- But that check compares only the scalar z average, not the full vector, and it cannot detect a base sensor that is mechanically co-moving.

**Consequence:** calibration accepts a dual setup that is not a valid differential pair. This enables RC-1.

### RC-6 — Telemetry and documentation gaps prevent verification

These do not cause the physio measurements, but they make diagnosis much harder and can mislead future analysis:

| Gap | Evidence | Effect |
|---|---|---|
| `recoil_status` missing from CSV | Firmware packet has it (`BLEReadings.h`); the header in `telemetry.dart:62–65` and the row writer in `telemetry_recorder.dart:187` omit it | Recoil compliance cannot be analyzed from uploads |
| No type-6 config report | All 10 complete sessions contain only types 1 and 4; `f71deb5f` contains 1 and 5 | Runtime mode, preset, `K`, profile, and duration are unknown |
| `events.csv` only has start | All 12 files contain only `recording_started` | No stop/interrupt/error context |
| Packet type map wrong in docs | `DATA_FORMAT.md` says 4 = calibration_progress, 5 = calibration_ready; firmware says 4 = final summary, 5 = error, 6 = config | Offline tools will misread the final summary |
| `quality_flags` width wrong | Docs say uint16; firmware uses uint8 | Binary parsing risk |
| Base Z described as +1000 mg | Observed 847–888 mg in dual sessions | Offline gravity removal is wrong |
| Offline replay formula incomplete | Docs use `-(chest_z − base_z)` with no gravity projection or offset removal | Replay drifts and cannot reproduce firmware |
| `depth_tenths_mm` described as “mean depth” | Live packets carry the latest stroke depth, repeated at 5 Hz | Users/tools treat repeated values as independent strokes |
| `session.json` counters inconsistent | Gap sessions: `missing_samples = 9` but 10 indices missing; `sample_count = rows + 1`. Across sessions, `frame_count` is 1–2 higher than the number of distinct frames | Integrity checks under-report gaps |

### RC-7 — Isolated I2C fault in `f71deb5f` (separate issue)

`f71deb5f` ended after 2.73 s. Its only non-realtime packet is type 5 with error code 7, which maps to `ERR_I2C_FAULT` (`BLEReadings.h:46`). It contains 264 raw samples, 15 live packets, one live depth at 10.00 cm, and no final summary. This is a hardware/bus reliability event, not evidence about compression detection. It should be tracked separately.

---

## 5. Session-by-Session Notes

Every archive was parsed and inspected. The short notes below highlight what each contributes to the diagnosis.

- **`343540cf` (P005, dual HIGH)** — Highest dual stroke count (53/88, 60%) but still misses 35 strokes. Net/chest 10.2%, net–chest correlation −0.13. Final depth 1.80 cm with repeated 1.58 cm values. This is the clearest “low depth” case: the signal is cancelled, not mis-scaled by the app.
- **`44c2e739` (P012, single HIGH)** — Detection is fine (86 strokes, 108 cpm). 74/86 strokes clamp at 10 cm; final 4.22 cm is the mean of 12 survivors. Live packets show 10.00 cm 82% of the time. Demonstrates the summary-selection bug.
- **`48011a51` (P009, single BALANCED)** — 70 strokes, 69 clamp. Final 4.00 cm is one stroke. The most extreme example of “one survivor defines the average.”
- **`6ee8938f` (P007, single STRICT)** — 70/70 strokes clamp; final 10.00 cm via fallback. Detection is perfect, depth output is useless. This isolates the depth saturation problem from detection.
- **`7c5ea2c3` (P003, dual STRICT)** — 5 detected strokes in 66 s, final rate 0, CCF 0, depth 3.15 cm from 3 non-clamped strokes. Chest-only replay finds 102. STRICT thresholds sit above the cancelled net SD. Also has a 10-sample gap.
- **`848e796c` (P008, single STRICT)** — 73 strokes, 71 clamp; final 6.59 cm is the mean of two survivors. Also has one packet sequence gap (`303 → 305`) that is not reflected in any integrity counter.
- **`a4dc7413` (P001, dual BALANCED)** — 20/53 (38%), no clamps, final 3.02 cm, per-stroke CV 55% (113–750). Shows that even when clamping is absent, the dual depth is unstable.
- **`e5c4ad3a` (P006, dual HIGH)** — 49/75 (65%), no clamps, final 2.24 cm, per-stroke CV 75% (76–944). Best illustration of residual noise producing wild depth swings. Has a 10-sample gap.
- **`e5e68774` (P002, dual BALANCED)** — 1/97 detection (1%). Final 4.39 cm and rate/CCF 0 come from a single stroke. The worst missed-compression case.
- **`f501e7c8` (P004, dual STRICT)** — 8/69 (12%), reported rate 52 cpm from a short burst while average detected rate is 17 cpm. 3/8 clamp; final 3.31 cm from 4 valid strokes. Shows how rate ignores >1.5 s gaps.
- **`f71deb5f` (P003, dual BALANCED)** — Interrupted by I2C fault at 2.73 s. No final summary. Not usable for algorithm comparison.

---

## 6. Why Detection Fails in Dual Mode — The Mechanism

The detector is a state machine with five conditions that must all be satisfied:

1. **Start:** filtered net acceleration must exceed `startThreshold()`.
2. **Compress:** it must later go negative.
3. **Recoil:** it must swing below `recoilArmLevel()` to arm the exit.
4. **Finish:** it must then rise above `STROKE_FINISH_THRESHOLD_G = −0.02`.
5. **Depth gate:** the integrated depth must exceed `minStrokeDepthCm`.

In dual mode, the net signal is small and not phase-locked to the chest:

- The start threshold is crossed mostly by noise bursts.
- The recoil swing is often too small to arm, so the stroke times out.
- When a stroke does complete, the integrated depth may fall below the preset minimum, so it is discarded.
- The surviving strokes are the largest residual artifacts, which is why their depth values are erratic.

This is why simply lowering thresholds (HIGH preset) improves detection but does not fix it: it detects more noise, not more real compressions. The correct fix is to restore a meaningful chest signal, not to keep lowering thresholds.

### Thresholds vs signal, quantitatively

For a zero-mean residual with SD `σ`, a start floor `T` is exceeded on only a small fraction of samples. Approximate one-sided tail probabilities:

| Session | Net SD | STRICT start floor | Floor / SD | Approx. tail | Observed retention |
|---|---:|---:|---:|---:|---:|
| `7c5ea2c3` | 0.070 g | 0.12 g | 1.71 | ~4% | 5% |
| `f501e7c8` | 0.085 g | 0.12 g | 1.41 | ~8% | 12% |
| `e5e68774` | 0.062 g | 0.08 g (BAL) | 1.29 | ~10% | 1% |
| `a4dc7413` | 0.085 g | 0.08 g (BAL) | 0.94 | ~17% | 38% |
| `343540cf` | 0.060 g | 0.05 g (HIGH) | 0.83 | ~20% | 60% |
| `e5c4ad3a` | 0.054 g | 0.05 g (HIGH) | 0.93 | ~18% | 65% |

The tail estimate is only a sanity check, not a model of the state machine, but the broad ordering matches: the stricter floors (0.12 g and 0.08 g) produce the lowest retention, while the HIGH floors produce the highest. `e5e68774` is the outlier (1% retention despite a 10% start tail); its recoil-arm stage is failing even when a start occurs.

---

## 7. Data Integrity and Metadata

### 7.1 Raw sample gaps

Two sessions have a real 10-sample gap:

| Session | Missing indices | Actual missing | `session.json` says | Frame sequence gap | Consistent? |
|---|---|---:|---:|---|---|
| `7c5ea2c3` | 6220–6229 | 10 | 9 | 622 → 624 | **No** |
| `e5c4ad3a` | 1150–1159 | 10 | 9 | 115 → 117 | **No** |

For both, the JSON `sample_count` is one higher than the number of CSV rows, and `missing_samples` is correspondingly one lower; `last_sample_index` is correct. The upload counter appears to count one extra sample, so integrity reports understate loss by one when a gap occurs. This does not affect the algorithm (the firmware never saw those samples).

`848e796c` has a packet sequence gap (`303 → 305`) with no corresponding note or counter. No other session has a packet gap.

### 7.2 Clipping

The raw accelerometer occasionally hits the ±4 g range limit:

| Session | Chest clipped samples | Base clipped samples |
|---|---:|---:|
| `343540cf` | 10 | 5 |
| `f501e7c8` | 5 | 1 |
| `6ee8938f` | 2 | 0 |

Clipping is rare and localized, but it can inflate a single stroke’s integrated depth. It is not the main cause of the 10 cm clamp (the single sessions with 70/70 clamps have zero or two clipped samples).

### 7.3 Metadata mismatches

- `events.csv` has only `recording_started` in all 12 sessions. There is no `recording_stopped`, `interrupted`, or error event, even for `f71deb5f` or `ce67d9d5`.
- `packets.csv` has no `recoil_status`, despite the firmware packet containing it.
- No type-2/3 calibration-progress packets and no type-6 config report were recorded. Either calibration happened before recording started, or the app does not record those types.
- `session.json` has no final metrics block; the only final depth/rate/CCF is in the type-4 packet. Offline tools must parse `packets.csv` to recover the summary.

### 7.4 Documentation errors in `supabase/DATA_FORMAT.md`

| Documented | Actual firmware / data |
|---|---|
| Type 2 = `final_summary` | Type 2 = calibration progress |
| Type 3 = `error` | Type 3 = calibration success |
| Type 4 = `calibration_progress` | Type 4 = final summary |
| Type 5 = `calibration_ready` | Type 5 = error |
| (no type 6) | Type 6 = config report |
| `quality_flags` uint16 | uint8 |
| Base Z ≈ +1000 mg | 847–888 mg observed |
| Net = `-(chest_z − base_z)` | Must project onto gravity axis and remove static magnitude/offset |
| `depth_tenths_mm` = mean depth | Live packets carry the latest stroke depth; final packet carries the session mean |
| `events.csv` includes stop/interrupted | Only `recording_started` present |

These mismatches are enough to make an offline replay produce different counts and depths from the firmware. Any future analysis should treat `DATA_FORMAT.md` as stale until corrected.

---

## 8. What Is Not the Cause

To avoid chasing the wrong fix:

- **Not the sample rate.** All full sessions sample at 10.00 ms median; p99 is 10–11 ms. The 2.7 s `f71deb5f` fragment has a 40 ms p99 because it ended during a fault.
- **Not BLE throughput.** Only two 10-sample gaps and one packet gap exist in ~49,700 samples.
- **Not the app’s unit conversion.** `depthCm = tenths / 100`, `depthMm = tenths / 10` is correct. 158 is 1.58 cm / 15.8 mm.
- **Not a universal detector failure.** Single-mode sessions detect 70–86 strokes at plausible rates.
- **Not CCF or rate as independent bugs.** Both are downstream of missed strokes and pause handling. They become meaningless when only 1–8 strokes are detected.
- **Not battery/CPU.** No evidence in the raw timing or flags.
- **Not the depth clamp alone.** The clamp explains the summary bias, but not the 1.58 cm dual readings or the 1% detection rate.

---

## 9. Recommended Next Steps (No Code Changes Yet)

These are diagnostic and design actions, ordered by information gain.

### 9.1 Prove or disprove the base-motion hypothesis

1. Run one controlled dual session with the base MPU rigidly mounted to a **stationary backboard/floor**, not the chest pad or a flexible surface.
2. Run one session with the base MPU disconnected / dual mode disabled (`USE_DUAL_MPU = false`) as a control.
3. Compare, for the same participant and cadence:
   - chest SD vs base SD,
   - chest–base correlation,
   - net/chest ratio,
   - detected strokes,
   - final depth.

**Decision gate:** dual subtraction is viable only if base–chest correlation drops well below ~0.8 and net/chest rises above ~50%. If the base still co-moves, dual subtraction should not be used for depth or detection.

### 9.2 Instrument the depth pipeline before changing it

Record, per stroke, in the upload:

- raw integrated depth **before** `depthScale()` and before the clamp,
- runtime `depthCalibrationK`, profile, mode, and preset,
- `depthKnown`,
- net peak/trough,
- whether the stroke was post-pause,
- `recoil_status`.

Without the pre-clamp value and `K`, it is impossible to tell whether the 10 cm clamp comes from over-integration, a high `K`, or a genuine deep compression.

### 9.3 Fix the summary aggregation semantics

The final average should be defined explicitly. Reasonable options:

- average all measured strokes, including clamped values, and separately report a `clamped_count`;
- exclude clamped strokes but report `valid_strokes / total_strokes` alongside the average;
- never let the fallback silently report 10.00 cm when all strokes clamped.

The current behavior produces a number that looks like a session average but is actually a selected-subset average.

### 9.4 Re-evaluate the default manikin `K`

The single-mode data is consistent with the default 4.30× scale, but 69–70 of 70 strokes clamp in two sessions. To reach 10 cm after that scale, the unscaled integral must be at least ~2.3 cm per cycle for nearly every stroke. A controlled manikin trial with a known target depth (e.g. 5.0 cm) should be used to check whether `K` is too high, whether the integrator over-reads on sharp transients, or both.

### 9.5 Fix the telemetry contract

- Add `recoil_status` to `packets.csv`.
- Record type-6 config reports.
- Record stop/interrupt/error events in `events.csv`.
- Correct `DATA_FORMAT.md` packet types, widths, base Z, and replay formula.
- Fix the off-by-one in `missing_samples`, `sample_count`, and `frame_count`.

These changes do not alter device behavior, but without them every future field analysis will repeat this reconstruction work.

### 9.6 Track `f71deb5f` separately

The I2C fault is a hardware/bus reliability issue. Check the PCA9548A channel wiring, pull-ups, and connector seating. Do not use this session to evaluate the detection algorithm.

---

## 10. Verification Checklist

Use this to reproduce the conclusions:

- [ ] Extract each zip to a scratch directory; confirm four files per session.
- [ ] Parse `raw.csv` and verify `sample_index` is monotonic except for the two documented gaps.
- [ ] Compute each sensor’s static vector and dynamic vertical signal using the gravity projection, not raw Z.
- [ ] Compute chest SD, base SD, net SD, chest–base correlation, and base/chest gain for every dual session. Expect net/chest 10–21% and `r ≥ 0.978`.
- [ ] Replay the detector on chest-only and on differential net. Expect the counts in §3.1.
- [ ] Parse type-4 packets and confirm the final depths in §3.2.
- [ ] For each stroke, take the first live packet with a new `total_compressions`; count values at exactly `1000`.
- [ ] Confirm the final average equals the mean of non-clamped strokes in `848e796c` (725, 593), `44c2e739` (12 values), `48011a51` (400), and the fallback in `6ee8938f`.
- [ ] Search all packets for values in `[140, 170]`; confirm `158` maps to 15.8 mm and that no value of `15` (1.5 mm) exists.
- [ ] Confirm `f71deb5f` has type 5 / code 7 and no type 4.
- [ ] Confirm `ce67d9d5` has 257 rows, zero strokes, a zeroed type-4 summary, chest static magnitude ≈0.996 g, and base static magnitude ≈1.000 g.
- [ ] Replay the nine ground-truth sessions through the tuned model and confirm that strokes with interval deviation ≥20% from the session median have a much larger absolute depth deviation than strokes within ±10%.

---

## 11. Source Reference Map

| Concern | File / lines |
|---|---|
| Stroke state machine, detection, depth gate | `CPReady_Program/include/CompressionTracker.h:327–560` |
| Preset thresholds | `CPReady_Program/include/CompressionTracker.h:302–325` |
| Start / recoil thresholds | `CPReady_Program/include/CompressionTracker.h:591–601` |
| Depth scale (K / reference K) | `CPReady_Program/include/CompressionTracker.h:563–570` |
| Depth clamp | `CPReady_Program/include/CompressionTracker.h:496–501` |
| Valid-depth selection | `CPReady_Program/include/CompressionTracker.h:532–537` |
| Final summary average | `CPReady_Program/include/CompressionTracker.h:747–750` |
| Double integration | `CPReady_Program/include/DepthEstimator.h:63–141` |
| Gravity projection | `CPReady_Program/include/GravityAxis.h:41–58` |
| Differential net signal | `CPReady_Program/include/SensorManager.h:703–710` |
| Calibration alignment check | `CPReady_Program/include/SensorManager.h:621–660` |
| Thresholds, clamps, sampling | `CPReady_Program/include/CPReadyConfig.h:55–94`, `:126–152` |
| Packet type constants | `CPReady_Program/include/BLEReadings.h:22–46` |
| Recoil byte in packet | `CPReady_Program/include/BLEReadings.h:133–180` |
| App depth conversion | `FLUTTER/cpready/lib/src/core/metrics/cpr_metrics.dart:145–146` |
| App depth display | `FLUTTER/cpready/lib/src/widgets/metrics_card.dart:31–35` |
| CSV recorder | `FLUTTER/cpready/lib/src/core/telemetry/telemetry_recorder.dart:182–193` |
| Stale telemetry docs | `supabase/DATA_FORMAT.md:55–110` |

---

## 12. Bottom Line

- **If the goal is to stop missing compressions:** fix the dual-sensor reference. The current base sensor is measuring the same motion as the chest, so the differential signal is mostly noise. No threshold tuning will recover a signal that has been subtracted away.
- **If the goal is to fix the 1.5 cm reading:** the value is real in the sense that the firmware computed 1.58 cm, but it is not the participant’s compression depth. It is what remains after roughly 80–90% of the chest signal is cancelled. The app is displaying it correctly.
- **If the goal is to fix the 10 cm readings:** the integrator plus the default 4.30× scale is saturating, and the summary then hides the saturated strokes. That is a separate depth-pipeline problem that also needs a controlled calibration trial.
- **Before changing any algorithm:** run the base-mount control experiment in §9.1 and capture the pre-clamp depth plus runtime `K` in §9.2. Without those two pieces of evidence, threshold or `K` changes would be guesses.

---

## 13. Revision 2 — New Session and Rhythm Sensitivity (2026-11-05)

### 13.1 The new `ce67d9d5` file is an idle capture, not a rhythm trial

`ce67d9d5-8ac5-43d9-8e85-1c31f106345d` is 2.56 s long and contains **zero compressions**. It has 257 raw samples, 26 frames, 13 realtime packets, and one type-4 final summary. The final summary reports rate 0, depth 0, CCF 0, compressions 0, and quality flags 9. The app marks it `interrupted` because a session with no compressions cannot be `completed`; that status is an app semantic, not evidence of a crash.

The useful finding is the static baseline:

| Metric | Baseline dual sessions | Baseline single sessions | New `ce67d9d5` |
|---|---:|---:|---:|
| Chest static magnitude | 1.066–1.148 g | 1.108–1.148 g | **0.996 g** |
| Base static magnitude | 0.834–0.894 g | 0 (unused) | **1.000 g** |
| Chest dynamic SD | 0.333–0.639 g | 0.438–0.581 g | 0.028 g |
| Base dynamic SD | 0.324–0.626 g | 0 | 0.000 g |
| Detected strokes | 1–103 | 70–86 | 0 |
| Final depth | 1.8–4.39 cm | 4.00–10.00 cm | 0 |

The chest stream contains a highly periodic 33 Hz dither (z alternates 968 / 996 / 1037 mg; x alternates −16 / −2 / 18 mg). The base is constant at 1000 mg on all axes. This is not physiological chest motion. It is consistent with a stationary device and a small high-frequency sensor/board artifact, or with a synthetic idle test. The dither is below every preset’s start threshold, so zero detections is the correct result.

The new file therefore supports one narrow conclusion: **the static calibration/gain mismatch is much better than in the baseline sessions.** It does not validate compression depth, stroke detection, or rhythm tracking, because it contains no compression at all. It also still uses `schema_version: 1` and the old `raw.csv` header, with no `unclamped_depth_mm`, no `recoil_status`, and no type-6 config report. It cannot confirm which `K`, preset, or firmware model produced it.

### 13.2 What the rhythm complaint means in this pipeline

The user’s observation is specific: **the less steady the rhythm, the less accurate the depth and the more the number moves.** That is not a separate sensor failure. It is the expected consequence of three design choices:

1. depth is integrated over a window whose start and end are both detected from the waveform;
2. the window is allowed to include up to a fixed 220 ms of pre-onset data;
3. the live number is the most recent stroke, not a robust average.

When the rhythm is steady, the window is approximately one cycle and the boundary assumptions hold. When the rhythm is irregular, the window length, the amount of idle dwell inside it, and the fraction of the cycle represented by the fixed pre-onset cap all change. The double integral then returns a different depth for the same physical compression.

### 13.3 Replay method

To isolate the algorithm from the old dual-sensor cancellation, the nine complete sessions with Laerdal ground truth were replayed through the current tuned chest-only model described in `GROUND_TRUTH_ANALYSIS.md`:

- `DEPTH_CALIBRATION_K = 10.85`
- `NOMINAL_INTEGRATOR_K = 11.20`
- `MAX_PRE_ONSET_INTEGRATION_SAMPLES = 22`
- each session’s recorded preset (`STRICT`, `BALANCED`, or `HIGH`)

For each detected stroke, the replay records the detected cycle interval and the pre-clamped scaled depth. “Regular” means the interval is within ±10% of that session’s median interval. “Irregular” means it is at least 20% away from the median. This within-session comparison controls for preset, participant, and session-level amplitude.

This is a replay of the **current tuned model**, not the firmware that produced the baseline archives. It is valid for exposing how the algorithm reacts to timing; it is not a reconstruction of the old device’s exact per-stroke output.

### 13.4 Result: irregular cycles fluctuate about 7.7× more

Trial numbers below match the `DATA/organized_trials/` folders.

| Trial | Preset | GT mean depth | Replay mean depth | Error | Interval CV | Depth CV | Irregular strokes | Irregular mean depth |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `01` | BALANCED | 46 mm | 51.4 mm | +5.4 mm | 12.2% | 30.0% | 3 | 85.1 mm |
| `04` | STRICT | 54 mm | 54.4 mm | +0.4 mm | 10.2% | 12.4% | 2 | 31.1 mm |
| `05` | STRICT | 57 mm | 57.7 mm | +0.7 mm | 4.8% | 7.9% | 0 | — |
| `06` | HIGH | 60 mm | 59.4 mm | −0.6 mm | 7.5% | 12.2% | 1 | 15.9 mm |
| `07` | HIGH | 59 mm | 57.0 mm | −2.0 mm | 5.8% | 12.5% | 1 | 48.0 mm |
| `08` | STRICT | 54 mm | 57.0 mm | +3.0 mm | 17.3% | 9.3% | 5 | 50.9 mm |
| `09` | STRICT | 57 mm | 53.8 mm | −3.2 mm | 7.3% | 9.3% | 1 | 38.8 mm |
| `10` | BALANCED | 58 mm | 57.8 mm | −0.2 mm | 7.6% | 15.6% | 1 | 100.0 mm |
| `11` | HIGH | 51 mm | 52.3 mm | +1.3 mm | 13.0% | 29.2% | 5 | 88.3 mm |

Across all 652 usable replay strokes:

- strokes within ±10% of the session median interval deviate from the session median depth by **3.36 mm on average**;
- strokes at least 20% away from the median interval deviate by **26.14 mm on average**;
- that is a **7.7× increase in per-stroke fluctuation** for the same nominal compression task.

The irregular group is small (19 strokes), so the exact ratio should not be treated as a calibration constant. But the direction is unambiguous, and the examples are exactly the user’s symptom: the irregular strokes produce both very high values (`10` → 100.0 mm, `11` → 88.3 mm, `01` → 85.1 mm) and very low values (`06` → 15.9 mm, `04` → 31.1 mm, `09` → 38.8 mm). The number swings in both directions rather than simply reading low.

At the session level, the correlation between interval CV and absolute depth error is **r = 0.42**, and between interval CV and depth CV is **r = 0.38** across the nine sessions. Those correlations are moderate rather than strong because only nine sessions are available and depth amplitude, preset, and detection differences also vary. The within-session comparison is the stronger evidence because it holds those session-level factors fixed.

### 13.5 Root causes of the rhythm sensitivity

#### RC-8 — The integration window is rhythm-dependent

The closed-cycle depth is integrated from a start index to a detected stroke-end index. The start is bounded by:

```text
cycleStart = max(lastStrokeEndSampleIndex, onsetSampleIndex - 22)
```

The end is the sample where recoil is considered complete. The double integrator subtracts the mean acceleration so that velocity returns to zero at the end of the window, then subtracts the mean velocity so that displacement returns to its starting level. That correction is only valid if the window represents **exactly one complete cycle**.

With a steady rhythm the window is close to one cycle, so the boundary correction is approximately correct. With an irregular rhythm:

- a short cycle makes the fixed 22-sample pre-onset cap a larger fraction of the cycle;
- a long cycle or a pause makes it a smaller fraction, and the window may include idle dwell;
- a late or early onset detection shifts both the start and the apparent cycle length;
- a late recoil completion shifts the end;
- a missed onset makes the next window span two or more cycles, with no period-plausibility check to reject it.

At 100–120 cpm, one cycle is 50–60 samples. The fixed 22-sample cap is therefore roughly 37–44% of a normal cycle. A timing change of only a few samples is a several-percent change in the integration window, which is enough to move the depth by millimetres. This is the core reason the reading is rhythm-sensitive even when the physical compression depth is unchanged.

#### RC-9 — The 1.5 s pause test is a cliff

The tracker classifies a stroke as post-pause when:

```text
raw_period_ms > 1500
```

A 1.4 s pause is treated as a continuous cycle and can include idle motion in the integration window. A 1.6 s pause switches to the from-rest path, which requires a stable rest estimate; if rest is unstable, the code falls back to a shorter window. The estimate can therefore jump discontinuously as the pause crosses 1.5 s, even if the physical compression is identical.

The earlier ground-truth work already measured the dwell effect: integration across 180–400 ms of top-of-chest dwell inflated depth by roughly +5.2 to +7.2 mm on several trials. Capping the pre-onset window at 22 samples reduced that bias, but it did not remove the dependence on where the pause falls relative to the cap. A fixed threshold also cannot distinguish “slow but continuous CPR” from “stopped and restarted.”

#### RC-10 — The live display shows the last stroke, not a robust average

Even in the tuned replay, per-stroke depth CV ranges from **7.9% to 30.0%**. The live telemetry packet repeats the most recent depth, and the 5 Hz heartbeat repeats that same value. A single bad stroke therefore looks like a sustained reading for several packets. The final summary may average the session, but the number the user watches during the session is the noisiest one.

The rate and CCF have the same issue. Rate is a median of the last three periods; with an irregular rhythm that median jumps as soon as one long or short interval enters the window. CCF is computed from detected strokes and periods, so missed or irregular strokes change it. The user sees depth, rate, and CCF move together and reasonably concludes that “unsteady rhythm makes the readings inaccurate.”

#### RC-11 — Dual mode amplifies every rhythm error

In the baseline dual sessions, missed strokes are already common because the differential signal cancels most of the chest motion. A missed stroke makes the next closed-cycle window span multiple cycles, which is the same failure mode as an irregular rhythm but much more frequent. The packet also repeats the previous depth when the current stroke has no valid depth, so a missed or invalid stroke can leave a stale value on screen.

The new `ce67d9d5` file does not exercise this path: it has no compressions and the base is static. The dual-mode amplification therefore remains a baseline finding; it is not validated or cleared by the new file.

### 13.6 Why the session-level correlation is only moderate

The rhythm effect is real, but it is not the only source of error:

- only nine sessions have complete ground truth;
- ground truth provides a mean depth, not a per-stroke depth, so per-stroke “error” is measured against the session median rather than a true per-stroke reference;
- preset and participant differ across sessions;
- a physically unsteady rhythm usually also changes compression amplitude, and the device cannot separate “timing changed the window” from “the person actually compressed shallower”;
- the replay uses the current tuned model, not the historical firmware, and the baseline archives were recorded with a different `K`/clamp behavior;
- the irregular group has only 19 strokes, so the 7.7× ratio has wide uncertainty.

The correct interpretation is therefore: **the replay demonstrates a strong mechanism and a large within-session effect, not a precise population estimate.** It is enough to explain the complaint and to justify a controlled rhythm test; it is not enough to pick a new threshold by itself.

### 13.7 What to measure next

A controlled rhythm protocol would settle the remaining ambiguity without guessing:

1. Use one manikin and one target depth (for example 5.0 cm) at three rates: 80, 100, and 120 cpm.
2. For each rate, record both a metronome-steady run and an intentionally irregular run with 10–30% period jitter and occasional 0.5–1.5 s pauses.
3. Record per-stroke: detected interval, pre-onset window length, post-pause flag, pre-clamp depth, scaled depth, clamp flag, preset, and `K`.
4. Compare depth MAE, per-stroke depth CV, and clamp rate between steady and irregular runs at the same target depth.

Acceptance test: if irregular runs have more than about twice the per-stroke depth CV of steady runs at the same true depth, the windowing explanation is confirmed. If they do not, the residual is likely amplitude variation or a detector miss rather than the integrator.

Algorithm directions that follow from this analysis — not implemented here:

- validate the detected period against the recent median and reject or re-anchor windows that span more than one cycle;
- replace the fixed 1.5 s pause cliff with a pause test relative to the recent median period (for example, greater than two median periods);
- use a median of the last three valid stroke depths for the live display instead of the last stroke;
- make the pre-onset window proportional to the detected period rather than a fixed 22 samples;
- report a rhythm/validity flag so the app can show “unstable rhythm” instead of silently showing a noisy number;
- keep chest-only as the depth source of truth; the base sensor is a reference only after it passes a stationarity check.

### 13.8 Revised bottom line for Revision 2

- The new `ce67d9d5` capture shows a **clear static-calibration improvement** (chest 0.996 g, base 1.000 g) and no false strokes or false 10 cm clamp, but it contains **zero compressions**. It cannot be used to claim that depth or rhythm accuracy is fixed.
- The rhythm complaint is supported by the replay: irregular cycles produce **7.7× larger per-stroke depth deviation** than regular cycles, with swings in both directions. The dominant mechanism is the rhythm-dependent integration window, reinforced by the fixed 1.5 s pause test and the last-stroke live display.
- The remaining problem after calibration is therefore **segmentation and display robustness**, not just sensor noise. The next useful data set is a controlled steady-versus-irregular trial at a known depth, with the per-stroke fields listed in §13.7.
- No firmware, Flutter, Supabase, or configuration source file was modified in this revision. Only this analysis file was changed.
