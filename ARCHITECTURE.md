# CPReady Raw Telemetry Pipeline — Architecture & Changes

## High-Level Data Flow

```
┌──────────────┐    100 Hz I2C    ┌─────────────┐    BLE Notify    ┌─────────────┐
│ 2× MPU-6050  │ ──────────────► │  ESP32      │ ───────────────► │  Flutter    │
│ (chest+base) │                 │  Firmware   │  2 characteristics │  App        │
└──────────────┘                 └─────────────┘                 └─────────────┘
                                          │                              │
                                          │  Char 1: metrics (16 B)      │
                                          │  Char 2: raw telemetry       │
                                          ▼                              ▼
                                   ┌─────────────┐              ┌─────────────┐
                                   │  Telemetry  │              │  Local CSVs │
                                   │  Stream     │              │  + JSON     │
                                   └─────────────┘              └─────────────┘
                                                                       │
                                                                       ▼
                                                             ┌─────────────┐
                                                             │  Supabase   │
                                                             │  Storage +  │
                                                             │  PostgREST  │
                                                             └─────────────┘
```

---

## Firmware Changes (`CPReady_Program/`)

### New Files
| File | Purpose |
|------|---------|
| `include/TelemetryFrames.h` | Frozen binary contract: 16-byte header + 16-byte sample × N (max 10). `static_assert` enforces sizes. All offsets documented. |
| `include/TelemetryStream.h` | Batching engine: MTU-derived samples/frame, sequence counter, drop counter, flush, enable/disable. |
| `test_native/telemetry_frames.cpp` | 24 assertions on frame layout, encoding, bounds. |

### Modified Files
| File | Key Changes |
|------|-------------|
| `include/SensorManager.h` | • Added `#ifdef FAKE_SENSORS` guard around `begin()` and `readSensors()`<br>• `sample100Hz()` now takes optional `TelemetryFrames::SensorRawSample* outRaw` to capture raw chest/base milli-g alongside filtered net<br>• `toMilliG()` helper for int16 conversion |
| `include/BleManager.h` | • New raw characteristic UUID `6e400004-b5a3-f393-e0a9-e50e24dcca9e` (notify + read)<br>• `BLEDevice::setMTU(247)` at init<br>• `getMtu()` and `sendTelemetryFrame()` exposed |
| `include/CPReadyConfig.h` | Added `BLE_TARGET_MTU = 247` |
| `src/main.cpp` | • `TELEM:1` / `TELEM:0` command handlers<br>• On `TELEM:1`: `telemetry.setEnabled(true)`, `ble.sendCommand("TELEM:1")`<br>• In active loop: `sensor.sample100Hz(..., &rawSample)`, `telemetry.addSample(rawSample)`<br>• On STOP/fault/disconnect: `telemetry.setEnabled(false)`, `ble.sendCommand("TELEM:0")` |
| `src/simulation.cpp` | • Emits synthetic raw frames (chest.z = `-rawNetG`, base = 0)<br>• Handles `TELEM` commands |

### Build Environment
```ini
# platformio.ini
[env:fake_sensors]
build_flags = -I include -D FAKE_SENSORS
```
- **`pio run -e fake_sensors`**: `FAKE_SENSORS` is defined, so `begin()` returns true immediately and `readSensors()` emits a 100 cpm sine wave. No I2C hardware needed.
- **`pio run -e esp32dev`**: Real I2C init + MPU-6050 reads (for vest testers).

---

## Flutter App Changes (`FLUTTER/cpready/`)

### New Files (Core Telemetry)
| File | Responsibility |
|------|----------------|
| `lib/src/config/telemetry.dart` | Constants: UUID, frame sizes, file names, Supabase config via `--dart-define` |
| `lib/src/core/telemetry/raw_frame.dart` | `RawTelemetryFrame.fromBytes()` — strict length/type/version/count validation |
| `lib/src/core/telemetry/session_metadata.dart` | `SessionMetadata` + RFC 4122 v4 UUID generator |
| `lib/src/core/telemetry/telemetry_recorder.dart` | Local CSVs + atomic JSON. 1 s flush. Gap counting. Stop/abort. |
| `lib/src/core/telemetry/telemetry_session_record.dart` | SQLite queue row: `recording` → `complete`/`interrupted` → `uploaded`/`failed` |
| `lib/src/core/telemetry/upload_service.dart` | HTTPS upload: Storage POST (files) + PostgREST (metadata). 409 = success. Retry 5×. |

