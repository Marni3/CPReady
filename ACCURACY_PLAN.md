# CPReady Measurement Accuracy Plan

**Document type:** Engineering and research plan (proposal, not a change record)
**Status:** Draft for review — no firmware, app, or database change is proposed as already done here
**Scope:** Compression depth, rate, count, recoil, and CCF as reported by the vest and the app, measured against a manikin reference
**Companions:** `ANALYSIS.md` (diagnosis), `GROUND_TRUTH_ANALYSIS.md` (manikin mapping and replay), `RESEARCHER_ERROR_BOUNDS_AND_TUNING_GUIDE.md` (parameter sensitivity tables), `ALGORITHM_REFINEMENT_REPORT.md` (how the current estimator was designed)

---

## 0. How to read this document

This plan is written for whoever picks up the accuracy work next.

Three things are deliberately separated, because they are usually conflated:

1. **What is measurably wrong** (Section 2–3). Evidence, not opinion.
2. **What could be changed** (Section 5). Every option, including the ones that are probably not worth it.
3. **What must be decided before anything is changed** (Section 10). A register of questions, each with the assumption that will be used if nobody answers.

If only one section is read, read Section 0.1. If only two, read 0.1 and 4.

### 0.1 Summary of the position

- Absolute **mean depth** accuracy on the nine reference sessions is already inside the clinical band that matters for coaching: in-sample MAE **1.88 mm**, RMSE 2.49 mm, bias +0.54 mm over 667 compressions. That number is real but **optimistic**, because the two tuned parameters were selected on the same nine sessions. Refitting one scalar and holding out one session at a time raises MAE to about **2.4 mm** with a worst session of **5.6 mm** (Section 2.3).
- The nine reference sessions are **underpowered** for the claims people want to make. The 95 % confidence interval on the mean bias is roughly **±2 mm**. An improvement smaller than ~2 mm cannot be demonstrated with n = 9 (Section 7.6). More tuning on this corpus will produce numbers, not knowledge.
- The **mean is not the main defect any more**. The user-visible problems are event-level: a split trigger that produced 1.16 cm then 8.09 cm on consecutive strokes, a 1.013 s sampling stall that manufactured a pause and a 0.00 cm stroke, first-stroke depths of 0.00 / 7.81 / 3.20 cm where the session median was ~5.1–5.4 cm, and a final summary that averages every non-zero stroke including those outliers (Section 2.5).
- **Re-analysing the existing dataset as a whole is worth doing, but it will not by itself make the device more accurate.** It can remove selection bias from tuning and it can support one genuinely structural change — reconstructing the whole recording's displacement instead of windowing each stroke. It cannot create per-stroke ground truth, and per-stroke ground truth is what the remaining error is hiding behind (Section 4).
- The highest-value next step is **not** another parameter sweep. It is a **frozen replay harness plus a reference-instrumented trial protocol**, then **low-risk event-level firmware fixes**, then the estimator change, in that order (Section 6).

---

## 1. What "accuracy" means for this device

### 1.1 The five reported quantities

| Quantity | Produced by | Consumption | Unit / resolution |
|---|---|---|---|
| Depth | `DepthEstimator` double integration, scaled by `K / 11.2` | Live display, coaching cues, summary | cm, packet carries tenths of mm; clamp at 10.0 cm |
| Rate | Median of the last 3 valid periods | Live display, coaching | cpm, integer in packet |
| Count | Stroke state machine | Summary, CCF | integer (16-bit in protocol v2) |
| Recoil | Acceleration-based estimate, flagged `RECOIL_ESTIMATED` | Summary percentage | percent at session end, boolean per stroke |
| CCF | Active compression time / session time | Summary | percent |

Only **depth** has a continuous physical reference on the manikin. Rate and count are derived from the same event stream, so any segmentation error corrupts all three at once. That coupling is why a single split trigger can look like a depth problem, a rate problem, and a count problem simultaneously.

### 1.2 Metric set that should be used from now on

The published work has reported mainly "session mean depth MAE". That single number hid the defects that users actually noticed. The following set is proposed as the standing scorecard. Each metric has a defined unit of analysis, because mixing them is how optimistic numbers get produced.

| ID | Metric | Unit of analysis | Definition | Proposed target |
|---|---|---|---|---|
| M1 | Depth bias | session | mean(reported) − mean(reference) | \|bias\| ≤ 3 mm |
| M2 | Depth MAE | session, then averaged with equal session weight | mean over sessions of \|bias_s\| | ≤ 3 mm |
| M3 | Depth RMSE | session | as above, squared | ≤ 4 mm |
| M4 | Worst-session depth error | session | max_s \|bias_s\| | ≤ 6 mm |
| M5 | Per-stroke depth deviation | stroke, within session | SD of per-stroke depth / session mean (CV) | ≤ 12 % steady, ≤ 18 % irregular |
| M6 | Gross depth outliers | stroke | fraction of strokes < 30 mm or > 70 mm on a 50 mm target | < 1 % |
| M7 | Stroke count error | session | reported − reference | ≤ 1 stroke per 30 |
| M8 | Rate error | session | reported − reference | ≤ 2 cpm |
| M9 | Live discontinuity | stroke-to-stroke | count of adjacent live depths differing by > 15 mm | 0 per session |
| M10 | Unmeasured-stroke honesty | stroke | fraction of displayed 0.00 cm that were **not** flagged unknown | 0 |
| M11 | Stall detection | session | sampling gaps > 50 ms with no flag | 0 |
| M12 | Good-depth fraction agreement | session | \|model % ≥ 50 mm − reference % ≥ 50 mm\| | ≤ 5 points |

M5–M12 are the metrics that separate "the average is right" from "the device is right". They are all computable from data that already exists except M12, which needs the reference's good-depth percentage (already present on the Laerdal screenshots for the nine reference trials).

### 1.3 Reference uncertainty is part of the error budget

The Laerdal Little Anne QC reports mean depth to the nearest millimetre, computed by its own spring/optical mechanism and rounded before display. The device's own tolerance is not published. Two consequences follow, and they should be stated in any accuracy claim:

- A reported MAE below roughly 1–2 mm is at or below the resolution of the reference and should not be claimed as device accuracy.
- Comparisons are meaningful in **millimetres**, not tenths. The packet's 0.1 mm resolution is a transport format, not a measurement capability.

---

## 2. What the data currently shows

### 2.1 Corpus inventory

Seventeen session archives exist in `DATA/`. What they contain, and what can be concluded from each:

