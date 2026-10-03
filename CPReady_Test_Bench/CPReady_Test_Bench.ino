#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <MPU6050.h> // electroniccats/MPU6050 library

// ==============================================================================
// CPReady Standalone Medical Test Bench & Metric Calibration Portal
// Single-file firmware for Arduino IDE with embedded Web Portal & NVS Protection
// ==============================================================================

// ---- Hardware Pins (ESP32 Standard) ----
#define BENCH_I2C_SDA_PIN          21
#define BENCH_I2C_SCL_PIN          22
#define BENCH_BUZZER_PIN           25

// ---- I2C Bus Settings ----
#define BENCH_I2C_CLOCK_HZ         400000 // Fast Mode 400 kHz
#define BENCH_I2C_TIMEOUT_MS       25     // Prevent bus freeze on loose wires
#define BENCH_CHEST_I2C_ADDR       0x68   // Primary chest sensor (AD0 -> GND)
#define BENCH_BASE_I2C_ADDR        0x69   // Secondary spine reference (AD0 -> 3.3V)

// ---- Wi-Fi SoftAP Configuration (OPEN HOTSPOT) ----
#define BENCH_WIFI_SSID            "CPReady-TestBench" // Open Wi-Fi (No password required)
#define BENCH_WEB_PORT             80
#define BENCH_DNS_PORT             53

// ---- Algorithmic Defaults (AHA Clinical Standards) ----
#define DEFAULT_DEPTH_K            11.2f  // Depth calibration scalar: D = K * da * T^2
#define DEFAULT_COMPRESS_THRESH_G  0.45f  // Downward trigger threshold in g
#define DEFAULT_RECOIL_THRESH_G    -0.35f // Upward rebound threshold to confirm release in g
#define DEFAULT_REFRACTORY_MS      250    // Lockout ms between strokes (rejects bounces, max 240 cpm)
#define DEFAULT_CALIB_TIME_MS      2000   // Hands-idle resting baseline measurement duration (ms)
#define DEFAULT_PRACTICE_SEC       60     // Default practice trial timer duration (0 = unlimited)
#define DEFAULT_USE_DUAL_MPU       false  // Default to single MPU for student testing

// ---- NVS Flash-Wear Safeguard Limits ----
#define NVS_MIN_WRITE_INTERVAL_MS  5000   // Minimum 5.0 seconds between flash writes (prevents flash frying)
#define NVS_NAMESPACE              "cpready_bench"

// ==============================================================================
// 1. SETTINGS & NVS FLASH-WEAR AUDIT MANAGER
// ==============================================================================
struct BenchSettings {
    float    depthK;
    float    compressionThreshG;
    float    recoilThreshG;
    uint32_t refractoryMs;
    uint32_t calibTimeMs;
    uint32_t practiceSec;
    bool     useDualMpu;

    // In-memory cache of last saved values to perform dirty-checking
    float    lastSavedDepthK;
    float    lastSavedCThresh;
    float    lastSavedRThresh;
    uint32_t lastSavedRefr;
    bool     lastSavedDual;
    uint32_t lastNvsWriteTime;

    void init() {
        depthK             = DEFAULT_DEPTH_K;
        compressionThreshG = DEFAULT_COMPRESS_THRESH_G;
        recoilThreshG      = DEFAULT_RECOIL_THRESH_G;
        refractoryMs       = DEFAULT_REFRACTORY_MS;
        calibTimeMs        = DEFAULT_CALIB_TIME_MS;
        practiceSec        = DEFAULT_PRACTICE_SEC;
        useDualMpu         = DEFAULT_USE_DUAL_MPU;

        lastSavedDepthK    = depthK;
        lastSavedCThresh   = compressionThreshG;
        lastSavedRThresh   = recoilThreshG;
        lastSavedRefr      = refractoryMs;
        lastSavedDual      = useDualMpu;
        lastNvsWriteTime   = 0;
    }

    void loadFromNVS() {
        init();
        Preferences prefs;
        if (prefs.begin(NVS_NAMESPACE, true)) { // Read-only
            depthK             = prefs.getFloat("depth_k", DEFAULT_DEPTH_K);
            compressionThreshG = prefs.getFloat("c_thresh", DEFAULT_COMPRESS_THRESH_G);
            recoilThreshG      = prefs.getFloat("r_thresh", DEFAULT_RECOIL_THRESH_G);
            refractoryMs       = prefs.getUInt("refr_ms", DEFAULT_REFRACTORY_MS);
            calibTimeMs        = prefs.getUInt("calib_ms", DEFAULT_CALIB_TIME_MS);
            practiceSec        = prefs.getUInt("prac_sec", DEFAULT_PRACTICE_SEC);
            useDualMpu         = prefs.getBool("dual_mpu", DEFAULT_USE_DUAL_MPU);
            prefs.end();

            // Cache saved state
            lastSavedDepthK  = depthK;
            lastSavedCThresh = compressionThreshG;
            lastSavedRThresh = recoilThreshG;
            lastSavedRefr    = refractoryMs;
            lastSavedDual    = useDualMpu;
        }
    }

    // AUDITED SAFE WRITE: Dirty-checking + Rate-limiting + Value Clamping
    bool saveToNVS(uint32_t nowMillis, String& outReason) {
        // Guard 1: Enforce minimum write cooldown (prevents rapid clicking flash wear)
        if (lastNvsWriteTime > 0 && (nowMillis - lastNvsWriteTime < NVS_MIN_WRITE_INTERVAL_MS)) {
            outReason = "Rate limited: Please wait 5 seconds between saves to protect Flash memory.";
            return false;
        }

        // Guard 2: Clamp values to strictly safe physiological ranges
        if (depthK < 1.0f) depthK = 1.0f;
        if (depthK > 50.0f) depthK = 50.0f;
        if (compressionThreshG < 0.10f) compressionThreshG = 0.10f;
        if (compressionThreshG > 3.00f) compressionThreshG = 3.00f;
        if (recoilThreshG < -3.00f) recoilThreshG = -3.00f;
        if (recoilThreshG > -0.01f) recoilThreshG = -0.01f;
        if (refractoryMs < 100) refractoryMs = 100;
        if (refractoryMs > 1000) refractoryMs = 1000;

        // Guard 3: Dirty Checking (Do not write if identical to what is in memory)
        bool hasChanged = (abs(depthK - lastSavedDepthK) > 0.001f) ||
                          (abs(compressionThreshG - lastSavedCThresh) > 0.001f) ||
                          (abs(recoilThreshG - lastSavedRThresh) > 0.001f) ||
                          (refractoryMs != lastSavedRefr) ||
                          (useDualMpu != lastSavedDual);

        if (!hasChanged) {
            outReason = "No changes detected. Memory write skipped to protect Flash life.";
            return true; // Already saved
        }

        Preferences prefs;
        if (!prefs.begin(NVS_NAMESPACE, false)) { // Read-Write
            outReason = "Could not open NVS storage.";
            return false;
        }

        prefs.putFloat("depth_k", depthK);
        prefs.putFloat("c_thresh", compressionThreshG);
        prefs.putFloat("r_thresh", recoilThreshG);
        prefs.putUInt("refr_ms", refractoryMs);
        prefs.putUInt("calib_ms", calibTimeMs);
        prefs.putUInt("prac_sec", practiceSec);
        prefs.putBool("dual_mpu", useDualMpu);
        prefs.end();

        // Update cache and timestamp
        lastSavedDepthK  = depthK;
        lastSavedCThresh = compressionThreshG;
        lastSavedRThresh = recoilThreshG;
        lastSavedRefr    = refractoryMs;
        lastSavedDual    = useDualMpu;
        lastNvsWriteTime = nowMillis;

        outReason = "Settings successfully saved to Flash memory.";
        return true;
    }

    void resetToDefaults(uint32_t nowMillis) {
        depthK             = DEFAULT_DEPTH_K;
        compressionThreshG = DEFAULT_COMPRESS_THRESH_G;
        recoilThreshG      = DEFAULT_RECOIL_THRESH_G;
        refractoryMs       = DEFAULT_REFRACTORY_MS;
        calibTimeMs        = DEFAULT_CALIB_TIME_MS;
        practiceSec        = DEFAULT_PRACTICE_SEC;
        useDualMpu         = DEFAULT_USE_DUAL_MPU;
        String msg;
        saveToNVS(nowMillis, msg);
    }
};

// ==============================================================================
// 2. KINEMATIC ENGINE & AUDIO COACHING STATE MACHINE
// ==============================================================================
enum class BenchStrokeState : uint8_t {
    WAITING_FOR_DOWNSLICK = 0,
    COMPRESSING = 1,
    RECOILING = 2
};

struct BenchReading {
    float    rate_cpm;
    float    depth_cm;
    bool     recoil_complete;
    float    ccf_percent;
    uint32_t elapsed_seconds;
    uint16_t stroke_count;
    float    current_accel;
};

struct BenchSummary {
    float    avg_rate_cpm;
    float    avg_depth_cm;
    float    recoil_compliance_percent;
    float    final_ccf_percent;
    uint16_t total_compressions;
    uint16_t total_duration_sec;
};

class BenchTracker {
private:
    BenchStrokeState state;
    BenchReading reading;
    BenchSummary lastSummary;

