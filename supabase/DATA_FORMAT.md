# CPReady Raw Telemetry — Data Format Reference

Every recorded session produces **four files** in a folder named by the session UUID:

```
recordings/
└── <session_uuid>/
    ├── raw.csv        # 100 Hz raw accelerometer samples
    ├── packets.csv    # Firmware metrics packets (existing BLE protocol)
    ├── events.csv     # Session lifecycle events
    └── session.json   # Metadata + summary
```

The same four files exist locally on the device under the app's documents directory.

---

## 1. `raw.csv` — 100 Hz Raw Accelerometer

**Source:** BLE raw telemetry characteristic (`6e400004-b5a3-f393-e0a9-e50e24dcca9e`), notify-only.

**Rate:** 100 Hz (one row per sample). Firmware batches up to 10 samples per BLE notification depending on negotiated MTU.

**Columns (schema v2):**

| Column | Type | Description |
|--------|------|-------------|
| `t_us` | uint32 | Device `micros()` timestamp at read. Wraps ~71 min. |
| `sample_index` | uint32 | Monotonic per session (0, 1, 2...). Gaps = dropped samples. |
| `frame_sequence` | uint16 | BLE notification sequence number (wraps at 65535). |
| `stroke_count` | uint16 | Firmware's stroke counter at this frame. |
| `device_state` | uint8 | `0`=STANDBY, `1`=CALIBRATING, `2`=ACTIVE_SESSION, `3`=SESSION_PAUSED, `4`=FAULT_ERROR, `5`=CALIBRATED_READY. |
| `flags` | uint8 | Bitmask: `1`=streaming, `2`=sensor fault, `4`=overrun, `8`=calibrating. |
| `chest_x_mg` | int16 | Chest sensor X axis, milli-g (±32767 = ±32.767g). |
| `chest_y_mg` | int16 | Chest sensor Y axis. |
| `chest_z_mg` | int16 | Chest sensor Z axis (gravity + compression). |
| `base_x_mg` | int16 | Base/spine sensor X axis (`0` when only 1 MPU is connected). |
| `base_y_mg` | int16 | Base sensor Y axis (`0` when only 1 MPU is connected). |
| `base_z_mg` | int16 | Base sensor Z axis (`0` when only 1 MPU is connected). |
| `unclamped_depth_mm` | uint8 | Latest stroke depth in mm before the 10.0 cm display ceiling clamp (`0..255`). |

**Important:**
- `chest_*_mg` and `base_*_mg` are **unfiltered raw sensor readings**.
- When two MPUs are physically connected, `base_*_mg` is still recorded in `raw.csv` even when the runtime algorithm is in **1-MPU (Chest Only)** mode (`SET_MPU:1`), enabling offline differential vs single-sensor comparisons.
- In 1-MPU mode (`DEFAULT_USE_DUAL_MPU = false`), net compression acceleration is `-aChestG` along the learned 3-axis resting gravity vector. In 2-MPU mode (`SET_MPU:2`), net compression acceleration is `-(aChestG - aBaseG)`.
- All values are **little-endian** on the wire; CSV is human-readable decimal.

**Gap detection:**
- `sample_index` jumps → missing samples (BLE drop or firmware overrun).
- `frame_sequence` jumps → entire frames lost.
- `flags` bit 2 (overrun) set → firmware buffer overflow.

---

## 2. `packets.csv` — Firmware Metrics Packets

**Source:** BLE metrics characteristic (`6e400002-b5a3-f393-e0a9-e50e24dcca9e`), notify-only (`6e400003-b5a3-f393-e0a9-e50e24dcca9e` is the write-only command characteristic).

**Rate:** ~5–10 Hz during compressions; one packet per stroke + 5 Hz periodic realtime updates.

**Columns (schema v2):**

| Column | Type | Description |
|--------|------|-------------|
| `received_at` | ISO8601 UTC | Phone receipt timestamp. |
| `packet_type` | uint8 | `1`=realtime, `2`=calib_progress, `3`=calib_success, `4`=final_summary, `5`=error, `6`=config_report. |
| `recoil_status` | uint8 | Live (`packet_type=1`): `1`=full recoil, `0`=leaning. Summary (`packet_type=4`): recoil compliance % (`0..100`). |
| `rate_cpm` | uint16 | Compressions per minute (live median of recent periods, or session mean on `packet_type=4`). |
| `depth_tenths_mm` | uint16 | Compression depth in 0.1 mm (`540` = 54.0 mm = 5.40 cm). Live = latest stroke; `packet_type=4` = session mean depth. |
| `ccf_percent` | uint8 | Chest compression fraction (`0..100%`). |
| `audio_prompt_code` | uint8 | For `packet_type=1`: `0`=none, `1`=push_harder, `2`=push_shallower, `3`=release_fully, `4`=speed_up, `5`=slow_down, `6`=good_job. For `packet_type=5`: error reason code (`1..8`). |
| `total_compressions` | uint16 | Cumulative stroke count this session (from protocol v2 16-bit `stroke_count`). |
| `elapsed_sec` | uint16 | Session elapsed seconds (firmware clock). |
| `quality_flags` | uint8 | Bitmask: `1`=steady_cadence, `2`=first_stroke, `4`=bench_mode, `8`=recoil_estimated. |
| `sequence` | uint16 | BLE notification sequence number (protocol v2+). |

