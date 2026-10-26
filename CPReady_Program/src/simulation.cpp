/**
 * CPReady simulation firmware.
 *
 * Build target: PlatformIO environment `simulation` (`CPREADY_SIMULATION`).
 *
 * Exposes the same GATT service, the same 12-byte telemetry packet and the same
 * text commands as the sensor build, but replaces the MPU-6050 pair with the
 * synthetic signal from SyntheticVest. That signal is processed by the
 * production CompressionTracker, so rate, depth, recoil, CCF, quality flags,
 * audio cue codes and the final summary all come from the same logic the vest
 * runs.
 *
 * The sensor build remains src/main.cpp; this file is compiled only for the
 * simulation environment.
 */

#ifdef CPREADY_SIMULATION

#include <Arduino.h>
#include <Preferences.h>

#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"
#include "BleManager.h"
#include "CompressionTracker.h"
#include "SimulationConfig.h"
#include "SyntheticVest.h"

// --- Subsystems -------------------------------------------------------------

static BleManager         simBle;
static CompressionTracker simTracker;
static Preferences        simPrefs;
static SyntheticVest      simVest;

// --- Session state ----------------------------------------------------------

static DeviceState simState = DeviceState::STANDBY;

static uint32_t simCalibrationStartMs    = 0;
static uint32_t simCalibrationProgressMs = 0;
static uint32_t simLastCalibrationMicros = 0;

static uint32_t simLastNotifyMs     = 0;
static uint32_t simLastSampleMicros = 0;

static uint32_t simPracticeDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;

// --- Calibration window -----------------------------------------------------

static uint16_t simCalibrationSamples = 0;
static float    simCalibrationMinG    = 0.0f;
static float    simCalibrationMaxG    = 0.0f;

// Injected motion makes the baseline fail the same spread check the device
// applies, so the error and retry path can be exercised without sensors.
static bool simCalibrationMotion = false;

// --- Diagnostics ------------------------------------------------------------

static uint8_t     simForcedCue      = PROMPT_NONE;
static uint8_t     simLastLoggedCue  = PROMPT_NONE;
static int8_t      simLastPhase      = -1;
static String      simSerialLine     = "";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static const char* stateName(DeviceState state) {
    switch (state) {
        case DeviceState::STANDBY:          return "STANDBY";
        case DeviceState::CALIBRATING:      return "CALIBRATING";
        case DeviceState::ACTIVE_SESSION:   return "ACTIVE_SESSION";
        case DeviceState::SESSION_PAUSED:   return "SESSION_PAUSED";
        case DeviceState::FAULT_ERROR:      return "FAULT_ERROR";
        case DeviceState::CALIBRATED_READY: return "CALIBRATED_READY";
        default:                            return "UNKNOWN";
    }
}

static const char* profileName(CPReadyConfig::KinematicProfile profile) {
    return profile == CPReadyConfig::KinematicProfile::BENCH_TEST
        ? "BENCH_TEST"
        : "MANIKIN_STANDARD";
}

static const char* cueName(uint8_t code) {
    switch (code) {
        case PROMPT_PUSH_HARDER:   return "push harder";
        case PROMPT_PUSH_LESS:     return "push shallower";
        case PROMPT_RELEASE_FULLY: return "release chest completely";
        case PROMPT_SPEED_UP:      return "speed up";
        case PROMPT_SLOW_DOWN:     return "slow down";
        case PROMPT_GOOD_JOB:      return "good compressions";
        default:                   return "none";
    }
}

/**
 * Calibration and progress packets follow the sensor build's layout: recoil
 * reported as complete, steady cadence flag set, no audio cue, elapsed window.
 */
static CPRMetricsPacket makeCalibrationPacket(uint8_t packetType, uint16_t elapsedSec) {
    CPRMetricsPacket pkt{};
    pkt.packet_type        = packetType;
    pkt.recoil_status      = 1;
    pkt.audio_prompt_code  = PROMPT_NONE;
    pkt.session_elapsed_sec = elapsedSec;
    pkt.quality_flags      = CADENCE_FLAG_STEADY;
    return pkt;
}

/** Error packets carry an optional reason code in audio_prompt_code (Byte 7), matching main.cpp. */
static CPRMetricsPacket makeErrorPacket(uint8_t reason = ERR_NONE) {
    CPRMetricsPacket pkt{};
    pkt.packet_type       = PKT_TYPE_ERROR;
    pkt.audio_prompt_code = reason;
    return pkt;
}

