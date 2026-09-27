#include <Arduino.h>
#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"
#include "SensorManager.h"
#include "CompressionTracker.h"
#include "BleManager.h"
#include "FeedbackController.h"

// Subsystem Instances
SensorManager      sensors;
CompressionTracker tracker;
BleManager         ble;
FeedbackController feedback;

// System State Machine
DeviceState state = DeviceState::STANDBY;
uint32_t calibrationStartMillis = 0;
uint32_t lastBleNotifyMillis = 0;

// Configurable target duration (in seconds, default set in CPReadyConfig; 0 = manual stop)
uint32_t practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC; 

/**
 * Standardized BLE Message / Command Dispatcher
 * 
 * Takes an incoming text message from the Flutter/mobile app.
 * If software developers add new UI buttons, they simply configure the app
 * to send a text string over BLE, and insert their corresponding logic below.
 */
void onReceiveMessage_BLE(String message) {
    message.trim();
    message.toUpperCase();
    Serial.println("[BLE CMD] Received: " + message);

    if (message == "START") {
        Serial.println("[FLOW] Start received. Initiating 2-second idle calibration...");
        sensors.resetCalibration();
        calibrationStartMillis = millis();
        state = DeviceState::CALIBRATING;

        // Protocol Step 1: Buzzer buzzes ONCE indicating calibration is underway
        feedback.playCalibrationStart();
    }
    else if (message == "STOP") {
        Serial.println("[FLOW] Stop received. Practice session ended.");
        state = DeviceState::STANDBY;

        // Protocol Step 3: Buzzer buzzes THREE times indicating practice is complete
        feedback.playSessionComplete();
    }
    else if (message == "PAUSE") {
        Serial.println("[FLOW] Pause received.");
        state = DeviceState::SESSION_PAUSED;
    }
    else if (message == "RESUME") {
        Serial.println("[FLOW] Resume received.");
        state = DeviceState::ACTIVE_SESSION;
    }
    // Extensibility Example: Setting practice duration dynamically
    else if (message.startsWith("SET_TIME:")) {
        int sec = message.substring(9).toInt();
        if (sec > 0) {
            practiceDurationSec = sec;
            Serial.printf("[CONFIG] Session duration set to %d seconds.\n", practiceDurationSec);
        }
    }
    else {
        Serial.println("[BLE CMD] Unhandled custom command: " + message);
    }
}

void setup() {
    Serial.begin(115200);
    Serial.println("\n=========================================");
    Serial.println("     CPReady Firmware Initializing       ");
    Serial.println("=========================================");

    feedback.begin(CPReadyConfig::BUZZER_PIN);

    #if ENABLE_DEMO_MODE
    Serial.println("[DEMO] *** DEMO / SIMULATION MODE ENABLED ***");
    Serial.println("[DEMO] Emulating CPR metrics for mobile app testing.");
    #else
    if (!sensors.begin()) {
        Serial.println("[ERROR] Could not connect to both MPU6050 sensors (0x68 and 0x69). Check wiring!");
        state = DeviceState::FAULT_ERROR;
    } else {
        Serial.println("[OK] Both MPU6050 sensors initialized successfully.");
    }
    #endif

    ble.begin(CPReadyConfig::BLE_DEVICE_NAME);
    Serial.printf("[OK] BLE GATT Server Advertising as '%s'. Ready for app connection.\n", CPReadyConfig::BLE_DEVICE_NAME);
}

void loop() {
    uint32_t now = millis();
    uint32_t nowMicros = micros();

    // 1. Process incoming BLE string commands safely in the main thread
    if (ble.hasPendingCommand()) {
        String cmd = ble.consumeCommand();
        onReceiveMessage_BLE(cmd);
    }

    // 2. Non-blocking audio sequencer update (handles 1, 2, or 3 beep patterns)
    feedback.update(now);

    // 3. State: CALIBRATING (Trainee rests hands idle on chest for configured duration)
    if (state == DeviceState::CALIBRATING) {
        #if !ENABLE_DEMO_MODE
        float dummyAccel;
        if (sensors.sample100Hz(dummyAccel, nowMicros)) {
            sensors.recordCalibrationSample();
        }
        #endif

        // Check if calibration window has elapsed
        if (now - calibrationStartMillis >= CPReadyConfig::CALIBRATION_DURATION_MS) {
            #if !ENABLE_DEMO_MODE
            sensors.finalizeCalibration();
            #endif
            Serial.println("[FLOW] Calibration finished. Baselines stored.");

            // Protocol Step 2: Buzzer buzzes TWICE indicating compressions should begin!
            feedback.playCompressionsBegin();

            tracker.startSession(now);
            state = DeviceState::ACTIVE_SESSION;
            Serial.println("[FLOW] Live practice session started! Ready for compressions.");
        }
    }

    // 4. State: ACTIVE_SESSION (Active CPR compression monitoring)
    else if (state == DeviceState::ACTIVE_SESSION) {
        #if ENABLE_DEMO_MODE
        // Broadcast synthetic demo metrics at configured update rate (default 5 Hz)
        if (now - lastBleNotifyMillis >= CPReadyConfig::BLE_NOTIFY_INTERVAL_MS) {
            lastBleNotifyMillis = now;

            CPRReading demoReading;
            demoReading.rate_cpm = DEMO_RATE_CPM;
            demoReading.depth_cm = (float)DEMO_DEPTH_MM / 10.0f; // mm to cm
            demoReading.recoil_complete = DEMO_RECOIL_OK;
            demoReading.ccf_percentage = DEMO_CCF_PERCENT;
            demoReading.elapsed_seconds = (now - calibrationStartMillis - CPReadyConfig::CALIBRATION_DURATION_MS) / 1000;

            ble.sendMetrics(demoReading.toPacket());
            Serial.println("[DEMO TX] " + demoReading.toDebugString());

            if (practiceDurationSec > 0 && demoReading.elapsed_seconds >= practiceDurationSec) {
                Serial.println("[FLOW] Practice time limit reached.");
                state = DeviceState::STANDBY;
                feedback.playSessionComplete();
            }
        }
        #else
        float netAccel = 0.0f;
        if (sensors.sample100Hz(netAccel, nowMicros)) {
            // Process current sample through the harmonic pedometer engine
            bool strokeCompleted = tracker.processSample(netAccel, now);

            // Transmit immediately upon stroke completion, or throttle at configured interval
            if (strokeCompleted || (now - lastBleNotifyMillis >= CPReadyConfig::BLE_NOTIFY_INTERVAL_MS)) {
                lastBleNotifyMillis = now;

                const CPRReading& reading = tracker.getReading();
                CPRMetricsPacket packet = reading.toPacket();

                ble.sendMetrics(packet);

                if (strokeCompleted) {
                    Serial.println("[STROKE] " + reading.toDebugString());
                }
            }

            // Auto-stop if session exceeds configured practice duration
            if (practiceDurationSec > 0 && tracker.getReading().elapsed_seconds >= practiceDurationSec) {
                Serial.println("[FLOW] Practice time limit reached.");
                state = DeviceState::STANDBY;

                // Protocol Step 3: Buzzer buzzes THREE times indicating practice is complete
                feedback.playSessionComplete();
            }
        }
        #endif
    }
}
