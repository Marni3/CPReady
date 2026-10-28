# CPReady Lab Mode: Architecture (for review)

**Status:** proposal, 27 October 2026. Nothing in this document has been built yet.
**Branch:** `for-finalization`.
**Why:** to make the firmware and app reliable and accurate, the team needs recordings of real
compressions on the real vest and manikin, paired with what the person was asked to do. The
audit (`CPREADY_SYSTEM_AUDIT_AND_IMPROVEMENT_PLAN.md`) has three open questions that only such
data can answer:

| Question | Audit item |
|---|---|
| Is the new depth method (multi-harmonic) accurate on our manikin, and how far off is the current K model? | C6, P2.2 |
| Is stroke detection reliable on real signals: shallow, fast, ringing, hand repositioning? | C2–C4, P2.3 |
| Can anything without a force sensor detect leaning? Is an FSR402 or RFP602 module good enough if added? | C5, P2.6 |

Lab mode also answers the research questions that need data the product doesn't keep
(audit H10): Bluetooth loss rate, response time, and logging completeness.

---

## 1. Principles

1. **The production build stays untouched.** Lab code is compiled only into separate
   firmware and app builds. The normal app and firmware gain no new behaviour and no new risk.
2. **Record raw data, not just results.** The vest streams both accelerometers (x, y, z) and
   the optional force sensor at the full 100 Hz. Any future algorithm can then be re-run on
   the same recording, and today's detector is recorded alongside for comparison.
3. **Every recording is labelled.** The app runs a fixed script of short "bouts" (target,
   shallow, deep, slow, fast, leaning…). Each bout is stored with what was requested,
   what the trainee reported afterwards, and the manikin app's mean depth for that bout.
4. **Losses are visible.** Every frame carries a sequence number and a device timestamp, so
   gaps are counted, never hidden.
5. **Decide the pass/fail rules before collecting data** (§7), so the results can't be
   argued into fitting.

Assumption to confirm: you answered "It'll be on the theme" to the question about who runs
sessions. I've read that as **the app's script runs the session, with no second person
tapping markers.** Everything below assumes that.

---

## 2. System overview

```
 ┌──────────── Vest: ESP32 lab firmware (env esp32dev_lab) ────────────┐
 │ SensorManager ──100 Hz──► CompressionTracker (unchanged)            │
 │      │ raw x,y,z ×2 + force          │ metrics packets (v2, 16 B)  │
 │      ▼                               ▼                              │
 │ LabStream: 8–10 samples/frame   BLE char 6e400002 (as today)        │
 │      ▼                                                              │
 │ BLE char 6e400004 (lab only)   Serial CSV mirror (optional)         │
 └──────────────────────────────────────────────────────────────────────┘
                 │ Bluetooth LE                        │ USB (fallback)
 ┌─────────── Phone: CPReady Lab app ───────────┐   laptop log
 │ LabRunner (guided script) ─► LabRecorder ─► files per session       │
 │ Metronome · bout review · data-quality check · export               │
 └──────────────────────────────────────────────┘
                 │ exported folder
 ┌──── PC: lab analysis tool (C++, reuses the firmware headers) ────┐
 │ re-runs today's detector and the harmonic estimator on raw data,  │
 │ writes per-stroke and per-bout tables (open in Excel or Sheets)   │
 └───────────────────────────────────────────────────────────────────┘
```

---

## 3. Firmware

### 3.1 Builds

| Environment | Contents |
|---|---|
| `esp32dev` | Production, as committed on this branch. No lab code. |
| `esp32dev_lab` | Production + `-D CPREADY_LAB`. Uses the `huge_app.csv` partition so lab code can't run out of flash (the production image is already at 89.9 %). |
| `simulation_lab` | The simulation build + lab streaming of synthetic raw data, so the whole lab flow can be tested with a bare ESP32 board and no sensors. |

### 3.2 What the lab firmware adds

