# CPReady Embedded Firmware Project

ESP32-based firmware for the **CPReady** CPR Training Vest prototype.

---

## 1. Directory Structure

```
CPReady_Program/
├── include/                   # C++ Header files (Modular Subsystems)
│   ├── CPReadyConfig.h        # ★ MASTER CONFIGURATION FILE (Tune all parameters here)
│   ├── BLEReadings.h          # ★ BLE TELEMETRY & PACKET STRUCT (Includes Dart parser)
│   ├── CPRTypes.h             # Common state enums and command packet layout
│   ├── SensorManager.h        # Dual MPU6050 I2C Fast Mode driver & differential subtraction
│   ├── CompressionTracker.h   # Harmonic pedometer engine (Rate, Depth, Recoil, CCF)
│   └── BleManager.h           # BLE GATT Server, Notify characteristic, string command mailbox
├── src/
│   └── main.cpp               # Standard C++ entry point (PlatformIO / ESP-IDF)
│   └── simulation.cpp         # Simulation of Fake Packets (PlatformIO / ESP-IDF)
├── docs/
│   ├── CALIBRATION_AND_TUNING_GUIDE.md # Step-by-step calibration & parameter guide
│   ├── CPReady_Calibration_and_Tuning_Guide.pdf # Printable PDF walkthrough
│   ├── SOFTWARE_DEVELOPER_GUIDE.md # Quick guide for mobile app developers & integration
│   ├── ARCHITECTURE.md        # Object-oriented architecture & sequence diagrams
│   ├── ALGORITHM_RESEARCH.md  # Deep dive into pedometer & CPR resuscitation literature
│   └── ALGORITHM_RESEARCH.pdf # Formatted 7-page PDF with rendered LaTeX equations
├── platformio.ini             # PlatformIO build configuration
├── CPReady_Program.ino        # Arduino IDE entry point sketch
└── README.md                  # This file
```

---

## 2. Tuning Parameters Without Changing Code

If you or the students need to adjust calibration factors, detection thresholds, pin assignments, or target ranges, open:
📁 **`include/CPReadyConfig.h`**

All parameters are heavily commented with their default values and tuning guidelines:
- `DEPTH_CALIBRATION_K` (Default: `11.2f`): Increase if readings are too shallow; decrease if too deep.
  After flashing the October 2026 detector fixes, re-run Manikin Calibration: K values saved
  with the old detector were fitted to its miscounted strokes.
- `COMPRESSION_START_THRESHOLD_G` (Default: `0.45g`): Upper cap of the adaptive downstroke
  threshold (the threshold follows 40 % of the recent signal envelope, floor `MIN_START_THRESHOLD_G`).
- `RECOIL_THRESHOLD_G` (Default: `-0.35g`): Acceleration proxy for recoil. Without a force sensor
  it cannot detect leaning, so it is reported as an estimate (`RECOIL_MEASURED_BY_FORCE_SENSOR`).
- `REFRACTORY_LOCKOUT_MS` (Default: `300 ms`): Minimum interval between stroke *onsets* (200 cpm ceiling).
- `CALIBRATION_DURATION_MS` (Default: `2000 ms`): Idle hand-placement baseline window.

---

## 3. Bluetooth Low Energy Telemetry & Dart Integration

The binary packet format is documented in **`include/BLEReadings.h`**. The command
and packet reference is `docs/SOFTWARE_DEVELOPER_GUIDE.md` §3 and §4.5.
- Pushes a **16-byte packed binary payload** (`CPRMetricsPacket`, protocol v2) at every
  stroke end and as a 5 Hz heartbeat.
- Bytes 12..15 carry a 16-bit stroke count and a sequence number for lost-packet counting.

## 3a. Tests Without Hardware

- `test_native/tracker_regression.cpp`: native regression test for the stroke detector
  (see `test_native/README.md`). Run it after any change to `CompressionTracker.h`.
- `pio run -e simulation`: firmware that feeds synthetic strokes through the production
  tracker over BLE, so the app can be exercised without sensors.

---

## 4. How to Build & Flash

### Option A: PlatformIO (Recommended)
1. Open the `CPReady_Program` directory in VS Code with the PlatformIO extension installed.
2. Connect your ESP32 development board via USB.
3. Click the PlatformIO **Build** button (check mark) or **Upload** button (right arrow).

### Option B: Arduino IDE (not recommended)
PlatformIO is the supported build. `CPReady_Program.ino` is a copy of `src/main.cpp`
kept for reference. The Arduino IDE cannot build this folder as it stands: it would
compile both the `.ino` and `src/main.cpp` (duplicate `setup()`/`loop()`) and it does
not search `include/`. To use the IDE:
1. Copy `CPReady_Program.ino` and every file from `include/` into a new sketch folder.
2. Copy `lib/Adafruit_MPU6050` into your Arduino `libraries` folder (this vendored copy
   adds MPU-6500/clone support and read-error reporting). Also install
   **Adafruit Unified Sensor** and **Adafruit BusIO** from the Library Manager.
   Do **not** use the Electronic Cats MPU6050 library.
3. Select **ESP32 Dev Module** and flash.