    float peakAccel;
    float troughAccel;
    uint32_t lastStrokePeakMillis;
    uint32_t strokeStartMillis;
    uint32_t sessionStartMillis;
    uint32_t totalActiveCompressionMillis;
    uint32_t lastCompressionDetectedMillis;

    uint32_t totalStrokeCount;
    uint32_t goodRecoilCount;
    float    cumulativeDepthSum;
    float    cumulativeRateSum;

    // Audio Coaching Hysteresis State Machine
    uint8_t  pendingCueCode;              // 0: none, 1: Push harder, 2: Push shallower, 3: Release completely, 4: Speed up, 5: Slow down, 6: Good compressions
    uint8_t  lastCandidateCue;
    uint8_t  consecutiveErrorStreak;
    uint32_t lastCueEmitMillis;
    uint32_t compliantStreakStartMillis;

public:
    BenchTracker() : state(BenchStrokeState::WAITING_FOR_DOWNSLICK) {
        reset();
    }

    void reset() {
        state = BenchStrokeState::WAITING_FOR_DOWNSLICK;
        peakAccel = 0.0f;
        troughAccel = 0.0f;
        lastStrokePeakMillis = 0;
        strokeStartMillis = 0;
        sessionStartMillis = 0;
        totalActiveCompressionMillis = 0;
        lastCompressionDetectedMillis = 0;

        totalStrokeCount = 0;
        goodRecoilCount = 0;
        cumulativeDepthSum = 0.0f;
        cumulativeRateSum = 0.0f;

        pendingCueCode = 0;
        lastCandidateCue = 0;
        consecutiveErrorStreak = 0;
        lastCueEmitMillis = 0;
        compliantStreakStartMillis = 0;

        reading = {0.0f, 0.0f, true, 0.0f, 0, 0, 0.0f};
        lastSummary = {0.0f, 0.0f, 100.0f, 0.0f, 0, 0};
    }

    void startSession(uint32_t currentMillis) {
        reset();
        sessionStartMillis = currentMillis;
        compliantStreakStartMillis = currentMillis;
    }

    bool isSessionActive() const { return sessionStartMillis > 0; }

    uint8_t consumeCueCode() {
        uint8_t cue = pendingCueCode;
        pendingCueCode = 0; // Clear once read so client speaks only once per event
        return cue;
    }

    bool processSample(float netAccel, uint32_t currentMillis, const BenchSettings& cfg) {
        reading.current_accel = netAccel;
        if (sessionStartMillis == 0) return false;

        reading.elapsed_seconds = (currentMillis - sessionStartMillis) / 1000;

        switch (state) {
            case BenchStrokeState::WAITING_FOR_DOWNSLICK:
                if (netAccel > cfg.compressionThreshG && 
                    (currentMillis - lastStrokePeakMillis > cfg.refractoryMs)) {
                    state = BenchStrokeState::COMPRESSING;
                    strokeStartMillis = currentMillis;
                    peakAccel = netAccel;
                    troughAccel = netAccel;
                }
                break;

            case BenchStrokeState::COMPRESSING:
                if (netAccel > peakAccel) {
                    peakAccel = netAccel;
                }
                if (netAccel < 0.0f) {
                    state = BenchStrokeState::RECOILING;
                    troughAccel = netAccel;
                }
                break;

            case BenchStrokeState::RECOILING:
                if (netAccel < troughAccel) {
                    troughAccel = netAccel;
                }
                if (netAccel >= -0.05f) {
                    uint32_t cyclePeriodMs = currentMillis - lastStrokePeakMillis;
                    lastStrokePeakMillis = currentMillis;
                    lastCompressionDetectedMillis = currentMillis;

                    // 1. Instantaneous Rate (AHA target: 100-120 cpm)
                    if (cyclePeriodMs > 0 && cyclePeriodMs < 2000) {
                        reading.rate_cpm = 60000.0f / (float)cyclePeriodMs;
                        totalActiveCompressionMillis += cyclePeriodMs;
                    }

                    // 2. Harmonic Depth: D = K * a_pp * T^2 (AHA target: 5.0-6.0 cm)
                    float peakToPeakAccel = peakAccel - troughAccel;
                    float cyclePeriodSec = (float)cyclePeriodMs / 1000.0f;
                    reading.depth_cm = cfg.depthK * (peakToPeakAccel * cyclePeriodSec * cyclePeriodSec);

                    if (reading.depth_cm < 0.0f)  reading.depth_cm = 0.0f;
                    if (reading.depth_cm > 10.0f) reading.depth_cm = 10.0f;

                    // 3. Recoil Check (< recoilThreshG confirms upward springback)
                    reading.recoil_complete = (troughAccel < cfg.recoilThreshG);

                    // 4. Clinical Resuscitation CCF % (Target >= 60%)
                    uint32_t totalSessionTime = currentMillis - sessionStartMillis;
                    if (totalSessionTime > 0) {
                        reading.ccf_percent = ((float)totalActiveCompressionMillis / (float)totalSessionTime) * 100.0f;
                        if (reading.ccf_percent > 100.0f) reading.ccf_percent = 100.0f;
                    }

                    // 5. Session Accumulators
                    totalStrokeCount++;
                    reading.stroke_count = (uint16_t)totalStrokeCount;
                    if (reading.recoil_complete) {
                        goodRecoilCount++;
                    }
                    cumulativeDepthSum += reading.depth_cm;
                    cumulativeRateSum  += reading.rate_cpm;

                    // 6. Clinical Audio Coaching Hysteresis State Machine
                    // Priority Hierarchy: Depth Error > Recoil Leaning > Rate Error > Reinforcement Praise
                    uint8_t desiredCue = 0;
                    if (reading.depth_cm < 5.0f) {
                        desiredCue = 1; // "Push harder"
                    } else if (reading.depth_cm > 6.0f) {
                        desiredCue = 2; // "Push shallower"
                    } else if (!reading.recoil_complete) {
                        desiredCue = 3; // "Release completely"
                    } else if (reading.rate_cpm < 100.0f) {
                        desiredCue = 4; // "Speed up"
                    } else if (reading.rate_cpm > 120.0f) {
                        desiredCue = 5; // "Slow down"
                    }

                    if (desiredCue > 0) {
                        compliantStreakStartMillis = currentMillis; // Break compliant streak
                        if (desiredCue == lastCandidateCue) {
                            consecutiveErrorStreak++;
                        } else {
                            lastCandidateCue = desiredCue;
                            consecutiveErrorStreak = 1;
                        }

                        // Anti-Nagging Hysteresis: Require 3 consecutive strokes (~1.8s - 2.5s) of sustained deviation
                        // AND enforce at least 5.0 seconds cooldown between consecutive voice prompts
                        if (consecutiveErrorStreak >= 3 && (currentMillis - lastCueEmitMillis >= 5000)) {
                            pendingCueCode = desiredCue;
                            lastCueEmitMillis = currentMillis;
                            consecutiveErrorStreak = 0;
                        }
                    } else {
                        // Rescuer is compliant within all AHA guidelines!
                        consecutiveErrorStreak = 0;
                        lastCandidateCue = 0;

                        // Positive Reinforcement Praise: Emit "Good compressions" every 15s of sustained compliance
                        if (compliantStreakStartMillis > 0 && 
                            (currentMillis - compliantStreakStartMillis >= 15000) &&
                            (currentMillis - lastCueEmitMillis >= 15000)) {
                            pendingCueCode = 6; // "Good compressions"
                            lastCueEmitMillis = currentMillis;
                            compliantStreakStartMillis = currentMillis; // Reset compliant timer interval
                        }
                    }

                    state = BenchStrokeState::WAITING_FOR_DOWNSLICK;
                    return true;
                }
                break;
        }

        return false;
    }

    BenchSummary finalizeSession(uint32_t endMillis) {
        BenchSummary s;
        s.total_compressions = (uint16_t)totalStrokeCount;
        s.total_duration_sec = sessionStartMillis > 0 ? (uint16_t)((endMillis - sessionStartMillis) / 1000) : 0;

        if (totalStrokeCount > 0) {
            s.avg_depth_cm = cumulativeDepthSum / (float)totalStrokeCount;
            s.avg_rate_cpm = cumulativeRateSum / (float)totalStrokeCount;
            s.recoil_compliance_percent = ((float)goodRecoilCount / (float)totalStrokeCount) * 100.0f;
        } else {
            s.avg_depth_cm = 0.0f;
            s.avg_rate_cpm = 0.0f;
            s.recoil_compliance_percent = 100.0f;
        }

        s.final_ccf_percent = reading.ccf_percent;
        lastSummary = s;
        sessionStartMillis = 0;
        return s;
    }

    const BenchReading& getReading() const { return reading; }
    const BenchSummary& getLastSummary() const { return lastSummary; }
};

// ==============================================================================
// 3. SENSOR SUBSYSTEM (Single & Dual MPU Dynamic Support + Bus Hang Recovery)
// ==============================================================================
class BenchSensors {
private:
    MPU6050 chestMpu;
    MPU6050 baseMpu;
    bool chestDetected;
    bool baseDetected;
    bool dualMode;
    bool isCalibrated;