| Part | What it does |
|---|---|
| `include/LabStream.h` | Collects each 100 Hz sample into a frame and sends it when full. The samples are the exact ones the tracker used, taken from the library's raw counts after the existing 14-byte read, so no extra bus traffic is added. |
| `include/ForceSensor.h` | One interface with drivers: **None**, **Analog pin** (FSR402, or the RFP602 voltage-conversion module's AO output), and **I2C**. The I2C driver depends on your RFP602 module (§3.4). |
| BLE | A third characteristic, `6e400004-…` (notify), exists only in lab builds. The firmware calls `BLEDevice::setMTU(247)`, reads the MTU the phone negotiated, and sizes frames to fit. |
| Commands (lab only) | `LAB_STREAM:1` / `LAB_STREAM:0`; `LAB_FORCE:NONE` / `LAB_FORCE:ADC` / `LAB_FORCE:I2C` (saved in flash); `LAB_INFO`. |
| Info packet | The reply to `LAB_INFO`: firmware version and git hash, build flags, each MPU's WHO_AM_I and multiplexer channel, accelerometer range and filter, profile, K, detector thresholds, the last calibration's gravity offsets, and the force-sensor type. |
| Serial mirror | With `-D CPREADY_LAB_SERIAL`, the same samples are printed as CSV at 921600 baud. It's a fallback if Bluetooth streaming proves unreliable on a given phone. |

The tracker, the command state table and the metrics packets are **identical** to
production. The recording therefore shows exactly what the product would have done on the
same compressions.

### 3.3 Raw frame layout (lab protocol version 1)

All fields are little-endian.

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | frame type `0x10` |
| 1 | 1 | lab protocol version `1` |
| 2 | 2 | frame sequence number (uint16, wraps) |
| 4 | 1 | samples in this frame, *n* |
| 5 | 1 | channel mask: bit 0 chest xyz, bit 1 base xyz, bit 2 force |
| 6 | 1 | device state |
| 7 | 1 | fault bits: I2C fault, frozen sensor, saturation, sample overrun |
| 8 | 2 | tracker stroke count at the end of the frame |
| 10 | 4 | device time (µs) of the last completed stroke |
| 14 | 20 × *n* | samples |

Each 20-byte sample holds:

| Bytes | Field |
|---|---|
| 0–3 | device time (µs, uint32) |
| 4–9 | chest x, y, z (int16, raw counts) |
| 10–15 | base x, y, z (int16, raw counts) |
| 16–17 | force (uint16: mV for the analog driver, counts for I2C) |
| 18–19 | the filtered net acceleration the tracker saw (int16, mg) |

**Sizing.** With *n* = 10, a frame is 214 bytes, sent 10 times a second (about 2.1 KB/s).
That is well within BLE capacity once the MTU is at least 217. At smaller MTUs the
firmware lowers *n*. Below an MTU of 37 it refuses to stream and reports why in the info
packet.

**Timing.** Per-sample device times reveal any sampling jitter. Comparing frame device times
with phone receive times gives the Bluetooth delay (§6).

### 3.4 Force sensor hardware notes

- **FSR402 (analog).**
  - Wiring: 3.3 V → FSR → GPIO34 (ADC1, input-only) → measuring resistor → GND.
  - Start with 10 kΩ for the measuring resistor. Raise it to 22–47 kΩ if light leaning reads
    near zero.
  - Sampling: four averaged `analogReadMilliVolts()` reads per 10 ms sample, at 11 dB
    attenuation.
  - The 402's active area is a 12.7 mm disc, much smaller than the heel of a hand. Put a
    small rigid puck over it so the hand's force passes through the sensor, and mount it
    where the hands go.
- **RFP602 with its voltage-conversion module.**
  - **Power the module from 3.3 V, not 5 V.** Its AO output follows the supply, and above
    about 3.3 V it would exceed the ESP32's ADC input.
  - Its AO pin goes to GPIO34, exactly like the FSR402.
- **"RFP602 I2C module".** I couldn't find a datasheet for an I2C version. If it is an
  ADS1115 or ADS1015 ADC reading the sensor, the driver is standard: address 0x48–0x4B, on
  the main bus or a spare multiplexer channel. If it is a vendor board, I need its listing or
  datasheet. Until then the I2C driver is a stub that reports "not supported".
- **Calibration.** For a rough newton scale, place known weights on the pad (for example 1,
  2 and 5 kg bags) during the sensor check (§5.1). Leaning analysis doesn't need newtons. It
  compares each release with the same session's hands-resting baseline, which also limits the
  effect of FSR drift.

---

## 4. App

### 4.1 Build and install

- A separate Android build flavour, `lab`:
  - application ID suffix `.lab`;
  - app name "CPReady Lab";
  - built with `flutter build apk --flavor lab --dart-define=CPREADY_LAB=true`.
- It installs **next to** the normal app, so a stable app is always available for practice
  and trials.
- In the normal build the lab code is compiled out: `AppFeatures.labMode` is a `const` read
  from the dart-define.

### 4.2 Modules

The modules follow the existing layout: values in `lib/src/config`, logic in `lib/src/core`,
UI in `lib/src/screens`.

| File | Role |
|---|---|
| `config/lab.dart` | Lab UUID, frame layout constants, file names, default bout durations. |
| `config/lab_protocols.dart` | The protocols in §5, written as data. Changing the script needs no code change. |
| `core/lab/raw_frame.dart` | Decodes and validates a raw frame (length, version, *n*); rejects malformed frames. |
| `core/lab/lab_recorder.dart` | Writes the session files (§6). Counts frame and sample gaps, flushes once a second, and writes `session.json` atomically (write a temporary file, then rename). |
| `core/lab/lab_runner.dart` | The bout state machine (§5.3), driven by an injectable clock so it can be fully unit-tested. |
| `core/lab/metronome.dart` | Plays **pre-rendered click tracks** (80, 100, 110, 120 and 140 cpm). Clicks scheduled by a timer can drift by tens of milliseconds; a pre-rendered track keeps exact time. |
| `core/ble/ble.dart` | Discovers the lab characteristic if present, exposes `rawFrames`, and logs the negotiated MTU. The normal app ignores the characteristic. |
| `screens/lab/*` | Lab home (sessions list, export), setup (participant code, manikin, surface, force sensor), runner, bout review, and session summary (data quality). |

### 4.3 Export

**Proposed:** add the `share_plus` package, so the summary screen can send a session folder
to Drive, email or a PC in one tap.

**Alternative without a new dependency:** sessions are written under the app's external
files folder (`Android/data/<app id>/files/lab/`), which a PC can copy over USB.

---

## 5. The guided tests

### 5.1 Session flow

```
Lab home → New session → Setup form → Sensor check (5.2) → choose protocol:
  A. Guided bouts (5.3)   B. Full-effort 2 min (5.4)   C. Recorded practice (5.5)
→ Session summary (data quality) → Export
```

The setup form records:

- a participant **code** (never a name);
- the manikin model;
- the surface (floor, mat or bed);
- vest placement notes;
- the force-sensor type;
- dominant hand;
- a free-text note.

### 5.2 Sensor check (about 1 minute; run at the start of every session)

| Step | Instruction | What it measures |
|---|---|---|
| Still | "Hands off the manikin, don't touch the vest" (10 s) | Noise floor, tilt from the gravity vector, sampling jitter, Bluetooth loss at rest |
| Resting hands | "Rest your hands on the chest, don't push" (10 s) | Force-sensor baseline; small offsets |
| Weights (optional, with a force sensor) | "Place the 1 kg / 2 kg / 5 kg weight on the pad" (5 s each) | Rough force scale |
| Live check | The app shows live values from both sensors and the force reading | Catches a swapped, loose or dead sensor before any data is wasted |

The app blocks the next step if any of these is true:

- a fault bit is set;
- frame loss is above 2 %;
- a sensor reads exactly the same value for 0.5 s;
- tilt is above 20°.

### 5.3 Protocol A: guided bouts (about 8 minutes)

**How each bout works:**

1. **Instruction screen** with a short text and picture. While it shows, the app sends
   `CALIBRATE`, so the 2 s still baseline runs with hands off.
2. **3-2-1 countdown**, then the app sends `SET_TIME:0` and `START`, and the metronome
   starts. CPReady's own voice coaching and live numbers are **hidden**, so the trainee follows
   the instruction rather than the device.
3. **Bout runs** for its set time with a large countdown timer. A beep at the start and end
   is loud enough to be heard on a screen recording of the manikin's app.
4. The app sends **`STOP`** and stores the firmware's summary packet for the bout.
5. **Review screen** asks:
   - "Did you manage it?" (Yes / Partly / No);
   - optionally, "Manikin app mean depth for this bout" (mm);
   - **Redo bout** or **Next**.

| Bout | Instruction | Metronome | Time | Mainly tests |
|---|---|---|---|---|
| A1 Target | 5–6 cm, let the chest come all the way up | 110 | 30 s | Depth and rate baseline |
| A2 Shallow | About 3–4 cm | 110 | 20 s | Detection of shallow strokes; "push harder" |
| A3 Deep | Deeper than 6 cm (as the manikin allows) | 110 | 20 s | Depth at the top of the range |
| A4 Slow | 5–6 cm | 80 | 20 s | Rate low; long stroke periods |
| A5 Fast | 5–6 cm | 140 | 20 s | Rate high; lockout limits |
| A6 Leaning | 5–6 cm, but keep some weight on the chest at the top | 110 | 20 s | Leaning features, with and without a force sensor |
| A7 Pause | Compress 10 s → hands off 5 s → compress 10 s | 110 | 25 s | CCF, pause detection, first stroke after a pause |
| A8 Reposition | Compress 10 s → lift and re-place hands, no pushing, 5 s → compress 10 s | 110 | 25 s | Phantom strokes from bumps |
| A9 Free | "Do it your usual way" | none | 30 s | Natural technique |

Each bout is followed by 20 s of rest, during which the next calibration runs. Bouts A2–A6
can be **shuffled per participant**, with the order and the random seed saved, so fatigue
doesn't always land on the same bout. The first pilot runs in fixed order.

### 5.4 Protocol B: full effort (2 minutes)

One continuous 2-minute session with no metronome. CPReady's feedback is **off by default**.
It shows natural rate drift, depth decay with fatigue, and leaning onset as the trainee
tires. A second run with feedback **on** is optional, to measure the effect of the feedback
itself (useful for the paper). The manikin app's mean depth is entered at the end.

### 5.5 Protocol C: recorded practice

The **normal practice flow**, unchanged, with lab recording running underneath. It records
when each voice cue played and how long each packet took to arrive. This checks that the
product behaves reliably end to end, not just its measurements.

---

## 6. Recorded data

One folder per session: `lab/<yyyyMMdd-HHmmss>_<participant code>/`.

| File | Contents | Size for 10 min |
|---|---|---|
| `session.json` | Schema version. App and firmware versions (from `LAB_INFO`). Phone model, MTU, setup form. Protocol and bout order with seed. One entry per bout: requested condition, start and end time (phone and device clocks), the firmware summary, the self-report, the manikin mean depth, and a data-quality block. | small |
| `raw.csv` | One row per sample: `t_device_us, frame_seq, chest_x, chest_y, chest_z, base_x, base_y, base_z, force, net_mg`. Raw counts; the scale factors are in `session.json`. | about 4 MB |
| `frames.csv` | One row per frame: `t_phone_ms, frame_seq, first_sample_us, n`. Used for loss and latency. | small |
| `packets.csv` | Every metrics, status and error packet: phone receive time, all decoded fields, and the raw bytes in hex. | small |
| `events.csv` | `t_phone_ms, event, detail`: bout start and end, command sent and its result, cue played, connect, disconnect, MTU, errors. | small |

**Reliability rules:**

- Files are appended as data arrives and flushed every second. A crash loses at most one
  second of data.
- `session.json` is rewritten after every bout.
- A disconnect mid-bout marks the bout **incomplete**. The data so far is kept, and the app
  offers Redo.

**Data-quality block, computed on the phone and shown on the summary screen:**

- frames received versus expected, and the loss %;
- longest gap;
- sample-time jitter (p99);
- fault bits seen;
- saturated samples;
- stroke count from the firmware versus from the raw recording.

---

## 7. Analysis and decision rules

**PC tool.** `tools/lab_analysis/` is C++ and compiles the firmware headers directly, like
`test_native/`. It reads a session folder and writes `per_stroke.csv` and `per_bout.csv`,
which open in Excel or Google Sheets. For each bout:

1. **Reference stroke count** from an offline analysis of the raw chest and base signals,
   checked by eye on a plot. This is independent of the real-time detector.
2. Today's **detector** replayed on the raw data, which should match the recorded packets.
3. **Depth** from both the current K model and the harmonic estimator, compared with the
   manikin app's per-bout mean.
4. **Leaning features**, for A1 versus A6:
   - the force minimum between strokes, if a force sensor is fitted;
   - release speed;
   - release time.
5. **Bluetooth:** frame loss, and the delay estimated from frame device time to phone
   receive time.

**Decision rules, agreed before collecting data:**

| Decision | Adopt if |
|---|---|
| Replace the K model with the harmonic estimator | Mean absolute per-bout error ≤ 5 mm against the manikin's mean, across A1–A6, **and** better than the K model |
| Stroke detection is release-ready | ≥ 98 % sensitivity and precision against the reference count in every bout; **zero** phantom strokes in A8 |
| Show a leaning hint without a force sensor | Some accelerometer feature separates A6 from A1 with ≥ 85 % sensitivity **and** specificity, tested by leaving one participant out at a time. Otherwise recoil stays "not measured". |
| Adopt a force sensor | Same rule, using the force minimum, plus stable baselines across sessions |
| Bluetooth is reliable | Frame loss < 1 % at 1 m and at 5 m; the delay's 95th percentile is under a target you set (I suggest 250 ms) |
| Sampling is reliable | Jitter p99 < 2 ms; no I2C faults across all sessions |

**Suggested size:** a 1–2 person pilot to shake out the procedure, then at least 5
participants doing Protocols A and B. The paper's sample size is the team's call.

---

## 8. Tests for the lab code itself

| Level | Tests |
|---|---|
| Firmware (native, PC) | Frame packing against a byte-exact fixture; *n* chosen correctly for each MTU; the force driver's averaging. |
| App unit tests | The frame decoder against the **same** byte fixtures (one source of truth); recorder output and gap counting, including sequence wrap-around; runner state machine with a fake clock (redo, incomplete bout, disconnect mid-bout). |
| App widget test | One full bout: instruction → countdown → recording → review, with a fake BLE controller. |
| End to end, no sensors | `simulation_lab` on any ESP32 board, with the lab app on a phone, through the whole protocol. |
| Hardware pilot | One session by a team member, then compare the summary screen with expectations before recruiting participants. |

---

## 9. Build order and effort

| Step | Work | Estimate |
|---|---|---|
| L1 | Firmware: lab environments, `LabStream`, lab commands, info packet, analog force driver, I2C driver stub, serial mirror, native tests | 1.5 days |
| L2 | App core: lab flavour, raw characteristic, decoder, recorder, export, unit tests | 1.5 days |
| L3 | App UI: setup, sensor check, runner, metronome tracks, review, summary, widget test | 2 days |
| L4 | PC analysis tool and an operator's guide (one page, printable) | 1 day |
| L5 | `simulation_lab` dry run | 0.5 day |

These estimates are for one developer working full days. Everything except L5's run on a
real board can be built and tested without the vest.

**Risks:**

- **Phone Bluetooth quirks.** Mitigated by MTU sizing, loss counting and the serial
  fallback.
- **Unknown RFP602 I2C board.** The driver stays a stub until the datasheet is known.
- **Manikin app workflow.** See question 2 below.
- **Fatigue.** Rest periods, plus the full-effort run is kept to 2 minutes.

---

## 10. Questions for the team

1. **RFP602 I2C module:** can you share the product link or a photo of the board's markings?
2. **Manikin app:**
   - Can you start and stop a session per bout and read its mean depth?
   - Does it run on a separate phone or tablet?
   - Does it also show the count or rate?
3. **Separate install:** is a separate "CPReady Lab" app alongside the normal one OK
   (recommended), or should lab mode be a hidden switch in the normal app?
4. **Export:** is adding `share_plus` OK, or should export be USB-only?
5. **Who runs sessions:** please confirm the assumption in §1.
