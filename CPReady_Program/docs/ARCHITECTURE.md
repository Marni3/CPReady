# CPReady Firmware Architecture Specification

**Project**: CPReady – Supplementary CPR Training Vest  
**Target Hardware**: ESP32 Dev Module (WROOM-32 / ESP32-S3)  
**Engineering Consultant**: Sir Reyn  
**Document Purpose**: Object-Oriented, Non-Blocking, Single-Threaded Architecture for Capstone Firmware Implementation

---

## 1. Architectural Principles & Constraints

### 1.1 Non-Blocking Execution Model
The firmware strictly prohibits the use of blocking delay calls (`delay()`) inside the active operational loop. All temporal operations—such as sensor sampling intervals (100 Hz), peak detection refractory lockouts (250 ms), and Bluetooth Low Energy notification throttling (5–10 Hz)—are governed by discrete `millis()` or `micros()` software timers.

### 1.2 Single-Threaded Application Orchestration
While the ESP32 hardware employs dual Xtensa cores and runs FreeRTOS under the Arduino abstraction layer, all application logic, math pipelines, and state transitions are consolidated into a deterministic single-threaded execution flow within `loop()`. This prevents thread synchronization bugs, mutex contention, and race conditions, ensuring that software developers with Dart/Flutter or basic Arduino backgrounds can easily follow, debug, and modify the code.

### 1.3 Asynchronous BLE-to-Main-Loop Bridge
Because the underlying ESP32 BLE stack (such as `NimBLEDevice` or standard `BLEDevice`) processes radio packets within an asynchronous background FreeRTOS task, callbacks cannot directly manipulate the main application state without concurrency risks. Instead, incoming BLE write events place commands into a lightweight, volatile single-command mailbox. The main thread inspects this mailbox during its normal loop cycle and dispatches the standardized `onReceiveMessage_BLE` handler safely in the primary thread context.

---

## 2. Interactive Session Protocol & Mobile Audio Guidance

All acoustic prompts, metronome pacing, and instructional voice coaching are delivered directly through the smartphone speaker via the mobile application, driven by standardized BLE packet notifications:

```mermaid
sequenceDiagram
    autonumber
    participant App as Flutter Mobile App
    participant PhoneSPK as Phone Speaker
    participant ESP as ESP32 (CPReady)
    participant Trainee as Trainee / Manikin

    Note over App,Trainee: Step 1: Pre-Session Calibration
    App->>ESP: BLE Write: "CALIBRATE"
    ESP-->>App: BLE Notify: Packet Type 2 (Calibration in progress)
    App->>Trainee: Displays "Calibrating... Keep hands still"
    Note over Trainee: Trainee rests hands idle on chest pad
    ESP->>ESP: Non-blocking 2-second static baseline sampling (200 samples)
    ESP-->>App: BLE Notify: Packet Type 3 (Calibrated Ready)
    App->>Trainee: Prompts "Ready to Begin Session"
    
    Note over App,Trainee: Step 2: Compressions Begin
    App->>ESP: BLE Write: "START"
    App->>PhoneSPK: "Begin compressions now!"
    Note over Trainee: Trainee begins active rhythmic CPR compressions
    ESP->>ESP: 100 Hz differential sampling & harmonic pedometer tracking
    ESP-->>App: BLE Notify: 8-byte CPRMetricsPacket (at stroke end or 10 Hz)
    opt Audio Prompt Code > 0
        App->>PhoneSPK: Spoken voice cue ("Push harder", "Release completely", etc.)
    end
    
    Note over App,Trainee: Step 3: Session Complete
    App->>ESP: BLE Write: "STOP" (or practice timer reaches limit)
    ESP->>ESP: Aggregate final averages & CCF %
    ESP-->>App: BLE Notify: 11-byte summary packet (Packet Type 4)
    App->>PhoneSPK: Plays session complete chime
    ESP->>ESP: State returns to STANDBY
```

---

## 3. High-Level Class Architecture

```mermaid
classDiagram
    class SensorManager {
        -MPU6050 chestSensor
        -MPU6050 baseSensor
        -float chestGravityOffset
        -float baseGravityOffset
        -float lastFilteredNetAccel
        -uint32_t lastSampleMicros
        +begin() bool
        +sample100Hz(outNetAccel, currentMicros) bool
        +resetCalibration() void
        +recordCalibrationSample() void
        +finalizeCalibration() void
    }

    class CompressionTracker {
        -StrokeState state
        -CPRMetrics metrics
        -float peakAccel
        -float troughAccel
        -uint32_t lastStrokePeakMillis
        -uint32_t totalActiveCompressionMillis
        +reset() void
        +startSession(currentMillis) void
        +processSample(netAccel, currentMillis) bool
        +getMetrics() CPRMetrics
    }

    class BleManager {
        -BLEServer* pServer
        -BLECharacteristic* pNotifyChar
        -BLECharacteristic* pCommandChar
        -volatile bool hasCommandFlag
        -char mailboxString[64]
        +begin(deviceName) void
        +sendPacket(packet) bool
        +hasPendingCommand() bool
        +consumeCommand() String
    }
```

---

## 4. Software Extensibility: `onReceiveMessage_BLE`

The command dispatcher in the main sketch takes a simple string argument. This enables Flutter/Dart developers to add new buttons or features simply by mapping UI clicks to text messages:

```cpp
void onReceiveMessage_BLE(String message) {
    message.trim();
    message.toUpperCase();

    if (message == "CALIBRATE") {
        sensors.resetCalibration();
        calibrationStartMillis = millis();
        state = DeviceState::CALIBRATING;
    }
    else if (message == "START") {
        if (state == DeviceState::CALIBRATED_READY) {
            tracker.startSession(millis());
            state = DeviceState::ACTIVE_SESSION;
        }
    }
    else if (message == "STOP") {
        endAndFinalizeSession(millis());
    }
    else if (message == "PAUSE") {
        state = DeviceState::SESSION_PAUSED;
    }
    else if (message == "RESUME") {
        state = DeviceState::ACTIVE_SESSION;
    }
    // Software developers can easily add new custom commands here:
    else if (message.startsWith("SET_TIME:")) {
        int sec = message.substring(9).toInt();
        practiceDurationSec = sec;
    }
}
```

---

## 5. Binary BLE Notification Packet (8 Bytes)

The ESP32 pushes an 8-byte structured binary payload on each completed compression cycle (or at a throttled rate of 5–10 Hz) via a custom BLE Notify characteristic:

| Byte Offset | Field Name | Data Type | Units / Scale | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0..1` | `compression_rate` | `uint16_t` | 1 cpm | Instantaneous rate (Target: 100–120 cpm) |
| `2..3` | `compression_depth` | `uint16_t` | 0.1 mm | Compression depth (Target: 500–600 = 5.0–6.0 cm) |
| `4` | `recoil_status` | `uint8_t` | Boolean (0 or 1) | 1 = Full chest recoil; 0 = Incomplete return / leaning |
| `5` | `ccf_percent` | `uint8_t` | 1% | Current session CCF (Target: $\ge 60\%$) |
| `6..7` | `elapsed_seconds` | `uint16_t` | 1 s | Cumulative session runtime |
