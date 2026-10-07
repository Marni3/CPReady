/**
 * CPReady Simulation BLE Firmware
 *
 * Build target: PlatformIO environment `simulation`
 * Selected via platformio.ini [env:simulation] build_src_filter and the
 * CPREADY_SIMULATION build flag.
 *
 * Keeps the same BLE GATT service/characteristics and the same 11-byte CPReady
 * packet format from BLEReadings.h, but replaces the real sensor/session logic
 * with hardcoded fake packets.
 *
 * The whole file is guarded by CPREADY_SIMULATION so that:
 *  - the default [env:esp32dev] build compiles this file to nothing, and
 *  - the Arduino IDE (.ino) build never sees a second setup()/loop().
 *
 * DO NOT flash this file unless you explicitly want fake-telemetry mode.
 * The normal firmware entry point remains src/main.cpp.
 *
 */

#ifdef CPREADY_SIMULATION

#include <Arduino.h>
#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"
#include "BleManager.h"
#include "FeedbackController.h"

// --- Fake telemetry parameters (tune here) ---------------------------------
static const uint16_t FAKE_RATE_CPM           = 110;
static const float    FAKE_DEPTH_CM           = 5.4f;  // 54 mm
static const bool     FAKE_RECOIL_OK          = true;
static const uint8_t  FAKE_CCF_PERCENT        = 78;
static const uint16_t FAKE_STROKE_INTERVAL_MS = 550;   // fake stroke every ~550 ms

// --- File-local subsystem instances (avoid symbol collisions) --------------
static BleManager         fakeBle;
static FeedbackController fakeFeedback;

// --- File-local fake session state -----------------------------------------
static DeviceState fakeState                     = DeviceState::STANDBY;
static uint32_t    fakeCalibrationStartMillis    = 0;
static uint32_t    fakeLastCalibProgressMillis   = 0;
static uint32_t    fakeLastNotifyMillis          = 0;
static uint32_t    fakePracticeDurationSec       = CPReadyConfig::DEFAULT_PRACTICE_DURATION_SEC;
static uint16_t    fakeStrokeCount               = 0;
static uint16_t    fakeElapsedSec                = 0;

// ---------------------------------------------------------------------------
// Fake packet generators (11-byte layout per BLEReadings.h)
// ---------------------------------------------------------------------------

static CPRMetricsPacket makeFakeCalibProgress() {
    CPRMetricsPacket pkt;
    pkt.packet_type         = PKT_TYPE_CALIB_PROGRESS;
    pkt.recoil_status       = 1;
    pkt.rate_cpm            = 0;
    pkt.depth_tenths_mm     = 0;
    pkt.ccf_percent         = 0;
    pkt.audio_prompt_code   = PROMPT_NONE;
    pkt.total_compressions  = 0;
    pkt.session_elapsed_sec = (uint16_t)((millis() - fakeCalibrationStartMillis) / 1000);
    return pkt;
}

static CPRMetricsPacket makeFakeCalibSuccess() {
    CPRMetricsPacket pkt;
    pkt.packet_type         = PKT_TYPE_CALIB_SUCCESS;
    pkt.recoil_status       = 1;
    pkt.rate_cpm            = 0;
    pkt.depth_tenths_mm     = 0;
    pkt.ccf_percent         = 0;
    pkt.audio_prompt_code   = PROMPT_NONE;
    pkt.total_compressions  = 0;
    pkt.session_elapsed_sec = 0;
    return pkt;
}

static CPRMetricsPacket makeFakeRealtime() {
    CPRMetricsPacket pkt;
    pkt.packet_type         = PKT_TYPE_REALTIME;
    pkt.recoil_status       = FAKE_RECOIL_OK ? 1 : 0;
    pkt.rate_cpm            = FAKE_RATE_CPM;
    pkt.depth_tenths_mm     = (uint16_t)round(FAKE_DEPTH_CM * 100.0f);
    pkt.ccf_percent         = FAKE_CCF_PERCENT;
    pkt.audio_prompt_code   = PROMPT_NONE;
    pkt.total_compressions  = fakeStrokeCount > 255 ? 255 : fakeStrokeCount;
    pkt.session_elapsed_sec = fakeElapsedSec;
    return pkt;
}

static CPRMetricsPacket makeFakeFinalSummary() {
    CPRMetricsPacket pkt;
    pkt.packet_type         = PKT_TYPE_FINAL_SUMMARY;
    pkt.recoil_status       = FAKE_RECOIL_OK ? 100 : 50;
    pkt.rate_cpm            = FAKE_RATE_CPM;
    pkt.depth_tenths_mm     = (uint16_t)round(FAKE_DEPTH_CM * 100.0f);
    pkt.ccf_percent         = FAKE_CCF_PERCENT;
    pkt.audio_prompt_code   = PROMPT_NONE;
    pkt.total_compressions  = fakeStrokeCount > 255 ? 255 : fakeStrokeCount;
    pkt.session_elapsed_sec = fakeElapsedSec;
    return pkt;
}