    float chestZOffset;
    float baseZOffset;
    float calibChestAccum;
    float calibBaseAccum;
    uint32_t calibSampleCount;

    uint32_t nextSampleMicros;
    static constexpr uint32_t SAMPLE_INTERVAL_US = 10000; // Deterministic 100 Hz (10,000 us)

public:
    BenchSensors() : 
        chestMpu(BENCH_CHEST_I2C_ADDR), 
        baseMpu(BENCH_BASE_I2C_ADDR),
        chestDetected(false),
        baseDetected(false),
        dualMode(false),
        isCalibrated(false),
        chestZOffset(0.0f),
        baseZOffset(0.0f),
        calibChestAccum(0.0f),
        calibBaseAccum(0.0f),
        calibSampleCount(0),
        nextSampleMicros(0) {}

    bool begin(bool enableDual) {
        dualMode = enableDual;
        Wire.begin(BENCH_I2C_SDA_PIN, BENCH_I2C_SCL_PIN);
        Wire.setClock(BENCH_I2C_CLOCK_HZ);
        Wire.setTimeOut(BENCH_I2C_TIMEOUT_MS);

        delay(100);
        scanSensors();

        if (chestDetected) {
            initMpu(chestMpu);
        }
        if (baseDetected && dualMode) {
            initMpu(baseMpu);
        }

        nextSampleMicros = micros() + SAMPLE_INTERVAL_US;
        return chestDetected;
    }

    void scanSensors() {
        Wire.beginTransmission(BENCH_CHEST_I2C_ADDR);
        chestDetected = (Wire.endTransmission() == 0);

        Wire.beginTransmission(BENCH_BASE_I2C_ADDR);
        baseDetected = (Wire.endTransmission() == 0);
    }

    void setDualMode(bool enableDual) {
        dualMode = enableDual;
        if (dualMode && baseDetected) {
            initMpu(baseMpu);
        }
    }

    void recoverBus() {
        Wire.end();
        pinMode(BENCH_I2C_SDA_PIN, INPUT_PULLUP);
        pinMode(BENCH_I2C_SCL_PIN, OUTPUT);
        // Clock 9 pulses to clear stuck I2C slave state
        for (int i = 0; i < 9; i++) {
            digitalWrite(BENCH_I2C_SCL_PIN, HIGH);
            delayMicroseconds(5);
            digitalWrite(BENCH_I2C_SCL_PIN, LOW);
            delayMicroseconds(5);
        }
        Wire.begin(BENCH_I2C_SDA_PIN, BENCH_I2C_SCL_PIN);
        Wire.setClock(BENCH_I2C_CLOCK_HZ);
        Wire.setTimeOut(BENCH_I2C_TIMEOUT_MS);
    }

    void resetCalibration() {
        calibChestAccum = 0.0f;
        calibBaseAccum = 0.0f;
        calibSampleCount = 0;
        isCalibrated = false;
    }

    void recordCalibrationSample() {
        int16_t ax1, ay1, az1;
        chestMpu.getAcceleration(&ax1, &ay1, &az1);
        float chestG = (float)az1 / 16384.0f;
        calibChestAccum += chestG;

        if (dualMode && baseDetected) {
            int16_t ax2, ay2, az2;
            baseMpu.getAcceleration(&ax2, &ay2, &az2);
            float baseG = (float)az2 / 16384.0f;
            calibBaseAccum += baseG;
        }

        calibSampleCount++;
    }

    void finalizeCalibration() {
        if (calibSampleCount > 0) {
            chestZOffset = calibChestAccum / (float)calibSampleCount;
            if (dualMode && baseDetected) {
                baseZOffset = calibBaseAccum / (float)calibSampleCount;
            } else {
                baseZOffset = 0.0f;
            }
            isCalibrated = true;
        }
    }

    bool sample100Hz(float& outNetAccel, uint32_t currentMicros) {
        if ((int32_t)(currentMicros - nextSampleMicros) < 0) {
            return false; // Deterministic rate-limiter: Wait until 10,000 us has passed
        }
        nextSampleMicros += SAMPLE_INTERVAL_US;

        if (!chestDetected) {
            outNetAccel = 0.0f;
            return true;
        }

        int16_t ax1, ay1, az1;
        chestMpu.getAcceleration(&ax1, &ay1, &az1);
        float chestZ_g = (float)az1 / 16384.0f;
        float dynamicChest = -(chestZ_g - chestZOffset); // Inverted so downward push = positive g

        if (dualMode && baseDetected) {
            int16_t ax2, ay2, az2;
            baseMpu.getAcceleration(&ax2, &ay2, &az2);
            float baseZ_g = (float)az2 / 16384.0f;
            float dynamicBase = -(baseZ_g - baseZOffset);

            // True Differential Sternal Kinematics: Decouples foam bounce
            outNetAccel = dynamicChest - dynamicBase;
        } else {
            outNetAccel = dynamicChest;
        }

        return true;
    }

    bool isChestDetected() const { return chestDetected; }
    bool isBaseDetected() const { return baseDetected; }
    bool getIsCalibrated() const { return isCalibrated; }
    float getChestOffset() const { return chestZOffset; }
    float getBaseOffset() const { return baseZOffset; }

private:
    void initMpu(MPU6050& mpu) {
        mpu.initialize();
        mpu.setFullScaleAccelRange(MPU6050_ACCEL_FS_2); // +/- 2g range for maximum sensitivity
        mpu.setDLPFMode(MPU6050_DLPF_BW_42);           // 42 Hz Digital Low-Pass Filter
    }
};

// ==============================================================================
// 4. BUZZER ACOUSTIC SEQUENCER
// ==============================================================================
uint32_t buzzerToggleTime = 0;
uint8_t  buzzerBeepsLeft = 0;
bool     buzzerActive = false;
uint16_t buzzerOnMs = 120;
uint16_t buzzerOffMs = 100;

void playBeeps(uint8_t count, uint16_t onMs = 120, uint16_t offMs = 100) {
    buzzerBeepsLeft = count;
    buzzerOnMs = onMs;
    buzzerOffMs = offMs;
    digitalWrite(BENCH_BUZZER_PIN, HIGH);
    buzzerActive = true;
    buzzerToggleTime = millis() + buzzerOnMs;
}

void updateBuzzer(uint32_t now) {
    if (buzzerBeepsLeft == 0 && !buzzerActive) return;

    if (now >= buzzerToggleTime) {
        if (buzzerActive) {
            digitalWrite(BENCH_BUZZER_PIN, LOW);
            buzzerActive = false;
            buzzerBeepsLeft--;
            buzzerToggleTime = now + buzzerOffMs;
        } else if (buzzerBeepsLeft > 0) {
            digitalWrite(BENCH_BUZZER_PIN, HIGH);
            buzzerActive = true;
            buzzerToggleTime = now + buzzerOnMs;
        }
    }
}

