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
uint32_t demoSessionStartMillis = 0;

// Configurable target duration (in seconds, default set in CPReadyConfig; 0 = manual stop)
uint32_t practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;

// Calibration progress / success packet: recoil reported as complete, steady cadence flag set.
CPRMetricsPacket makeCalibrationPacket(uint8_t packetType, uint16_t elapsedSec) {
    CPRMetricsPacket pkt{};
    pkt.packet_type         = packetType;
    pkt.recoil_status       = 1;
    pkt.audio_prompt_code   = PROMPT_NONE;
    pkt.session_elapsed_sec = elapsedSec;
    pkt.quality_flags       = CADENCE_FLAG_STEADY;
    return pkt;
}

// Error packet: the reason code travels in byte 7 (audio_prompt_code).
void sendError(uint8_t reason) {
    CPRMetricsPacket pkt{};
    pkt.packet_type       = PKT_TYPE_ERROR;
    pkt.audio_prompt_code = reason;
    ble.sendPacket(pkt);
}

// Commands that change configuration are refused while a calibration or session runs,
// so a session never mixes two profiles or two depth scalars.
bool configChangeAllowed() {
    return state == DeviceState::STANDBY || state == DeviceState::CALIBRATED_READY ||
           state == DeviceState::FAULT_ERROR;
}

bool rejectConfigChange(const String& message) {
    if (configChangeAllowed()) return false;
    Serial.println("[FLOW WARN] " + message + " rejected: calibration or session in progress.");
    sendError(ERR_WRONG_STATE);
    return true;
}

// Parses a non-negative whole number; false for anything else (toInt() would return 0).
bool parseSeconds(const String& text, uint32_t& outSeconds) {
    if (text.length() == 0 || text.length() > 5) return false;
    for (unsigned int i = 0; i < text.length(); i++) {
        if (!isDigit(text[i])) return false;
    }
    outSeconds = (uint32_t)text.toInt();
    return true;
}

void startCalibration(uint32_t now) {
    // A new calibration starts a new session attempt: drop the previous summary so a
    // later GET_RESULTS can never return another trainee's results.
    tracker.reset();
    sensors.resetCalibration();
    calibrationStartMillis = now;
    lastCalibProgressNotifyMillis = now;
    state = DeviceState::CALIBRATING;
    ble.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_PROGRESS, 0));
}

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
    uint32_t activeMs = now - demoSessionStartMillis;
    summary.total_compressions = (uint16_t)(activeMs / 550);
    summary.total_duration_sec = (uint16_t)(activeMs / 1000);
    #else
    CPRSessionSummary summary = tracker.finalizeSession(now);
    #endif

    // Transmit finalized results packet (Packet Type 4) to Flutter
    CPRMetricsPacket finalPacket = summary.toPacket(PKT_TYPE_FINAL_SUMMARY);
    ble.sendPacket(finalPacket);
    #if !ENABLE_DEMO_MODE
    if (summary.total_duration_sec > 0) {
        float sampleHz = (float)tracker.getTotalSamplesProcessed() / (float)summary.total_duration_sec;
        Serial.printf("[DIAG RATE] Effective sensor sampling: %u samples over %u s (%.1f Hz - Target: 100 Hz)\n",
            (unsigned)tracker.getTotalSamplesProcessed(), (unsigned)summary.total_duration_sec, sampleHz);
    }
    #endif
    Serial.printf("[FINAL TX] Rate: %.0f cpm | Depth: %.2f cm | Recoil: %.0f%% | CCF: %.0f%% | Total: %d\n",
        summary.avg_rate_cpm, summary.avg_depth_cm, summary.recoil_compliance_percent, summary.final_ccf_percent, summary.total_compressions);
    #if !ENABLE_DEMO_MODE
    if (summary.total_duration_sec > 0) {
        float sampleHz = (float)tracker.getTotalSamplesProcessed() / (float)summary.total_duration_sec;
        Serial.printf("[DIAG RATE] Effective sensor sampling: %u samples over %u s (%.1f Hz - Target: 100 Hz)\n",
            (unsigned)tracker.getTotalSamplesProcessed(), (unsigned)summary.total_duration_sec, sampleHz);
    }
    #endif
}