static CPRConfigPacket makeConfigPacket(uint8_t profile, float depthK, uint32_t autoStopDurationSec) {
    bool isBench = (profile == 1);
    float defaultK = isBench ? CPReadyConfig::BENCH_DEPTH_CALIBRATION_K : CPReadyConfig::DEPTH_CALIBRATION_K;
    bool hasCustomK = fabsf(depthK - defaultK) > 0.05f;
    uint8_t flags = 0;
    if (isBench) flags |= 0x01;
    if (hasCustomK) flags |= 0x02;

    CPRConfigPacket cfgPkt{};
    cfgPkt.packet_type           = PKT_TYPE_CONFIG_REPORT;
    cfgPkt.profile               = profile;
    cfgPkt.depth_k_x100          = (uint16_t)roundf(depthK * 100.0f);
    cfgPkt.config_flags          = flags;
    cfgPkt.practice_duration_sec = (uint16_t)autoStopDurationSec;
    cfgPkt.default_duration_sec  = (uint16_t)CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
    cfgPkt.protocol_version      = 1;
    cfgPkt.reserved              = 0;
    return cfgPkt;
}

// ---------------------------------------------------------------------------
// Flow
// ---------------------------------------------------------------------------

/**
 * Opens the 2 s baseline window.
 *
 * The window counts 100 Hz samples and tracks the peak-to-peak spread of the
 * net signal, matching the sample-count and net-spread limits SensorManager
 * checks. A synthetic stroke source has no static gravity offset to remove, so
 * this stage gates the session rather than altering the waveform; the depth
 * reported later is a peak-to-peak quantity and a constant offset would cancel.
 */
static void beginSimCalibration(uint32_t now) {
    simCalibrationStartMs    = now;
    simCalibrationProgressMs = now;
    simLastCalibrationMicros = micros();
    simCalibrationSamples    = 0;
    simCalibrationMinG       = 999.0f;
    simCalibrationMaxG       = -999.0f;

    simState = DeviceState::CALIBRATING;

    simBle.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_PROGRESS, 0));
    Serial.printf("[FLOW] Calibration started: %u ms baseline window.\n",
                  (unsigned)CPReadyConfig::CALIBRATION_DURATION_MS);
}

/**
 * Starts an active session and restarts the stroke scenario.
 *
 * The reference scalar matches the active profile's default so the simulated
 * stroke keeps its physical size; a retuned tracker scalar then shows up as a
 * proportional change in the reported depth.
 */
static void startSimSession(uint32_t now) {
    const bool steadyTrial =
        simPracticeDurationSec > 0 &&
        simPracticeDurationSec <= SimConfig::STEADY_TRIAL_MAX_SEC;

    const float referenceK =
        simTracker.getProfile() == CPReadyConfig::KinematicProfile::BENCH_TEST
            ? CPReadyConfig::BENCH_DEPTH_CALIBRATION_K
            : CPReadyConfig::DEPTH_CALIBRATION_K;

    simTracker.startSession(now);
    simVest.begin(now, referenceK, steadyTrial);

    simLastNotifyMs     = now;
    simLastSampleMicros = micros();
    simLastPhase        = -1;
    simLastLoggedCue    = PROMPT_NONE;
    simState            = DeviceState::ACTIVE_SESSION;

    Serial.printf("[FLOW] Session started: %s | reference K %.2f | duration %u s\n",
                  steadyTrial ? "steady depth trial" : "cue scenario",
                  referenceK, (unsigned)simPracticeDurationSec);
}

/** Finalises the tracker and publishes the session summary. */
static void endSimSession(uint32_t now, const char* reason) {
    CPRSessionSummary summary = simTracker.finalizeSession(now);
    CPRMetricsPacket pkt = summary.toPacket(PKT_TYPE_FINAL_SUMMARY);

    simBle.sendPacket(pkt);
    simState     = DeviceState::STANDBY;
    simLastPhase = -1;
    simPracticeDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;

    Serial.printf("[FINAL TX] %s | Rate %.0f cpm | Depth %.2f cm | Recoil %.0f%% | "
                  "CCF %.0f%% | Strokes %u | Time %u s\n",
                  reason,
                  summary.avg_rate_cpm,
                  summary.avg_depth_cm,
                  summary.recoil_compliance_percent,
                  summary.final_ccf_percent,
                  (unsigned)summary.total_compressions,
                  (unsigned)summary.total_duration_sec);
}