// ==============================================================================
// 5. EMBEDDED MEDICAL WEB UI (Clean Clinical White/Blue Aesthetic + Live Audio)
// ==============================================================================
const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>CPReady Medical Test Bench</title>
<style>
:root {
  --bg: #f8fafc;
  --card: #ffffff;
  --card-border: #e2e8f0;
  --text-main: #0f172a;
  --text-muted: #64748b;
  --primary: #0284c7;
  --primary-light: #e0f2fe;
  --primary-hover: #0369a1;
  --teal-accent: #0d9488;
  --teal-light: #ccfbf1;
  --success: #16a34a;
  --success-light: #dcfce7;
  --warning: #d97706;
  --warning-light: #fef3c7;
  --danger: #dc2626;
  --danger-light: #fee2e2;
  --shadow-sm: 0 1px 3px rgba(0,0,0,0.05);
  --shadow-md: 0 4px 16px -2px rgba(2, 132, 199, 0.08);
}
* { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
body { background: var(--bg); color: var(--text-main); padding: 12px; min-height: 100vh; }
.container { max-width: 480px; margin: 0 auto; display: flex; flex-direction: column; gap: 12px; }

/* Top Clinical Header */
header { background: var(--card); border: 1px solid var(--card-border); padding: 16px; border-radius: 20px; box-shadow: var(--shadow-md); display: flex; justify-content: space-between; align-items: center; }
.brand h1 { font-size: 1.25rem; font-weight: 800; color: var(--primary); letter-spacing: -0.02em; }
.brand p { font-size: 0.75rem; color: var(--text-muted); font-weight: 500; }
.status-pill-group { display: flex; flex-direction: column; gap: 4px; align-items: flex-end; }
.pill { padding: 3px 8px; border-radius: 20px; font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.03em; }
.pill-green { background: var(--success-light); color: var(--success); }
.pill-amber { background: var(--warning-light); color: var(--warning); }
.pill-red { background: var(--danger-light); color: var(--danger); }

/* Voice Coach Banner */
.voice-banner { background: #0284c7; color: #ffffff; padding: 10px 16px; border-radius: 16px; display: none; align-items: center; justify-content: space-between; box-shadow: 0 4px 15px rgba(2, 132, 199, 0.3); animation: slideDown 0.3s ease; }
@keyframes slideDown { from { transform: translateY(-10px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }
.voice-banner .cue-text { font-size: 0.85rem; font-weight: 700; display: flex; align-items: center; gap: 8px; }
.sound-wave { display: inline-flex; align-items: center; gap: 2px; }
.sound-wave span { width: 3px; height: 12px; background: #ffffff; border-radius: 2px; animation: wave 0.8s infinite ease-in-out; }
.sound-wave span:nth-child(2) { animation-delay: 0.2s; height: 16px; }
.sound-wave span:nth-child(3) { animation-delay: 0.4s; height: 10px; }
@keyframes wave { 0%, 100% { transform: scaleY(0.4); } 50% { transform: scaleY(1); } }

/* Mode Switcher Pill Banner */
.mode-banner { background: var(--card); border: 1px solid var(--card-border); padding: 14px 16px; border-radius: 20px; box-shadow: var(--shadow-sm); display: flex; justify-content: space-between; align-items: center; gap: 8px; }
.mode-details h3 { font-size: 0.85rem; font-weight: 700; color: var(--text-main); }
.mode-details p { font-size: 0.7rem; color: var(--text-muted); margin-top: 1px; }
.btn-pill-toggle { background: var(--primary-light); color: var(--primary); border: 1px solid #bae6fd; padding: 7px 14px; border-radius: 24px; font-weight: 700; font-size: 0.75rem; cursor: pointer; transition: all 0.2s; white-space: nowrap; }
.btn-pill-toggle.dual { background: var(--teal-accent); color: #ffffff; border-color: var(--teal-accent); }

/* Action Cards */
.card { background: var(--card); border: 1px solid var(--card-border); border-radius: 20px; padding: 16px; box-shadow: var(--shadow-md); }
.action-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.btn { width: 100%; min-height: 48px; border-radius: 14px; font-weight: 700; font-size: 0.85rem; border: none; cursor: pointer; display: inline-flex; align-items: center; justify-content: center; gap: 6px; transition: all 0.15s; }
.btn:active { transform: scale(0.97); }
.btn-primary { background: var(--primary); color: #ffffff; box-shadow: 0 4px 12px rgba(2, 132, 199, 0.25); }
.btn-primary:hover { background: var(--primary-hover); }
.btn-success { background: var(--success); color: #ffffff; }
.btn-danger { background: var(--danger); color: #ffffff; }
.btn-secondary { background: #f1f5f9; color: var(--text-main); border: 1px solid #cbd5e1; }

/* Calibration Banner */
.calib-banner { background: #f0f9ff; border: 1px dashed #38bdf8; border-radius: 14px; padding: 10px 14px; display: flex; justify-content: space-between; align-items: center; margin-top: 8px; }
.calib-banner span { font-size: 0.75rem; font-weight: 600; color: var(--primary); }

/* Live Telemetry Cards */
.telemetry-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.metric-box { background: var(--card); border: 1px solid var(--card-border); border-radius: 18px; padding: 14px; display: flex; flex-direction: column; justify-content: space-between; box-shadow: var(--shadow-sm); position: relative; overflow: hidden; }
.metric-box::before { content: ""; position: absolute; top: 0; left: 0; right: 0; height: 4px; background: #cbd5e1; }
.metric-box.state-good::before { background: var(--success); }
.metric-box.state-warn::before { background: var(--warning); }
.metric-box.state-alert::before { background: var(--danger); }
.box-label { font-size: 0.7rem; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.04em; }
.box-val { font-size: 1.85rem; font-weight: 800; color: var(--text-main); margin: 4px 0; display: flex; align-items: baseline; gap: 4px; }
.box-val .unit { font-size: 0.8rem; font-weight: 600; color: var(--text-muted); }
.box-target { font-size: 0.68rem; color: var(--text-muted); font-weight: 600; }

/* Recoil Pill */
.recoil-indicator { padding: 8px 12px; border-radius: 10px; font-size: 0.8rem; font-weight: 800; text-align: center; margin: 4px 0; }
.recoil-good { background: var(--success-light); color: var(--success); }
.recoil-lean { background: var(--danger-light); color: var(--danger); animation: pulse 1s infinite; }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }

/* Audio Coaching Interactive Tester */
.audio-card { background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 18px; padding: 14px; margin-top: 4px; }
.audio-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
.audio-header h3 { font-size: 0.85rem; font-weight: 800; color: var(--success); display: flex; align-items: center; gap: 6px; }
.voice-pills { display: flex; flex-wrap: wrap; gap: 6px; }
.voice-btn { background: #ffffff; border: 1px solid #86efac; color: #166534; padding: 6px 10px; border-radius: 20px; font-size: 0.72rem; font-weight: 700; cursor: pointer; transition: all 0.15s; display: inline-flex; align-items: center; gap: 4px; }
.voice-btn:hover { background: #dcfce7; transform: scale(1.02); }
.voice-btn:active { transform: scale(0.96); }

/* Sliders & Tuning Section */
.tuning-title { font-size: 0.95rem; font-weight: 800; color: var(--text-main); margin-bottom: 12px; display: flex; justify-content: space-between; align-items: center; }
.setting-card { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 14px; padding: 12px; margin-bottom: 10px; }
.setting-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
.setting-name { font-size: 0.8rem; font-weight: 700; color: var(--text-main); }
.setting-badge { font-size: 0.75rem; font-weight: 800; color: var(--primary); background: #ffffff; padding: 2px 8px; border-radius: 12px; border: 1px solid #cbd5e1; }
.setting-help { font-size: 0.68rem; color: var(--text-muted); line-height: 1.35; margin-bottom: 8px; }
.slider-wrap { display: flex; align-items: center; gap: 10px; }
input[type="range"] { flex: 1; accent-color: var(--primary); height: 6px; }

/* Toast Notification */
.toast { position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%); background: #0f172a; color: #ffffff; padding: 10px 18px; border-radius: 30px; font-size: 0.8rem; font-weight: 600; box-shadow: 0 10px 25px rgba(0,0,0,0.2); display: none; z-index: 1000; text-align: center; }
.code-box { background: #f1f5f9; border: 1px solid #cbd5e1; border-radius: 10px; padding: 10px; font-family: monospace; font-size: 0.68rem; color: #0369a1; white-space: pre-wrap; display: none; margin-top: 10px; max-height: 130px; overflow-y: auto; }
</style>
</head>
<body>

<div class="container">
  <!-- Top Clinical Header -->
  <header>
    <div class="brand">
      <h1>CPReady Bench</h1>
      <p>Clinical CPR Metric Validation <span class="pill pill-green" style="margin-left:4px;">Live ESP32</span></p>
    </div>
    <div class="status-pill-group">
      <span id="pillChest" class="pill pill-green">Chest: OK (0x68)</span>
      <span id="pillBase" class="pill pill-amber">Spine: Offline</span>
    </div>
  </header>

  <!-- Live Voice Coaching Banner (Appears when phone speaks) -->
  <div id="voiceBanner" class="voice-banner">
    <div class="cue-text">
      <div class="sound-wave"><span></span><span></span><span></span></div>
      <span id="voiceCueText">Voice Coach Active</span>
    </div>
    <span style="font-size:0.65rem; opacity:0.85;">Phone Speaker</span>
  </div>

  <!-- Single vs Dual MPU Mode Switcher -->
  <div class="mode-banner">
    <div class="mode-details">
      <h3 id="modeTitle">Single MPU (Chest Only)</h3>
      <p id="modeDesc">Measuring sternal compression with baseline zeroing.</p>
    </div>
    <button id="btnMode" class="btn-pill-toggle" onclick="toggleSensorMode()">Switch Mode</button>
  </div>

  <!-- Session & Calibration Controls -->
  <div class="card">
    <div class="action-grid">
      <button class="btn btn-primary" onclick="startCalibration()">
        <svg width="16" height="16" fill="currentColor" viewBox="0 0 16 16"><path d="M8 15A7 7 0 1 1 8 1a7 7 0 0 1 0 14zm0 1A8 8 0 1 0 8 0a8 8 0 0 0 0 16z"/><path d="M8 4a.5.5 0 0 1 .5.5v3h3a.5.5 0 0 1 0 1h-3v3a.5.5 0 0 1-1 0v-3h-3a.5.5 0 0 1 0-1h3v-3A.5.5 0 0 1 8 4z"/></svg>
        Calibrate (2s)
      </button>
      <button id="btnSession" class="btn btn-success" onclick="toggleSession()">Start Test</button>
    </div>
    <div class="calib-banner">
      <span id="calibLabel">Rest hands on chest & calibrate</span>
      <button onclick="resetStats()" style="background:none; border:none; color:var(--text-muted); font-size:0.7rem; font-weight:700; cursor:pointer;">Reset Stats</button>
    </div>
  </div>

  <!-- Real-Time AHA Telemetry Cards (Mobile Stack) -->
  <div class="telemetry-row">
    <!-- Rate -->
    <div id="boxRate" class="metric-box">
      <div class="box-label">Rate</div>
      <div class="box-val"><span id="valRate">--</span> <span class="unit">cpm</span></div>
      <div class="box-target">AHA: 100–120 cpm</div>
    </div>

    <!-- Depth -->
    <div id="boxDepth" class="metric-box">
      <div class="box-label">Depth</div>
      <div class="box-val"><span id="valDepth">--</span> <span class="unit">cm</span></div>
      <div class="box-target">AHA: 5.0–6.0 cm (<span id="valDepthMm">--</span>mm)</div>
    </div>
  </div>

  <div class="telemetry-row">
    <!-- Recoil -->
    <div id="boxRecoil" class="metric-box">
      <div class="box-label">Recoil</div>
      <div id="recoilPill" class="recoil-indicator recoil-good">READY</div>
      <div class="box-target">Compliance: <span id="valRecoilPct">100%</span></div>
    </div>

    <!-- CCF -->
    <div id="boxCCF" class="metric-box">
      <div class="box-label">CCF Active</div>
      <div class="box-val"><span id="valCCF">--</span> <span class="unit">%</span></div>
      <div class="box-target">AHA Target: &ge; 60%</div>
    </div>
  </div>

  <!-- Stroke and Time Footer Row -->
  <div class="telemetry-row">
    <div class="metric-box">
      <div class="box-label">Compressions</div>
      <div class="box-val"><span id="valStrokes">0</span> <span class="unit">strokes</span></div>
      <div class="box-target">Elapsed: <span id="valElapsed">0s</span></div>
    </div>
    <div class="metric-box">
      <div class="box-label">Net Accel</div>
      <div class="box-val"><span id="valAccel">0.00</span> <span class="unit">g</span></div>
      <div class="box-target">Trigger: <span id="valThreshSub">0.45 g</span></div>
    </div>
  </div>

  <!-- Voice Coaching Interactive Tester -->
  <div class="audio-card">
    <div class="audio-header">
      <h3>
        <svg width="18" height="18" fill="currentColor" viewBox="0 0 16 16"><path d="M11.536 14.01A8.473 8.473 0 0 0 14.026 8a8.473 8.473 0 0 0-2.49-6.01l-.708.707A7.476 7.476 0 0 1 13.025 8c0 2.071-.84 3.946-2.197 5.303l.708.707z"/><path d="M10.121 12.596A6.48 6.48 0 0 0 12.025 8a6.48 6.48 0 0 0-1.904-4.596l-.707.707A5.482 5.482 0 0 1 11.025 8a5.482 5.482 0 0 1-1.61 3.89l.706.706z"/><path d="M8.707 11.182A4.486 4.486 0 0 0 10.025 8a4.486 4.486 0 0 0-1.318-3.182L8 5.525A3.489 3.489 0 0 1 9.025 8 3.49 3.49 0 0 1 8 10.475l.707.707zM6.717 3.55A.5.5 0 0 1 7 4v8a.5.5 0 0 1-.812.39L3.825 10.5H1.5A.5.5 0 0 1 1 10V6a.5.5 0 0 1 .5-.5h2.325l2.363-1.89a.5.5 0 0 1 .529-.06z"/></svg>
        Web Speech Voice Coach (Phone Speaker)
      </h3>
      <button id="btnVoiceToggle" class="voice-btn" onclick="toggleVoiceMaster()" style="border-color:#16a34a; background:#dcfce7;">
        🔊 Voice: ON
      </button>
    </div>
    <p style="font-size:0.7rem; color:#15803d; margin-bottom:8px; line-height:1.35;">
      Voice cues trigger automatically as you compress based on AHA depth, recoil, and cadence. You can also tap below to test:
    </p>
    <div class="voice-pills">
      <button class="voice-btn" onclick="speakPhrase('Push harder')">🗣️ "Push harder"</button>
      <button class="voice-btn" onclick="speakPhrase('Push shallower')">🗣️ "Push shallower"</button>
      <button class="voice-btn" onclick="speakPhrase('Release completely')">🗣️ "Release completely"</button>
      <button class="voice-btn" onclick="speakPhrase('Speed up')">🗣️ "Speed up"</button>
      <button class="voice-btn" onclick="speakPhrase('Slow down')">🗣️ "Slow down"</button>
      <button class="voice-btn" onclick="speakPhrase('Good compressions')">🗣️ "Good compressions"</button>
    </div>

    <!-- Voice Selector Dropdown -->
    <div style="margin-top: 8px; display: flex; align-items: center; gap: 6px;">
      <label for="voiceSelect" style="font-size: 0.7rem; font-weight: 700; color: #166534; white-space: nowrap;">Voice Engine:</label>
      <select id="voiceSelect" style="flex: 1; padding: 4px 8px; border-radius: 8px; border: 1px solid #86efac; font-size: 0.7rem; background: #ffffff; color: #0f172a;" onchange="onVoiceSelected(this.value)">
        <option value="-1">Default System Voice</option>
      </select>
    </div>
  </div>

  <!-- Tuning & Explanations Panel -->
  <div class="card">
    <div class="tuning-title">
      <span>Parameter Calibration</span>
      <button class="btn btn-secondary" onclick="restoreDefaults()" style="width:auto; min-height:32px; padding:4px 10px; font-size:0.7rem;">Reset</button>
    </div>

    <!-- Depth K -->
    <div class="setting-card">
      <div class="setting-header">
        <span class="setting-name">Depth Multiplier (K)</span>
        <span id="lblDepthK" class="setting-badge">11.2</span>
      </div>
      <p class="setting-help">Scales measured bounce into centimeters. If your physical ruler measures 5.0 cm but the screen shows 4.0 cm, increase this number.</p>
      <div class="slider-wrap">
        <input type="range" id="rngDepthK" min="5.0" max="25.0" step="0.1" value="11.2" oninput="updateSetting('DepthK', this.value)">
      </div>
    </div>

    <!-- Push Threshold -->
    <div class="setting-card">
      <div class="setting-header">
        <span class="setting-name">Push Sensitivity</span>
        <span id="lblCThresh" class="setting-badge">0.45 g</span>
      </div>
      <p class="setting-help">Minimum force to trigger a downstroke. Lower this if soft compressions aren't counting; raise it if bumps trigger false strokes.</p>
      <div class="slider-wrap">
        <input type="range" id="rngCThresh" min="0.20" max="1.00" step="0.01" value="0.45" oninput="updateSetting('CThresh', this.value)">
      </div>
    </div>

    <!-- Recoil Threshold -->
    <div class="setting-card">
      <div class="setting-header">
        <span class="setting-name">Recoil Strictness</span>
        <span id="lblRThresh" class="setting-badge">-0.35 g</span>
      </div>
      <p class="setting-help">Upward snap-back check. If trainees release fully but it warns 'Leaning', move this slider closer to zero (e.g. -0.25 g).</p>
      <div class="slider-wrap">
        <input type="range" id="rngRThresh" min="-0.80" max="-0.10" step="0.01" value="-0.35" oninput="updateSetting('RThresh', this.value)">
      </div>
    </div>

    <!-- Refractory Lockout -->
    <div class="setting-card">
      <div class="setting-header">
        <span class="setting-name">Refractory Lockout</span>
        <span id="lblRefr" class="setting-badge">250 ms</span>
      </div>
      <p class="setting-help">Rest window between strokes to stop foam bounce from double-counting. 250 ms safely caps rate to 240 cpm.</p>
      <div class="slider-wrap">
        <input type="range" id="rngRefr" min="150" max="400" step="10" value="250" oninput="updateSetting('Refr', this.value)">
      </div>
    </div>

    <!-- Safe Save Button (Dirty Checking + Rate Limited on ESP32) -->
    <button id="btnSaveMemory" class="btn btn-primary" onclick="saveToMemory()" style="margin-top:6px;">
      💾 Save Settings to Memory (Safe Flash)
    </button>
    <button class="btn btn-secondary" onclick="exportCode()" style="margin-top:8px;">
      📋 Generate C++ Config for Paper
    </button>
    <div id="exportBox" class="code-box"></div>
  </div>
</div>

<div id="toast" class="toast"></div>

<!-- ============================================================================== -->
<!-- REAL FRONTEND SCRIPT (LIVE REST API INTEGRATION + WEB SPEECH ENGINE)            -->
<!-- ============================================================================== -->
<script>
let voiceMasterEnabled = true;
let selectedVoiceIndex = -1;
let availableVoices = [];

// Initialize and populate available system voices
function initVoices() {
  if (!('speechSynthesis' in window)) return;
  availableVoices = window.speechSynthesis.getVoices();
  const sel = document.getElementById('voiceSelect');
  if (!sel) return;
  sel.innerHTML = '<option value="-1">Default System Voice</option>';
  availableVoices.forEach((v, idx) => {
    const opt = document.createElement('option');
    opt.value = idx;
    opt.textContent = `${v.name} (${v.lang})${v.default ? ' [Default]' : ''}`;
    if (v.lang.startsWith('en') && selectedVoiceIndex === -1 && (v.name.includes('Natural') || v.name.includes('Online') || v.name.includes('Google') || v.name.includes('Siri') || v.name.includes('Zira'))) {
      selectedVoiceIndex = idx;
    }
    sel.appendChild(opt);
  });
  if (selectedVoiceIndex >= 0) sel.value = selectedVoiceIndex;
}

if ('speechSynthesis' in window) {
  initVoices();
  window.speechSynthesis.onvoiceschanged = initVoices;
}

function onVoiceSelected(idx) {
  selectedVoiceIndex = parseInt(idx);
}

// Unlock audio on initial user gesture (critical for mobile browser autoplay policies)
let audioUnlocked = false;
let audioCtx = null;

function getAudioContext() {
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (AudioContextClass) audioCtx = new AudioContextClass();
  }
  if (audioCtx && audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
  return audioCtx;
}

// Medical AED-style prompt chime (wakes up mobile DAC/Bluetooth hardware and eliminates first-syllable cut-offs)
function playWakeupChime() {
  try {
    const ctx = getAudioContext();
    if (!ctx) return;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    // Gentle dual-tone medical ping: D5 (587 Hz) ramping to A5 (880 Hz)
    osc.frequency.setValueAtTime(587.33, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(880, ctx.currentTime + 0.07);
    gain.gain.setValueAtTime(0.001, ctx.currentTime);
    gain.gain.linearRampToValueAtTime(0.12, ctx.currentTime + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.09);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.1);
  } catch (e) {
    console.warn('Audio chime warning:', e);
  }
}

function unlockAudio() {
  if (audioUnlocked) return;
  getAudioContext();
  if ('speechSynthesis' in window) {
    const silent = new SpeechSynthesisUtterance('');
    silent.volume = 0;
    window.speechSynthesis.speak(silent);
  }
  audioUnlocked = true;
}
document.addEventListener('touchstart', unlockAudio, { once: true });
document.addEventListener('click', unlockAudio, { once: true });

// Persistent reference to prevent Chromium on Windows from garbage-collecting the utterance mid-speech
window._activeUtterance = null;

// Speech Synthesis Engine
function speakPhrase(phrase) {
  if (!voiceMasterEnabled) return;
  if (!('speechSynthesis' in window)) {
    showToast('Web Speech API not supported in this browser');
    return;
  }

  // 1. Play prompt chime to wake mobile speaker amplifier & alert rescuer
  playWakeupChime();

  // 2. Unpause engine for Windows Chrome/Edge SAPI
  if (window.speechSynthesis.paused) {
    window.speechSynthesis.resume();
  }
  if (window.speechSynthesis.speaking) {
    window.speechSynthesis.cancel();
  }

  // 3. 120ms delay: allows speaker hardware DAC to ramp up and avoids Windows Chromium cancel() race deadlock
  setTimeout(() => {
    // Leading comma provides 100ms acoustic lead-in so the initial consonant is never clipped
    const paddedText = ',  ' + phrase;
    const u = new SpeechSynthesisUtterance(paddedText);
    u.rate = 1.02; // natural clinical pacing
    u.pitch = 1.0;
    u.lang = 'en-US';

    if (selectedVoiceIndex >= 0 && availableVoices[selectedVoiceIndex]) {
      u.voice = availableVoices[selectedVoiceIndex];
    } else {
      const enVoice = availableVoices.find(v => v.lang.startsWith('en'));
      if (enVoice) u.voice = enVoice;
    }

    const banner = document.getElementById('voiceBanner');
    const bannerText = document.getElementById('voiceCueText');
    bannerText.innerText = 'Voice Coach: "' + phrase + '"';

    u.onstart = () => {
      banner.style.display = 'flex';
    };
    u.onend = () => {
      banner.style.display = 'none';
      window._activeUtterance = null;
    };
    u.onerror = (e) => {
      console.warn('Speech error:', e);
      banner.style.display = 'none';
      window._activeUtterance = null;
    };

    // Store reference globally so V8 garbage collection does not drop speech on Windows
    window._activeUtterance = u;

    window.speechSynthesis.speak(u);

    // Additional safety resume for Chromium Windows bug where speech pauses randomly
    if (window.speechSynthesis.paused) {
      window.speechSynthesis.resume();
    }
  }, 120);
}

function handleCueTrigger(cueCode) {
  const cues = {
    1: 'Push harder',
    2: 'Push shallower',
    3: 'Release chest completely',
    4: 'Speed up',
    5: 'Slow down',
    6: 'Good compressions'
  };
  if (cues[cueCode]) {
    speakPhrase(cues[cueCode]);
  }
}

function toggleVoiceMaster() {
  voiceMasterEnabled = !voiceMasterEnabled;
  const btn = document.getElementById('btnVoiceToggle');
  if (voiceMasterEnabled) {
    btn.innerHTML = '🔊 Voice: ON';
    btn.style.background = '#dcfce7';
    btn.style.borderColor = '#16a34a';
    btn.style.color = '#166534';
    showToast('Voice coaching unmuted');
  } else {
    btn.innerHTML = '🔇 Voice: MUTED';
    btn.style.background = '#fee2e2';
    btn.style.borderColor = '#ef4444';
    btn.style.color = '#991b1b';
    window.speechSynthesis.cancel();
    showToast('Voice coaching muted');
  }
}

// UI State & REST API Logic
let cfg = { depthK: 11.2, compressionThreshG: 0.45, recoilThreshG: -0.35, refractoryMs: 250, useDualMpu: false };
let sessionActive = false;

function showToast(msg) {
  const t = document.getElementById('toast');
  t.innerText = msg;
  t.style.display = 'block';
  setTimeout(() => { t.style.display = 'none'; }, 3200);
}

function updateSetting(key, val) {
  val = parseFloat(val);
  if (key === 'DepthK') {
    cfg.depthK = val;
    document.getElementById('lblDepthK').innerText = val.toFixed(1);
  } else if (key === 'CThresh') {
    cfg.compressionThreshG = val;
    document.getElementById('lblCThresh').innerText = val.toFixed(2) + ' g';
    document.getElementById('valThreshSub').innerText = val.toFixed(2) + ' g';
  } else if (key === 'RThresh') {
    cfg.recoilThreshG = val;
    document.getElementById('lblRThresh').innerText = val.toFixed(2) + ' g';
  } else if (key === 'Refr') {
    cfg.refractoryMs = parseInt(val);
    document.getElementById('lblRefr').innerText = val + ' ms';
  }
}

async function fetchMetrics() {
  try {
    const res = await fetch('/api/metrics');
    if (!res.ok) return;
    const d = await res.json();

    // 1. Process Live Voice Coaching Cue from ESP32 Firmware
    if (d.cue && d.cue > 0) {
      handleCueTrigger(d.cue);
    }

    // Rate
    const rateEl = document.getElementById('valRate');
    const boxRate = document.getElementById('boxRate');
    if (d.rate > 0) {
      rateEl.innerText = Math.round(d.rate);
      boxRate.className = 'metric-box ' + (d.rate >= 100 && d.rate <= 120 ? 'state-good' : (d.rate < 100 ? 'state-warn' : 'state-alert'));
    } else {
      rateEl.innerText = '--';
      boxRate.className = 'metric-box';
    }

    // Depth
    const depthEl = document.getElementById('valDepth');
    const depthMmEl = document.getElementById('valDepthMm');
    const boxDepth = document.getElementById('boxDepth');
    if (d.depth > 0) {
      depthEl.innerText = d.depth.toFixed(1);
      depthMmEl.innerText = Math.round(d.depth * 10);
      boxDepth.className = 'metric-box ' + (d.depth >= 5.0 && d.depth <= 6.0 ? 'state-good' : (d.depth < 5.0 ? 'state-warn' : 'state-alert'));
    } else {
      depthEl.innerText = '--';
      depthMmEl.innerText = '--';
      boxDepth.className = 'metric-box';
    }

    // Recoil
    const pill = document.getElementById('recoilPill');
    if (d.strokes > 0) {
      if (d.recoil_ok) {
        pill.className = 'recoil-indicator recoil-good';
        pill.innerText = 'FULL RELEASE';
      } else {
        pill.className = 'recoil-indicator recoil-lean';
        pill.innerText = 'LEANING / INCOMPLETE';
      }
    } else {
      pill.className = 'recoil-indicator recoil-good';
      pill.innerText = 'READY';
    }
    document.getElementById('valRecoilPct').innerText = Math.round(d.recoil_pct) + '%';

    // CCF
    const ccfEl = document.getElementById('valCCF');
    const boxCCF = document.getElementById('boxCCF');
    if (d.elapsed > 0) {
      ccfEl.innerText = Math.round(d.ccf);
      boxCCF.className = 'metric-box ' + (d.ccf >= 60 ? 'state-good' : 'state-warn');
    } else {
      ccfEl.innerText = '--';
      boxCCF.className = 'metric-box';
    }

    // Strokes & Accel
    document.getElementById('valStrokes').innerText = d.strokes;
    document.getElementById('valElapsed').innerText = d.elapsed + 's';
    document.getElementById('valAccel').innerText = (d.accel >= 0 ? '+' : '') + d.accel.toFixed(2);

    // Hardware Badges
    const pChest = document.getElementById('pillChest');
    pChest.className = 'pill ' + (d.chest_ok ? 'pill-green' : 'pill-red');
    pChest.innerText = d.chest_ok ? 'Chest: OK (0x68)' : 'Chest: N/A';

    const pBase = document.getElementById('pillBase');
    pBase.className = 'pill ' + (d.base_ok ? 'pill-green' : 'pill-amber');
    pBase.innerText = d.base_ok ? 'Spine: OK (0x69)' : 'Spine: Offline';

    // Calibration State
    const calibLabel = document.getElementById('calibLabel');
    if (d.is_calibrating) {
      calibLabel.innerText = 'Calibrating... Keep still!';
      calibLabel.style.color = 'var(--warning)';
    } else if (d.is_calibrated) {
      calibLabel.innerText = 'Calibrated & Ready';
      calibLabel.style.color = 'var(--success)';
    }

    sessionActive = d.session_active;
    const btnS = document.getElementById('btnSession');
    if (sessionActive) {
      btnS.className = 'btn btn-danger';
      btnS.innerText = 'Stop Test';
    } else {
      btnS.className = 'btn btn-success';
      btnS.innerText = 'Start Test';
    }
  } catch (e) {
    console.error(e);
  }
}

async function loadConfig() {
  try {
    const res = await fetch('/api/config');
    if (!res.ok) return;
    const c = await res.json();
    cfg = c;
    document.getElementById('rngDepthK').value = c.depthK;
    document.getElementById('rngCThresh').value = c.compressionThreshG;
    document.getElementById('rngRThresh').value = c.recoilThreshG;
    document.getElementById('rngRefr').value = c.refractoryMs;
    updateSetting('DepthK', c.depthK);
    updateSetting('CThresh', c.compressionThreshG);
    updateSetting('RThresh', c.recoilThreshG);
    updateSetting('Refr', c.refractoryMs);
    renderModeUI(c.useDualMpu);
  } catch (e) {
    console.error(e);
  }
}

function renderModeUI(isDual) {
  cfg.useDualMpu = isDual;
  const t = document.getElementById('modeTitle');
  const d = document.getElementById('modeDesc');
  const b = document.getElementById('btnMode');
  if (isDual) {
    t.innerText = 'Dual MPU (Decoupled)';
    d.innerText = 'Subtracting spine reference to eliminate mattress/foam bounce.';
    b.innerText = 'Switch to Single';
    b.className = 'btn-pill-toggle dual';
  } else {
    t.innerText = 'Single MPU (Chest Only)';
    d.innerText = 'Measuring sternal compression with baseline zeroing.';
    b.innerText = 'Switch to Dual';
    b.className = 'btn-pill-toggle';
  }
}

async function toggleSensorMode() {
  const newMode = !cfg.useDualMpu;
  await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'set_mode', dual: newMode })
  });
  renderModeUI(newMode);
  showToast(newMode ? 'Switched to Dual MPU Mode' : 'Switched to Single MPU Mode');
}

async function startCalibration() {
  showToast('Hold hands still on chest pad...');
  await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'calibrate' })
  });
}

async function toggleSession() {
  const act = sessionActive ? 'stop_session' : 'start_session';
  const res = await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: act })
  });
  const data = await res.json();
  if (data.message) {
    showToast(data.message);
  }
}

async function resetStats() {
  await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'reset_session' })
  });
  showToast('Statistics reset');
}

