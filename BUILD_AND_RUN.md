# Quick Start — Build & Run

## Prerequisites
- ESP32 dev board (or ESP32-S3) + USB cable
- Android phone (API 21+) with USB debugging
- PlatformIO (`pip install platformio`)
- Flutter SDK (3.19+)
- Supabase account (for upload)

---

## 1. Firmware

### With Real Sensors (Vest)
```bash
cd CPReady_Program
# esp32dev environment: real I2C sensors
pio run -e esp32dev -t upload
pio device monitor -b 115200
```
Expected boot log:
```
[I2C SCAN] Probing I2C bus...
[I2C SCAN]  -> Device detected at address 0x68 (MPU-6050 Default)
[I2C MUX] PCA9548A Multiplexer detected at address 0x70.
[I2C MUX] Chest sensor mapped to SD3 (0x68).
[I2C MUX] Base sensor mapped to SD2 (0x68).
[OK] BLE GATT Server Advertising as 'CPReady'. Ready for app connection.
```

### Without Sensors (Bench / CI)
```bash
cd CPReady_Program
# fake_sensors environment: synthetic sensors, no hardware
pio run -e fake_sensors -t upload
pio device monitor -b 115200
```
Expected boot log:
```
[FAKE] Sensor init bypassed — no I2C hardware required.
[OK] BLE GATT Server Advertising as 'CPReady'. Ready for app connection.
```

---

## 2. Supabase Setup (One Time)

1. Go to https://supabase.com → New Project
2. Copy **Project URL** (e.g., `https://abc123.supabase.co`)
3. Settings → API → **anon public** key (starts with `eyJ...` or `sb_publishable_...`)
4. SQL Editor → Run contents of `supabase/telemetry_schema.sql`
5. Verify: Storage → Buckets → `recordings` exists (private); Table Editor → `telemetry_sessions` exists

---

## 3. Flutter APK

```bash
cd FLUTTER/cpready
flutter pub get
flutter build apk --debug \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_ANON_KEY
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

Install on phone:
```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## 4. Run a Session

1. **Open app** → Home screen
2. **Connect** to "CPReady" (scan → tap)
3. **Practice Setup**:
   - Enter trainee name
   - **Enable "Record raw sensor data"** (toggle)
   - Participant code: `P001` (or your code)
   - Experiment: `practice` (or `baseline`, `test-v2`, etc.)
   - Notes: optional
   - Continue
4. **Hand Placement** → Continue
5. **Calibration** → Keep vest still 2s → Continue
6. **Countdown** → Begin Compression → **Live Practice**
7. Perform compressions (or let fake sensor run)
8. **Hold to End Session** → Session Complete screen appears

---

## 5. Verify Data

### In App (Session Complete)
- Green "Session Saved" banner
- Telemetry line: `15000 samples · 1500 frames · uploaded` (or `saved locally`)

### In Supabase Dashboard
- **Storage** → `recordings` bucket → folder `<session_uuid>` → 4 files
- **Table Editor** → `telemetry_sessions` → one row with `status = uploaded`

### Local Files (Debug)
```bash
# List sessions
adb shell run-as com.example.cpready ls files/recordings/

# Pull one session's raw.csv
adb exec-out run-as com.example.cpready cat files/recordings/<uuid>/raw.csv > raw.csv
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| "No raw telemetry characteristic" | Firmware built without raw char? Re-flash. |
| Calibration fails (gravity implausible) | Vest not flat? Fake sensor gravity sign wrong? |
| Upload shows "not configured" | APK built without `--dart-define` creds. Rebuild. |
| Upload shows "failed" | Check Supabase URL/key; run SQL; bucket policy. |
| No samples in raw.csv | Raw characteristic not subscribed; check BLE logs. |
| `pio upload` fails: port busy | `pkill -f "pio\|monitor\|screen"` then retry. |

---

## Switching Between Fake/Real Sensors

No file edits are required. `CPReady_Program/platformio.ini` defines two build environments:

```ini
[env:esp32dev]      ; real I2C sensors
build_flags = -I include

[env:fake_sensors]  ; synthetic sensors, no hardware
build_flags = -I include -D FAKE_SENSORS
```

Select the environment with `-e`:
```bash
pio run -e esp32dev -t upload      # real sensors
pio run -e fake_sensors -t upload  # fake sensors
```