// ---------------------------------------------------------------------------
// Command handling
// ---------------------------------------------------------------------------

static void handleBleCommand(String message) {
    message.trim();
    message.toUpperCase();
    Serial.println("[BLE CMD] Received: " + message);

    if (message == "CALIBRATE") {
        if (simState == DeviceState::ACTIVE_SESSION) {
            Serial.println("[FLOW] Calibrate rejected: active session running.");
            simBle.sendPacket(makeErrorPacket(ERR_WRONG_STATE));
            return;
        }
        beginSimCalibration(millis());
    }
    else if (message == "START") {
        if (simState == DeviceState::CALIBRATED_READY) {
            startSimSession(millis());
        }
        else if (simState == DeviceState::CALIBRATING) {
            Serial.println("[FLOW] Start rejected: calibration still running.");
            simBle.sendPacket(makeErrorPacket(ERR_WRONG_STATE));
        }
        else {
            Serial.println("[FLOW] Start from an uncalibrated state; running calibration first.");
            beginSimCalibration(millis());
        }
    }
    else if (message == "STOP") {
        if (simState == DeviceState::ACTIVE_SESSION ||
            simState == DeviceState::SESSION_PAUSED) {
            endSimSession(millis(), "stop command");
        }
        else {
            Serial.println("[FLOW] Stop with no active session; last summary resent.");
            simBle.sendPacket(simTracker.getLastSummary().toPacket(PKT_TYPE_FINAL_SUMMARY));
        }
    }
    else if (message == "GET_RESULTS") {
        simBle.sendPacket(simTracker.getLastSummary().toPacket(PKT_TYPE_FINAL_SUMMARY));
        Serial.println("[FLOW] Summary resent.");
    }
    else if (message == "PAUSE") {
        simState = DeviceState::SESSION_PAUSED;
        Serial.println("[FLOW] Session paused.");
    }
    else if (message == "RESUME") {
        if (simState == DeviceState::SESSION_PAUSED) {
            simState = DeviceState::ACTIVE_SESSION;
            Serial.println("[FLOW] Session resumed.");
        }
    }
    else if (message.startsWith("SET_TIME:")) {
        const int seconds = message.substring(9).toInt();
        if (seconds > 0) {
            simPracticeDurationSec = (uint32_t)seconds;
            Serial.printf("[CONFIG] Session duration set to %u s.\n", (unsigned)simPracticeDurationSec);
        }
    }
    else if (message.startsWith("SET_K:")) {
        const float k = message.substring(6).toFloat();
        if (k >= 1.0f && k <= 30.0f) {
            simTracker.setDepthK(k);
            simPrefs.putFloat("depth_k", k);
            Serial.printf("[NVS] Depth scalar K set to %.2f.\n", k);
        }
    }
    else if (message == "SET_PROFILE:BENCH") {
        simTracker.setProfile(CPReadyConfig::KinematicProfile::BENCH_TEST);
        simPrefs.putUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::BENCH_TEST);
        Serial.printf("[NVS] Profile BENCH_TEST applied (K %.2f).\n", simTracker.getDepthK());
    }
    else if (message == "SET_PROFILE:MANIKIN") {
        simTracker.setProfile(CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        simPrefs.putUChar("profile", (uint8_t)CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        Serial.printf("[NVS] Profile MANIKIN_STANDARD applied (K %.2f).\n", simTracker.getDepthK());
    }
    else if (message.startsWith("CALIBRATE_TARGET:")) {
        const float targetCm = message.substring(17).toFloat();
        const float previousK = simTracker.getDepthK();
        float newK = 0.0f;

        if (simTracker.calibrateFromLastSummary(targetCm, newK)) {
            if (simTracker.getProfile() == CPReadyConfig::KinematicProfile::BENCH_TEST) {
                simPrefs.putFloat("k_bench", newK);
            } else {
                simPrefs.putFloat("k_manikin", newK);
            }
            Serial.printf("[CALIB] Target %.2f cm scales K %.2f -> %.2f.\n",
                          targetCm, previousK, newK);
            simBle.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_SUCCESS, 0));
        }
        else {
            Serial.printf("[CALIB] Target %.2f cm rejected: no completed session depth available.\n",
                          targetCm);
            simBle.sendPacket(makeErrorPacket(ERR_NO_TRIAL_DATA));
        }
    }
    else if (message == "RESET_CONFIG") {
        simPrefs.clear();
        simTracker.setProfile(CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
        simTracker.setDepthK(CPReadyConfig::DEPTH_CALIBRATION_K);
        simPracticeDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
        Serial.println("[NVS] Simulation configuration cleared.");
    }
    else if (message == "GET_CONFIG") {
        CPRConfigPacket cfgPkt = makeConfigPacket(
            (uint8_t)simTracker.getProfile(),
            simTracker.getDepthK(),
            simPracticeDurationSec
        );
        simBle.sendPacket(cfgPkt);
        Serial.printf("[CONFIG] Profile: %s | Depth K: %.2f | Start: %.2fg | Recoil: %.2fg | Duration: %u s\n",
                      profileName(simTracker.getProfile()),
                      simTracker.getDepthK(),
                      simTracker.getCompressionStartThresholdG(),
                      simTracker.getRecoilThresholdG(),
                      (unsigned)simPracticeDurationSec);
    }
    else {
        Serial.println("[BLE CMD] Unhandled command: " + message);
    }
}