// Sensor fault during calibration or a session: abandon it (no summary), tell the app,
// and wait in FAULT_ERROR until a CALIBRATE succeeds in re-initialising the sensors.
void enterSensorFault() {
    Serial.println("[FAULT] Sensor communication failed. Session abandoned; send CALIBRATE to retry.");
    tracker.reset();
    sensors.resetCalibration();
    practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
    state = DeviceState::FAULT_ERROR;
    sendError(ERR_I2C_FAULT);
}

void saveDepthK(float k) {
    bool isBench = (tracker.getProfile() == CPReadyConfig::KinematicProfile::BENCH_TEST);
    prefs.putFloat(isBench ? "k_bench" : "k_manikin", k);
}

/**
 * Standardized BLE Message / Command Dispatcher
 *
 * Receives incoming text commands from the mobile application. Every command is
 * checked against the current state; an invalid one answers ERR_WRONG_STATE.
 */
void onReceiveMessage_BLE(String message) {
    message.trim();
    message.toUpperCase();
    Serial.println("[BLE CMD] Received: " + message);
    uint32_t now = millis();

    if (message == "CALIBRATE") {
        if (state == DeviceState::ACTIVE_SESSION || state == DeviceState::SESSION_PAUSED) {
            Serial.println("[FLOW WARN] Calibrate requested while a session is running! Rejecting.");
            sendError(ERR_WRONG_STATE);
            return;
        }
        #if !ENABLE_DEMO_MODE
        if (state == DeviceState::FAULT_ERROR || sensors.hasFault()) {
            if (!sensors.reinitialize()) {
                Serial.println("[FAULT] Sensors still unavailable.");
                state = DeviceState::FAULT_ERROR;
                sendError(ERR_I2C_FAULT);
                return;
            }
            state = DeviceState::STANDBY;
        }
        #endif
        Serial.println("[FLOW] Calibrate received. Initiating stationary baseline calibration...");
        startCalibration(now);
    }
    else if (message == "START") {
        if (state == DeviceState::CALIBRATED_READY) {
            Serial.println("[FLOW] Device is calibrated and ready. Starting active CPR session!");
            tracker.startSession(now);
            demoSessionStartMillis = now;
            lastBleNotifyMillis = now;
            state = DeviceState::ACTIVE_SESSION;
        }
        else if (state == DeviceState::ACTIVE_SESSION) {
            // A retried START must not restart or abandon the running session.
            Serial.println("[FLOW] Start received while already running; ignored.");
        }
        else {
            // START needs a fresh baseline. The old fallback silently re-calibrated, which
            // abandoned a running session and left the app showing a session that never began.
            Serial.println("[FLOW WARN] Start rejected: send CALIBRATE and wait for the baseline first.");
            sendError(state == DeviceState::FAULT_ERROR ? ERR_I2C_FAULT : ERR_WRONG_STATE);
        }
    }
    else if (message == "STOP") {
        if (state == DeviceState::ACTIVE_SESSION || state == DeviceState::SESSION_PAUSED) {
            Serial.println("[FLOW] Stop received from app during active operation.");
            endAndFinalizeSession(now);
        } else if (state == DeviceState::CALIBRATING || state == DeviceState::CALIBRATED_READY) {
            // No session ran, so there is nothing to summarise.
            Serial.println("[FLOW] Stop received before the session started; calibration cancelled.");
            sensors.resetCalibration();
            state = DeviceState::STANDBY;
        } else {
            Serial.println("[FLOW] Stop received while idle; ignoring to preserve session summary.");
        }
    }
    else if (message == "GET_RESULTS") {
        Serial.println("[FLOW] Retransmission requested via GET_RESULTS.");
        CPRMetricsPacket finalPacket = tracker.getLastSummary().toPacket(PKT_TYPE_FINAL_SUMMARY);
        ble.sendPacket(finalPacket);
    #if !ENABLE_DEMO_MODE
    if (summary.total_duration_sec > 0) {
        float sampleHz = (float)tracker.getTotalSamplesProcessed() / (float)summary.total_duration_sec;
        Serial.printf("[DIAG RATE] Effective sensor sampling: %u samples over %u s (%.1f Hz - Target: 100 Hz)\n",
            (unsigned)tracker.getTotalSamplesProcessed(), (unsigned)summary.total_duration_sec, sampleHz);
    }
    #endif
    }
    else if (message == "PAUSE") {
        if (state == DeviceState::ACTIVE_SESSION) {
            Serial.println("[FLOW] Pause received; session clock stopped.");
            tracker.pauseSession(now);
            state = DeviceState::SESSION_PAUSED;
        } else if (state != DeviceState::SESSION_PAUSED) {
            sendError(ERR_WRONG_STATE);
        }
    }
    else if (message == "RESUME") {
        if (state == DeviceState::SESSION_PAUSED) {
            Serial.println("[FLOW] Resume received.");
            tracker.resumeSession(now);
            state = DeviceState::ACTIVE_SESSION;
        } else if (state != DeviceState::ACTIVE_SESSION) {
            sendError(ERR_WRONG_STATE);
        }
    }
    else if (message.startsWith("SET_TIME:")) {
        if (rejectConfigChange(message)) return;
        uint32_t sec = 0;
        if (parseSeconds(message.substring(9), sec) && sec <= 3600) {
            practiceDurationSec = sec;
            Serial.printf("[CONFIG] Session duration set to %u seconds (0 = manual stop).\n", (unsigned)practiceDurationSec);
        } else {
            Serial.println("[CONFIG] Invalid SET_TIME value ignored.");
        }
    }
    else if (message.startsWith("SET_K:")) {
        if (rejectConfigChange(message)) return;
        float k = message.substring(6).toFloat();
        if (k >= CPReadyConfig::DEPTH_K_MIN && k <= CPReadyConfig::DEPTH_K_MAX) {
            tracker.setDepthK(k);
            saveDepthK(k);
            Serial.printf("[NVS] Depth calibration scalar K updated to %.2f (persisted to flash)\n", k);
        }
    }
    else if (message == "SET_PROFILE:BENCH") {
        if (rejectConfigChange(message)) return;
        tracker.setProfile(CPReadyConfig::KinematicProfile::BENCH_TEST);
        prefs.putUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::BENCH_TEST);
        Serial.printf("[NVS] Kinematic profile set to BENCH_TEST (active K=%.2f)\n", tracker.getDepthK());
    }
    else if (message == "SET_PROFILE:MANIKIN") {
        if (rejectConfigChange(message)) return;
        tracker.setProfile(CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        prefs.putUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        Serial.printf("[NVS] Kinematic profile set to MANIKIN_STANDARD (active K=%.2f)\n", tracker.getDepthK());
    }
    else if (message.startsWith("CALIBRATE_TARGET:")) {
        if (rejectConfigChange(message)) return;
        float targetCm = message.substring(17).toFloat();
        float newK = 0.0f;
        if (tracker.calibrateFromLastSummary(targetCm, newK)) {
            saveDepthK(newK);
            Serial.printf("[CALIB] Auto-calibrated scalar K to %.2f based on target %.2f cm (persisted to flash)\n", newK, targetCm);
            ble.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_SUCCESS, 0));
        } else {
            Serial.printf("[CALIB ERR] Failed to calibrate target %.2f cm! Check: target>0 (%.2f), trialAvgDepth>0 (%.2f), strokes>=5 (%u)\n", targetCm, targetCm, tracker.getLastSummary().avg_depth_cm, (unsigned)tracker.getLastSummary().total_compressions);
            sendError(ERR_NO_TRIAL_DATA);
        }
    }
    else if (message == "RESET_CONFIG") {
        if (rejectConfigChange(message)) return;
        prefs.clear();
        tracker.setManikinK(CPReadyConfig::DEPTH_CALIBRATION_K);
        tracker.setBenchK(CPReadyConfig::BENCH_DEPTH_CALIBRATION_K);
        tracker.setProfile(CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        practiceDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
        Serial.println("[NVS] Flash cleared! Restored factory defaults (MANIKIN_STANDARD, K=11.2).");
    }
    else if (message == "GET_CONFIG") {
        bool isBench = (tracker.getProfile() == CPReadyConfig::KinematicProfile::BENCH_TEST);
        float defaultK = isBench ? CPReadyConfig::BENCH_DEPTH_CALIBRATION_K : CPReadyConfig::DEPTH_CALIBRATION_K;
        bool hasCustomK = fabsf(tracker.getDepthK() - defaultK) > 0.05f;
        uint8_t flags = 0;
        if (isBench) flags |= 0x01;
        if (hasCustomK) flags |= 0x02;

        CPRConfigPacket cfgPkt{};
        cfgPkt.packet_type           = PKT_TYPE_CONFIG_REPORT;
        cfgPkt.profile               = isBench ? 1 : 0;
        cfgPkt.depth_k_x100          = (uint16_t)roundf(tracker.getDepthK() * 100.0f);
        cfgPkt.config_flags          = flags;
        cfgPkt.practice_duration_sec = (uint16_t)practiceDurationSec;
        cfgPkt.default_duration_sec  = (uint16_t)CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
        cfgPkt.protocol_version      = 1;
        cfgPkt.reserved              = 0;

        ble.sendPacket(cfgPkt);

        Serial.printf("[CONFIG] Profile: %s | Depth K: %.2f | StartThresh: %.2fg | RecoilThresh: %.2fg | Duration: %u sec\n",
            isBench ? "BENCH_TEST" : "MANIKIN_STANDARD",
            tracker.getDepthK(), tracker.getCompressionStartThresholdG(), tracker.getRecoilThresholdG(), (unsigned)practiceDurationSec);
    }
    else {
        Serial.println("[BLE CMD] Unhandled command: " + message);
    }
}