---

## 3. `events.csv` — Session Lifecycle

**Source:** App-generated.

| Column | Type | Description |
|--------|------|-------------|
| `received_at` | ISO8601 UTC | Phone timestamp. |
| `event` | string | `recording_started`, `device_config`, `stroke`, `device_error`, `final_summary`, `recording_stopped`, `interrupted`. |
| `detail` | string | Session UUID for `recording_started`; JSON config for `device_config`; stroke count for `stroke`; JSON summary for `final_summary`; sample/frame counts for stop. |

---

## 4. `session.json` — Metadata + Summary

**Source:** App, written at start (`status: "recording"`) and atomically rewritten at stop (`status: "complete"` or `"interrupted"`).

```json
{
  "schema_version": 2,
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "participant_code": "P001",
  "experiment": "practice",
  "notes": "baseline test",
  "device_name": "CPReady",
  "device_id": "a1:b2:c3:d4:e5:f6",
  "app_version": "1.0.0",
  "started_at": "2026-11-01T12:00:00.000Z",
  "ended_at": "2026-11-01T12:02:30.000Z",
  "status": "complete",
  "sample_count": 15000,
  "frame_count": 1500,
  "missing_samples": 0,
  "missing_frames": 0,
  "firmware_dropped_frames": 0,
  "first_sample_index": 0,
  "last_sample_index": 14999,
  "device_config": {
    "profile": "manikin",
    "depth_k": 11.2,
    "practice_duration_sec": 120
  },
  "final_summary": {
    "rate_cpm": 110,
    "depth_tenths_mm": 560,
    "recoil_percent": 100,
    "ccf_percent": 92,
    "total_compressions": 180,
    "elapsed_sec": 120,
    "quality_flags": 9
  },
  "files": ["raw.csv", "packets.csv", "events.csv"]
}
```

**Status values:** `recording` | `complete` | `interrupted` | `incomplete` (app killed mid-session) | `uploaded` | `failed`.

---

## Offline Replay / Re-computation

Firmware depth is computed per stroke by `DepthEstimator.h` (`closedCycleDepthCm` for continuous strokes and `fromRestDepthCm` after pauses), not by an unbounded cumulative sum over the whole file:

1. Learn the resting 3-axis gravity unit vector $\hat{u}$ from the motionless baseline (`GravityAxis.h`) and project each sample: $a_{	ext{chest}}(t) = ec{a}(t)\cdot\hat{u} - \|ec{g}_0\|$, with downward compression positive (`rawNet = -aChestG` in 1-MPU mode).
2. Detect stroke boundaries on the 1-pole IIR low-pass filtered signal (`LOWPASS_FILTER_ALPHA = 0.25`, $f_c pprox 4.5	ext{ Hz}$).
3. Over each closed cycle $[i_{	ext{start}}, i_{	ext{end}}]$ of duration $T = \sum \Delta t_k$:
   - Remove cycle mean acceleration $ar{a} = rac{1}{T}\sum a_k \Delta t_k$ so $v(T) = v(0) = 0$.
   - Integrate velocity $v_j = \sum_{k \le j}(a_k - ar{a})\Delta t_k$ and remove cycle mean velocity $ar{v} = rac{1}{T}\sum v_j \Delta t_j$ so $x(T) = x(0) = 0$.
   - Integrate displacement $x_j = \sum_{k \le j}(v_k - ar{v})\Delta t_k$ and take $\max_j x_j 	imes (K / 11.20)$.

---

## Supabase Storage Layout

```
bucket: recordings (private)
object path: <session_uuid>/raw.csv
object path: <session_uuid>/packets.csv
object path: <session_uuid>/events.csv
object path: <session_uuid>/session.json
```

Table `telemetry_sessions` has one row per session with `storage_prefix = <session_uuid>`. Join on `id = session_id`.

---

## Local Device Access (Debug)

```bash
# List sessions
adb shell run-as com.example.cpready ls files/recordings/

# Pull one session
adb exec-out run-as com.example.cpready cat files/recordings/<uuid>/raw.csv > raw.csv
```
