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

**Columns:**

| Column | Type | Description |
|--------|------|-------------|
| `t_us` | uint32 | Device `micros()` timestamp at read. Wraps ~71 min. |
| `sample_index` | uint32 | Monotonic per session (0, 1, 2...). Gaps = dropped samples. |
| `frame_sequence` | uint16 | BLE notification sequence number (wraps at 65535). |
| `stroke_count` | uint16 | Firmware's stroke counter at this frame. |
| `device_state` | uint8 | Firmware state machine state (idle/calibrating/active/fault). |
| `flags` | uint8 | Bitmask: `1`=streaming, `2`=sensor fault, `4`=overrun, `8`=calibrating. |
| `chest_x_mg` | int16 | Chest sensor X axis, milli-g (±32767 = ±32.767g). |
| `chest_y_mg` | int16 | Chest sensor Y axis. |
| `chest_z_mg` | int16 | Chest sensor Z axis (gravity + compression). |
| `base_x_mg` | int16 | Base/spine sensor X axis. |
| `base_y_mg` | int16 | Base sensor Y axis. |
| `base_z_mg` | int16 | Base sensor Z axis (gravity). |

**Important:**
- This is **pure sensor data** — no filtering, no depth computation, no stroke detection.
- Chest Z carries gravity (~+1000 mg when z points down) plus compression signal.
- Base Z is ~+1000 mg static (base sensor sits on floor/backboard).
- Net acceleration (compression) = `-(chest_z - base_z)` in g, after removing gravity.
- All values are **little-endian** on the wire; CSV is human-readable decimal.

**Gap detection:**
- `sample_index` jumps → missing samples (BLE drop or firmware overrun).
- `frame_sequence` jumps → entire frames lost.
- `flags` bit 2 (overrun) set → firmware buffer overflow.

---

## 2. `packets.csv` — Firmware Metrics Packets

**Source:** Original BLE metrics characteristic (`6e400003-b5a3-f393-e0a9-e50e24dcca9e`), notify-only. **Unchanged by this PR.**

**Rate:** ~5–10 Hz during compressions; one packet per stroke + periodic realtime updates.

**Columns:**

| Column | Type | Description |
|--------|------|-------------|
| `received_at` | ISO8601 UTC | Phone receipt timestamp. |
| `packet_type` | uint8 | `1`=realtime, `2`=final_summary, `3`=error, `4`=calibration_progress, `5`=calibration_ready. |
| `rate_cpm` | uint16 | Compressions per minute (firmware computed). |
| `depth_tenths_mm` | uint16 | **Mean depth per stroke** in tenths of mm (e.g., `530` = 53.0 mm). Firmware computes this per stroke from double integration of net acceleration. |
| `ccf_percent` | uint8 | Chest compression fraction (0–100). |
| `audio_prompt_code` | uint8 | Voice cue code (0=none, 1=push_faster, 2=push_slower, etc.). |
| `total_compressions` | uint16 | Cumulative stroke count this session. |
| `elapsed_sec` | uint16 | Session elapsed seconds (firmware clock). |
| `quality_flags` | uint16 | Bitmask: `1`=steady_cadence, `2`=first_stroke, `4`=bench_mode, `8`=recoil_estimated. |
| `sequence` | uint16 | Packet sequence (protocol v2+). Null for older firmware. |

**This is where "mean depth" lives** — `depth_tenths_mm` is the firmware's per-stroke calculation. The raw CSV has no depth; you compute it offline from `raw.csv` if you want to verify or re-derive.

---

## 3. `events.csv` — Session Lifecycle

**Source:** App-generated.

| Column | Type | Description |
|--------|------|-------------|
| `received_at` | ISO8601 UTC | Phone timestamp. |
| `event` | string | `recording_started`, `stroke`, `recording_stopped`, `interrupted`, `aborted`. |
| `detail` | string | Session UUID for `recording_started`; stroke count for `stroke`; reason for stop. |

---

## 4. `session.json` — Metadata + Summary

**Source:** App, written at start (`status: "recording"`) and atomically rewritten at stop (`status: "complete"` or `"interrupted"`).

```json
{
  "schema_version": 1,
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
  "missing_samples": 2,
  "missing_frames": 1,
  "firmware_dropped_frames": 0,
  "first_sample_index": 0,
  "last_sample_index": 14999,
  "files": ["raw.csv", "packets.csv", "events.csv"]
}
```

**Status values:** `recording` | `complete` | `interrupted` | `incomplete` (app killed mid-session) | `uploaded` | `failed`.

---

## Offline Replay / Re-computation

To re-derive depth from `raw.csv` (matches firmware algorithm conceptually):

```python
import pandas as pd
import numpy as np

df = pd.read_csv('raw.csv')
# Net acceleration in g (remove gravity)
net_g = -(df['chest_z_mg'] - df['base_z_mg']) / 1000.0
# Double integrate with Riemann sum (dt = 0.01s)
velocity = np.cumsum(net_g) * 9.80665 * 0.01  # m/s
depth = np.cumsum(velocity) * 0.01            # m
# Peak depth per stroke = max depth between zero-crossings of velocity
```

The firmware uses a low-pass filter (α ≈ 0.1) + zero-velocity update at each stroke; the raw double-integration above will drift without those corrections.

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