// ---------------------------------------------------------------------------
// Serial console
// ---------------------------------------------------------------------------

static void printSimStatus() {
    const CPRReading& reading = simTracker.getReading();

    Serial.printf("[SIM] State %s | Profile %s | K %.2f | Duration %u s\n",
                  stateName(simState),
                  profileName(simTracker.getProfile()),
                  simTracker.getDepthK(),
                  (unsigned)simPracticeDurationSec);
    Serial.printf("[SIM] Elapsed %u s | Strokes %u | Rate %.0f cpm | Depth %.2f cm | Cue %u\n",
                  (unsigned)reading.elapsed_seconds,
                  (unsigned)reading.stroke_count,
                  reading.rate_cpm,
                  reading.depth_cm,
                  (unsigned)reading.audio_prompt_code);
    Serial.printf("[SIM] Calibration motion injection %s | Forced cue %u\n",
                  simCalibrationMotion ? "ON" : "OFF",
                  (unsigned)simForcedCue);
}

static void handleSerialCommand(String line) {
    line.trim();
    line.toUpperCase();

    if (!line.startsWith("SIM:")) {
        Serial.println("[SIM] Unrecognised input: " + line);
        return;
    }

    if (line == "SIM:STATUS") {
        printSimStatus();
    }
    else if (line == "SIM:CALIB") {
        beginSimCalibration(millis());
    }
    else if (line == "SIM:START") {
        if (simState == DeviceState::CALIBRATED_READY) {
            startSimSession(millis());
        }
        else {
            Serial.println("[SIM] START needs a completed baseline calibration.");
        }
    }
    else if (line == "SIM:STOP") {
        if (simState == DeviceState::ACTIVE_SESSION ||
            simState == DeviceState::SESSION_PAUSED) {
            endSimSession(millis(), "console stop");
        }
        else {
            Serial.println("[SIM] No active session to stop.");
        }
    }
    else if (line == "SIM:CALIB:FAIL") {
        simCalibrationMotion = true;
        Serial.println("[SIM] Calibration motion injection enabled; baselines fail until SIM:CALIB:OK.");
    }
    else if (line == "SIM:CALIB:OK") {
        simCalibrationMotion = false;
        Serial.println("[SIM] Calibration motion injection disabled.");
    }
    else if (line.startsWith("SIM:CUE:")) {
        const int code = line.substring(8).toInt();
        if (code >= 1 && code <= 6) {
            simForcedCue = (uint8_t)code;
            Serial.printf("[SIM] Cue %d (%s) queued for the next realtime packet.\n",
                          code, cueName((uint8_t)code));
        }
        else {
            Serial.println("[SIM] Cue code must be 1..6.");
        }
    }
    else {
        Serial.println("[SIM] Commands: SIM:STATUS | SIM:CALIB | SIM:START | SIM:STOP | "
                       "SIM:CUE:<1-6> | SIM:CALIB:FAIL | SIM:CALIB:OK");
    }
}

static void pollSerial() {
    while (Serial.available() > 0) {
        const char c = (char)Serial.read();

        if (c == '\n' || c == '\r') {
            if (simSerialLine.length() > 0) {
                handleSerialCommand(simSerialLine);
                simSerialLine = "";
            }
        }
        else if (simSerialLine.length() < 48) {
            simSerialLine += c;
        }
    }
}

