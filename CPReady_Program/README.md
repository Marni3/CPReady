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
│   ├── BleManager.h           # BLE GATT Server, Notify characteristic, string command mailbox
│   └── FeedbackController.h   # Non-blocking 1-2-3 acoustic buzzer pattern sequencer
├── src/
│   └── main.cpp               # Standard C++ entry point (PlatformIO / ESP-IDF)
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
- `COMPRESSION_START_THRESHOLD_G` (Default: `0.45g`): Sensitivity for detecting a downstroke.
- `RECOIL_THRESHOLD_G` (Default: `-0.35g`): Upward acceleration needed to confirm complete recoil.
- `REFRACTORY_LOCKOUT_MS` (Default: `250 ms`): Minimum interval between strokes (rejects bounces).
- `CALIBRATION_DURATION_MS` (Default: `2000 ms`): Idle hand-placement baseline window.
- `BUZZER_PIN` (Default: `25`): GPIO output for the piezo buzzer.

---

## 3. Bluetooth Low Energy Telemetry & Dart Integration

The binary packet format is documented in **`include/BLEReadings.h`**.
- Pushes an **8-byte packed binary payload** (`CPRMetricsPacket`) at stroke end or 10 Hz.
- Includes a copy-paste Dart `ByteData` parser class for Flutter developers.

---

## 4. How to Build & Flash

### Option A: PlatformIO (Recommended)
1. Open the `CPReady_Program` directory in VS Code with the PlatformIO extension installed.
2. Connect your ESP32 development board via USB.
3. Click the PlatformIO **Build** button (check mark) or **Upload** button (right arrow).

### Option B: Arduino IDE
1. Open `CPReady_Program.ino` in Arduino IDE.
2. In the Board Manager, select **ESP32 Dev Module**.
3. Install the **MPU6050** library by Electronic Cats via the Library Manager.
4. Set the Upload Speed to `115200` and flash the board.
