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
uint32_t lastCalibProgressNotifyMillis = 0;

// Configurable target duration (in seconds, default set in CPReadyConfig; 0 = manual stop)
uint32_t practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC; 

// Helper: Finalizes the active session, broadcasts final summary packet, and plays 3 beeps
void endAndFinalizeSession(uint32_t now) {
    Serial.println("[FLOW] Finalizing CPR practice session...");
    state = DeviceState::STANDBY;
    sensors.resetCalibration();

    #if ENABLE_DEMO_MODE
    CPRSessionSummary summary;
    summary.avg_rate_cpm = DEMO_RATE_CPM;
    summary.avg_depth_cm = (float)DEMO_DEPTH_MM / 10.0f;
    summary.recoil_compliance_percent = DEMO_RECOIL_OK ? 100.0f : 50.0f;
    summary.final_ccf_percent = DEMO_CCF_PERCENT;
    if (now > calibrationStartMillis + CPReadyConfig::CALIBRATION_DURATION_MS) {
        uint32_t activeMs = now - calibrationStartMillis - CPReadyConfig::CALIBRATION_DURATION_MS;
        summary.total_compressions = (uint16_t)(activeMs / 550);
        summary.total_duration_sec = (uint16_t)(activeMs / 1000);
    } else {
        summary.total_compressions = 0;
        summary.total_duration_sec = 0;
    }
    #else
    CPRSessionSummary summary = tracker.finalizeSession(now);
    #endif

    // Transmit finalized results packet (Packet Type 4) to Flutter
    CPRMetricsPacket finalPacket = summary.toPacket(PKT_TYPE_FINAL_SUMMARY);
    ble.sendPacket(finalPacket);
    Serial.printf("[FINAL TX] Rate: %.0f cpm | Depth: %.2f cm | Recoil: %.0f%% | CCF: %.0f%% | Total: %d\n",
        summary.avg_rate_cpm, summary.avg_depth_cm, summary.recoil_compliance_percent, summary.final_ccf_percent, summary.total_compressions);

    // Protocol Step 3: Buzzer buzzes THREE times indicating practice is complete
    feedback.playSessionComplete();
}

/**
 * Standardized BLE Message / Command Dispatcher
 * 
 * Receives incoming text commands from the mobile application.
 */
