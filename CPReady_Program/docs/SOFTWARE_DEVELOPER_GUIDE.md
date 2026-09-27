# CPReady Software Developer Integration Guide

**Target Audience**: Flutter / Mobile Application Developers & Firmware Contributors  
**Hardware Platform**: ESP32 Dev Module (Dual MPU6050 Sensors via I2C, Piezo Buzzer)  
**Primary Communication**: Bluetooth Low Energy (BLE)  

---

## 1. Quick Overview

The **CPReady** firmware turns an ESP32 into a smart CPR training vest worn over a training manikin. It tracks the four core American Heart Association (AHA) quality metrics:
- **Compression Rate**: Target 100–120 compressions per minute (cpm).
- **Compression Depth**: Target 50–60 mm (5.0–6.0 cm).
- **Chest Recoil**: Verification of complete upward chest release between downstrokes (flags rescuer leaning).
- **Chest Compression Fraction (CCF)**: Target $\ge 60\%$, ideally $> 80\%$ active compression time.

The system uses a single-threaded, non-blocking execution model. All time-sensitive tasks (100 Hz kinematic sampling, debounce lockouts, buzzer beep sequences, and 5 Hz BLE telemetry updates) are governed by millisecond software timers without using blocking `delay()` calls.

---

## 2. Codebase Map (What Each File Does)

| File | Purpose | What You Need to Know |
| :--- | :--- | :--- |
| **`include/CPReadyConfig.h`** | Master Configuration File | Central file for all parameters. Toggle demo mode, adjust test duration, set BLE device name, or tune sensitivity without touching code. |
| **`include/BLEReadings.h`** | BLE Packet & Data Model | Defines the packed 8-byte binary packet structure and provides a ready-to-use Dart/Flutter decoder. |
| **`include/BleManager.h`** | BLE GATT Server & Mailbox | Implements the Nordic UART GATT profile and a thread-safe string command mailbox. |
| **`src/main.cpp`** / **`CPReady_Program.ino`** | Main Application Loop | Orchestrates the state machine, updates non-blocking timers, and dispatches text commands in `onReceiveMessage_BLE()`. |
| **`include/CompressionTracker.h`** | Harmonic Pedometer Engine | Implements peak/trough detection, refractory bounce lockout, and cycle period integration for depth and rate. |
| **`include/SensorManager.h`** | Dual MPU6050 Driver | Reads top (chest) and bottom (base) accelerometers over I2C Fast Mode (400 kHz) and subtracts bed motion. |
| **`include/FeedbackController.h`** | Acoustic Buzzer Sequencer | Drives the 1-2-3 acoustic protocol completely non-blockingly. |
| **`include/CPRTypes.h`** | System Enums | Defines device states (`STANDBY`, `CALIBRATING`, `ACTIVE_SESSION`, `SESSION_PAUSED`, `FAULT_ERROR`). |

---

## 3. What the Software Developer Must Check Out

### 3.1 BLE Service & Characteristic UUIDs
The firmware implements the standard **Nordic UART Service (NUS)** layout:

- **Advertised Device Name**: `CPReady`
- **Service UUID**: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- **Metrics Telemetry (Notify)**: `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
- **Command Control (Write)**: `6e400003-b5a3-f393-e0a9-e50e24dcca9e`

### 3.2 Parsing the 8-Byte Binary Packet
Telemetry is broadcast as an exact **8-byte packed binary struct** (little-endian) to minimize latency and packet overhead:

| Byte Offset | Field Name | Data Type | Units & Interpretation |
| :---: | :--- | :---: | :--- |
| **0..1** | `rate_cpm` | `uint16` | Instantaneous cadence in compressions/min (e.g., `110`) |
| **2..3** | `depth_tenths_mm` | `uint16` | Compression depth in tenths of a millimeter. Divide by `100.0` for centimeters or by `10.0` for millimeters (e.g., `550` = `55.0 mm` = `5.50 cm`) |
| **4** | `recoil_status` | `uint8` | `1` = Full recoil achieved (good), `0` = Incomplete recoil (rescuer is leaning) |
| **5** | `ccf_percent` | `uint8` | Cumulative chest compression fraction percentage `0..100` (e.g., `74` = `74%`) |
| **6..7** | `session_elapsed_sec`| `uint16` | Total practice time elapsed in seconds (e.g., `120`) |

#### Ready-to-Use Dart Parser (Copy-Paste for Flutter)
```dart
import 'dart:typed_data';