| Group | Sessions | Sensor | Firmware state | Reference available | Usable for |
|---|---|---|---|---|---|
| Reference trials | `01`, `04`–`11` (9 sessions) | 2-MPU (`01`, `04`–`07`), 1-MPU (`08`–`11`) | Pre-v5, `K` per session | Laerdal screenshot: strokes, mean depth, rate, good-depth %, release % | Absolute accuracy, tuning, held-out validation |
| Partial reference | `02` | 2-MPU | Pre-v5 | Screenshot exists, depth/rate below the fold | Count only, and only weakly |
| Aborted | `03` | 2-MPU | Pre-v5 | none | I2C fault evidence only |
| Old schema, no reference | `2928353c` | 1-MPU | stale `K = 48.2` | none | Failure demonstration (74/77 strokes clamped) |
| Schema 2, no reference | `3f74e948`, `af47d3f5`, `b6d1fe73`, `8f4e8e4c` | 1-MPU, `depth_k = 10.85` | v5 | none | Event-level behaviour, stability, telemetry validation |
| Idle capture | `ce67d9d5` | 2-MPU | current | none | Static calibration, false-stroke rejection |

**Nine sessions carry a depth reference. They are all from one manikin, one vest, and a small number of testers over two days.** No held-out mount, tester, manikin, or foam condition exists in the corpus. This is the single most important limitation in this document, and Section 7 is written around it.

### 2.2 Headline accuracy (in-sample)

Production model v5 (`DEPTH_CALIBRATION_K = 10.85`, `MAX_PRE_ONSET_INTEGRATION_SAMPLES = 22`), 1-MPU chest-only replay:

| Metric | Value |
|---|---|
| Sessions / compressions | 9 / 667 |
| Depth bias | +0.54 mm |
| Depth MAE | 1.88 mm |
| Depth RMSE | 2.49 mm |
| Worst session | +5.43 mm (`01`, shallowest reference at 46 mm) |
| Stroke count MAE | 0.78 strokes (max 2) |
| Rate MAE | 1.60 cpm (max 3.91) |

These reproduce `RESEARCHER_ERROR_BOUNDS_AND_TUNING_GUIDE.md` §3 and are the numbers to beat — with the caveat below.

### 2.3 The honesty adjustment: these are in-sample numbers

`K` and `MAX_PRE` were both chosen by minimising error on these same nine sessions. Reporting that minimum as expected field accuracy is selection bias. Because reported depth is exactly proportional to `K` (`d = d_phys · K / 11.2`), the effect of the scalar can be re-derived without a new replay:

- Refit a single scale factor on eight sessions by minimising MAE (the weighted median of reference/replay ratios), then predict the ninth.
- Repeat for all nine.

Result: **leave-one-session-out MAE ≈ 2.4 mm, worst held-out session 5.6 mm** (`01`). In-sample 1.88 mm is therefore about 25–30 % optimistic for a *single* tuned scalar. `MAX_PRE`, the four preset parameters, and the `HIGH`-preset recoil arming were also selected on this corpus, so the true optimism of the full configuration is larger than that.

Two further statistical facts belong here:

- The per-session signed errors are `+5.43, +0.44, +0.72, −0.65, −2.00, +3.05, −3.18, −0.21, +1.26` mm. SD = 2.58 mm, so the 95 % CI on mean bias is **≈ [−1.4, +2.5] mm**.
- Those residuals are **not** a function of depth. Two sessions at the same 54 mm reference land at `+0.44` and `+3.05` mm. A single global gain cannot remove that; it is a per-session or per-mount term (Section 3, E3).

**Implication:** the corpus can certify "within a few millimetres, no depth-dependent trend", but it cannot certify a 1 mm improvement, and it cannot distinguish v5 from a v6 tuned on the same rows.

### 2.4 What the residual actually looks like

Three patterns are visible in the per-session errors and should drive the next experiments:

1. **Session-level offsets of ±3 mm** with the same nominal procedure. Consistent with mount angle, pad compression, strap tension, or foam break-in differing between sessions.
2. **Bias sign clusters by day/topology**, not by depth: the four 1-MPU reference sessions span `+3.05 … −3.18` mm. If the estimator were the dominant error, the sign would follow technique; instead it follows the physical setup.
3. **The worst case is the shallowest session** (46 mm reference, +5.43 mm), which is the direction that matters clinically: a shallow compression is the one the coach must not over-report. This deserves a dedicated shallow-depth trial rather than an explanation.

### 2.5 Event-level accuracy — what the mean hides

From the schema-2 uploads (no reference, but self-consistent telemetry):

| Session | Strokes | Mean per-stroke depth | CV | Strokes < 35 mm or > 65 mm |
|---|---:|---:|---:|---|
| `3f74e948` | 61 | 51.3 mm | 13.9 % | 2 (stroke 22 = 11.6 mm, stroke 23 = 80.9 mm) |
| `8f4e8e4c` | 111 | 52.3 mm | 5.6 % | 0 |
| `af47d3f5` | 86 | 54.1 mm | 8.0 % | 1 (first stroke = 78.1 mm) |
| `b6d1fe73` | 115 | 51.4 mm | 9.3 % | 2 (first = 32.0 mm, last = 15.5 mm) |

The `3f74e948` pair is a single compression split into a 11.6 mm fragment and an 80.9 mm follow-on 0.8 s later; both carried `quality_flags = 9`, i.e. the "steady rhythm" bit. That is the archetype of the remaining defect: **the average survives, the moment does not.** The same session's mean moves by only +0.17 mm if the pair is removed, which is exactly why mean-depth metrics never caught it.

`b6d1fe73` contains the corpus's only sampling discontinuity: `t_us` jumps by 1.013 s while `sample_index` advances by one and `frame_sequence` does not change. A frame-loss check cannot see it, so the app reports `missing_samples: 0`. The detector experiences it as a 1.504 s pause, emits a 0.00 cm stroke, and the final stroke is truncated at 15.5 mm.

### 2.6 Detection accuracy

- **2-MPU trials are not a depth problem at all.** Chest and base channels correlate at r = 0.978–0.995, and the differential retains only 10–21 % of the chest amplitude. The base sensor is mechanically coupled to the chest plate through the manikin's spring/hinge assembly. Subtraction is therefore actively destructive on this hardware, and no tuning of `K` fixes it. Counts of 5/103 and 8/69 are the signature.
- **1-MPU detection is now close.** Count MAE 0.78 strokes across nine sessions, with errors at burst boundaries and post-recoil ringing.
- **Jitter costs accuracy only when it changes the window.** `ANALYSIS.md` §13 measured ~7.7× larger per-stroke depth deviation on irregular cycles than steady ones. That is the empirical case for the estimator change in Section 5.1.