async function saveToMemory() {
  const btn = document.getElementById('btnSaveMemory');
  btn.disabled = true;
  btn.innerText = 'Saving to Flash...';

  try {
    const res = await fetch('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cfg)
    });
    const data = await res.json();
    showToast(data.message || 'Saved successfully');
  } catch (err) {
    showToast('Save failed');
  } finally {
    setTimeout(() => {
      btn.disabled = false;
      btn.innerText = '💾 Save Settings to Memory (Safe Flash)';
    }, 2000);
  }
}

async function restoreDefaults() {
  if (confirm('Reset parameters to factory defaults?')) {
    await fetch('/api/action', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'restore_defaults' })
    });
    await loadConfig();
    showToast('Defaults restored');
  }
}

function exportCode() {
  const box = document.getElementById('exportBox');
  const code = 
`// ==============================================================
// CPReady Calibrated Parameters (Exported from Test Bench)
// ==============================================================
#define DEPTH_CALIBRATION_K    ${cfg.depthK.toFixed(2)}f   // Tested depth scalar
#define COMPRESSION_THRESH_G   ${cfg.compressionThreshG.toFixed(2)}f   // Downstroke sensitivity
#define RECOIL_THRESH_G        ${cfg.recoilThreshG.toFixed(2)}f  // Upward rebound check
#define REFRACTORY_LOCKOUT_MS  ${cfg.refractoryMs}      // Foam debounce lockout
#define SENSOR_MODE_DUAL       ${cfg.useDualMpu ? 'true' : 'false'}   // Decoupling mode`;

  box.innerText = code;
  box.style.display = 'block';
}