// ---------------------------------------------------------------------------
// State updates
// ---------------------------------------------------------------------------

static void updateCalibration(uint32_t now, uint32_t nowMicros) {
    if (nowMicros - simLastCalibrationMicros >= SimConfig::SAMPLE_INTERVAL_MICROS) {
        simLastCalibrationMicros = nowMicros;

        // A still vest reads zero net acceleration. Injected motion alternates
        // above and below zero, which exceeds the permitted net spread.
        const float sampleG = simCalibrationMotion
            ? ((simCalibrationSamples % 2u) ? 0.20f : -0.20f)
            : 0.0f;

        if (sampleG < simCalibrationMinG) simCalibrationMinG = sampleG;
        if (sampleG > simCalibrationMaxG) simCalibrationMaxG = sampleG;
        simCalibrationSamples++;
    }

    if (now - simCalibrationProgressMs >= CPReadyConfig::CALIBRATION_PROGRESS_INTERVAL_MS) {
        simCalibrationProgressMs = now;
        const uint16_t elapsedSec = (uint16_t)((now - simCalibrationStartMs) / 1000);
        simBle.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_PROGRESS, elapsedSec));
        Serial.printf("[CALIB TX] Progress %u s.\n", (unsigned)elapsedSec);
    }

    if (now - simCalibrationStartMs < CPReadyConfig::CALIBRATION_DURATION_MS) return;

    const bool enoughSamples = simCalibrationSamples >= CPReadyConfig::CALIBRATION_MIN_SAMPLE_COUNT;
    const float spreadG = simCalibrationMaxG - simCalibrationMinG;
    const bool stable = spreadG <= CPReadyConfig::CALIBRATION_MAX_NET_SPREAD_G;

    if (enoughSamples && stable) {
        simState = DeviceState::CALIBRATED_READY;
        simBle.sendPacket(makeCalibrationPacket(PKT_TYPE_CALIB_SUCCESS, 0));
        Serial.printf("[FLOW] Calibration complete: %u samples, net spread %.2f g. Ready to start.\n",
                      (unsigned)simCalibrationSamples, spreadG);
    }
    else {
        simState = DeviceState::STANDBY;
        uint8_t reason = (simCalibrationSamples < CPReadyConfig::CALIBRATION_MIN_SAMPLE_COUNT)
            ? ERR_LOW_SAMPLE_COUNT
            : ERR_MOTION_UNSTABLE;
        simBle.sendPacket(makeErrorPacket(reason));
        Serial.printf("[CALIB FAIL] Samples %u (min %u), net spread %.2f g (max %.2f g).\n",
                      (unsigned)simCalibrationSamples,
                      (unsigned)CPReadyConfig::CALIBRATION_MIN_SAMPLE_COUNT,
                      spreadG,
                      CPReadyConfig::CALIBRATION_MAX_NET_SPREAD_G);
    }
}

static void updateActiveSession(uint32_t now, uint32_t nowMicros) {
    if (nowMicros - simLastSampleMicros < SimConfig::SAMPLE_INTERVAL_MICROS) return;
    simLastSampleMicros = nowMicros;

    const uint8_t phaseIndex = simVest.phaseIndexAt(now);
    if ((int8_t)phaseIndex != simLastPhase) {
        simLastPhase = (int8_t)phaseIndex;
        const SimConfig::Phase& phase = SimConfig::PHASES[phaseIndex];
        Serial.printf("[SIM] Phase %u/%u: %s (%u cpm, %.1f cm, trough %.2f g)\n",
                      (unsigned)(phaseIndex + 1),
                      (unsigned)SimConfig::PHASE_COUNT,
                      phase.label,
                      (unsigned)phase.rateCpm,
                      phase.depthCm,
                      phase.troughG);
    }

    const float netAccelG = simVest.netAccelAt(now);
    const bool strokeCompleted = simTracker.processSample(netAccelG, now);

    if (!strokeCompleted && (now - simLastNotifyMs < CPReadyConfig::BLE_NOTIFY_INTERVAL_MS)) {
        return;
    }
    simLastNotifyMs = now;

    const CPRReading& reading = simTracker.getReading();
    CPRMetricsPacket pkt = reading.toPacket(PKT_TYPE_REALTIME);

    // A queued console cue replaces the engine's decision for one packet, which
    // allows each speaker cue to be checked without waiting for the scenario.
    if (simForcedCue != PROMPT_NONE) {
        pkt.audio_prompt_code = simForcedCue;
        simForcedCue = PROMPT_NONE;
    }

    simBle.sendPacket(pkt);

    if (strokeCompleted) {
        Serial.println("[STROKE] " + reading.toDebugString());
    }

    // The tracker keeps the last cue in the reading until the next stroke, and
    // the 5 Hz heartbeat repeats it; log the transition only, not every copy.
    if (pkt.audio_prompt_code != PROMPT_NONE &&
        pkt.audio_prompt_code != simLastLoggedCue) {
        Serial.printf("[CUE] %s (%u) at %u s\n",
                      cueName(pkt.audio_prompt_code),
                      (unsigned)pkt.audio_prompt_code,
                      (unsigned)pkt.session_elapsed_sec);
    }
    simLastLoggedCue = pkt.audio_prompt_code;

    if (simPracticeDurationSec > 0 &&
        simTracker.getReading().elapsed_seconds >= simPracticeDurationSec) {
        endSimSession(now, "duration reached");
    }
}

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------