void onReceiveMessage_BLE(String message) {
    message.trim();
    message.toUpperCase();
    Serial.println("[BLE CMD] Received: " + message);

    if (message == "CALIBRATE") {
        Serial.println("[FLOW] Calibrate received. Initiating stationary baseline calibration...");
        sensors.resetCalibration();
        calibrationStartMillis = millis();
        lastCalibProgressNotifyMillis = calibrationStartMillis;
        state = DeviceState::CALIBRATING;

        // Broadcast initial calibration progress packet (Packet Type 2)
        CPRMetricsPacket calibPkt = {PKT_TYPE_CALIB_PROGRESS, 1, 0, 0, 0, PROMPT_NONE, 0, 0};
        ble.sendPacket(calibPkt);

        // Protocol Step 1: Buzzer buzzes ONCE indicating calibration is underway
        feedback.playCalibrationStart();
    }
    else if (message == "START") {
        if (state == DeviceState::CALIBRATED_READY) {
            Serial.println("[FLOW] Device is calibrated and ready. Starting active CPR session!");
            // Protocol Step 2: Buzzer buzzes TWICE indicating compressions should begin!
            feedback.playCompressionsBegin();
            tracker.startSession(millis());
            state = DeviceState::ACTIVE_SESSION;
            Serial.println("[FLOW] Live practice session started! Ready for compressions.");
        }
        else if (state == DeviceState::CALIBRATING) {
            Serial.println("[FLOW WARN] Start requested while calibration is still ongoing! Rejecting.");
            CPRMetricsPacket errPkt = {PKT_TYPE_ERROR, 0, 0, 0, 0, PROMPT_NONE, 0, 0};
            ble.sendPacket(errPkt);
        }
        else {
            // Fallback / legacy 1-step behavior: trigger calibration first
            Serial.println("[FLOW] Start received from uncalibrated state. Auto-calibrating first...");
            sensors.resetCalibration();
            calibrationStartMillis = millis();
            lastCalibProgressNotifyMillis = calibrationStartMillis;
            state = DeviceState::CALIBRATING;

            CPRMetricsPacket calibPkt = {PKT_TYPE_CALIB_PROGRESS, 1, 0, 0, 0, PROMPT_NONE, 0, 0};
            ble.sendPacket(calibPkt);
            feedback.playCalibrationStart();
        }
    }
    else if (message == "STOP") {
        Serial.println("[FLOW] Stop received from app.");
        endAndFinalizeSession(millis());
    }
    else if (message == "GET_RESULTS") {
        Serial.println("[FLOW] Retransmission requested via GET_RESULTS.");
        CPRMetricsPacket finalPacket = tracker.getLastSummary().toPacket(PKT_TYPE_FINAL_SUMMARY);
        ble.sendPacket(finalPacket);
    }
    else if (message == "PAUSE") {
        Serial.println("[FLOW] Pause received.");
        state = DeviceState::SESSION_PAUSED;
    }
    else if (message == "RESUME") {
        Serial.println("[FLOW] Resume received.");
        state = DeviceState::ACTIVE_SESSION;
    }
    else if (message.startsWith("SET_TIME:")) {
        int sec = message.substring(9).toInt();
        if (sec > 0) {
            practiceDurationSec = sec;
            Serial.printf("[CONFIG] Session duration set to %d seconds.\n", practiceDurationSec);
        }
    }
    else {
        Serial.println("[BLE CMD] Unhandled command: " + message);
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

    // 1. Check for Bluetooth Disconnection during active operation
    if (ble.checkAndClearDisconnectionEvent()) {
        if (state == DeviceState::CALIBRATING || state == DeviceState::ACTIVE_SESSION || 
            state == DeviceState::SESSION_PAUSED || state == DeviceState::CALIBRATED_READY) {
            Serial.println("[BLE WARN] Disconnected during active session! Immediately aborting.");
            feedback.abort();
            tracker.reset();
            sensors.resetCalibration();
            state = DeviceState::STANDBY;
        }
    }

    // 2. Process incoming BLE string commands safely in the main thread
    if (ble.hasPendingCommand()) {
        String cmd = ble.consumeCommand();
        onReceiveMessage_BLE(cmd);
    }

    // 3. Non-blocking audio sequencer update (handles 1, 2, or 3 beep patterns)
    feedback.update(now);

    // 4. State: CALIBRATING (Trainee rests hands idle on chest for configured duration)
    if (state == DeviceState::CALIBRATING) {
        #if !ENABLE_DEMO_MODE
        float dummyAccel;
        if (sensors.sample100Hz(dummyAccel, nowMicros)) {
            sensors.recordCalibrationSample();
        }
        #endif

        // Periodically broadcast calibration progress packet (Packet Type 2)
        if (now - lastCalibProgressNotifyMillis >= CPReadyConfig::CALIBRATION_PROGRESS_INTERVAL_MS) {
            lastCalibProgressNotifyMillis = now;
            uint16_t elapsedCalib = (uint16_t)((now - calibrationStartMillis) / 1000);
            CPRMetricsPacket calibPkt = {PKT_TYPE_CALIB_PROGRESS, 1, 0, 0, 0, PROMPT_NONE, 0, elapsedCalib};
            ble.sendPacket(calibPkt);
        }

        // Check if calibration window has elapsed
        if (now - calibrationStartMillis >= CPReadyConfig::CALIBRATION_DURATION_MS) {
            #if !ENABLE_DEMO_MODE
            sensors.finalizeCalibration();
            if (!sensors.isCalibrationStable()) {
                Serial.println("[ERROR] Calibration aborted: stability/plausibility checks failed.");
                CPRMetricsPacket errorPkt = {PKT_TYPE_ERROR, 0, 0, 0, 0, PROMPT_NONE, 0, 0};
                ble.sendPacket(errorPkt);
                sensors.resetCalibration();
                state = DeviceState::STANDBY;
            } else {
            #endif
                Serial.println("[FLOW] Calibration finished. Baselines stored. System is CALIBRATED_READY.");

                // Signal Flutter that calibration succeeded (Packet Type 3)
                CPRMetricsPacket successPkt = {PKT_TYPE_CALIB_SUCCESS, 1, 0, 0, 0, PROMPT_NONE, 0, 0};
                ble.sendPacket(successPkt);

                // Transition to CALIBRATED_READY and await instructor's "START"
                state = DeviceState::CALIBRATED_READY;
            #if !ENABLE_DEMO_MODE
            }
            #endif
        }
    }

    // 5. State: ACTIVE_SESSION (Active CPR compression monitoring)
    else if (state == DeviceState::ACTIVE_SESSION) {
        #if ENABLE_DEMO_MODE
        // Broadcast synthetic demo metrics at configured update rate (default 5 Hz)
        if (now - lastBleNotifyMillis >= CPReadyConfig::BLE_NOTIFY_INTERVAL_MS) {
            lastBleNotifyMillis = now;

            CPRReading demoReading;
            demoReading.rate_cpm          = DEMO_RATE_CPM;
            demoReading.depth_cm          = (float)DEMO_DEPTH_MM / 10.0f; // mm to cm
            demoReading.recoil_complete   = DEMO_RECOIL_OK;
            demoReading.ccf_percentage    = DEMO_CCF_PERCENT;
            demoReading.elapsed_seconds   = (now - calibrationStartMillis - CPReadyConfig::CALIBRATION_DURATION_MS) / 1000;
            demoReading.audio_prompt_code = PROMPT_NONE;
            demoReading.stroke_count      = (uint16_t)(demoReading.elapsed_seconds * 1.8f);

            ble.sendPacket(demoReading.toPacket(PKT_TYPE_REALTIME));
            Serial.println("[DEMO TX] " + demoReading.toDebugString());

            if (practiceDurationSec > 0 && demoReading.elapsed_seconds >= practiceDurationSec) {
                Serial.println("[FLOW] Practice time limit reached in demo mode.");
                endAndFinalizeSession(now);
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
                CPRMetricsPacket packet = reading.toPacket(PKT_TYPE_REALTIME);

                ble.sendPacket(packet);

                if (strokeCompleted) {
                    Serial.println("[STROKE] " + reading.toDebugString());
                }
            }

            // Auto-stop if session exceeds configured practice duration
            if (practiceDurationSec > 0 && tracker.getReading().elapsed_seconds >= practiceDurationSec) {
                Serial.println("[FLOW] Practice time limit reached.");
                endAndFinalizeSession(now);
            }
        }
        #endif
    }
}