// Loads the per-profile depth scalars. Older firmware also wrote a shared "depth_k" key
// on every change; it is migrated once (only into the profile it belonged to) and removed,
// so a bench K can no longer leak into the manikin K after a reboot.
void loadDepthCalibration(uint8_t savedProfile) {
    // K values saved under the old K * da * T^2 model were fitted to that model's
    // stroke-shape bias. Applied to the integrated depth they would mis-scale it, so
    // they are discarded once and every profile starts again from its default.
    if (prefs.getUChar("depth_model", 0) != CPReadyConfig::DEPTH_MODEL_VERSION) {
        prefs.remove("depth_k");
        prefs.remove("k_manikin");
        prefs.remove("k_bench");
        prefs.putUChar("depth_model", CPReadyConfig::DEPTH_MODEL_VERSION);
        Serial.println("[NVS] Depth model changed: saved K values reset. Re-run Manikin Calibration.");
    }

    if (prefs.isKey("depth_k")) {
        float legacyK = prefs.getFloat("depth_k", 0.0f);
        const char* key = (savedProfile == (uint8_t)CPReadyConfig::KinematicProfile::BENCH_TEST) ? "k_bench" : "k_manikin";
        if (!prefs.isKey(key) && legacyK >= CPReadyConfig::DEPTH_K_MIN && legacyK <= CPReadyConfig::DEPTH_K_MAX) {
            prefs.putFloat(key, legacyK);
        }
        prefs.remove("depth_k");
    }

    float savedManikinK = prefs.getFloat("k_manikin", CPReadyConfig::DEPTH_CALIBRATION_K);
    float savedBenchK = prefs.getFloat("k_bench", CPReadyConfig::BENCH_DEPTH_CALIBRATION_K);

    // Same bounds as SET_K, so a value acknowledged at runtime survives a reboot
    if (savedManikinK < CPReadyConfig::DEPTH_K_MIN || savedManikinK > CPReadyConfig::DEPTH_K_MAX) savedManikinK = CPReadyConfig::DEPTH_CALIBRATION_K;
    if (savedBenchK < CPReadyConfig::DEPTH_K_MIN || savedBenchK > CPReadyConfig::DEPTH_K_MAX) savedBenchK = CPReadyConfig::BENCH_DEPTH_CALIBRATION_K;

    tracker.setManikinK(savedManikinK);
    tracker.setBenchK(savedBenchK);
}