window.onload = () => {
  loadConfig();
  setInterval(fetchMetrics, 100);
};
</script>
</body>
</html>
)rawliteral";

// ==============================================================================
// 6. GLOBAL INSTANCES & HTTP REST API HANDLERS
// ==============================================================================
BenchSettings settings;
BenchSensors  sensors;
BenchTracker  tracker;
WebServer     server(BENCH_WEB_PORT);
DNSServer     dnsServer;

bool     isCalibrating = false;
bool     autoStartSessionAfterCalib = false;
uint32_t calibStartTime = 0;
uint32_t lastSensorScanTime = 0;

// Lightweight JSON parser helpers with string sanitization
float parseJsonFloat(const String& body, const String& key, float defaultVal) {
    int idx = body.indexOf("\"" + key + "\"");
    if (idx < 0) return defaultVal;
    int colon = body.indexOf(':', idx);
    if (colon < 0) return defaultVal;
    int end = body.indexOf(',', colon);
    if (end < 0) end = body.indexOf('}', colon);
    if (end < 0) return defaultVal;
    String val = body.substring(colon + 1, end);
    val.replace("\"", ""); // strip quotes if formatted as string
    val.replace(" ", "");
    val.trim();
    return val.toFloat();
}

bool parseJsonBool(const String& body, const String& key, bool defaultVal) {
    int idx = body.indexOf("\"" + key + "\"");
    if (idx < 0) return defaultVal;
    int colon = body.indexOf(':', idx);
    if (colon < 0) return defaultVal;
    int end = body.indexOf(',', colon);
    if (end < 0) end = body.indexOf('}', colon);
    if (end < 0) return defaultVal;
    String val = body.substring(colon + 1, end);
    val.replace("\"", "");
    val.trim();
    return (val.indexOf("true") >= 0 || val == "1");
}