### 2.7 An unused second constraint the corpus already contains

Each reference screenshot reports **good-depth percentage** as well as mean depth. Mean depth alone cannot distinguish "every stroke 55 mm" from "half at 45, half at 65". Good-depth % can, roughly, because it is the fraction of strokes above the manikin's depth threshold (nominally 50 mm).

Checked against the schema-2 per-stroke distributions, the model's implied fraction ≥ 50 mm is broadly consistent with the reference's good-depth % at similar means:

| Reference mean / good-depth % | Comparable no-reference session | Model % ≥ 50 mm |
|---|---|---|
| 51 mm / 59 % (`11`) | `3f74e948` (51.3 mm) | 62.3 % |
| 54 mm / 77 % (`04`) | `b6d1fe73` (51.4 mm) | 78.3 % |
| 54 mm / 80 % (`08`) | `af47d3f5` (54.1 mm) | 88.4 % |
| 57 mm / 97 % (`05`) | `8f4e8e4c` (52.3 mm) | 79.3 % |

This is encouraging but **not a validation**: the sessions are different people on different days, and the manikin's threshold and its own per-stroke measurement are not the same quantity as ours. It is, however, the cheapest available distributional check and should be added to the scorecard (M12) for every future reference trial. If a future change tightens the per-stroke distribution without moving the mean, M12 will catch it and M1 will not.

### 2.8 Data-integrity facts that constrain any analysis

- Sampling interval is exactly 10.00 ms in the schema-2 sessions (p1/p99 = 9.99/10.01 ms). The old schema shows 9.0–11.0 ms. The ±2 % jitter bound in the tuning guide is therefore pessimistic for current firmware and optimistic for old captures — do not pool them for timing analysis.
- `raw.csv` schema 2 carries `unclamped_depth_mm` per sample, and `packets.csv` carries per-stroke `recoil_status`. Old-schema rows carry neither, and the old `depth_tenths_mm` is post-clamp, so old and new sessions are not directly comparable at event level.
- In the old schema, 74 of 77 strokes in `2928353c` clamped at 10.0 cm, and the reported 5.04 cm is the mean of the three non-clamped strokes, i.e. the three shortest intervals. Any analysis that treats old-schema summary depth as a measurement is wrong.
- `packets.csv` repeats the current depth on every frame. Counting rows as strokes inflates n by 2–4× and biases the per-stroke distribution toward long-dwell strokes. Strokes must be counted on `total_compressions` increments or on `stroke` events.

---

## 3. Error budget

The purpose of this table is to stop the next optimisation from chasing whichever term is easiest to measure. Magnitudes are best estimates from the cited evidence, not joint fits.

| ID | Source | Mechanism | Approx. magnitude | Character | Mitigation today | Residual |
|---|---|---|---|---|---|---|
| E1 | Window truncation | Fixed 22-sample pre-onset cap clips a slow downstroke, or admits top-of-chest dwell | −3 to +7 mm | stroke, rate-dependent | `MAX_PRE = 22` | dominant on irregular/slow strokes |
| E2 | Closed-cycle assumption | Stroke body not returned to start (leaning in/out, drift) | ~25 % of the lean change on that stroke | stroke | zero-mean `ā`, `v̄` | unmeasured, unbounded |
| E3 | Mount and foam gain | Pad compliance, strap tension, angle, foam break-in change effective `K` per mount | ±3 mm session bias | session | one global `K`, manikin calibration | the ±3 mm session offsets in §2.3 |
| E4 | Sensor scale error | MPU-6050 clones ±3 % sensitivity | ±3 % of depth (≈1.7 mm at 55 mm) | device | none | constant per device |
| E5 | Gravity projection residual | Calibration tilt estimate imperfect; chest rotates during compression | ~0.5–1.5 mm | slow drift | `GravityAxis` projection | small |
| E6 | Timing | True-Δt integration, 10 ms quantisation | 0.3–0.7 mm | random | per-sample `t_us` | small |
| E7 | Quantisation | 0.1 mm transport, 1 mm reference rounding | ±0.5 mm | random | none | floor |
| E8 | Clamp | 10.0 cm ceiling destroys stroke value | up to 50 mm on affected strokes | stroke | removed by `K = 10.85` in 1-MPU | live only in old device state |
| E9 | Summary selection | Mean of every non-zero stroke, including post-pause and truncated strokes | 0.2–0.6 mm on 60–120 stroke sessions; unbounded on short sessions | session | v5 counts all non-zero | real but second-order |
| E10 | Segmentation split/merge | One compression becomes two strokes or two become one | 10–70 mm on affected strokes, ~0.2 mm on session mean | stroke | recoil arm, min-depth gate | the visible defect |
| E11 | Clock/sampling stall | 1.013 s jump with no index discontinuity | one false pause, one 0.00 cm stroke | event | none | unhandled |
| E12 | Reference uncertainty | Manikin internal sensor + 1 mm rounding | 1–2 mm | reference | none | the accuracy floor |
| E13 | Analysis weighting | Stroke-weighted pooling favours 103-stroke sessions over 52-stroke ones | up to ~1 mm on aggregate metrics | analysis | none | must be fixed in the harness |

Reading the budget: E1, E3 and E10 are the only terms at or above 3 mm, and they are respectively **algorithmic**, **mechanical**, and **segmentation**. E4/E6/E7 together are below 2 mm and are not worth engineering effort until the first three are addressed. No amount of `K` tuning touches E1, E2, E10, E11 or E13.

---

## 4. Whole-dataset re-analysis versus fixed-length per-stroke windows

This is the central methodological question, and it is really three questions wearing one sentence. They have different answers.

### 4.1 The three readings

| Reading | What it means concretely | Verdict |
|---|---|---|
| **(a) Fit parameters on the whole corpus rather than per-session** | One global `K`, one global `MAX_PRE`, one preset table, validated across sessions instead of tuned per recording | **Good, already done, and incomplete.** It must be reported out-of-sample. In-sample corpus fitting is what produced the 1.88 mm headline. |
| **(b) Compute depth over the whole recording at once instead of per stroke** | One continuous double integration of the session, drift removed by a zero-phase high-pass, then per-cycle peak-to-trough amplitude | **The most promising remaining structural idea.** Directly attacks E1/E2. Must be prototyped offline and validated before it goes near firmware. |
| **(c) Use the dataset as a whole to derive per-stroke truth or a learned correction** | Treat 667 compressions as 667 training labels and fit a depth model | **No. The labels do not exist.** Nine sessions carry nine mean depths. 667 strokes are 9 labels, not 667. |