void setup() {
    Serial.begin(115200);
    Serial.println("\n=========================================");
    Serial.println("     CPReady Firmware Initializing       ");
    Serial.println("=========================================");

    // Initialize Flash NVS Preferences & Load Calibrated Parameters
    prefs.begin(CPReadyConfig::NVS_NAMESPACE, false);
    uint8_t savedProfile = prefs.getUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
    if (savedProfile > 1) savedProfile = 0;

    loadDepthCalibration(savedProfile);
    tracker.setProfile((CPReadyConfig::KinematicProfile)savedProfile);

    Serial.printf("[NVS] Flash configuration loaded: Profile=%s | Manikin K=%.2f | Bench K=%.2f (Active K=%.2f)\n",
        savedProfile == (uint8_t)CPReadyConfig::KinematicProfile::BENCH_TEST ? "BENCH_TEST" : "MANIKIN_STANDARD",
        tracker.getManikinK(), tracker.getBenchK(), tracker.getDepthK());

    #if ENABLE_DEMO_MODE
    Serial.println("[DEMO] *** DEMO / SIMULATION MODE ENABLED ***");
    Serial.println("[DEMO] Emulating CPR metrics for mobile app testing.");
    #else
    if (!sensors.begin()) {
        #if USE_DUAL_MPU
        Serial.println("[ERROR] Failed to initialize the MPU6050 sensors! Check the PCA9548A (0x70) or the 0x68/0x69 wiring.");
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
            Serial.println("[OK] Dual-MPU mode initialized on the main bus (0x68 chest, 0x69 base).");
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
    uint32_t dropped = ble.consumeDroppedCommandCount();
    if (dropped > 0) {
        Serial.printf("[BLE WARN] %u command(s) dropped: command queue full.\n", (unsigned)dropped);
    }

    // State: CALIBRATING (Trainee rests hands idle on chest for configured duration)
    if (state == DeviceState::CALIBRATING) {
        #if !ENABLE_DEMO_MODE
        sensors.recordCalibrationSample(nowMicros);
        if (sensors.hasFault()) {
            enterSensorFault();
            return;
        }
        #endif

        // Periodically broadcast calibration progress packet (Packet Type 2)
        if (now - lastCalibProgressNotifyMillis >= CPReadyConfig::CALIBRATION_PROGRESS_INTERVAL_MS) {
            lastCalibProgressNotifyMillis = now;
            uint16_t elapsedCalib = (uint16_t)((now - calibrationStartMillis) / 1000);
            ble.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_PROGRESS, elapsedCalib));
        }

        // Check if calibration window has elapsed
        if (now - calibrationStartMillis >= CPReadyConfig::CALIBRATION_DURATION_MS) {
            #if !ENABLE_DEMO_MODE
            sensors.finalizeCalibration();
            if (!sensors.isCalibrationStable()) {
                uint8_t reason = sensors.getCalibrationFailureReason();
                Serial.printf("[ERROR] Calibration aborted: stability/plausibility checks failed (reason=%d).\n", reason);
                sendError(reason);
                sensors.resetCalibration();
                state = DeviceState::STANDBY;
            } else {
            #endif
                Serial.println("[FLOW] Calibration finished. Baselines stored. System is CALIBRATED_READY.");

                // Signal Flutter that calibration succeeded (Packet Type 3)
                ble.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_SUCCESS, 0));

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
            demoReading.elapsed_seconds   = (now - demoSessionStartMillis) / 1000;
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
        float rawNetAccel = 0.0f;
        bool sampled = sensors.sample100Hz(netAccel, rawNetAccel, nowMicros);
        if (sensors.hasFault()) {
            enterSensorFault();
            return;
        }
        if (sampled) {
            // Filtered sample detects strokes; the raw sample is integrated for depth
            bool strokeCompleted = tracker.processSample(netAccel, rawNetAccel, now);

            // Transmit immediately upon stroke completion, or throttle at configured interval
            if (strokeCompleted || (now - lastBleNotifyMillis >= CPReadyConfig::BLE_NOTIFY_INTERVAL_MS)) {
                lastBleNotifyMillis = now;

                const CPRReading& reading = tracker.getReading();
                CPRMetricsPacket packet = reading.toPacket(PKT_TYPE_REALTIME);

                ble.sendPacket(packet);

                if (strokeCompleted) {
                    Serial.println("[STROKE] " + reading.toDebugString());
                }
                // The cue is announced once; the 5 Hz heartbeat must not repeat it.
                tracker.clearAudioPrompt();
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
        // Standby, Calibrated Ready, Paused or Fault Error: yield CPU to feed IDLE and BLE background tasks
        delay(5);
    }

    // Yield CPU slice to feed FreeRTOS BLE stack and IDLE watchdog without adding a 1ms+ sleep tick during sessions
    if (state != DeviceState::ACTIVE_SESSION && state != DeviceState::CALIBRATING) {
        delay(1);
    } else {
        taskYIELD();
    }
}