String parseJsonString(const String& body, const String& key) {
    int idx = body.indexOf("\"" + key + "\"");
    if (idx < 0) return "";
    int quote1 = body.indexOf('"', idx + key.length() + 2);
    if (quote1 < 0) return "";
    int quote2 = body.indexOf('"', quote1 + 1);
    if (quote2 < 0) return "";
    return body.substring(quote1 + 1, quote2);
}

void handleRoot() {
    server.sendHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    server.send_P(200, "text/html", INDEX_HTML);
}

void handleGetMetrics() {
    const BenchReading& r = tracker.getReading();
    BenchSummary summary = tracker.getLastSummary();
    uint8_t cueCode = tracker.consumeCueCode(); // One-shot trigger

    char buf[500];
    snprintf(buf, sizeof(buf),
        "{\"rate\":%.1f,\"depth\":%.2f,\"recoil_ok\":%s,\"recoil_pct\":%.1f,\"ccf\":%.1f,\"strokes\":%u,\"elapsed\":%u,\"accel\":%.2f,\"chest_ok\":%s,\"base_ok\":%s,\"is_calibrating\":%s,\"is_calibrated\":%s,\"session_active\":%s,\"cue\":%u}",
        r.rate_cpm, r.depth_cm, r.recoil_complete ? "true" : "false",
        summary.recoil_compliance_percent, r.ccf_percent, r.stroke_count, r.elapsed_seconds,
        r.current_accel,
        sensors.isChestDetected() ? "true" : "false",
        sensors.isBaseDetected() ? "true" : "false",
        isCalibrating ? "true" : "false",
        sensors.getIsCalibrated() ? "true" : "false",
        tracker.isSessionActive() ? "true" : "false",
        cueCode
    );

    // Prevent iOS Safari aggressive caching
    server.sendHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    server.sendHeader("Pragma", "no-cache");
    server.sendHeader("Expires", "0");
    server.send(200, "application/json", buf);
}

void handleGetConfig() {
    char buf[280];
    snprintf(buf, sizeof(buf),
        "{\"depthK\":%.2f,\"compressionThreshG\":%.2f,\"recoilThreshG\":%.2f,\"refractoryMs\":%u,\"calibTimeMs\":%u,\"practiceSec\":%u,\"useDualMpu\":%s}",
        settings.depthK, settings.compressionThreshG, settings.recoilThreshG,
        settings.refractoryMs, settings.calibTimeMs, settings.practiceSec,
        settings.useDualMpu ? "true" : "false"
    );
    server.sendHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    server.send(200, "application/json", buf);
}

void handlePostConfig() {
    if (server.hasArg("plain")) {
        String body = server.arg("plain");
        settings.depthK             = parseJsonFloat(body, "depthK", settings.depthK);
        settings.compressionThreshG = parseJsonFloat(body, "compressionThreshG", settings.compressionThreshG);
        settings.recoilThreshG      = parseJsonFloat(body, "recoilThreshG", settings.recoilThreshG);
        settings.refractoryMs       = (uint32_t)parseJsonFloat(body, "refractoryMs", (float)settings.refractoryMs);
        settings.useDualMpu         = parseJsonBool(body, "useDualMpu", settings.useDualMpu);

        sensors.setDualMode(settings.useDualMpu);

        // Safe Audited NVS Write with dirty-checking and rate-limiting
        String reason;
        bool ok = settings.saveToNVS(millis(), reason);

        char resp[200];
        snprintf(resp, sizeof(resp), "{\"status\":\"%s\",\"message\":\"%s\"}", ok ? "ok" : "rate_limited", reason.c_str());
        server.send(ok ? 200 : 429, "application/json", resp);
    } else {
        server.send(400, "application/json", "{\"error\":\"missing body\"}");
    }
}