### Modified Files
| File | Key Changes |
|------|-------------|
| `lib/src/core/ble/ble.dart` | • `requestMtu(247)` after connect<br>• Raw characteristic discovery + `setNotifyValue(true)`<br>• `rawFrames` broadcast stream |
| `lib/src/core/ble/ble_controller.dart` | Telemetry settings (`telemetryEnabled`, `participantCode`, `experiment`, `notes`) + `rawFrames` accessor |
| `lib/src/core/history/session_repository.dart` | SQLite schema v5: `telemetry_sessions` table + CRUD |
| `lib/src/core/app_scope.dart` | Holds `TelemetryUploadService`, exposes to widget tree |
| `lib/main.dart` | App-start + lifecycle (`resumed`) → `uploadService.retryPending()` |
| `lib/src/screens/setup/practice_setup_screen.dart` | Telemetry opt-in section (toggle off by default, participant code, experiment, notes). Disabled when `!supportsRawTelemetry`. |
| `lib/src/screens/live_practice/live_practice_screen.dart` | • On session start: `recorder.start()`, subscribe `rawFrames`, save queue row `recording`, send `TELEM:1`<br>• On packet: `recorder.addMetrics()`<br>• On raw frame: `recorder.addFrame()`<br>• On end: `recorder.stop()`, upgrade queue row to `complete`/`interrupted`, fire-and-forget `uploadAndRecord()` |
| `lib/src/screens/session_complete/session_complete_screen.dart` | `_TelemetryStatus` widget: shows samples/frames + upload state (saved/uploading/uploaded/not-configured/failed/no-samples) |
| `android/app/src/main/AndroidManifest.xml` | Added `android.permission.INTERNET` |

### No New Dependencies
- Uses `dart:io`/`HttpClient` for upload
- Uses `path_provider` (already in pubspec) for local files
- Supabase via REST only — no `supabase_flutter` package

---

## Supabase Schema (`supabase/telemetry_schema.sql`)

```sql
-- Private bucket
insert into storage.buckets (id, name, public) values ('recordings','recordings',false);

-- Metadata table
create table public.telemetry_sessions (
  id uuid primary key,
  participant_code text not null,
  experiment text,
  notes text,
  status text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  sample_count int not null default 0,
  frame_count int not null default 0,
  missing_samples int not null default 0,
  missing_frames int not null default 0,
  size_bytes bigint not null default 0,
  device_name text,
  device_id text,
  app_version text,
  storage_prefix text not null,
  schema_version int not null default 1,
  created_at timestamptz not null default now()
);

-- Insert-only anon policies
alter table public.telemetry_sessions enable row level security;
create policy "anon insert telemetry sessions"
  on public.telemetry_sessions for insert to anon
  with check (char_length(participant_code) between 1 and 64);

create policy "anon upload recordings"
  on storage.objects for insert to anon
  with check (bucket_id = 'recordings');
```

**No SELECT/UPDATE/DELETE for anon** — app only writes. Read via dashboard or service role.

---

## Local Storage (Device)

```
<app_documents>/recordings/<session_uuid>/
  ├── raw.csv
  ├── packets.csv
  ├── events.csv
  └── session.json
```

- `session.json` written at start (`recording`) and atomically rewritten at stop.
- If app killed mid-session → row marked `incomplete` on next launch, not auto-uploaded.
- CSVs persist for manual recovery via `adb`.

---

## Build & Run

### Firmware
```bash
cd CPReady_Program
# With real sensors (default)
pio run -e esp32dev -t upload

# Without sensors (CI / bench test)
pio run -e fake_sensors -t upload
```

### Flutter APK
```bash
cd FLUTTER/cpready
flutter build apk --debug \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

### Supabase Setup
1. Create project at supabase.com
2. Run `supabase/telemetry_schema.sql` in SQL editor
3. Copy Project URL + anon/publishable key

---

## Test Coverage

| Layer | Tests |
|-------|-------|
| Firmware native | `test_native/telemetry_frames.cpp` — 24 pass |
| Flutter unit | `test/telemetry_test.dart` — 3 pass (decoder, recorder, gaps) |
| Flutter layout | `test/layout_matrix_test.dart` — 25 pass (all viewport sizes) |
| Pre-existing | 4 failures unrelated to this PR (`device_config_test`, `device_settings_test`) |

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Raw-first v1 | Record everything; derive detector behavior offline by replay |
| Opt-in telemetry | Default off; no impact on existing practice flow |
| Publishable key only | Never expose service-role key in app |
| Insert-only policies | App cannot read/modify others' data |
| 409 = success | Idempotent retry without extra round-trip |
| Local-first | Session survives app kill; upload retries on next launch |
| No new deps | Minimal attack surface, faster builds |
| `FAKE_SENSORS` flag | Single source, two build targets |