### 4.2 Why (a) is necessary but not sufficient

The current model is already "corpus-wide" in the sense that `K` and `MAX_PRE` are single global constants chosen to minimise aggregate error over all nine sessions. That is the right shape of model. What is missing is the discipline that makes corpus-wide fitting trustworthy:

- **Leave-one-session-out** for every selected parameter, reported alongside the in-sample number.
- **Nested selection**: if `K` and `MAX_PRE` are both chosen, the inner selection must not see the held-out session, or the held-out estimate is contaminated twice.
- **Equal session weight.** Aggregating all strokes together makes `04` (103 strokes) count twice as much as `01` (52). The reference reports one number per session, so the metric must be per session. E13.
- **A held-out mount, tester, or manikin.** No amount of cross-validation inside nine same-rig sessions substitutes for this. Cross-validation measures tuning stability; it does not measure generalisation to a new physical setup.

Done properly, corpus-wide re-fitting is a **validation** activity. It will not raise accuracy; it will tell the truth about the accuracy already achieved. That is worth doing before any further change, because without it nobody can tell whether v6 is better than v5 or merely better fitted.

### 4.3 Why (b) is the right structural move

The current estimator makes three assumptions per stroke:

1. the window `[i_start, i_end)` contains exactly one compression–recoil cycle;
2. chest displacement over that window is zero (used to solve for initial velocity);
3. the pre-onset lead-in is at most 22 samples.

Assumption 1 is the one that fails on irregular rhythm and after a lean. Assumption 3 is a patch over assumption 1. Reconstructing displacement **once, for the whole recording**, replaces all three with a single global assumption — that the chest's long-term mean position is stable, which a high-pass filter can enforce continuously instead of per window — and then reads each cycle's amplitude from the reconstructed curve.

Sketch (offline prototype, not firmware):

```
a_net[k]  = projected chest acceleration, g, positive downward
v[k]      = cumulative integral of (a_net − a_dc[k]) dt       # a_dc from a slow high-pass, e.g. 0.3–0.7 Hz
x[k]      = cumulative integral of (v − v_dc[k]) dt
depth_i   = (max x over cycle i − min x over cycle i) · g_cm/s² · K/11.2
```

The high-pass corner is the new tuning knob, and it is a **better-behaved** knob than `MAX_PRE`: it is a property of the physics (respiratory and postural drift sit below ~0.3 Hz; compressions at 1.7–2.5 Hz), not of one tester's dwell habit. It also makes the estimator causal-friendly if implemented as a forward filter with fixed lag, or non-causal if run offline.

Expected effect: large on irregular rhythm (E1/E2), neutral on steady rhythm. The 7.7× irregular/steady deviation ratio in `ANALYSIS.md` §13.4 is the number this change should be judged against.

Risks, stated plainly:

- **Drift vs signal.** A corner that is too low leaves drift; too high attenuates real displacement. At 80 cpm (1.33 Hz) the margin to a 0.5 Hz corner is thin. This needs a frequency sweep on real recordings, not synthetic ones.
- **Edge effects.** Session start and end lose a filter length of usable data. The first and last strokes will be worse, and the current first-stroke path is already the worst part of the pipeline.
- **Non-causal means offline-only, or a fixed lag in firmware.** A 0.5 Hz zero-phase filter needs seconds of lookahead. If live display matters, the firmware version must use a causal filter with a known group delay, and the delay must be subtracted from the timestamp reported with each stroke.
- **It changes `K`.** Any change to the amplitude estimator invalidates the current `K` and therefore the manikin calibration stored in NVS. `DEPTH_MODEL_VERSION` exists for exactly this; it must be incremented and calibration re-run.

### 4.4 Why (c) fails, quantitatively

A learned per-stroke model would need per-stroke depth labels. The corpus provides:

- 9 session means (depth),
- 9 session counts, 9 session rates,
- 9 good-depth percentages, 9 release percentages,
- 4 sessions with no depth reference at all.

Fitting anything richer than a global scalar plus one or two covariates means fitting more parameters than there are independent labels. A three-parameter model on nine points already has six residual degrees of freedom, and the parameters will be correlated (gain, rate dependence, dwell dependence all trade off). The 667 compressions do not help, because their labels are shared: every stroke in a session is constrained by the same one number.

There is one legitimate way to use the corpus as a whole for learning: **weak supervision with a session-level loss**, i.e. optimise a small parameter set so that the *predicted session mean* matches the reference mean, and validate by holding out sessions. That is exactly what `K` and `MAX_PRE` tuning already is. It is not a new capability, and it saturates at two or three parameters.

### 4.5 Decision table

| Situation | Prefer | Reason |
|---|---|---|
| Steady rhythm, coaching display, current firmware | Per-stroke window (current) | Already ≤ 5 mm; no new risk |
| Irregular rhythm, pauses, leaning | Whole-recording reconstruction | Removes the window assumption that fails here |
| Retrospective research analysis | Whole-recording reconstruction | Can use non-causal filtering and the full session |
| Firmware with tight RAM/flash and a 1 KB depth buffer | Per-stroke window, with period-proportional cap | Reconstruction needs a session-length buffer or a stateful filter |
| Any accuracy *claim* | Neither, until a held-out mount is measured | The corpus cannot support a generalisation claim |

**Verdict, in one sentence:** re-analysing the whole dataset is the right way to *validate* the model and the right way to *redesign* the estimator, but it is the wrong way to *learn* one, and on its own it will not move the number that users experience.

---

## 5. Solution catalogue

Every option considered, with an honest estimate of value. "Gain" is the expected effect on the scorecard if implemented well; "Cost" is engineering effort; "Evidence" is how confident the estimate is.

### 5.1 Estimator