void handlePostAction() {
    if (server.hasArg("plain")) {
        String body = server.arg("plain");
        String action = parseJsonString(body, "action");

        if (action == "calibrate") {
            sensors.resetCalibration();
            isCalibrating = true;
            autoStartSessionAfterCalib = false;
            calibStartTime = millis();
            playBeeps(1, 200, 100); // 1 beep: Calibration started
            server.send(200, "application/json", "{\"status\":\"calibrating\",\"message\":\"Calibration started. Hold still!\"}");
        }
        else if (action == "start_session") {
            // SAFEGUARD 1: If user starts test before calibrating, auto-calibrate first!
            if (!sensors.getIsCalibrated()) {
                Serial.println("[FLOW] Uncalibrated start prevented! Running baseline calibration first...");
                sensors.resetCalibration();
                isCalibrating = true;
                autoStartSessionAfterCalib = true; // Auto-transition into test once finished
                calibStartTime = millis();
                playBeeps(1, 200, 100);
                server.send(200, "application/json", "{\"status\":\"calibrating\",\"message\":\"Calibrating baseline first (2s)... Keep still!\"}");
                return;
            }

            tracker.startSession(millis());
            playBeeps(2, 100, 80); // 2 beeps: Test started
            server.send(200, "application/json", "{\"status\":\"session_started\",\"message\":\"Test session started! Ready for compressions.\"}");
        }
        else if (action == "stop_session") {
            tracker.finalizeSession(millis());
            playBeeps(3, 150, 100); // 3 beeps: Test ended
            server.send(200, "application/json", "{\"status\":\"session_stopped\",\"message\":\"Test session stopped.\"}");
        }
        else if (action == "reset_session") {
            tracker.reset();
            server.send(200, "application/json", "{\"status\":\"reset_done\",\"message\":\"Statistics reset.\"}");
        }
        else if (action == "set_mode") {
            bool dual = parseJsonBool(body, "dual", false);
            settings.useDualMpu = dual;
            sensors.setDualMode(dual);
            server.send(200, "application/json", "{\"status\":\"mode_updated\"}");
        }
        else if (action == "restore_defaults") {
            settings.resetToDefaults(millis());
            sensors.setDualMode(settings.useDualMpu);
            server.send(200, "application/json", "{\"status\":\"defaults_restored\"}");
        }
        else {
            server.send(400, "application/json", "{\"error\":\"unknown action\"}");
        }
    } else {
        server.send(400, "application/json", "{\"error\":\"missing body\"}");
    }
}

// ==============================================================================
// 7. ARDUINO SETUP & 100 HZ DETERMINISTIC LOOP
// ==============================================================================
void setup() {
    Serial.begin(115200);
    delay(400);
    Serial.println("\n==========================================");
    Serial.println("  CPReady Medical Test Bench & Calibrator ");
    Serial.println("==========================================");

    pinMode(BENCH_BUZZER_PIN, OUTPUT);
    digitalWrite(BENCH_BUZZER_PIN, LOW);

    // 1. Load settings safely from NVS
    settings.loadFromNVS();
    Serial.printf("[NVS] Loaded: K=%.1f | C=%.2fg | R=%.2fg | Dual=%s\n",
        settings.depthK, settings.compressionThreshG, settings.recoilThreshG,
        settings.useDualMpu ? "YES" : "NO");

    // 2. Initialize I2C Bus & MPU Sensors
    if (!sensors.begin(settings.useDualMpu)) {
        Serial.println("[WARN] Chest MPU (0x68) not detected! Check SDA=21, SCL=22.");
    } else {
        Serial.println("[OK] Primary Chest MPU (0x68) active.");
    }
    if (sensors.isBaseDetected()) {
        Serial.println("[OK] Spine Reference MPU (0x69) active.");
    } else {
        Serial.println("[INFO] Spine MPU (0x69) not connected. Running Single-MPU mode.");
    }

    // 3. Start OPEN Wi-Fi SoftAP (No password needed)
    WiFi.mode(WIFI_AP);
    IPAddress apIP(192, 168, 4, 1);
    WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
    bool apStarted = WiFi.softAP(BENCH_WIFI_SSID, nullptr, 1, 0, 4); // Open network, max 4 clients

    if (apStarted) {
        Serial.println("[WIFI] OPEN Wi-Fi Hotspot Started!");
        Serial.printf("[WIFI] Network SSID : %s (Open Network)\n", BENCH_WIFI_SSID);
        Serial.printf("[WIFI] Web Portal   : http://%s\n", WiFi.softAPIP().toString().c_str());

        // 4. Start Captive Portal DNS Server (Redirects all domain probes to ESP32 IP)
        dnsServer.start(BENCH_DNS_PORT, "*", apIP);
        Serial.println("[DNS] Captive Portal DNS Server started (Auto-popup enabled).");
    } else {
        Serial.println("[ERROR] Failed to start SoftAP!");
    }

    // 5. Register HTTP Web Server Routes & Captive Portal probes
    server.on("/", HTTP_GET, handleRoot);
    server.on("/api/metrics", HTTP_GET, handleGetMetrics);
    server.on("/api/config", HTTP_GET, handleGetConfig);
    server.on("/api/config", HTTP_POST, handlePostConfig);
    server.on("/api/action", HTTP_POST, handlePostAction);

    // Standard Captive Portal URL hooks for iOS, Android, and Windows
    server.on("/hotspot-detect.html", handleRoot); // Apple iOS
    server.on("/canonical.html", handleRoot);
    server.on("/generate_204", handleRoot);        // Android
    server.on("/gen_204", handleRoot);             // Android
    server.on("/ncsi.txt", handleRoot);            // Windows
    server.onNotFound(handleRoot);                 // Any other URL redirects to portal

    server.begin();
    Serial.println("[HTTP] Web Server running on port 80.");

    playBeeps(1, 100, 50); // Single startup chirp
}

void loop() {
    uint32_t now = millis();
    uint32_t nowMicros = micros();

    // 1. Process Captive Portal DNS queries (Triggers auto-popup on phones)
    dnsServer.processNextRequest();

    // 2. Handle incoming HTTP client requests
    server.handleClient();

    // 3. Update non-blocking buzzer pattern sequencer
    updateBuzzer(now);

    // 4. Background scan for newly connected sensors (ONLY during idle standby to prevent sampling jitter)
    if (!tracker.isSessionActive() && !isCalibrating) {
        if (now - lastSensorScanTime >= 3000) {
            lastSensorScanTime = now;
            if (!sensors.isChestDetected() || !sensors.isBaseDetected()) {
                sensors.scanSensors();
            }
        }
    }

    // 5. Baseline Calibration State Machine (2.0s hands-still measurement)
    if (isCalibrating) {
        float dummyAccel;
        if (sensors.sample100Hz(dummyAccel, nowMicros)) {
            sensors.recordCalibrationSample();
        }

        if (now - calibStartTime >= settings.calibTimeMs) {
            sensors.finalizeCalibration();
            isCalibrating = false;
            Serial.printf("[CALIB] Offsets: Chest=%.3fg | Spine=%.3fg\n",
                sensors.getChestOffset(), sensors.getBaseOffset());

            playBeeps(2, 120, 80); // 2 beeps: Ready for compressions!

            // If triggered by "Start Test", automatically begin the test session
            if (autoStartSessionAfterCalib) {
                autoStartSessionAfterCalib = false;
                tracker.startSession(now);
                Serial.println("[FLOW] Auto-started test session after successful calibration.");
            } else {
                Serial.println("[FLOW] Calibration completed. Ready for test.");
            }
        }
        return;
    }

    // 6. Active Kinematic Sampling at deterministic 100 Hz (10,000 us)
    float netAccel = 0.0f;
    if (sensors.sample100Hz(netAccel, nowMicros)) {
        bool strokeCompleted = tracker.processSample(netAccel, now, settings);

        if (strokeCompleted) {
            playBeeps(1, 20, 20); // 20 ms metronome click on stroke
            const BenchReading& r = tracker.getReading();
            Serial.printf("[STROKE] Rate: %3.0f cpm | Depth: %4.1f cm | Recoil: %s | CCF: %3.0f%%\n",
                r.rate_cpm, r.depth_cm, r.recoil_complete ? "OK" : "LEAN", r.ccf_percent);
        }

        // Auto-stop if trial practice duration limit reached
        if (tracker.isSessionActive() && settings.practiceSec > 0 && 
            tracker.getReading().elapsed_seconds >= settings.practiceSec) {
            tracker.finalizeSession(now);
            playBeeps(3, 150, 100); // 3 beeps: Practice trial finished
            Serial.println("[FLOW] Practice time limit reached.");
        }
    }
}