// ---------------------------------------------------------------------------
// Command handling (same textual commands as main firmware)
// ---------------------------------------------------------------------------

static void fakeHandleCommand(String message) {
    message.trim();
    message.toUpperCase();
    Serial.println("[FAKE BLE CMD] Received: " + message);

    if (message == "START") {
        Serial.println("[FAKE] START -> begin fake calibration flow");
        fakeCalibrationStartMillis  = millis();
        fakeLastCalibProgressMillis = millis();
        fakeLastNotifyMillis        = millis();
        fakeStrokeCount             = 0;
        fakeElapsedSec              = 0;
        fakeState                   = DeviceState::CALIBRATING;

        fakeBle.sendPacket(makeFakeCalibProgress());
        fakeFeedback.playCalibrationStart();
    }
    else if (message == "STOP") {
        Serial.println("[FAKE] STOP -> finalize fake session");
        fakeState = DeviceState::STANDBY;
        fakeBle.sendPacket(makeFakeFinalSummary());
        fakeFeedback.playSessionComplete();
    }
    else if (message == "GET_RESULTS") {
        Serial.println("[FAKE] GET_RESULTS -> retransmit fake summary");
        fakeBle.sendPacket(makeFakeFinalSummary());
    }
    else if (message == "PAUSE") {
        Serial.println("[FAKE] PAUSE");
        fakeState = DeviceState::SESSION_PAUSED;
    }
    else if (message == "RESUME") {
        Serial.println("[FAKE] RESUME");
        if (fakeState == DeviceState::SESSION_PAUSED) {
            fakeState = DeviceState::ACTIVE_SESSION;
        }
    }
    else if (message.startsWith("SET_TIME:")) {
        int sec = message.substring(9).toInt();
        if (sec > 0) {
            fakePracticeDurationSec = (uint32_t)sec;
            Serial.printf("[FAKE] Session duration set to %d seconds.\n", sec);
        }
    }
    else {
        Serial.println("[FAKE BLE CMD] Unhandled command: " + message);
    }
}

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------

void setup() {
    Serial.begin(115200);
    Serial.println("\n=========================================");
    Serial.println("     CPReady FAKE-PACKET BLE Firmware    ");
    Serial.println("=========================================");
    Serial.println("[FAKE] No sensors required. Advertising as CPReady.");

    fakeFeedback.begin(CPReadyConfig::BUZZER_PIN);
    fakeBle.begin(CPReadyConfig::BLE_DEVICE_NAME);
    Serial.printf("[OK] BLE GATT Server Advertising as '%s'.\n", CPReadyConfig::BLE_DEVICE_NAME);
}

void loop() {
    uint32_t now = millis();

    // Process incoming BLE commands
    if (fakeBle.hasPendingCommand()) {
        String cmd = fakeBle.consumeCommand();
        fakeHandleCommand(cmd);
    }

    // Non-blocking buzzer sequencer
    fakeFeedback.update(now);

    // Fake calibration progress notifications
    if (fakeState == DeviceState::CALIBRATING) {
        if (now - fakeLastCalibProgressMillis >= 500) {
            fakeLastCalibProgressMillis = now;
            fakeBle.sendPacket(makeFakeCalibProgress());
        }

        if (now - fakeCalibrationStartMillis >= CPReadyConfig::CALIBRATION_DURATION_MS) {
            Serial.println("[FAKE] Calibration complete -> send success packet");
            fakeBle.sendPacket(makeFakeCalibSuccess());
            fakeFeedback.playCompressionsBegin();
            fakeLastNotifyMillis = now;
            fakeState = DeviceState::ACTIVE_SESSION;
        }
    }

    // Fake live telemetry stream
    if (fakeState == DeviceState::ACTIVE_SESSION) {
        if (now - fakeLastNotifyMillis >= CPReadyConfig::BLE_NOTIFY_INTERVAL_MS) {
            fakeLastNotifyMillis = now;

            fakeElapsedSec += 1;
            if (now % FAKE_STROKE_INTERVAL_MS < CPReadyConfig::BLE_NOTIFY_INTERVAL_MS) {
                fakeStrokeCount++;
            }

            fakeBle.sendPacket(makeFakeRealtime());
            Serial.printf("[FAKE TX] Realtime: rate=%u cpm depth=%.1fmm ccf=%u%% strokes=%u t=%us\n",
                          FAKE_RATE_CPM, FAKE_DEPTH_CM * 10.0f,
                          FAKE_CCF_PERCENT, fakeStrokeCount, fakeElapsedSec);
        }

        if (fakePracticeDurationSec > 0 && fakeElapsedSec >= fakePracticeDurationSec) {
            Serial.println("[FAKE] Practice time limit reached");
            fakeState = DeviceState::STANDBY;
            fakeBle.sendPacket(makeFakeFinalSummary());
            fakeFeedback.playSessionComplete();
        }
    }
}

#endif 
