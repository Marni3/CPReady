#include <Arduino.h>
#include <Preferences.h>
#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"
#include "SensorManager.h"
#include "CompressionTracker.h"
#include "BleManager.h"

// Subsystem Instances
SensorManager      sensors;
CompressionTracker tracker;
BleManager         ble;
Preferences        prefs;

// System State Machine
DeviceState state = DeviceState::STANDBY;
uint32_t calibrationStartMillis = 0;
uint32_t lastBleNotifyMillis = 0;
uint32_t lastCalibProgressNotifyMillis = 0;

// Configurable target duration (in seconds, default set in CPReadyConfig; 0 = manual stop)
uint32_t practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC; 

// Helper: Finalizes the active session and broadcasts final summary packet
void endAndFinalizeSession(uint32_t now) {
    Serial.println("[FLOW] Finalizing CPR practice session...");
    state = DeviceState::STANDBY;
    sensors.resetCalibration();
    practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;

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
        CPRMetricsPacket calibPkt = {PKT_TYPE_CALIB_PROGRESS, 1, 0, 0, 0, PROMPT_NONE, 0, 0, CADENCE_FLAG_STEADY};
        ble.sendPacket(calibPkt);
    }
    else if (message == "START") {
        if (state == DeviceState::CALIBRATED_READY) {
            Serial.println("[FLOW] Device is calibrated and ready. Starting active CPR session!");
            tracker.startSession(millis());
            state = DeviceState::ACTIVE_SESSION;
            Serial.println("[FLOW] Live practice session started! Ready for compressions.");
        }
        else if (state == DeviceState::CALIBRATING) {
            Serial.println("[FLOW WARN] Start requested while calibration is still ongoing! Rejecting.");
            CPRMetricsPacket errPkt = {PKT_TYPE_ERROR, 0, 0, 0, 0, PROMPT_NONE, 0, 0, 0};
            ble.sendPacket(errPkt);
        }
        else {
            // Fallback / legacy 1-step behavior: trigger calibration first
            Serial.println("[FLOW] Start received from uncalibrated state. Auto-calibrating first...");
            sensors.resetCalibration();
            calibrationStartMillis = millis();
            lastCalibProgressNotifyMillis = calibrationStartMillis;
            state = DeviceState::CALIBRATING;

            CPRMetricsPacket calibPkt = {PKT_TYPE_CALIB_PROGRESS, 1, 0, 0, 0, PROMPT_NONE, 0, 0, CADENCE_FLAG_STEADY};
            ble.sendPacket(calibPkt);
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
    else if (message.startsWith("SET_K:")) {
        float k = message.substring(6).toFloat();
        if (k >= 1.0f && k <= 30.0f) {
            tracker.setDepthK(k);
            prefs.putFloat("depth_k", k);
            Serial.printf("[NVS] Depth calibration scalar K updated to %.2f (persisted to flash)\n", k);
        }
    }
    else if (message == "SET_PROFILE:BENCH") {
        tracker.setProfile(CPReadyConfig::KinematicProfile::BENCH_TEST);
        prefs.putUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::BENCH_TEST);
        prefs.putFloat("depth_k", tracker.getDepthK());
        Serial.println("[NVS] Kinematic profile set to BENCH_TEST (persisted to flash: start 0.25g, recoil -0.18g, K=9.5)");
    }
    else if (message == "SET_PROFILE:MANIKIN") {
        tracker.setProfile(CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        prefs.putUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        prefs.putFloat("depth_k", tracker.getDepthK());
        Serial.println("[NVS] Kinematic profile set to MANIKIN_STANDARD (persisted to flash: start 0.45g, recoil -0.35g, K=11.2)");
    }
    else if (message.startsWith("CALIBRATE_TARGET:")) {
        float targetCm = message.substring(17).toFloat();
        float newK = 0.0f;
        if (tracker.calibrateFromLastSummary(targetCm, newK)) {
            prefs.putFloat("depth_k", newK);
            Serial.printf("[CALIB] Auto-calibrated scalar K to %.2f based on target %.2f cm (persisted to flash)\n", newK, targetCm);
            CPRMetricsPacket calibDonePkt = {PKT_TYPE_CALIB_SUCCESS, 1, 0, 0, 0, PROMPT_NONE, 0, 0, CADENCE_FLAG_STEADY};
            ble.sendPacket(calibDonePkt);
        } else {
            Serial.printf("[CALIB ERR] Failed to calibrate target %.2f cm: no valid completed session depth found!\n", targetCm);
            CPRMetricsPacket errPkt = {PKT_TYPE_ERROR, 0, 0, 0, 0, PROMPT_NONE, 0, 0, 0};
            ble.sendPacket(errPkt);
        }
    }
    else if (message == "RESET_CONFIG") {
        prefs.clear();
        tracker.setProfile(CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        tracker.setDepthK(CPReadyConfig::DEPTH_CALIBRATION_K);
        practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
        Serial.println("[NVS] Flash cleared! Restored factory defaults (MANIKIN_STANDARD, K=11.2).");
    }
    else if (message == "GET_CONFIG") {
        Serial.printf("[CONFIG] Profile: %s | Depth K: %.2f | StartThresh: %.2fg | RecoilThresh: %.2fg | Duration: %d sec\n",
            tracker.getProfile() == CPReadyConfig::KinematicProfile::BENCH_TEST ? "BENCH_TEST" : "MANIKIN_STANDARD",
            tracker.getDepthK(), tracker.getCompressionStartThresholdG(), tracker.getRecoilThresholdG(), practiceDurationSec);
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

    // Initialize Flash NVS Preferences & Load Calibrated Parameters
    // Note: setProfile resets depthCalibrationK to profile default, so setProfile MUST run before setDepthK.
    prefs.begin(CPReadyConfig::NVS_NAMESPACE, false);
    float savedK = prefs.getFloat("depth_k", CPReadyConfig::DEPTH_CALIBRATION_K);
    uint8_t savedProfile = prefs.getUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
    tracker.setProfile((CPReadyConfig::KinematicProfile)savedProfile);
    tracker.setDepthK(savedK);
    Serial.printf("[NVS] Flash configuration loaded: Profile=%s | Depth K=%.2f\n",
        savedProfile == (uint8_t)CPReadyConfig::KinematicProfile::BENCH_TEST ? "BENCH_TEST" : "MANIKIN_STANDARD", savedK);

    #if ENABLE_DEMO_MODE
    Serial.println("[DEMO] *** DEMO / SIMULATION MODE ENABLED ***");
    Serial.println("[DEMO] Emulating CPR metrics for mobile app testing.");
    #else
    if (!sensors.begin()) {
        #if USE_DUAL_MPU
        Serial.println("[ERROR] Failed to initialize MPU6050 sensors via PCA9548A multiplexer! Check wiring and 0x70 address.");
        #else
        Serial.println("[ERROR] Failed to initialize chest MPU6050 sensor! Check wiring.");
        #endif
        state = DeviceState::FAULT_ERROR;
    } else {
        #if USE_DUAL_MPU
        if (sensors.getHasMultiplexer()) {
            Serial.printf("[OK] Dual-MPU mode initialized via PCA9548A: Chest on SD%d (0x%02X), Base on SD%d (0x%02X).\n",
                sensors.getChestChannel(), sensors.getChestI2CAddress(),
                sensors.getBaseChannel(), sensors.getBaseI2CAddress());
        } else {
            Serial.println("[OK] Dual-MPU mode initialized.");
        }
        #else
        if (sensors.getHasMultiplexer()) {
            Serial.printf("[OK] Single-MPU mode initialized via PCA9548A on SD%d (0x%02X). Base sensor bypassed.\n",
                sensors.getChestChannel(), sensors.getChestI2CAddress());
        } else {
            Serial.printf("[OK] Single-MPU mode initialized: Direct bus mode (0x%02X). Base sensor bypassed.\n",
                sensors.getChestI2CAddress());
        }
        #endif
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
        practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
        if (state == DeviceState::CALIBRATING || state == DeviceState::ACTIVE_SESSION || 
            state == DeviceState::SESSION_PAUSED || state == DeviceState::CALIBRATED_READY) {
            Serial.println("[BLE WARN] Disconnected during active session! Immediately aborting.");
            tracker.reset();
            sensors.resetCalibration();
            state = DeviceState::STANDBY;
        }
    }

    // 2. Process incoming BLE string commands safely in the main thread
    while (ble.hasPendingCommand()) {
        String cmd = ble.consumeCommand();
        if (cmd.length() > 0) {
            onReceiveMessage_BLE(cmd);
        }
    }

    // State: CALIBRATING (Trainee rests hands idle on chest for configured duration)
    if (state == DeviceState::CALIBRATING) {
        #if !ENABLE_DEMO_MODE
        sensors.recordCalibrationSample(nowMicros);
        #endif

        // Periodically broadcast calibration progress packet (Packet Type 2)
        if (now - lastCalibProgressNotifyMillis >= CPReadyConfig::CALIBRATION_PROGRESS_INTERVAL_MS) {
            lastCalibProgressNotifyMillis = now;
            uint16_t elapsedCalib = (uint16_t)((now - calibrationStartMillis) / 1000);
            CPRMetricsPacket calibPkt = {PKT_TYPE_CALIB_PROGRESS, 1, 0, 0, 0, PROMPT_NONE, 0, elapsedCalib, CADENCE_FLAG_STEADY};
            ble.sendPacket(calibPkt);
        }

        // Check if calibration window has elapsed
        if (now - calibrationStartMillis >= CPReadyConfig::CALIBRATION_DURATION_MS) {
            #if !ENABLE_DEMO_MODE
            sensors.finalizeCalibration();
            if (!sensors.isCalibrationStable()) {
                Serial.println("[ERROR] Calibration aborted: stability/plausibility checks failed.");
                CPRMetricsPacket errorPkt = {PKT_TYPE_ERROR, 0, 0, 0, 0, PROMPT_NONE, 0, 0, 0};
                ble.sendPacket(errorPkt);
                sensors.resetCalibration();
                state = DeviceState::STANDBY;
            } else {
            #endif
                Serial.println("[FLOW] Calibration finished. Baselines stored. System is CALIBRATED_READY.");

                // Signal Flutter that calibration succeeded (Packet Type 3)
                CPRMetricsPacket successPkt = {PKT_TYPE_CALIB_SUCCESS, 1, 0, 0, 0, PROMPT_NONE, 0, 0, CADENCE_FLAG_STEADY};
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
            demoReading.quality_flags     = CADENCE_FLAG_STEADY;

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
    else {
        // Standby, Calibrated Ready, or Fault Error: yield CPU to feed IDLE and BLE background tasks
        delay(5);
    }
}