| ID | Solution | Gain | Cost | Risk | Evidence |
|---|---|---|---|---|---|
| S1 | Whole-recording displacement reconstruction (Section 4.3) | High on irregular rhythm; neutral on steady | High (new buffer, new filter, re-calibrate `K`) | Medium — drift corner, edges | Theory + 7.7× irregular penalty |
| S2 | Period-proportional pre-onset window: `N_pre = clamp(0.35 · period_samples, 12, 30)` instead of fixed 22 | Medium — removes the rate dependence of E1 without a new estimator | Low | Low | Dwell-vs-window table in the tuning guide |
| S3 | Cycle-closure residual as a validity gate: compute \|x(end) − x(start)\| and flag/withhold the stroke when it exceeds a fraction of amplitude | Medium — catches split strokes and lean transitions at the source | Low–Medium | Low | `3f74e948` stroke 23 is exactly this case |
| S4 | Amplitude-domain regression: depth ≈ f(a_peak-to-peak, period), fitted on session means | Low–Medium | Medium | High — shape sensitivity is what the old `K·a·T²` model already failed at | Prior failure documented in the refinement report |
| S5 | Cycle-aligned template stacking across the session (median cycle), depth from the template | Medium for stability, low for per-stroke truth | Medium | Medium — assumes cycles are similar | Standard practice in gait/CPR signal work; untested here |
| S6 | Monotone/physically-constrained fit: require the reconstructed `x` to have one extremum per cycle | Low | Medium | Medium | Theoretical |
| S7 | Two-pass offline: first pass detects cycles, second pass integrates with exact boundaries | Medium (research only) | Low | Low | Obvious; not usable live |
| S8 | Keep per-stroke window, but anchor the window on the *peak* rather than the filtered threshold crossing | Low–Medium | Low | Low | Filter delay is 80–180 ms per the tuning guide |

### 5.2 Calibration and hardware