void setup() {
    Serial.begin(115200);
    Serial.println("\n=========================================");
    Serial.println("     CPReady SIMULATION Firmware         ");
    Serial.println("=========================================");

    simPrefs.begin(SimConfig::NVS_NAMESPACE, false);

    const uint8_t savedProfile = simPrefs.getUChar(
        "profile", (uint8_t)CPReadyConfig::KinematicProfile::MANIKIN_STANDARD);
    float savedKManikin = simPrefs.getFloat("k_manikin", 0.0f);
    float savedKBench = simPrefs.getFloat("k_bench", 0.0f);

    if (savedKManikin <= 0.0f && savedKBench <= 0.0f) {
        float legacyK = simPrefs.getFloat("depth_k", 0.0f);
        if (legacyK >= 2.0f && legacyK <= 25.0f) {
            savedKManikin = legacyK;
            savedKBench = legacyK;
        }
    }
    if (savedKManikin >= 2.0f && savedKManikin <= 25.0f) {
        simTracker.setManikinDepthK(savedKManikin);
    }
    if (savedKBench >= 2.0f && savedKBench <= 25.0f) {
        simTracker.setBenchDepthK(savedKBench);
    }
    simTracker.setProfile((CPReadyConfig::KinematicProfile)savedProfile);

    Serial.printf("[NVS] Profile %s | Depth K %.2f\n",
                  profileName(simTracker.getProfile()),
                  simTracker.getDepthK());

    simBle.begin(CPReadyConfig::BLE_DEVICE_NAME);
    Serial.printf("[OK] BLE GATT server advertising as '%s'.\n", CPReadyConfig::BLE_DEVICE_NAME);
    Serial.println("[SIM] No sensors required.");
    Serial.println("[SIM] Console: SIM:STATUS | SIM:CALIB | SIM:START | SIM:STOP | "
                   "SIM:CUE:<1-6> | SIM:CALIB:FAIL | SIM:CALIB:OK");
}

void loop() {
    const uint32_t now = millis();
    const uint32_t nowMicros = micros();

    pollSerial();

    // A dropped link aborts an in-flight session, as in the sensor build.
    if (simBle.checkAndClearDisconnectionEvent()) {
        simPracticeDurationSec = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
        if (simState == DeviceState::CALIBRATING ||
            simState == DeviceState::ACTIVE_SESSION ||
            simState == DeviceState::SESSION_PAUSED ||
            simState == DeviceState::CALIBRATED_READY) {
            Serial.println("[BLE WARN] Disconnected during a session; aborting.");
            simTracker.reset();
            simState = DeviceState::STANDBY;
        }
    }

    while (simBle.hasPendingCommand()) {
        String cmd = simBle.consumeCommand();
        if (cmd.length() > 0) {
            handleBleCommand(cmd);
        }
    }

    if (simState == DeviceState::CALIBRATING) {
        updateCalibration(now, nowMicros);
    }
    else if (simState == DeviceState::ACTIVE_SESSION) {
        updateActiveSession(now, nowMicros);
    }
    else {
        delay(4);
    }
    delay(1);
}

#endif // CPREADY_SIMULATION