class CPRMetrics {
  final int rateCpm;
  final double depthCm;
  final double depthMm;
  final bool recoilComplete;
  final int ccfPercent;
  final int elapsedSeconds;

  CPRMetrics({
    required this.rateCpm,
    required this.depthCm,
    required this.depthMm,
    required this.recoilComplete,
    required this.ccfPercent,
    required this.elapsedSeconds,
  });

  factory CPRMetrics.fromBytes(List<int> bytes) {
    if (bytes.length < 8) {
      throw ArgumentError("Expected 8 bytes, got ${bytes.length}");
    }
    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));

    final rate = byteData.getUint16(0, Endian.little);
    final depthTenthsMm = byteData.getUint16(2, Endian.little);
    final recoil = byteData.getUint8(4) == 1;
    final ccf = byteData.getUint8(5);
    final elapsed = byteData.getUint16(6, Endian.little);

    return CPRMetrics(
      rateCpm: rate,
      depthCm: depthTenthsMm / 100.0,
      depthMm: depthTenthsMm / 10.0,
      recoilComplete: recoil,
      ccfPercent: ccf,
      elapsedSeconds: elapsed,
    );
  }
}
```

---

## 4. Sending Commands from the App to the Firmware

Write UTF-8 strings to the **Command Characteristic** (`6e400003-b5a3-f393-e0a9-e50e24dcca9e`). The firmware dispatches these in `onReceiveMessage_BLE()` in `main.cpp`:

| Command String | Behavior | Hardware & Buzzer Reaction |
| :--- | :--- | :--- |
| `"START"` | Begins session | Buzzer buzzes **1 time** for 2.0s hands-still calibration; then buzzes **2 times** to signal compressions begin. |
| `"STOP"` | Terminates session | Buzzer buzzes **3 times** signaling trial is over; resets state to `STANDBY`. |
| `"PAUSE"` | Pauses practice | Halts active compression tracking without resetting timers. |
| `"RESUME"` | Resumes practice | Resumes live tracking. |
| `"SET_TIME:60"` | Dynamic trial duration | Sets trial duration to 60 seconds (or any integer in seconds; `0` runs indefinitely). |

### Adding New Commands
If you add a new UI button in Flutter (for example, a buzzer mute or reset button), simply add an `else if` branch inside `onReceiveMessage_BLE()` in `src/main.cpp`:
```cpp
else if (message == "MUTE") {
    // Custom logic here
}
```

---

## 5. Demo / Simulation Mode (Develop Without Hardware)

You do **not** need the physical manikin or sensors connected to build and test the mobile application.

1. Open `include/CPReadyConfig.h`.
2. Set `#define ENABLE_DEMO_MODE true`.
3. Flash the ESP32.

The device will immediately bypass sensor checks and stream realistic AHA metrics (`55 mm` depth, `110 cpm` rate, full recoil, `74%` CCF) at 5 Hz directly to your mobile app. This makes designing Flutter graphs, real-time gauges, and session summary screens completely independent of physical testing.

---

## 6. How to Tune Values for Physical Testing

If you are running physical trials on a manikin and need to calibrate without touching C++ code:
- **Depth Discrepancy**: If a physical ruler measures 5.0 cm but the app displays 4.2 cm, open `include/CPReadyConfig.h` and update `DEPTH_CALIBRATION_K` using the formula:  
  $$\text{New } K = \text{Current } K \times \left(\frac{\text{Ruler Depth}}{\text{App Depth}}\right) = 11.2 \times \left(\frac{5.0}{4.2}\right) = 13.3$$
- **Compression Sensitivity**: If light presses do not register, lower `COMPRESSION_THRESH_G` (e.g., from `0.45` to `0.35`). If table vibrations trigger false strokes, raise it (e.g., to `0.60`).
- **Chest Recoil / Leaning**: If the rescuer leans but the app does not flag it, make `RECOIL_THRESH_G` more negative (e.g., from `-0.35` to `-0.45`).
- **Trial Duration**: Change `PRACTICE_DURATION_SEC` to `30` or `60` for rapid testing, or `120` for standard AHA evaluations.