| ID | Solution | Gain | Cost | Risk | Evidence |
|---|---|---|---|---|---|
| S9 | Per-mount gain calibration against a known-depth jig (a 50 mm stop, or the manikin's own calibration mode) | High on E3 (±3 mm session bias) | Low per use, needs a physical jig | Low | The ±3 mm same-condition session spread |
| S10 | Automatic per-session gain from a tap/known-push calibration at session start | Medium | Medium | Medium — user compliance, false calibration | Requires a known reference the device does not have |
| S11 | Base-sensor stationarity check: use the base channel only when its own variance is below a threshold | Removes a destructive subtraction in dual builds | Low | Low | r = 0.978–0.995 coupling |
| S12 | Drop dual-sensor depth entirely; base sensor becomes a posture/reference channel only | High for existing dual devices | Low (config) | Low | `01`–`07` evidence |
| S13 | Better IMU (±1 % scale, 200 Hz, gyro for rotation compensation) | Medium (E4, E5) | High (hardware revision) | Medium | E4 budget line |
| S14 | Force/deflection sensor at the pad to measure compliance directly | High (E3 becomes measurable) | Very high | Medium | Hardware change; out of scope for firmware-only work |

### 5.3 Segmentation and event handling

| ID | Solution | Gain | Cost | Risk | Evidence |
|---|---|---|---|---|---|
| S15 | Pause test relative to recent median period (`gap > 2.5 × median`) instead of fixed 1500 ms | Medium — removes the cliff at 1.5 s | Low | Low | 1.504 s stall produced a false pause |
| S16 | Split/merge repair: if a stroke is < 40 % of the running median depth and the next interval is < 60 % of median, merge or suppress | High on M6/M9 | Low–Medium | Medium — could suppress a genuine shallow stroke | `3f74e948` 11.6 + 80.9 mm pair |
| S17 | First-stroke validity state: display "measuring" until two consecutive strokes agree, never show an unvalidated number as depth | High on M10 | Low (app + flag) | Low | 0.00 / 7.81 / 3.20 cm first strokes |
| S18 | Sampling-gap detection on `t_us` deltas, independent of `sample_index`; flag and reset the cycle on gaps > 50 ms | High on M11 | Low | Low | 1.013 s stall with clean indices |
| S19 | End-of-session guard: discard the final stroke if the recording stops within one period of it | Low–Medium | Low | Low | 15.5 mm last stroke in `b6d1fe73` |
| S20 | Recoil-arming adaptive to the measured rebound amplitude per stroke rather than a fixed fraction | Medium on count at burst edges | Low | Low | Preset table sensitivity |

### 5.4 Aggregation and display

| ID | Solution | Gain | Cost | Risk | Evidence |
|---|---|---|---|---|---|
| S21 | Live depth = median of last 3 valid strokes | High on M9 (visible jumps) | Low | Low | 1.16 → 8.09 cm jump |
| S22 | Summary = quality-filtered mean (exclude unknown, no-recoil, first/last, gap-adjacent) with the count of excluded strokes reported | Medium on M1; high on trust | Low | Low | Summary currently includes every non-zero stroke |
| S23 | Expose a per-session validity summary (`n` used, `n` excluded, worst event) instead of reusing the last packet's flags | Medium on diagnosability | Low | Low | Final `quality_flags = 9` in all four schema-2 sessions |
| S24 | Report depth as a median with an interquartile range rather than a mean | Low for accuracy; medium for honesty | Low | Low | Per-stroke CV 5.6–13.9 % |
| S25 | Distinguish "unknown" from "0.00 cm" in the protocol and the app | High on M10 | Low | Low | Last-stroke and post-pause behaviour |

### 5.5 Data, tooling, and process

| ID | Solution | Gain | Cost | Risk | Evidence |
|---|---|---|---|---|---|
| S26 | Frozen replay harness in-repo with a versioned scoring script and golden outputs | High — everything else depends on it | Medium | Low | No harness currently ships with the data |
| S27 | LOOCV + nested selection as the default reported number | High (corrects 25–30 % optimism) | Low | Low | §2.3 |
| S28 | Schema v3 per-stroke telemetry (Section 8) | High on diagnosability | Medium (firmware + app + DB) | Low | Current fields cannot separate E1 from E10 |
| S29 | Reference-instrumented trial protocol with per-stroke ground truth (Section 7) | Highest long-term value | High (rig + sessions) | Medium | The 9-label ceiling |
| S30 | Stratified corpus: ≥ 3 mounts, ≥ 3 testers, ≥ 2 manikins, ≥ 2 foam ages | High on generalisation claims | High | Low | No held-out setup exists today |

---

## 6. Recommended sequence

The ordering is chosen so that each phase makes the next one measurable. Nothing in Phase 1 depends on the estimator work, and the estimator work must not start before Phase 0 exists.

### Phase 0 — Make the current number honest (no firmware change)

1. Ship the replay harness: load `raw.csv`, apply `GravityAxis` → `DepthEstimator` → `CompressionTracker`, emit per-stroke records, and reproduce the nine published session means within ±0.05 mm. This is the regression gate for everything later (S26).
2. Implement the scorecard (M1–M13) with **equal session weight**, and record exactly which strokes were excluded and why (S27, E13).
3. Report LOOCV and nested-selection numbers next to in-sample numbers. Expect MAE to move from 1.88 to ~2.4 mm; that is a correction, not a regression.
4. Re-run the published parameter tables through the same harness so that every table in the tuning guide is reproducible from one command.

**Gate G0:** any future change can be scored in one command, on the same nine sessions, with the same exclusions, and the harness reproduces the v5 baseline bit-for-bit.

### Phase 1 — Event-level fixes (low risk, high visibility)

S15 (median-relative pause), S17 (first-stroke validity), S18 (stall detection), S19 (end-of-session guard), S21 (median live depth), S22/S23 (summary filtering and validity reporting), S25 (unknown ≠ 0.00).

These do not touch the estimator and therefore cannot invalidate `K`. They address every defect that users actually reported.

**Gate G1:** on the four schema-2 sessions plus a fresh steady 5 cm run, zero adjacent live-depth jumps > 15 mm, zero unflagged 0.00 cm, zero sampling gaps > 50 ms unflagged, and summary changed by < 1 mm.

### Phase 2 — Reference-instrumented data collection

Run the protocol in Section 7 with per-stroke reference. Minimum viable: 12 sessions across 3 mounts × 2 testers × (steady, irregular), at 50 mm. Add a shallow (40 mm) and deep (60 mm) arm if the rig allows.

**Gate G2:** a corpus with at least three independent mounts and at least one held-out mount. Until this exists, no accuracy claim beyond "on this rig" is defensible.

### Phase 3 — Estimator change, behind a build flag

1. Implement S2 (period-proportional window) as the cheap version. It is a one-line change to the window bound and is testable against G0 immediately.
2. Prototype S1 (whole-recording reconstruction) offline on the Phase-2 corpus and the nine reference sessions, sweeping the high-pass corner. Compare against S2 on M1–M6 and on the irregular/steady CV ratio.
3. Only promote S1 to firmware if it beats S2 on the irregular arm by more than the MDE (Section 7.6), with `DEPTH_MODEL_VERSION` incremented and calibration redone.

**Gate G3:** irregular/steady per-stroke CV ratio ≤ 1.5 (currently ~7.7), with steady-arm depth MAE not worse than the v5 baseline.

### Phase 4 — Mechanical and hardware

S9 (per-mount calibration jig) is the cheapest way to attack the ±3 mm session term and should be attempted before S13/S14. S11/S12 (dual-sensor policy) should be a configuration decision, not a code change.

---

## 7. Experimental protocol

### 7.1 Condition matrix

Minimum useful design, one manikin, one vest, one firmware build:

| Factor | Levels | Why |
|---|---|---|
| Target depth | 40, 50, 60 mm | Tests gain linearity; 40 mm is where the worst session error was |
| Rate | 80, 100, 120 cpm (metronome) | E1 is rate-dependent |
| Rhythm | steady; irregular (±20 % period jitter, occasional 0.5–1.5 s pauses) | The 7.7× claim |
| Mount | 3 independent pad placements, one held out entirely | E3, generalisation |
| Tester | ≥ 2, one held out | Technique dependence |
| Session length | 30 compressions | Matches the reference's own reporting window |

A full cross of every factor is unnecessary. A defensible minimum: 3 mounts × 2 testers × 2 rhythms at 50 mm (12 sessions), plus 4 sessions at 40 mm and 4 at 60 mm on the primary mount (8 sessions). Twenty sessions is enough to halve the current CI on bias.

### 7.2 Per-stroke reference options

The corpus's central limitation is that the manikin reports session aggregates. Options, in increasing cost:

| Option | Per-stroke accuracy | Practicality |
|---|---|---|
| Laerdal export or service log, if it exists | Reference-grade | Ask the vendor; unknown |
| High-speed camera (≥ 120 fps) with a marker on the pad, tracked offline | ~1 mm | Cheap, requires careful calibration and lighting |
| String potentiometer or linear encoder on the pad | ~0.2 mm | Best, needs a mechanical fixture |
| Laser/ToF rangefinder on the pad | ~1 mm | Cheap, sensitive to angle and surface |
| Two cameras, stereo | ~0.5 mm | Overkill |

Any of the middle three converts the corpus from 9 labels to ~700, which is the difference between tuning a scalar and validating a model.

### 7.3 Session procedure

1. Mount and calibrate; record the tilt angles and the `K` in use.
2. Start the manikin's app and the vest recording together; note both clocks.
3. Perform the prescribed count at the metronome rate.
4. Stop both; export both.
5. Record in `session.json` notes: mount id, tester id, depth target, rhythm condition, any pause, any hand repositioning.
6. Photograph the manikin screen (the current practice) as a cross-check.

### 7.4 Metadata that must be captured

Beyond the current schema: `depth_k` (present in schema 2), `preset`, `firmware_version`, `depth_model_version`, `mount_id`, `tester_id`, `target_depth_mm`, `rhythm_condition`, and for each stroke the fields in Section 8.

### 7.5 Splitting and leakage rules

- Split by **session**, never by stroke. Strokes within a session share a label and a mount.
- Split by **mount** for any generalisation claim. Leave-one-session-out measures stability; leave-one-mount-out measures generalisation.
- Never tune on a session that contributed to the reference used to validate it.
- Never pool 2-MPU and 1-MPU sessions in one fit. They are different instruments.
- Never pool old-schema and schema-2 sessions for depth analysis (post-clamp vs pre-clamp).

### 7.6 Statistical analysis plan

- Unit of analysis: **session** for M1–M4, **stroke** for M5–M11, **session** for M12.
- Aggregate with equal session weight; report the per-session table, not only the aggregate.
- Report bias with a 95 % CI, and MAE with a bootstrap CI over sessions.
- Minimum detectable effect: with per-session error SD ≈ 2.6 mm and n = 9, the 95 % CI on bias is ≈ ±2.0 mm. To resolve a 1 mm difference at 95 % confidence requires roughly **n ≈ 27 sessions**. Any claim of sub-2 mm improvement on the current corpus is unsupported by construction.
- Pre-register the primary metric. If M1 is primary, do not switch to M5 after seeing the result.

---

## 8. Instrumentation and telemetry requirements

The current per-stroke record cannot separate window truncation (E1) from mis-segmentation (E10). A schema v3 per-stroke row should carry:

```text
stroke_index, t_start_us, t_onset_us, t_end_us,
window_start_index, window_end_index, pre_onset_samples, period_ms,
depth_unclamped_mm, depth_reported_mm, depth_known, from_rest, post_pause,
recoil_status, quality_flags, preset, depth_k, profile,
max_dt_ms_in_window, gap_flag, closure_residual_mm
```

Three of these are load-bearing:

- `window_start_index` / `pre_onset_samples` make E1 directly measurable instead of inferred.
- `closure_residual_mm` (the cycle-closure error from S3) is the natural validity signal for split strokes and lean transitions.
- `max_dt_ms_in_window` / `gap_flag` make the 1.013 s stall visible without relying on `sample_index`.

Also fix in the same pass:

- `recoil_status` currently carries `0/1` in live packets and `98/99/100` in the final packet. Split it into `recoil_ok` (boolean) and `recoil_percent` (integer) before a downstream parser is written against the wrong type.
- The final `quality_flags` should be a session aggregate (e.g. "rhythm was unsteady at least once"), not the last reading's flags.
- The stale comment in `CompressionTracker.h::depthScale()` still describes `DEPTH_CALIBRATION_K` as `48.2` and "4.30× default manikin scaling". It is `10.85` and the scale is `10.85/11.2 ≈ 0.969`. Comments that contradict the constants are how the next engineer reintroduces the bug.

---

## 9. Risks to this plan

| Risk | Consequence | Mitigation |
|---|---|---|
| Phase 0 harness is built to reproduce the authors' exclusions rather than the data | Every later comparison inherits the same blind spot | Freeze exclusions as data, not code; report sensitivity to exclusion rule |
| Phase 1 fixes change the summary and look like a regression | Pressure to revert good fixes | Gate G1 is measured on M9–M11, not M1 |
| The manikin's own sensor drifts or is uncalibrated | Absolute accuracy measured against a moving reference | Cross-check with a second reference (camera/pot) on a subset |
| Whole-recording reconstruction is judged on the same nine sessions | Overfit to nine mounts of one rig | Only promote after Phase 2 |
| `K` is re-tuned on the same nine sessions and shipped | A v6 that is better fitted and no better in the field | Nested selection; increment `DEPTH_MODEL_VERSION`; recalibrate |
| Effort goes to sensor/timing precision (E4/E6) | < 1 mm gained while E1/E3/E10 stay at 3–7 mm | Error budget in Section 3 is the priority order |
| New corpus is collected with different firmware | Sessions not comparable | Record `depth_model_version` and `depth_k` per session; never pool |

### 9.1 What would change this recommendation

- If the Laerdal can export per-stroke depth, Phase 2 collapses in cost and the estimator work can start immediately.
- If the product only needs coaching feedback (AHA band 50–60 mm, ±1 stroke), then Phase 1 alone is sufficient and Phase 3 may never be justified.
- If dual-sensor hardware is already deployed in the field, S11/S12 become urgent regardless of the estimator plan.
- If a hardware revision (S13/S14) is already funded, defer S9 and re-plan around the new sensor.

---

## 10. Open questions

Each question states why it matters and the assumption that will be used until it is answered. Questions are grouped by who can answer them. None of these blocks Phase 0.

### 10.1 Purpose and acceptance

1. **What decision does the number drive?** Real-time coaching, a research dataset, a graded score, or a published claim? *Matters because the acceptable error differs by an order of magnitude.* Assumption: coaching plus research, not a clinical claim.
2. **What error is acceptable?** Depth in mm, count in strokes, rate in cpm, live jitter in mm. *Matters because it sets the MDE and therefore the corpus size.* Assumption: ±5 mm session depth, ±1 stroke per 30, ±2 cpm, no live jump > 15 mm.
3. **Must the device agree with the Laerdal, or with the chest?** They are different quantities, and the current `K` is calibrated to the former. *Matters because `K = 10.85` is a compliance correction, not a physical constant.* Assumption: agreement with the manikin display is the requirement.
4. **Is "good depth" in the app defined the same way as the manikin's?** Threshold, band, and per-stroke vs session. *Matters for M12 and for any score comparison.* Assumption: ≥ 50 mm, per stroke.
5. **Is a high score with a wrong live number acceptable?** *Matters because S21/S22 trade session mean stability against responsiveness.* Assumption: no; event-level correctness takes priority.
6. **Who signs off an accuracy claim, and against what protocol?** *Matters because it determines whether Phase 2 is mandatory.* Assumption: unresolved; treat all current numbers as internal.

### 10.2 Reference and ground truth

7. **Can the Laerdal Little Anne QC export per-stroke data?** *The single highest-leverage unknown.* Assumption: no.
8. **What is the manikin's own depth measurement uncertainty and calibration state?** *Sets the accuracy floor.* Assumption: ±1–2 mm, uncalibrated.
9. **Is the 50 mm threshold exactly 50.0 mm, or 2 inches (50.8 mm)?** *Shifts M12 by a few points.* Assumption: 50.0 mm.
10. **How old is the foam, and has it been re-foamed?** *Directly changes E3.* Assumption: unknown and varying.
11. **Are multiple manikins available, and do they differ in spring rate?** *Determines whether generalisation can be tested.* Assumption: one manikin.
12. **Can a camera or string potentiometer be fitted without altering the compression?** *Determines whether per-stroke truth is obtainable.* Assumption: yes, with care.
13. **Do the two unpaired screenshots (`2:13`, `2:16`) have recoverable session data anywhere?** *Two more reference sessions would help.* Assumption: no.

### 10.3 Corpus and comparability

14. **Will new sessions be recorded on the same firmware build as the nine reference sessions?** *Pooling across builds is invalid.* Assumption: no; treat as a new corpus.
15. **Are the schema-2 sessions from the same vest, mount, and manikin as the reference trials?** *Determines whether they can be used for stability analysis only.* Assumption: same manikin, different day.
16. **How many distinct testers contributed to the nine reference sessions?** *Affects the generalisation claim.* Assumption: two or fewer.
17. **Is `2928353c` (77 strokes, 74 clamped) representative of any field device still in use?** *If yes, it is a live bug, not history.* Assumption: old firmware, no longer shipped.
18. **Should old-schema sessions be retained in the analysis set at all?** *They are post-clamp and cannot be compared.* Assumption: exclude from depth analysis, retain as failure evidence.

### 10.4 Firmware and hardware constraints

19. **May the depth algorithm change at all, or is v5 frozen for a release?** *Determines whether Phase 3 can happen.* Assumption: changeable behind a version bump.
20. **What are the flash and RAM ceilings?** Currently ~90 % flash, 41 KB RAM, 1 KB depth buffer. *A whole-session reconstruction needs either a stateful filter or a much larger buffer.* Assumption: 1 KB buffer is fixed; S1 must be stateful.
21. **Is 100 Hz fixed, or can sampling rise to 200 Hz?** *E6 is below 1 mm either way; only matters if S1 needs more resolution.* Assumption: 100 Hz fixed.
22. **Is the MPU-6050 fixed, or is a better IMU planned?** *Determines whether E4 is worth modelling.* Assumption: fixed.
23. **Are dual-sensor units in the field?** *If yes, S11/S12 are urgent.* Assumption: prototype only.
24. **Is the 10.0 cm clamp still reachable with `K = 10.85`?** *Old sessions clamped 69–74 of 70–77 strokes at `K = 48.2`.* Assumption: not reachable in normal use, but the code path remains.
25. **Is there a hardware watchdog that could detect the 1.013 s stall?** *S18 flags it; a watchdog would prevent it.* Assumption: none configured.
26. **What causes the sampling stall — I2C contention, flash write, BLE, or power?** *Unresolved; one occurrence in the corpus.* Assumption: unknown; needs reproduction.

### 10.5 Product semantics

27. **Should the summary be "all strokes" or "good strokes only"?** *Currently all non-zero strokes, which includes post-pause and truncated strokes.* Assumption: quality-filtered, with exclusions reported.
28. **Should the first stroke be displayed at all?** *Current values range 0.00–7.81 cm against a ~5.2 cm session median.* Assumption: show "measuring" until validated.
29. **How many strokes should the live display average over?** *Median of 3 is proposed; 5 is steadier but laggier.* Assumption: 3.
30. **What should the app show when depth is unknown?** Blank, dash, or previous value. *Previous value is what caused the original "stale depth" confusion.* Assumption: explicit unknown state.
31. **Does the rate shown live have to equal the rate in the summary?** They currently use different estimators (113–116 vs 118–125 cpm). *Two numbers for one quantity erodes trust.* Assumption: one estimator, active-time average in both.
32. **Is CCF required to match the manikin's CCF definition?** *Definitions differ (active time vs hands-on time).* Assumption: not comparable today.

### 10.6 Statistics and method

33. **Is in-sample or out-of-sample the number of record?** *Currently both are quoted interchangeably.* Assumption: out-of-sample only.
34. **Is the unit of analysis the session or the compression?** *They give different answers and different CIs.* Assumption: session.
35. **How should sessions be weighted when they differ in stroke count?** *Stroke-weighted pooling favours `04` (103) over `01` (52).* Assumption: equal session weight.
36. **What is the pre-registered primary metric?** *Without one, metric shopping is inevitable.* Assumption: M1 bias, with M2 as secondary.
37. **Is a 2 mm improvement worth a firmware risk?** *With n = 9 it is not even measurable.* Assumption: no; event-level defects first.
38. **How many sessions justify a generalisation claim?** *Proposed: ≥ 12 across ≥ 3 mounts.* Assumption: 12.
39. **Should the tuning guide's parameter tables be regenerated with LOOCV?** *They are currently in-sample optima presented as error bounds.* Assumption: yes, Phase 0.

### 10.7 Data engineering and governance

40. **Who owns the telemetry schema, and is a v3 change coordinated with the app and Supabase?** *A firmware-only field addition will be dropped silently.* Assumption: coordinated change required.
41. **Is `supabase/DATA_FORMAT.md` going to be corrected?** It documents the wrong packet map, quality-flag width, base Z convention, and replay formula. *Anyone building a parser from it will be wrong.* Assumption: it is stale.
42. **Where does the canonical replay code live?** It is not in the repository. *Without it, no number in any document can be reproduced.* Assumption: must be rebuilt (Phase 0).
43. **Are session recordings retained indefinitely, and are they de-identified?** *`participant_code` exists (`P014`), so some governance already applies.* Assumption: retained, coded.
44. **Who runs the next trial, and is manikin time available?** *Phase 2 is the schedule-critical item.* Assumption: unknown.

### 10.8 Claims and compliance

45. **Will any accuracy number appear in a paper, proposal, or product page?** *The research proposal and thesis are in the repository.* Assumption: yes, which makes Phase 2 mandatory.
46. **Is the device being positioned as a medical device or a training aid?** *Changes the evidence standard entirely.* Assumption: training aid.
47. **Is there an ethics/consent process for human testers?** *Existing sessions used participant codes.* Assumption: existing process covers it.

---

## 11. Appendix

### A. Where the evidence lives

| Topic | File |
|---|---|
| Failure mechanisms, revisions 1–3 | `ANALYSIS.md` |
| Manikin mapping, replay results, model v5 change list | `GROUND_TRUTH_ANALYSIS.md` |
| Parameter sensitivity tables, analytical bounds | `RESEARCHER_ERROR_BOUNDS_AND_TUNING_GUIDE.md` |
| Estimator design rationale and synthetic validation | `ALGORITHM_REFINEMENT_REPORT.md` |
| Telemetry contract (stale) | `supabase/DATA_FORMAT.md` |
| Estimator implementation | `CPReady_Program/include/DepthEstimator.h` |
| Windowing, presets, pause test, summary accumulation | `CPReady_Program/include/CompressionTracker.h` |
| Constants | `CPReady_Program/include/CPReadyConfig.h` |
| Dual-sensor subtraction and calibration | `CPReady_Program/include/SensorManager.h` |
| Tilt projection | `CPReady_Program/include/GravityAxis.h` |
| Per-session archives | `DATA/*.zip`, `DATA/organized_trials/` |
| Session↔screenshot mapping | `DATA/TRIAL_MAPPING.md`, `DATA/trial_manifest.json` |

### B. Reproducing the numbers in Section 2

1. Extract `DATA/*.zip` to a scratch directory.
2. For each session, read `raw.csv` and `session.json`.
3. Run `GravityAxis` → `DepthEstimator` → `CompressionTracker` at 100 Hz using the per-session `K` from `session.json` (schema 2) or the replay configuration in `GROUND_TRUTH_ANALYSIS.md` §3 (schema 1).
4. Compare session mean depth and stroke count against `ground_truth.json`.
5. For the LOOCV figure in §2.3: take the per-session replay means and reference means, and for each held-out session fit a single scale factor minimising MAE on the remaining eight, then predict. Reported depth is linear in `K`, so no replay is required for this step.

### C. Glossary

| Term | Meaning |
|---|---|
| Closed-cycle integration | Double integration over one compression–recoil window with mean acceleration and mean velocity removed |
| `K` / `DEPTH_CALIBRATION_K` | Multiplicative depth correction, `depth = d_phys · K / 11.2` |
| `MAX_PRE` | Maximum samples of pre-onset lead-in included in the window |
| Session / stroke | One recording / one detected compression |
| In-sample / LOOCV | Parameter fitted on all sessions / fitted with one session held out |
| MDE | Minimum detectable effect given the corpus size |
| E1…E13 | Error-budget entries in Section 3 |

### D. Change log

| Version | Change |
|---|---|
| 1.0 | Initial plan: error budget, event-level evidence, whole-dataset verdict, solution catalogue, protocol, open-questions register |
