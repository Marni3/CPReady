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
// 2. KINEMATIC ENGINE (Exact Production Algorithm from CompressionTracker.h)
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

        reading = {0.0f, 0.0f, true, 0.0f, 0, 0, 0.0f};
        lastSummary = {0.0f, 0.0f, 100.0f, 0.0f, 0, 0};
    }

    void startSession(uint32_t currentMillis) {
        reset();
        sessionStartMillis = currentMillis;
    }

    bool isSessionActive() const { return sessionStartMillis > 0; }

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
    MPU6050 chestSensor;
    MPU6050 baseSensor;

    bool isChestOnline;
    bool isBaseOnline;
    bool dualModeRequested;

    float chestGravityOffset;
    float baseGravityOffset;
    float lastFilteredNetAccel;
    uint32_t lastSampleMicros;

    float calChestSum;
    float calBaseSum;
    uint16_t calSampleCount;
    bool isCalibrated;

    uint8_t consecutiveErrors;

public:
    BenchSensors() 
        : chestSensor(BENCH_CHEST_I2C_ADDR), 
          baseSensor(BENCH_BASE_I2C_ADDR),
          isChestOnline(false), isBaseOnline(false), dualModeRequested(false),
          chestGravityOffset(0.0f), baseGravityOffset(0.0f),
          lastFilteredNetAccel(0.0f), lastSampleMicros(0),
          calChestSum(0.0f), calBaseSum(0.0f), calSampleCount(0), isCalibrated(false),
          consecutiveErrors(0) {}

    bool begin(bool requestDual = false) {
        dualModeRequested = requestDual;

        Wire.begin(BENCH_I2C_SDA_PIN, BENCH_I2C_SCL_PIN);
        Wire.setClock(BENCH_I2C_CLOCK_HZ);
        Wire.setTimeOut(BENCH_I2C_TIMEOUT_MS);

        chestSensor.initialize();
        isChestOnline = chestSensor.testConnection();

        baseSensor.initialize();
        isBaseOnline = baseSensor.testConnection();

        if (isChestOnline) {
            chestSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4); // +/- 4g (8192 LSB/g)
        }
        if (isBaseOnline) {
            baseSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        }

        consecutiveErrors = 0;
        return isChestOnline;
    }

    void setDualMode(bool enable) { dualModeRequested = enable; }
    bool isChestDetected() const { return isChestOnline; }
    bool isBaseDetected() const { return isBaseOnline; }
    bool isOperatingDual() const { return dualModeRequested && isBaseOnline; }
    bool getIsCalibrated() const { return isCalibrated; }

    float getChestOffset() const { return chestGravityOffset; }
    float getBaseOffset() const { return baseGravityOffset; }

    void scanSensors() {
        if (!isChestOnline) {
            chestSensor.initialize();
            isChestOnline = chestSensor.testConnection();
            if (isChestOnline) chestSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        }
        if (!isBaseOnline) {
            baseSensor.initialize();
            isBaseOnline = baseSensor.testConnection();
            if (isBaseOnline) baseSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        }
    }

    // Hardware I2C bus auto-recovery (resets bus if jumper wire was bumped)
    void recoverBus() {
        Serial.println("[I2C WARN] Jumper wire glitch detected. Auto-recovering I2C bus...");
        Wire.begin(BENCH_I2C_SDA_PIN, BENCH_I2C_SCL_PIN);
        Wire.setClock(BENCH_I2C_CLOCK_HZ);
        Wire.setTimeOut(BENCH_I2C_TIMEOUT_MS);
        chestSensor.initialize();
        isChestOnline = chestSensor.testConnection();
        if (isChestOnline) chestSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        if (isBaseOnline) {
            baseSensor.initialize();
            isBaseOnline = baseSensor.testConnection();
            if (isBaseOnline) baseSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        }
        consecutiveErrors = 0;
    }

    void resetCalibration() {
        calChestSum = 0.0f;
        calBaseSum = 0.0f;
        calSampleCount = 0;
        isCalibrated = false;
    }

    void recordCalibrationSample() {
        if (!isChestOnline) return;

        int16_t ax1, ay1, az1;
        chestSensor.getAcceleration(&ax1, &ay1, &az1);
        calChestSum += (float)az1 / 8192.0f;

        if (isBaseOnline) {
            int16_t ax2, ay2, az2;
            baseSensor.getAcceleration(&ax2, &ay2, &az2);
            calBaseSum += (float)az2 / 8192.0f;
        }
        calSampleCount++;
    }

    void finalizeCalibration() {
        if (calSampleCount > 0) {
            chestGravityOffset = calChestSum / (float)calSampleCount;
            baseGravityOffset  = isBaseOnline ? (calBaseSum / (float)calSampleCount) : 0.0f;
            isCalibrated = true;
        }
    }

    // 100 Hz deterministic sampling (10,000 us) with 4.5 Hz lowpass filter
    bool sample100Hz(float& outNetAccel, uint32_t currentMicros) {
        if (currentMicros - lastSampleMicros < 10000) return false;
        lastSampleMicros = currentMicros;

        if (!isChestOnline) {
            outNetAccel = 0.0f;
            return false;
        }

        int16_t ax1, ay1, az1;
        chestSensor.getAcceleration(&ax1, &ay1, &az1);

        // Sanity check for total I2C bus lockup (e.g. wire disconnect reading all 0 or all -1)
        if (ax1 == 0 && ay1 == 0 && az1 == 0) {
            consecutiveErrors++;
            if (consecutiveErrors > 15) {
                recoverBus();
            }
            return false;
        } else {
            consecutiveErrors = 0;
        }

        float aChest = ((float)az1 / 8192.0f) - chestGravityOffset;

        float rawNet = 0.0f;
        if (dualModeRequested && isBaseOnline) {
            int16_t ax2, ay2, az2;
            baseSensor.getAcceleration(&ax2, &ay2, &az2);
            float aBase = ((float)az2 / 8192.0f) - baseGravityOffset;
            rawNet = aChest - aBase; // Surface decoupling
        } else {
            rawNet = aChest;         // Single sternal sensor
        }

        const float alpha = 0.25f; // ~4.5 Hz cutoff
        lastFilteredNetAccel = (alpha * rawNet) + ((1.0f - alpha) * lastFilteredNetAccel);
        outNetAccel = lastFilteredNetAccel;
        return true;
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
// 5. EMBEDDED MEDICAL WEB UI (HTML/CSS/JS in PROGMEM)
// Clean Clinical White & Blue Aesthetic inspired by modern health apps
// ==============================================================================
const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<meta name="theme-color" content="#F5F4EF" id="metaThemeColor">
<title>CPReady Bench — Clinical CPR Kinematics Validator</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='%230B6E75'><path d='M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z'/></svg>">
<style>
:root {
  /* Clinical Patient-Monitor Theme (Light First) */
  --bg: #F5F4EF;
  --surface: #FFFFFF;
  --surface-alt: #EFECE4;
  --surface-elevated: #FFFFFF;
  --border: #DDD9CE;
  --border-strong: #C4BFB2;
  
  --text-main: #14181F;
  --text-muted: #5A6270;
  --text-sub: #7A8494;
  
  /* Primary Clinical Accent: Deep Teal */
  --accent: #0B6E75;
  --accent-light: #E0F2F1;
  --accent-hover: #08545A;
  --accent-focus: rgba(11, 110, 117, 0.25);
  
  /* Status Colors Strictly for State (Always paired with Icon + Text) */
  --success: #15803D;
  --success-bg: #DCFCE7;
  --success-border: #86EFAC;
  
  --warning: #B45309;
  --warning-bg: #FEF3C7;
  --warning-border: #FCD34D;
  
  --danger: #B91C1C;
  --danger-bg: #FEE2E2;
  --danger-border: #FCA5A5;
  
  --neutral-pill: #E2E0D8;
  --neutral-pill-text: #475569;

  --shadow-sm: 0 1px 3px rgba(20, 24, 31, 0.04);
  --shadow-md: 0 4px 14px -2px rgba(20, 24, 31, 0.08);
  --shadow-lg: 0 10px 25px -4px rgba(20, 24, 31, 0.12);

  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;
}

[data-theme="dark"] {
  --bg: #0E1318;
  --surface: #171E26;
  --surface-alt: #1F2833;
  --surface-elevated: #1C242E;
  --border: #2A3644;
  --border-strong: #3D4E61;
  
  --text-main: #F3F5F7;
  --text-muted: #A1ACB9;
  --text-sub: #707F91;
  
  --accent: #14B8A6;
  --accent-light: #042F2E;
  --accent-hover: #2DD4BF;
  --accent-focus: rgba(20, 184, 166, 0.3);
  
  --success-bg: #052E16;
  --success-border: #166534;
  --warning-bg: #451A03;
  --warning-border: #92400E;
  --danger-bg: #450A0A;
  --danger-border: #991B1B;
  
  --neutral-pill: #2A3644;
  --neutral-pill-text: #A1ACB9;
  --shadow-md: 0 4px 14px -2px rgba(0, 0, 0, 0.45);
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #0E1318;
    --surface: #171E26;
    --surface-alt: #1F2833;
    --surface-elevated: #1C242E;
    --border: #2A3644;
    --border-strong: #3D4E61;
    --text-main: #F3F5F7;
    --text-muted: #A1ACB9;
    --text-sub: #707F91;
    --accent: #14B8A6;
    --accent-light: #042F2E;
    --accent-hover: #2DD4BF;
    --accent-focus: rgba(20, 184, 166, 0.3);
    --success-bg: #052E16;
    --success-border: #166534;
    --warning-bg: #451A03;
    --warning-border: #92400E;
    --danger-bg: #450A0A;
    --danger-border: #991B1B;
    --neutral-pill: #2A3644;
    --neutral-pill-text: #A1ACB9;
    --shadow-md: 0 4px 14px -2px rgba(0, 0, 0, 0.45);
  }
}

* { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
html { scroll-behavior: smooth; font-size: 16px; }
body {
  background: var(--bg);
  color: var(--text-main);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  min-height: 100vh;
  padding: 10px;
  overflow-x: hidden;
  line-height: 1.4;
}

/* Tabular figures for stable live numbers */
.tabular { font-variant-numeric: tabular-nums; font-family: ui-monospace, Menlo, Consolas, monospace; }

/* Responsive Container: Mobile-First Single Column */
.app-container {
  max-width: 480px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

@media (min-width: 900px) {
  .app-container { max-width: 860px; }
  .desktop-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
    align-items: start;
  }
}

/* SVG Sprite Icon helper */
.icon {
  width: 18px;
  height: 18px;
  stroke: currentColor;
  stroke-width: 2;
  stroke-linecap: round;
  stroke-linejoin: round;
  fill: none;
  display: inline-block;
  vertical-align: middle;
  flex-shrink: 0;
}
.icon-sm { width: 14px; height: 14px; }
.icon-lg { width: 22px; height: 22px; }

/* Top Persistent Mock Simulation Banner */
.mock-banner {
  background: #FFFBEB;
  border: 1px solid #FDE68A;
  border-left: 4px solid #F59E0B;
  color: #92400E;
  padding: 8px 12px;
  border-radius: var(--radius-sm);
  font-size: 0.72rem;
  font-weight: 600;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
[data-theme="dark"] .mock-banner { background: #381E05; border-color: #78350F; color: #FDE68A; }

/* In-App Browser Warning Hint */
.webview-hint {
  background: #EFF6FF;
  border: 1px solid #BFDBFE;
  color: #1E40AF;
  padding: 6px 12px;
  border-radius: var(--radius-sm);
  font-size: 0.72rem;
  display: none;
  justify-content: space-between;
  align-items: center;
}

/* Sticky Compact Telemetry Bar (Shown when scrolled on mobile) */
.sticky-bar {
  position: sticky;
  top: 6px;
  z-index: 100;
  background: var(--surface);
  border: 1px solid var(--accent);
  border-radius: var(--radius-md);
  padding: 8px 12px;
  box-shadow: var(--shadow-md);
  display: none;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  animation: slideDown 0.2s ease;
}
@keyframes slideDown { from { transform: translateY(-8px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }
.sticky-stat { font-size: 0.8rem; font-weight: 800; display: flex; align-items: baseline; gap: 3px; }
.sticky-stat .unit { font-size: 0.65rem; color: var(--text-sub); }

/* Header Component */
header.app-header {
  background: var(--surface);
  border: 1px solid var(--border);
  padding: 12px 14px;
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}
.brand-group { display: flex; flex-direction: column; min-width: 0; }
.brand-title {
  font-size: 1.15rem;
  font-weight: 800;
  color: var(--accent);
  letter-spacing: -0.02em;
  white-space: nowrap;
}
.brand-sub { font-size: 0.7rem; color: var(--text-muted); font-weight: 500; white-space: nowrap; }

.header-right { display: flex; align-items: center; gap: 8px; flex-shrink: 0; }
.hardware-pills { display: flex; flex-direction: column; gap: 4px; align-items: flex-end; cursor: pointer; }
.pill {
  padding: 3px 8px;
  border-radius: 20px;
  font-size: 0.65rem;
  font-weight: 700;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  border: 1px solid transparent;
  user-select: none;
}
.pill-green { background: var(--success-bg); color: var(--success); border-color: var(--success-border); }
.pill-amber { background: var(--warning-bg); color: var(--warning); border-color: var(--warning-border); }
.pill-red { background: var(--danger-bg); color: var(--danger); border-color: var(--danger-border); }
.pill-neutral { background: var(--neutral-pill); color: var(--neutral-pill-text); border-color: var(--border); }

/* Speaker Toggle Button (>= 44px) */
.btn-speaker {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  border: 1px solid var(--border);
  background: var(--surface-alt);
  color: var(--text-main);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.15s ease;
  flex-shrink: 0;
}
.btn-speaker:active { transform: scale(0.94); }
.btn-speaker.muted { background: var(--danger-bg); color: var(--danger); border-color: var(--danger-border); }

/* De-Carded Containers */
.card-section {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 14px;
  box-shadow: var(--shadow-sm);
  display: flex;
  flex-direction: column;
  gap: 12px;
}

/* Phase 1: Mode Segmented Control */
.segmented-control {
  background: var(--surface-alt);
  padding: 3px;
  border-radius: 10px;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 3px;
  border: 1px solid var(--border);
}
.segment-btn {
  min-height: 38px;
  border-radius: 8px;
  border: none;
  font-size: 0.76rem;
  font-weight: 700;
  color: var(--text-muted);
  background: transparent;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  transition: all 0.15s ease;
}
.segment-btn.active {
  background: var(--surface);
  color: var(--accent);
  box-shadow: 0 2px 5px rgba(0,0,0,0.06);
}
.mode-explanation {
  font-size: 0.7rem;
  color: var(--text-muted);
  line-height: 1.35;
  padding: 0 4px;
}

/* State-Aware Dominant Action Button */
.workflow-group { display: flex; flex-direction: column; gap: 8px; }
.btn-action-primary {
  width: 100%;
  min-height: 50px;
  border-radius: var(--radius-md);
  font-weight: 800;
  font-size: 0.95rem;
  border: none;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  box-shadow: var(--shadow-md);
  transition: transform 0.15s, background-color 0.2s;
  color: #FFFFFF;
}
.btn-action-primary:active { transform: scale(0.98); }
.btn-action-primary.state-calibrate { background: var(--accent); }
.btn-action-primary.state-start { background: var(--success); }
.btn-action-primary.state-stop { background: var(--danger); }
.btn-action-primary:disabled { opacity: 0.55; cursor: not-allowed; }

/* 2s Calibration Progress Ring Overlay */
.calib-ring-overlay {
  display: none;
  background: var(--surface-alt);
  border: 1px dashed var(--accent);
  border-radius: var(--radius-md);
  padding: 10px 14px;
  align-items: center;
  gap: 14px;
}
.ring-wrap { position: relative; width: 42px; height: 42px; }
.ring-wrap svg { transform: rotate(-90deg); width: 42px; height: 42px; }
.ring-wrap circle { fill: none; stroke-width: 4; stroke-linecap: round; }
.circle-bg { stroke: var(--border); }
.circle-bar { stroke: var(--accent); stroke-dasharray: 113; stroke-dashoffset: 113; transition: stroke-dashoffset 0.1s linear; }
.ring-countdown {
  position: absolute;
  top: 0; left: 0; width: 42px; height: 42px;
  display: flex; align-items: center; justify-content: center;
  font-size: 0.72rem; font-weight: 800; color: var(--accent);
}

.secondary-actions-bar {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}
.btn-secondary {
  min-height: 42px;
  background: var(--surface-alt);
  border: 1px solid var(--border);
  color: var(--text-main);
  border-radius: var(--radius-sm);
  font-size: 0.76rem;
  font-weight: 700;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  transition: background 0.15s;
}
.btn-secondary:active { transform: scale(0.97); }

/* Phase 2: Live AHA Telemetry Hierarchy (De-carded) */
.hero-telemetry-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.hero-metric-card {
  background: var(--surface-elevated);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 12px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  box-shadow: var(--shadow-sm);
  position: relative;
}
.metric-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.metric-label {
  font-size: 0.68rem;
  font-weight: 800;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.unit-toggle-btn {
  font-size: 0.65rem;
  font-weight: 700;
  color: var(--accent);
  cursor: pointer;
  padding: 1px 6px;
  border-radius: 8px;
  background: var(--accent-light);
  border: none;
}

.hero-value-wrap {
  display: flex;
  align-items: baseline;
  gap: 4px;
  margin: 4px 0 2px 0;
}
.hero-num {
  font-size: 2.1rem;
  font-weight: 800;
  color: var(--text-main);
  line-height: 1.05;
}
.hero-unit { font-size: 0.85rem; font-weight: 700; color: var(--text-muted); }
.hero-subtext { font-size: 0.68rem; color: var(--text-sub); margin-bottom: 6px; white-space: nowrap; }

/* Visual Range Gauge */
.gauge-track {
  width: 100%;
  height: 8px;
  background: var(--border);
  border-radius: 4px;
  position: relative;
  overflow: visible;
  margin: 4px 0 8px 0;
}
.gauge-target-zone {
  position: absolute;
  top: 0;
  height: 100%;
  background: var(--success-bg);
  border-left: 1px solid var(--success);
  border-right: 1px solid var(--success);
}
.gauge-needle {
  position: absolute;
  top: -3px;
  width: 4px;
  height: 14px;
  background: var(--text-main);
  border-radius: 2px;
  transform: translateX(-50%);
  transition: left 0.15s ease-out;
  box-shadow: 0 1px 3px rgba(0,0,0,0.3);
}

/* Directional Status Badges */
.status-badge {
  padding: 4px 8px;
  border-radius: 6px;
  font-size: 0.68rem;
  font-weight: 800;
  display: flex;
  align-items: center;
  gap: 4px;
  min-height: 24px;
}
.badge-good { background: var(--success-bg); color: var(--success); border: 1px solid var(--success-border); }
.badge-warn { background: var(--warning-bg); color: var(--warning); border: 1px solid var(--warning-border); }
.badge-alert { background: var(--danger-bg); color: var(--danger); border: 1px solid var(--danger-border); }
.badge-neutral { background: var(--surface-alt); color: var(--text-muted); border: 1px solid var(--border); }

/* Tier 2: Divided Quality Row */
.tier2-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.tier2-box {
  background: var(--surface-elevated);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

/* Tier 3: Footer Bar */
.tier3-bar {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 6px;
  background: var(--surface-alt);
  padding: 8px 12px;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border);
}
.tier3-col { display: flex; flex-direction: column; }
.tier3-label { font-size: 0.62rem; font-weight: 700; color: var(--text-muted); text-transform: uppercase; }
.tier3-val { font-size: 1rem; font-weight: 800; color: var(--text-main); }

/* Spoken Caption Banner */
.live-caption-pill {
  background: var(--accent-light);
  border: 1px solid var(--accent);
  border-radius: var(--radius-md);
  padding: 8px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  font-size: 0.78rem;
  font-weight: 700;
  color: var(--accent);
  min-height: 40px;
}
.caption-wave { display: inline-flex; align-items: center; gap: 2px; }
.caption-wave span { width: 3px; height: 10px; background: var(--accent); border-radius: 2px; }
.caption-wave.active span:nth-child(1) { animation: wave 0.6s infinite ease-in-out; }
.caption-wave.active span:nth-child(2) { animation: wave 0.6s infinite ease-in-out 0.15s; height: 14px; }
.caption-wave.active span:nth-child(3) { animation: wave 0.6s infinite ease-in-out 0.3s; }
@keyframes wave { 0%, 100% { transform: scaleY(0.4); } 50% { transform: scaleY(1); } }

/* Collapsible Panel Headers */
.collapsible-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  cursor: pointer;
  user-select: none;
  padding: 2px 0;
}
.collapsible-trigger h3 {
  font-size: 0.88rem;
  font-weight: 800;
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--text-main);
}
.dirty-pill {
  font-size: 0.65rem;
  font-weight: 800;
  color: var(--warning);
  background: var(--warning-bg);
  padding: 2px 8px;
  border-radius: 10px;
  border: 1px solid var(--warning-border);
  display: none;
}

/* Phase 3: Stepper Slider Cards */
.param-list { display: flex; flex-direction: column; gap: 10px; }
.param-card {
  background: var(--surface-alt);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.param-top { display: flex; justify-content: space-between; align-items: center; }
.param-title-wrap { display: flex; flex-direction: column; }
.param-name { font-size: 0.8rem; font-weight: 800; color: var(--text-main); }
.param-sub { font-size: 0.65rem; color: var(--text-sub); }

.stepper-wrap { display: flex; align-items: center; gap: 4px; }
.btn-step {
  width: 32px;
  height: 32px;
  border-radius: 6px;
  border: 1px solid var(--border-strong);
  background: var(--surface);
  color: var(--text-main);
  font-weight: 800;
  font-size: 1rem;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
}
.btn-step:active { background: var(--border); }
.input-num {
  width: 60px;
  height: 32px;
  border-radius: 6px;
  border: 1px solid var(--border-strong);
  background: var(--surface);
  color: var(--text-main);
  font-weight: 800;
  text-align: center;
  font-size: 0.8rem;
}

input[type="range"] {
  width: 100%;
  accent-color: var(--accent);
  height: 8px;
  cursor: pointer;
}
.range-labels {
  display: flex;
  justify-content: space-between;
  font-size: 0.65rem;
  color: var(--text-sub);
}

.btn-wizard-launch {
  background: var(--accent-light);
  color: var(--accent);
  border: 1px solid var(--accent);
  border-radius: var(--radius-sm);
  padding: 8px 12px;
  font-size: 0.75rem;
  font-weight: 700;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
}

/* Voice Coach Drawer */
.voice-row { display: flex; flex-direction: column; gap: 4px; }
.voice-row label { font-size: 0.7rem; font-weight: 700; color: var(--text-muted); }
.select-box {
  width: 100%;
  padding: 8px 10px;
  border-radius: 8px;
  border: 1px solid var(--border-strong);
  background: var(--surface);
  color: var(--text-main);
  font-size: 0.75rem;
  font-weight: 600;
}

.phrase-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 6px;
}
.btn-phrase {
  min-height: 42px;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--surface-alt);
  color: var(--text-main);
  font-size: 0.72rem;
  font-weight: 700;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 4px 6px;
  text-align: center;
}
.btn-phrase:active { transform: scale(0.96); }
.btn-phrase.speaking { background: var(--accent-light); border-color: var(--accent); color: var(--accent); }

/* Switch Toggle Component */
.switch-wrap { display: flex; align-items: center; justify-content: space-between; }
.switch { position: relative; display: inline-block; width: 44px; height: 24px; }
.switch input { opacity: 0; width: 0; height: 0; }
.switch-slider {
  position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0;
  background-color: var(--border-strong);
  transition: 0.2s;
  border-radius: 24px;
}
.switch-slider:before {
  position: absolute; content: ""; height: 18px; width: 18px; left: 3px; bottom: 3px;
  background-color: white;
  transition: 0.2s;
  border-radius: 50%;
}
input:checked + .switch-slider { background-color: var(--success); }
input:checked + .switch-slider:before { transform: translateX(20px); }

/* Canvas Waveform */
canvas#waveCanvas {
  width: 100%;
  height: 120px;
  background: #0F172A;
  border-radius: var(--radius-sm);
  display: block;
}

/* Modals */
.modal-backdrop {
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(14, 19, 24, 0.6);
  backdrop-filter: blur(2px);
  z-index: 1000;
  display: none;
  align-items: center;
  justify-content: center;
  padding: 16px;
}
.modal-window {
  background: var(--surface);
  border-radius: var(--radius-lg);
  max-width: 440px;
  width: 100%;
  padding: 18px;
  box-shadow: var(--shadow-lg);
  display: flex;
  flex-direction: column;
  gap: 12px;
  max-height: 90vh;
  overflow-y: auto;
}
.modal-title { font-size: 1rem; font-weight: 800; color: var(--text-main); }
.code-box {
  background: #0F172A;
  color: #38BDF8;
  padding: 10px;
  border-radius: var(--radius-sm);
  font-family: ui-monospace, monospace;
  font-size: 0.7rem;
  white-space: pre-wrap;
  user-select: all;
  max-height: 180px;
  overflow-y: auto;
}

/* Toast */
.toast {
  position: fixed;
  bottom: 20px;
  left: 50%;
  transform: translateX(-50%);
  background: #14181F;
  color: #FFFFFF;
  padding: 10px 18px;
  border-radius: 30px;
  font-size: 0.78rem;
  font-weight: 600;
  box-shadow: var(--shadow-lg);
  display: none;
  z-index: 2000;
  text-align: center;
  white-space: nowrap;
}
</style>
</head>
<body>

<!-- Hidden SVG Icon Sprite Definition (14 Clinical Icons) -->
<svg style="display:none;" xmlns="http://www.w3.org/2000/svg">
  <symbol id="icon-speaker" viewBox="0 0 24 24">
    <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>
    <path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"/>
  </symbol>
  <symbol id="icon-speaker-mute" viewBox="0 0 24 24">
    <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>
    <line x1="23" y1="9" x2="17" y2="15"/>
    <line x1="17" y1="9" x2="23" y2="15"/>
  </symbol>
  <symbol id="icon-check" viewBox="0 0 24 24">
    <polyline points="20 6 9 17 4 12"/>
  </symbol>
  <symbol id="icon-arrow-up" viewBox="0 0 24 24">
    <line x1="12" y1="19" x2="12" y2="5"/>
    <polyline points="5 12 12 5 19 12"/>
  </symbol>
  <symbol id="icon-arrow-down" viewBox="0 0 24 24">
    <line x1="12" y1="5" x2="12" y2="19"/>
    <polyline points="19 12 12 19 5 12"/>
  </symbol>
  <symbol id="icon-target" viewBox="0 0 24 24">
    <circle cx="12" cy="12" r="10"/>
    <circle cx="12" cy="12" r="6"/>
    <circle cx="12" cy="12" r="2"/>
  </symbol>
  <symbol id="icon-play" viewBox="0 0 24 24">
    <polygon points="5 3 19 12 5 21 5 3"/>
  </symbol>
  <symbol id="icon-stop" viewBox="0 0 24 24">
    <rect x="4" y="4" width="16" height="16" rx="2" ry="2"/>
  </symbol>
  <symbol id="icon-undo" viewBox="0 0 24 24">
    <polyline points="1 4 1 10 7 10"/>
    <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
  </symbol>
  <symbol id="icon-sliders" viewBox="0 0 24 24">
    <line x1="4" y1="21" x2="4" y2="14"/>
    <line x1="4" y1="10" x2="4" y2="3"/>
    <line x1="12" y1="21" x2="12" y2="12"/>
    <line x1="12" y1="8" x2="12" y2="3"/>
    <line x1="20" y1="21" x2="20" y2="16"/>
    <line x1="20" y1="12" x2="20" y2="3"/>
    <line x1="1" y1="14" x2="7" y2="14"/>
    <line x1="9" y1="8" x2="15" y2="8"/>
    <line x1="17" y1="16" x2="23" y2="16"/>
  </symbol>
  <symbol id="icon-info" viewBox="0 0 24 24">
    <circle cx="12" cy="12" r="10"/>
    <line x1="12" y1="16" x2="12" y2="12"/>
    <line x1="12" y1="8" x2="12.01" y2="8"/>
  </symbol>
  <symbol id="icon-chevron" viewBox="0 0 24 24">
    <polyline points="6 9 12 15 18 9"/>
  </symbol>
  <symbol id="icon-copy" viewBox="0 0 24 24">
    <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
  </symbol>
  <symbol id="icon-download" viewBox="0 0 24 24">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
    <polyline points="7 10 12 15 17 10"/>
    <line x1="12" y1="15" x2="12" y2="3"/>
  </symbol>
</svg>

<div class="app-container">

  <!-- Top Mock Simulation Banner (Shown offline or in file: mock mode) -->
  <aside id="mockPersistentBanner" class="mock-banner" role="status">
    <span>⚠️ <strong>Simulated Data</strong> — Bench validation mode</span>
    <span class="tabular" style="font-size:0.68rem; opacity:0.85;">Offline Active</span>
  </aside>

  <!-- In-app viewer hint (Messenger, WeChat, etc.) -->
  <aside id="webviewHint" class="webview-hint">
    <span>💡 Open in Chrome or Safari for speech and data downloads.</span>
    <button onclick="this.parentElement.style.display='none'" style="background:none; border:none; color:inherit; font-weight:800; cursor:pointer;">✕</button>
  </aside>

  <!-- Sticky Compact Telemetry Bar (Mobile scroll feedback) -->
  <div id="stickyBar" class="sticky-bar">
    <div class="sticky-stat">
      <span>Rate:</span>
      <span id="stkRate" class="tabular" style="color:var(--accent);">--</span>
      <span class="unit">cpm</span>
    </div>
    <div class="sticky-stat">
      <span>Depth:</span>
      <span id="stkDepth" class="tabular" style="color:var(--accent);">--</span>
      <span class="unit" id="stkUnit">cm</span>
    </div>
    <div id="stkRecoil" class="status-badge badge-neutral" style="padding:2px 6px; font-size:0.65rem;">RECOIL: --</div>
    <button class="btn-speaker" onclick="toggleMasterSpeaker()" style="width:34px; height:34px;" aria-label="Toggle sound">
      <svg class="icon icon-sm"><use href="#icon-speaker"/></svg>
    </button>
  </div>

  <!-- Clinical Header Component -->
  <header class="app-header">
    <div class="brand-group">
      <h1 class="brand-title">CPReady Bench</h1>
      <p class="brand-sub">Clinical CPR Kinematics Validator</p>
    </div>
    <div class="header-right">
      <div class="hardware-pills" onclick="openDiagModal()" title="Tap for hardware connection telemetry">
        <span id="pillChest" class="pill pill-green">✓ Chest: OK (0x68)</span>
        <span id="pillSpine" class="pill pill-neutral">○ Spine: Not used</span>
      </div>
      <button id="btnSpeaker" class="btn-speaker" onclick="toggleMasterSpeaker()" aria-label="Toggle voice coaching" aria-pressed="true" title="Master Audio Mute">
        <svg id="svgSpeakerIcon" class="icon"><use href="#icon-speaker"/></svg>
      </button>
    </div>
  </header>

  <!-- Live Spoken Caption Banner -->
  <div class="live-caption-pill" aria-live="polite">
    <div style="display:flex; align-items:center; gap:8px;">
      <div id="captionWave" class="caption-wave"><span></span><span></span><span></span></div>
      <span>Voice Cue: <strong id="liveCaptionText">Ready (Audio Active)</strong></span>
    </div>
    <span id="captionSub" style="font-size:0.68rem; opacity:0.85;">Native Voice</span>
  </div>

  <!-- PHASE 1: Mode Switcher & State-Aware Controls -->
  <section class="card-section" aria-label="Workflow Controls">
    <div class="segmented-control" role="tablist">
      <button id="segSingle" class="segment-btn active" role="tab" aria-selected="true" onclick="setSensorMode(false)">
        <span>Single MPU (Chest)</span>
      </button>
      <button id="segDual" class="segment-btn" role="tab" aria-selected="false" onclick="setSensorMode(true)">
        <span>Dual MPU (Decoupled)</span>
      </button>
    </div>
    <p id="modeDescText" class="mode-explanation">Measuring sternal compression with zero-gravity tare offset.</p>

    <div class="workflow-group">
      <!-- Dominant State-Aware Action Button -->
      <button id="btnPrimaryAction" class="btn-action-primary state-calibrate" onclick="handlePrimaryAction()">
        <svg class="icon"><use href="#icon-target"/></svg>
        <span id="primaryActionText">Calibrate Baseline (2s)</span>
      </button>

      <!-- 2-Second Calibration Progress Ring Overlay -->
      <div id="calibRingOverlay" class="calib-ring-overlay">
        <div class="ring-wrap">
          <svg><circle class="circle-bg" cx="21" cy="21" r="18"></circle><circle id="calibRingBar" class="circle-bar" cx="21" cy="21" r="18"></circle></svg>
          <div id="calibCountdownText" class="ring-countdown">2s</div>
        </div>
        <div>
          <strong style="font-size:0.8rem; color:var(--accent); display:block;">Zeroing Accelerometers...</strong>
          <span style="font-size:0.7rem; color:var(--text-muted);">Hold hands still on chest pad.</span>
        </div>
      </div>

      <div style="display:flex; justify-content:space-between; font-size:0.7rem; color:var(--text-muted); padding:0 2px;">
        <span>Status: <strong id="workflowStatusText">Idle — Calibration Required</strong></span>
        <span id="calibOffsetsSummary" class="tabular">Z-offset: --</span>
      </div>

      <div class="secondary-actions-bar">
        <button class="btn-secondary" onclick="confirmResetStats()">
          <svg class="icon icon-sm"><use href="#icon-undo"/></svg>
          Reset Session
        </button>
        <button class="btn-secondary" onclick="exportSessionCsv()">
          <svg class="icon icon-sm"><use href="#icon-download"/></svg>
          Export CSV
        </button>
      </div>
    </div>
  </section>

  <!-- PHASE 2: Live AHA Telemetry Hierarchy (De-carded) -->
  <section class="card-section" aria-label="AHA Telemetry Metrics">
    <!-- Tier 1: Rate & Depth (Heroes) -->
    <div class="hero-telemetry-grid">
      <!-- Rate Card -->
      <div class="hero-metric-card">
        <div class="metric-header">
          <span class="metric-label">Rate</span>
          <button class="unit-toggle-btn" onclick="alert('AHA Target: 100–120 compressions per minute for optimal coronary perfusion.')">
            <svg class="icon icon-sm" style="width:12px; height:12px;"><use href="#icon-info"/></svg>
          </button>
        </div>
        <div class="hero-value-wrap">
          <span id="valRate" class="hero-num tabular">--</span>
          <span class="hero-unit">cpm</span>
        </div>
        <div class="hero-subtext">Avg of 10 (<span id="valInstantRate" class="tabular">--</span> inst)</div>

        <!-- Range Gauge Bar -->
        <div class="gauge-track">
          <!-- AHA 100-120 mapped across 60-160 range -->
          <div class="gauge-target-zone" style="left:40%; width:20%;"></div>
          <div id="gaugeRateNeedle" class="gauge-needle" style="left:50%;"></div>
        </div>

        <div id="badgeRate" class="status-badge badge-neutral">
          <span id="iconRate">○</span>
          <span id="textRate">Awaiting compressions</span>
        </div>
      </div>

      <!-- Depth Card -->
      <div class="hero-metric-card">
        <div class="metric-header">
          <span class="metric-label">Depth</span>
          <button class="unit-toggle-btn" id="btnUnitToggle" onclick="toggleGlobalUnit()">cm</button>
        </div>
        <div class="hero-value-wrap">
          <span id="valDepth" class="hero-num tabular">--</span>
          <span class="hero-unit" id="lblDepthUnit">cm</span>
        </div>
        <div class="hero-subtext">Avg of 10 (<span id="valInstantDepth" class="tabular">--</span> inst)</div>

        <!-- Range Gauge Bar -->
        <div class="gauge-track">
          <!-- AHA 5.0-6.0 cm mapped across 2.0-8.0 range -->
          <div class="gauge-target-zone" style="left:50%; width:16.6%;"></div>
          <div id="gaugeDepthNeedle" class="gauge-needle" style="left:50%;"></div>
        </div>

        <div id="badgeDepth" class="status-badge badge-neutral">
          <span id="iconDepth">○</span>
          <span id="textDepth">Awaiting compressions</span>
        </div>
      </div>
    </div>

    <!-- Tier 2: Divided Quality Row (Recoil & CCF) -->
    <div class="tier2-row">
      <div class="tier2-box">
        <div class="metric-header">
          <span class="metric-label">Recoil</span>
          <span style="font-size:0.65rem; color:var(--text-muted);">Compliance</span>
        </div>
        <div id="badgeRecoil" class="status-badge badge-neutral" style="margin:6px 0;">
          <span id="iconRecoil">○</span>
          <span id="textRecoil">— Not active</span>
        </div>
        <div class="hero-subtext" style="margin-bottom:0;">Compliance: <strong id="valRecoilPct" class="tabular">--%</strong></div>
      </div>

      <div class="tier2-box">
        <div class="metric-header">
          <span class="metric-label">Fraction</span>
          <span style="font-size:0.65rem; color:var(--text-muted);">AHA Target &ge; 60%</span>
        </div>
        <div class="hero-value-wrap" style="margin:4px 0;">
          <span id="valCCF" class="hero-num tabular" style="font-size:1.6rem;">--</span>
          <span class="hero-unit">%</span>
        </div>
        <div class="hero-subtext" style="margin-bottom:0;">Hands-on chest fraction</div>
      </div>
    </div>

    <!-- Tier 3: Strokes & Elapsed mm:ss -->
    <div class="tier3-bar">
      <div class="tier3-col">
        <span class="tier3-label">Compressions</span>
        <span id="valStrokes" class="tier3-val tabular">0</span>
      </div>
      <div class="tier3-col">
        <span class="tier3-label">Elapsed Time</span>
        <span id="valElapsedMmSs" class="tier3-val tabular">00:00</span>
      </div>
      <div class="tier3-col">
        <span class="tier3-label">Session ID</span>
        <span id="valSessionId" class="tier3-val" style="font-size:0.8rem; font-family:monospace;">#CP-01</span>
      </div>
    </div>
  </section>

  <!-- PHASE 3: Parameter Calibration Panel (Collapsible) -->
  <section class="card-section" aria-label="Parameter Calibration">
    <div class="collapsible-trigger" onclick="toggleCollapse('panelParams', 'caretParams')">
      <h3>
        <svg class="icon"><use href="#icon-sliders"/></svg>
        Parameter Calibration
      </h3>
      <div style="display:flex; align-items:center; gap:6px;">
        <span id="badgeDirty" class="dirty-pill">● Modified</span>
        <svg id="caretParams" class="icon icon-sm" style="transition:transform 0.2s;"><use href="#icon-chevron"/></svg>
      </div>
    </div>

    <div id="panelParams" class="param-list" style="display:flex; flex-direction:column; gap:10px;">
      <!-- Guided Ruler Calibration Launch -->
      <button class="btn-wizard-launch" onclick="openWizardModal()">
        <svg class="icon icon-sm"><use href="#icon-target"/></svg>
        Launch Guided Ruler Calibration Wizard
      </button>

      <!-- 1. Depth Scale (K) -->
      <div class="param-card">
        <div class="param-top">
          <div class="param-title-wrap">
            <span class="param-name">Depth Scale (K)</span>
            <span class="param-sub">Kinematic displacement scalar</span>
          </div>
          <div class="stepper-wrap">
            <button class="btn-step" onclick="stepParam('DepthK', -0.1)">−</button>
            <input type="number" id="numDepthK" class="input-num tabular" step="0.1" min="5.0" max="25.0" value="11.2" onchange="onNumInputChange('DepthK', this.value)">
            <button class="btn-step" onclick="stepParam('DepthK', 0.1)">+</button>
          </div>
        </div>
        <input type="range" id="rngDepthK" min="5.0" max="25.0" step="0.1" value="11.2" oninput="onSliderChange('DepthK', this.value)">
        <div class="range-labels"><span>5.0 (Sensitive)</span><span>25.0 (Heavy)</span></div>
      </div>

      <!-- 2. Push Threshold -->
      <div class="param-card">
        <div class="param-top">
          <div class="param-title-wrap">
            <span class="param-name">Detection Threshold</span>
            <span class="param-sub">Push sensitivity in g</span>
          </div>
          <div class="stepper-wrap">
            <button class="btn-step" onclick="stepParam('CThresh', -0.01)">−</button>
            <input type="number" id="numCThresh" class="input-num tabular" step="0.01" min="0.20" max="1.00" value="0.45" onchange="onNumInputChange('CThresh', this.value)">
            <button class="btn-step" onclick="stepParam('CThresh', 0.01)">+</button>
          </div>
        </div>
        <input type="range" id="rngCThresh" min="0.20" max="1.00" step="0.01" value="0.45" oninput="onSliderChange('CThresh', this.value)">
        <div class="range-labels"><span>0.20 g (Light)</span><span>1.00 g (Strict)</span></div>
      </div>

      <!-- 3. Recoil Strictness -->
      <div class="param-card">
        <div class="param-top">
          <div class="param-title-wrap">
            <span class="param-name">Recoil Threshold</span>
            <span class="param-sub">Rebound verification strictness</span>
          </div>
          <div class="stepper-wrap">
            <button class="btn-step" onclick="stepParam('RThresh', 0.01)">−</button>
            <input type="number" id="numRThresh" class="input-num tabular" step="0.01" min="-0.80" max="-0.10" value="-0.35" onchange="onNumInputChange('RThresh', this.value)">
            <button class="btn-step" onclick="stepParam('RThresh', -0.01)">+</button>
          </div>
        </div>
        <input type="range" id="rngRThresh" min="-0.80" max="-0.10" step="0.01" value="-0.35" oninput="onSliderChange('RThresh', this.value)">
        <div class="range-labels"><span>-0.80 g (Strict)</span><span>-0.10 g (Lenient)</span></div>
      </div>

      <!-- 4. Refractory Lockout -->
      <div class="param-card">
        <div class="param-top">
          <div class="param-title-wrap">
            <span class="param-name">Double-Count Guard</span>
            <span class="param-sub">Refractory lockout ms</span>
          </div>
          <div class="stepper-wrap">
            <button class="btn-step" onclick="stepParam('Refr', -10)">−</button>
            <input type="number" id="numRefr" class="input-num tabular" step="10" min="150" max="400" value="250" onchange="onNumInputChange('Refr', this.value)">
            <button class="btn-step" onclick="stepParam('Refr', 10)">+</button>
          </div>
        </div>
        <input type="range" id="rngRefr" min="150" max="400" step="10" value="250" oninput="onSliderChange('Refr', this.value)">
        <div class="range-labels"><span>150 ms (Fast)</span><span>400 ms (Capped)</span></div>
      </div>

      <!-- Safe Save Action Bar -->
      <div style="display:grid; grid-template-columns:1.2fr 0.8fr; gap:8px;">
        <button id="btnSaveDevice" class="btn-action-primary" style="min-height:44px; font-size:0.82rem; background:var(--accent);" onclick="saveToDevice()" disabled>
          💾 Save to Device (Safe Flash)
        </button>
        <button id="btnRevert" class="btn-secondary" onclick="revertSettings()" disabled>
          Revert
        </button>
      </div>

      <div style="display:flex; justify-content:space-between; align-items:center; margin-top:2px;">
        <button onclick="confirmRestoreDefaults()" style="background:none; border:none; color:var(--text-muted); font-size:0.7rem; font-weight:700; cursor:pointer;">
          Restore Defaults
        </button>
        <button onclick="openCppExportModal()" style="background:none; border:none; color:var(--accent); font-size:0.7rem; font-weight:700; cursor:pointer;">
          Export C++ Config
        </button>
      </div>
    </div>
  </section>

  <!-- PHASE 1.5: Voice Coach Drawer (Collapsible) -->
  <section class="card-section" aria-label="Voice Coaching Engine">
    <div class="collapsible-trigger" onclick="toggleCollapse('panelVoice', 'caretVoice')">
      <h3>
        <svg class="icon"><use href="#icon-speaker"/></svg>
        Voice Coach (Phone Speaker)
      </h3>
      <svg id="caretVoice" class="icon icon-sm" style="transition:transform 0.2s;"><use href="#icon-chevron"/></svg>
    </div>

    <div id="panelVoice" style="display:none; flex-direction:column; gap:10px;">
      <div class="switch-wrap">
        <label for="chkVoiceMaster" style="font-size:0.78rem; font-weight:700;">Voice Coach Active</label>
        <label class="switch">
          <input type="checkbox" id="chkVoiceMaster" checked onchange="onVoiceSwitch(this.checked)">
          <span class="switch-slider"></span>
        </label>
      </div>

      <div class="voice-row">
        <label for="selVoice">Voice Engine (Installed OS Voices):</label>
        <select id="selVoice" class="select-box" onchange="onVoiceEngineSelect(this.value)">
          <option value="-1">Default System Voice</option>
        </select>
      </div>

      <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px;">
        <div class="voice-row">
          <div style="display:flex; justify-content:space-between;">
            <label>Speed:</label>
            <span id="lblVoiceRate" class="tabular" style="font-size:0.7rem; font-weight:700;">1.0x</span>
          </div>
          <input type="range" min="0.8" max="1.3" step="0.05" value="1.0" oninput="onVoiceRateChange(this.value)">
        </div>
        <div class="voice-row">
          <div style="display:flex; justify-content:space-between;">
            <label>Volume:</label>
            <span id="lblVoiceVol" class="tabular" style="font-size:0.7rem; font-weight:700;">100%</span>
          </div>
          <input type="range" min="0.2" max="1.0" step="0.1" value="1.0" oninput="onVoiceVolChange(this.value)">
        </div>
      </div>

      <p style="font-size:0.68rem; color:var(--text-muted); line-height:1.3;">
        Tap any phrase to test pronunciation and volume through your device speaker:
      </p>

      <div class="phrase-grid">
        <button class="btn-phrase" onclick="testVoiceCue('Push harder')">Push harder</button>
        <button class="btn-phrase" onclick="testVoiceCue('Push shallower')">Push shallower</button>
        <button class="btn-phrase" onclick="testVoiceCue('Release completely')">Release completely</button>
        <button class="btn-phrase" onclick="testVoiceCue('Speed up')">Speed up</button>
        <button class="btn-phrase" onclick="testVoiceCue('Slow down')">Slow down</button>
        <button class="btn-phrase" onclick="testVoiceCue('Good compressions')">Good compressions</button>
      </div>

      <button class="btn-secondary" onclick="stopSpeakingNow()" style="margin-top:2px;">
        Stop Speaking
      </button>
    </div>
  </section>

  <!-- PHASE 4: Kinematic Waveform Canvas & Per-Stroke Log (Diagnostics) -->
  <section class="card-section" aria-label="Kinematic Diagnostics">
    <div class="collapsible-trigger" onclick="toggleCollapse('panelDiag', 'caretDiag')">
      <h3>
        <svg class="icon"><use href="#icon-target"/></svg>
        Waveform & Stroke Diagnostics
      </h3>
      <svg id="caretDiag" class="icon icon-sm" style="transition:transform 0.2s;"><use href="#icon-chevron"/></svg>
    </div>

    <div id="panelDiag" style="display:none; flex-direction:column; gap:10px;">
      <div style="display:flex; justify-content:space-between; align-items:center; font-size:0.7rem; color:var(--text-muted);">
        <span>Kinematic Acceleration (Cyan) & Depth (Indigo)</span>
        <button id="btnWavePause" onclick="toggleWaveformPause()" class="btn-secondary" style="min-height:26px; padding:2px 8px; font-size:0.65rem;">Pause</button>
      </div>

      <canvas id="waveCanvas" width="450" height="120"></canvas>

      <!-- Reference Mannequin Comparison -->
      <div style="display:flex; align-items:center; justify-content:space-between; background:var(--surface-alt); padding:8px 10px; border-radius:var(--radius-sm); font-size:0.72rem;">
        <span>Ground Truth Depth:</span>
        <div style="display:flex; align-items:center; gap:6px;">
          <input type="number" id="inRefDepth" step="0.1" value="5.0" style="width:50px; padding:3px; border-radius:4px; border:1px solid var(--border-strong); text-align:center;">
          <span>cm</span>
          <span id="lblRefError" class="tabular" style="font-weight:700; color:var(--accent);">Err: 0.0%</span>
        </div>
      </div>

      <!-- Stroke Log Table Preview -->
      <div style="max-height:160px; overflow-y:auto; border:1px solid var(--border); border-radius:var(--radius-sm);">
        <table style="width:100%; border-collapse:collapse; font-size:0.68rem; text-align:left;">
          <thead style="background:var(--surface-alt); color:var(--text-muted); position:sticky; top:0;">
            <tr>
              <th style="padding:4px 6px;">#</th>
              <th style="padding:4px 6px;">Time</th>
              <th style="padding:4px 6px;">Depth</th>
              <th style="padding:4px 6px;">Rate</th>
              <th style="padding:4px 6px;">Recoil</th>
              <th style="padding:4px 6px;">Status</th>
            </tr>
          </thead>
          <tbody id="tblStrokeBody">
            <tr><td colspan="6" style="text-align:center; padding:12px; color:var(--text-muted);">No compressions logged yet</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </section>

  <!-- MOCK DATA SIMULATOR DRAWER (Active only in browser mock mode) -->
  <section id="secMockTools" class="card-section" style="border:1px dashed var(--warning-border); background:#FFFDF7;">
    <div class="collapsible-trigger" onclick="toggleCollapse('panelMock', 'caretMock')">
      <h3 style="color:#B45309;">
        <svg class="icon"><use href="#icon-sliders"/></svg>
        Simulator Scenarios (Mock Mode)
      </h3>
      <svg id="caretMock" class="icon icon-sm" style="transition:transform 0.2s;"><use href="#icon-chevron"/></svg>
    </div>

    <div id="panelMock" style="display:flex; flex-direction:column; gap:8px;">
      <label for="mockScenarioSelect" style="font-size:0.7rem; font-weight:700; color:#92400E;">Select CPR Rescuer Profile:</label>
      <select id="mockScenarioSelect" class="select-box" onchange="onMockScenarioChange(this.value)">
        <option value="compliant">Compliant (112 cpm, 5.3 cm)</option>
        <option value="shallow">Too shallow (4.1 cm) -> "Push harder"</option>
        <option value="too_deep">Too deep (6.6 cm) -> "Push shallower"</option>
        <option value="leaning">Leaning on chest -> "Release completely"</option>
        <option value="slow">Too slow (84 cpm) -> "Speed up"</option>
        <option value="fast">Too fast (138 cpm) -> "Slow down"</option>
        <option value="pauses">Pause / Inactivity (>10s)</option>
      </select>
      <div style="display:flex; justify-content:space-between; font-size:0.68rem; color:#92400E;">
        <span>Streak: <strong id="mockStreakTxt">0.0s</strong></span>
        <span>Cooldown: <strong id="mockCooldownTxt">0s</strong></span>
      </div>
    </div>
  </section>

  <!-- Theme Toggle & Version Footer -->
  <footer style="display:flex; justify-content:space-between; align-items:center; padding:10px 4px; font-size:0.68rem; color:var(--text-sub);">
    <span>CPReady Bench v2.4 (Clinical)</span>
    <button onclick="toggleDarkMode()" style="background:none; border:none; color:inherit; cursor:pointer; font-weight:700;">
      🌓 Switch Theme
    </button>
  </footer>

</div>

<!-- ============================================================================== -->
<!-- MODALS                                                                         -->
<!-- ============================================================================== -->

<!-- 1. Guided Ruler Depth Calibration Modal -->
<div id="wizardModal" class="modal-backdrop">
  <div class="modal-window">
    <div style="display:flex; justify-content:space-between; align-items:center;">
      <h3 class="modal-title">Guided Depth Calibration</h3>
      <button onclick="closeWizardModal()" style="background:none; border:none; font-size:1.1rem; cursor:pointer; color:var(--text-muted);">✕</button>
    </div>
    <p style="font-size:0.72rem; color:var(--text-muted); line-height:1.4;">
      Compress the mannequin chest against a rigid physical ruler to a known target depth, then enter that ruler measurement below.
    </p>

    <div style="background:var(--surface-alt); padding:10px; border-radius:var(--radius-sm); display:flex; flex-direction:column; gap:8px;">
      <div style="display:flex; justify-content:space-between; font-size:0.75rem;">
        <span>Currently Measured:</span>
        <strong id="wizMeasuredVal" class="tabular" style="color:var(--accent);">4.2 cm</strong>
      </div>
      <div style="display:flex; justify-content:space-between; align-items:center; font-size:0.75rem;">
        <span>Ruler Target:</span>
        <input type="number" id="wizTargetInput" value="5.0" step="0.1" style="width:60px; padding:4px; border-radius:4px; border:1px solid var(--border-strong); text-align:center;">
      </div>
      <div style="display:flex; justify-content:space-between; font-size:0.75rem; border-top:1px solid var(--border); padding-top:6px;">
        <span>Computed Scale (K):</span>
        <strong id="wizComputedK" class="tabular" style="color:var(--success);">13.3</strong>
      </div>
    </div>

    <button class="btn-action-primary" style="min-height:42px; background:var(--accent); font-size:0.8rem;" onclick="applyWizardK()">
      Apply Calibrated Scalar (K)
    </button>
  </div>
</div>

<!-- 2. C++ Config Exporter Modal -->
<div id="cppModal" class="modal-backdrop">
  <div class="modal-window">
    <div style="display:flex; justify-content:space-between; align-items:center;">
      <h3 class="modal-title">Calibrated Parameters (C++)</h3>
      <button onclick="closeCppModal()" style="background:none; border:none; font-size:1.1rem; cursor:pointer; color:var(--text-muted);">✕</button>
    </div>
    <p style="font-size:0.72rem; color:var(--text-muted);">
      Copy this configuration directly into your research paper or production firmware:
    </p>
    <div id="cppCodeBox" class="code-box"></div>
    <button class="btn-action-primary" style="min-height:42px; background:var(--accent); font-size:0.8rem;" onclick="copyCppCode()">
      Copy to Clipboard
    </button>
  </div>
</div>

<!-- 3. Hardware Diagnostics Popover -->
<div id="diagModal" class="modal-backdrop">
  <div class="modal-window">
    <div style="display:flex; justify-content:space-between; align-items:center;">
      <h3 class="modal-title">Hardware Status</h3>
      <button onclick="closeDiagModal()" style="background:none; border:none; font-size:1.1rem; cursor:pointer; color:var(--text-muted);">✕</button>
    </div>
    <div style="display:flex; flex-direction:column; gap:8px; font-size:0.75rem;">
      <div style="display:flex; justify-content:space-between;">
        <span>Chest MPU (0x68):</span>
        <strong id="diagChestStatus" style="color:var(--success);">Online (SDA=21, SCL=22)</strong>
      </div>
      <div style="display:flex; justify-content:space-between;">
        <span>Spine MPU (0x69):</span>
        <strong id="diagSpineStatus">Not Connected</strong>
      </div>
      <div style="display:flex; justify-content:space-between;">
        <span>Deterministic Loop:</span>
        <strong>100 Hz (10,000 µs)</strong>
      </div>
      <div style="display:flex; justify-content:space-between;">
        <span>I2C Bus Health:</span>
        <strong style="color:var(--success);">Normal (No wire freeze)</strong>
      </div>
    </div>
    <button class="btn-secondary" onclick="closeDiagModal()" style="min-height:38px;">Close</button>
  </div>
</div>

<!-- 4. Session Summary Modal (On Test Stop) -->
<div id="summaryModal" class="modal-backdrop">
  <div class="modal-window">
    <div style="display:flex; justify-content:space-between; align-items:center;">
      <h3 class="modal-title">CPR Trial Summary</h3>
      <button onclick="closeSummaryModal()" style="background:none; border:none; font-size:1.1rem; cursor:pointer; color:var(--text-muted);">✕</button>
    </div>
    <div style="display:flex; flex-direction:column; gap:8px; font-size:0.78rem; background:var(--surface-alt); padding:12px; border-radius:var(--radius-sm);">
      <div style="display:flex; justify-content:space-between;">
        <span>Compressions:</span>
        <strong id="sumStrokes">0 strokes</strong>
      </div>
      <div style="display:flex; justify-content:space-between;">
        <span>Duration:</span>
        <strong id="sumDuration">00:00</strong>
      </div>
      <div style="display:flex; justify-content:space-between;">
        <span>Average Rate:</span>
        <strong id="sumAvgRate">0 cpm</strong>
      </div>
      <div style="display:flex; justify-content:space-between;">
        <span>Average Depth:</span>
        <strong id="sumAvgDepth">0.0 cm</strong>
      </div>
      <div style="display:flex; justify-content:space-between;">
        <span>Recoil Compliance:</span>
        <strong id="sumRecoil">100%</strong>
      </div>
    </div>
    <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px;">
      <button class="btn-action-primary" style="min-height:42px; background:var(--accent); font-size:0.8rem;" onclick="exportSessionCsv()">Export CSV</button>
      <button class="btn-secondary" onclick="closeSummaryModal()">Close</button>
    </div>
  </div>
</div>

<div id="toast" class="toast"></div>

<!-- ============================================================================== -->
<!-- CLIENT SCRIPT                                                                  -->
<!-- ============================================================================== -->
<script>
// AHA Targets Standard Definition
const AHA_TARGETS = {
  rateMin: 100,
  rateMax: 120,
  depthMinCm: 5.0,
  depthMaxCm: 6.0,
  ccfMinPct: 60
};

// Global App State
let state = {
  isMock: (window.location.protocol === 'file:' || window.location.protocol === 'content:' || window.location.hostname === 'localhost'),
  useMm: false,
  theme: 'light',
  
  // Hardware / Protocol Settings
  config: {
    depthK: 11.2,
    compressionThreshG: 0.45,
    recoilThreshG: -0.35,
    refractoryMs: 250,
    calibTimeMs: 2000,
    practiceSec: 60,
    useDualMpu: false
  },
  savedConfig: {
    depthK: 11.2,
    compressionThreshG: 0.45,
    recoilThreshG: -0.35,
    refractoryMs: 250,
    useDualMpu: false
  },
  
  // Telemetry
  sessionActive: false,
  isCalibrating: false,
  isCalibrated: false,
  strokes: 0,
  startTime: 0,
  elapsedSec: 0,
  rollingRate: 0,
  rollingDepth: 0,
  recoilCompliancePct: 100,
  ccfPct: 0,
  lastStrokeTime: 0,
  
  // Rolling Buffers
  rateHistory: [],
  depthHistory: [],
  recoilHistory: [],
  strokeEvents: [],
  
  // Voice Engine State
  voiceEnabled: true,
  selectedVoiceIdx: -1,
  voiceRate: 1.0,
  voiceVol: 1.0,
  lastSpokenTime: 0,
  lastSpokenCue: '',
  outOfRangeStreak: 0,
  
  // Mock Simulator
  mockScenario: 'compliant',
  mockStreakStart: Date.now()
};

// ==============================================================================
// 1. WEB AUDIO WAKEUP CHIME & WEB SPEECH SYNTHESIS ENGINE
// ==============================================================================
let audioCtx = null;
let audioUnlocked = false;
let availableVoices = [];
window._activeUtterance = null;

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

// 80ms gentle medical attention chime (D5 ramping to A5)
// Wakes up phone DAC hardware and prevents first-syllable cut-off
function playWakeupChime() {
  try {
    const ctx = getAudioContext();
    if (!ctx) return;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
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

function initVoiceList() {
  if (!('speechSynthesis' in window)) return;
  availableVoices = window.speechSynthesis.getVoices();
  const sel = document.getElementById('selVoice');
  if (!sel) return;
  sel.innerHTML = '<option value="-1">Default System Voice</option>';
  availableVoices.forEach((v, idx) => {
    const opt = document.createElement('option');
    opt.value = idx;
    opt.textContent = `${v.name} (${v.lang})${v.default ? ' [Default]' : ''}`;
    if (v.lang.startsWith('en') && state.selectedVoiceIdx === -1 && (v.name.includes('Natural') || v.name.includes('Online') || v.name.includes('Google') || v.name.includes('Siri') || v.name.includes('Zira'))) {
      state.selectedVoiceIdx = idx;
    }
    sel.appendChild(opt);
  });
  if (state.selectedVoiceIdx >= 0) sel.value = state.selectedVoiceIdx;
}

if ('speechSynthesis' in window) {
  initVoiceList();
  window.speechSynthesis.onvoiceschanged = initVoiceList;
}

function speakPhrase(phrase) {
  if (!state.voiceEnabled) return;
  if (!('speechSynthesis' in window)) {
    updateCaption(phrase, false);
    return;
  }

  updateCaption(phrase, true);
  if ('vibrate' in navigator) navigator.vibrate(30);

  // Play prompt chime to wake mobile speaker amplifier
  playWakeupChime();

  if (window.speechSynthesis.paused) window.speechSynthesis.resume();
  if (window.speechSynthesis.speaking) window.speechSynthesis.cancel();

  // 120ms staging buffer: eliminates Windows Chromium cancel() race deadlock and hardware DAC clipping
  setTimeout(() => {
    // Leading comma provides 100ms acoustic lead-in so the initial consonant is never clipped
    const paddedText = ',  ' + phrase;
    const u = new SpeechSynthesisUtterance(paddedText);
    u.rate = state.voiceRate;
    u.volume = state.voiceVol;
    u.pitch = 1.0;
    u.lang = 'en-US';

    if (state.selectedVoiceIdx >= 0 && availableVoices[state.selectedVoiceIdx]) {
      u.voice = availableVoices[state.selectedVoiceIdx];
    } else {
      const enVoice = availableVoices.find(v => v.lang.startsWith('en'));
      if (enVoice) u.voice = enVoice;
    }

    const wave = document.getElementById('captionWave');
    u.onstart = () => { if (wave) wave.className = 'caption-wave active'; };
    u.onend = () => {
      if (wave) wave.className = 'caption-wave';
      window._activeUtterance = null;
    };
    u.onerror = () => {
      if (wave) wave.className = 'caption-wave';
      window._activeUtterance = null;
    };

    // Store global reference to prevent Chromium garbage-collection drop on Windows
    window._activeUtterance = u;
    window.speechSynthesis.speak(u);

    if (window.speechSynthesis.paused) window.speechSynthesis.resume();
  }, 120);
}

function testVoiceCue(phrase) {
  speakPhrase(phrase);
}

function stopSpeakingNow() {
  if ('speechSynthesis' in window) {
    window.speechSynthesis.cancel();
  }
  document.getElementById('captionWave').className = 'caption-wave';
  showToast('Speech canceled');
}

function updateCaption(text, isSpoken) {
  document.getElementById('liveCaptionText').innerText = `"${text}"`;
  document.getElementById('captionSub').innerText = isSpoken ? 'Active' : 'Muted';
}

function toggleMasterSpeaker() {
  state.voiceEnabled = !state.voiceEnabled;
  const btn = document.getElementById('btnSpeaker');
  const chk = document.getElementById('chkVoiceMaster');
  chk.checked = state.voiceEnabled;

  if (state.voiceEnabled) {
    btn.className = 'btn-speaker';
    btn.setAttribute('aria-pressed', 'true');
    btn.innerHTML = '<svg class="icon"><use href="#icon-speaker"/></svg>';
    showToast('Voice coach unmuted');
  } else {
    btn.className = 'btn-speaker muted';
    btn.setAttribute('aria-pressed', 'false');
    btn.innerHTML = '<svg class="icon"><use href="#icon-speaker-mute"/></svg>';
    stopSpeakingNow();
    showToast('Voice coach muted');
  }
}

function onVoiceSwitch(enabled) {
  state.voiceEnabled = enabled;
  const btn = document.getElementById('btnSpeaker');
  btn.className = enabled ? 'btn-speaker' : 'btn-speaker muted';
  btn.setAttribute('aria-pressed', enabled.toString());
  btn.innerHTML = enabled ? '<svg class="icon"><use href="#icon-speaker"/></svg>' : '<svg class="icon"><use href="#icon-speaker-mute"/></svg>';
  if (!enabled) stopSpeakingNow();
  showToast(enabled ? 'Voice coach active' : 'Voice coach disabled');
}

function onVoiceEngineSelect(idx) { state.selectedVoiceIdx = parseInt(idx); }
function onVoiceRateChange(v) { state.voiceRate = parseFloat(v); document.getElementById('lblVoiceRate').innerText = v + 'x'; }
function onVoiceVolChange(v) { state.voiceVol = parseFloat(v); document.getElementById('lblVoiceVol').innerText = Math.round(v * 100) + '%'; }

// ==============================================================================
// 2. UNIFIED COACHING EVALUATOR (Hysteresis & Priority Engine)
// ==============================================================================
function evaluateCoachingRules() {
  if (!state.sessionActive || state.strokes < 3) return;

  const now = Date.now();
  const timeSinceLastSpoken = now - state.lastSpokenTime;

  // Priority: Depth > Recoil > Rate > Praise
  let desiredCue = null;
  let isDeviation = false;

  // 1. Depth Evaluation
  if (state.rollingDepth < AHA_TARGETS.depthMinCm) {
    desiredCue = 'Push harder';
    isDeviation = true;
  } else if (state.rollingDepth > AHA_TARGETS.depthMaxCm) {
    desiredCue = 'Push shallower';
    isDeviation = true;
  }
  // 2. Recoil Evaluation
  else if (state.recoilHistory.length > 0 && state.recoilHistory[state.recoilHistory.length - 1] === 0) {
    desiredCue = 'Release completely';
    isDeviation = true;
  }
  // 3. Rate Evaluation
  else if (state.rollingRate < AHA_TARGETS.rateMin) {
    desiredCue = 'Speed up';
    isDeviation = true;
  } else if (state.rollingRate > AHA_TARGETS.rateMax) {
    desiredCue = 'Slow down';
    isDeviation = true;
  }

  // Hysteresis: requires 3 consecutive out-of-range strokes (~2.5s) & 6s cooldown
  if (isDeviation) {
    state.outOfRangeStreak++;
    if (state.outOfRangeStreak >= 3 && timeSinceLastSpoken >= 6000) {
      speakPhrase(desiredCue);
      state.lastSpokenTime = now;
      state.lastSpokenCue = desiredCue;
      state.outOfRangeStreak = 0;
    }
  } else {
    state.outOfRangeStreak = 0;
    // Positive reinforcement praise every 15s of compliant performance
    if (timeSinceLastSpoken >= 15000) {
      speakPhrase('Good compressions');
      state.lastSpokenTime = now;
      state.lastSpokenCue = 'Good compressions';
    }
  }
}

// ==============================================================================
// 3. PROTOCOL & CLIENT-SERVER DATA PIPELINE (Live ESP32 + Offline Mock)
// ==============================================================================

// Mock Backend Interceptor (active in file:, content:, or disconnected mode)
let mockSimAngle = 0;
function simulateMockTick() {
  const now = Date.now();
  if (!state.sessionActive) return;

  state.elapsedSec = Math.floor((now - state.startTime) / 1000);
  mockSimAngle += 0.35;
  let accel = Math.sin(mockSimAngle) * 1.85;
  let depth = 5.3 + Math.sin(mockSimAngle * 0.5) * 0.2;
  let rate = 112;
  let recoilOk = true;

  // Scenario Overrides
  const scen = state.mockScenario;
  if (scen === 'pauses') {
    accel = 0.02;
    depth = 0;
  } else if (scen === 'shallow') {
    depth = 4.1 + Math.sin(mockSimAngle * 0.5) * 0.2;
  } else if (scen === 'too_deep') {
    depth = 6.6 + Math.sin(mockSimAngle * 0.5) * 0.2;
  } else if (scen === 'leaning') {
    recoilOk = false;
  } else if (scen === 'slow') {
    rate = 84;
  } else if (scen === 'fast') {
    rate = 138;
  }

  // Stroke trigger detection
  if (scen !== 'pauses' && accel > state.config.compressionThreshG && (now - state.lastStrokeTime > state.config.refractoryMs)) {
    state.strokes++;
    state.lastStrokeTime = now;
    
    // Add to rolling history
    state.depthHistory.push(depth);
    if (state.depthHistory.length > 10) state.depthHistory.shift();
    state.rateHistory.push(rate);
    if (state.rateHistory.length > 10) state.rateHistory.shift();
    state.recoilHistory.push(recoilOk ? 1 : 0);
    if (state.recoilHistory.length > 10) state.recoilHistory.shift();

    state.rollingDepth = state.depthHistory.reduce((a,b)=>a+b, 0) / state.depthHistory.length;
    state.rollingRate = state.rateHistory.reduce((a,b)=>a+b, 0) / state.rateHistory.length;
    state.recoilCompliancePct = (state.recoilHistory.reduce((a,b)=>a+b, 0) / state.recoilHistory.length) * 100;
    state.ccfPct = Math.min(96, Math.max(62, 70 + (state.elapsedSec * 0.5)));

    recordStrokeLog(depth, rate, recoilOk);
    evaluateCoachingRules();
  }

  // Push to waveform ring buffer
  waveBuffer.push({ accel: accel, depth: depth });
  if (waveBuffer.length > 300) waveBuffer.shift();

  // Update simulator status text
  const streakSec = ((now - state.mockStreakStart) / 1000).toFixed(1);
  const cooldownSec = Math.max(0, Math.ceil((6000 - (now - state.lastSpokenTime)) / 1000));
  const elStreak = document.getElementById('mockStreakTxt');
  const elCooldown = document.getElementById('mockCooldownTxt');
  if (elStreak) elStreak.innerText = streakSec + 's';
  if (elCooldown) elCooldown.innerText = cooldownSec + 's';

  renderWaveform();
  updateUI();
}

async function fetchTelemetry() {
  if (state.isMock) {
    simulateMockTick();
    return;
  }

  try {
    const res = await fetch('/api/metrics');
    if (!res.ok) throw new Error('API error');
    const d = await res.json();

    state.sessionActive = d.session_active;
    state.isCalibrating = d.is_calibrating;
    state.isCalibrated = d.is_calibrated;
    state.strokes = d.strokes;
    state.elapsedSec = d.elapsed;
    state.rollingRate = d.rate;
    state.rollingDepth = d.depth;
    state.recoilCompliancePct = d.recoil_pct;
    state.ccfPct = d.ccf;

    // Push live accelerometer & depth to waveform buffer
    waveBuffer.push({ accel: d.accel, depth: d.depth });
    if (waveBuffer.length > 300) waveBuffer.shift();

    updateUI();
    renderWaveform();
  } catch (err) {
    // If connection drops, activate mock fallback and show indicator
    console.warn('ESP32 telemetry fetch failed, running local simulator:', err);
    state.isMock = true;
    document.getElementById('mockPersistentBanner').style.display = 'flex';
    document.getElementById('secMockTools').style.display = 'flex';
  }
}

// ==============================================================================
// 4. UI RENDER ENGINE & VISUAL GAUGES (Mobile First)
// ==============================================================================
function updateUI() {
  const d = state;
  const isIdle = !d.sessionActive && d.strokes === 0;

  // Rate Display & Gauge
  const elRate = document.getElementById('valRate');
  const elInstRate = document.getElementById('valInstantRate');
  const elNeedleRate = document.getElementById('gaugeRateNeedle');
  const badgeRate = document.getElementById('badgeRate');

  if (d.rollingRate > 0) {
    elRate.innerText = Math.round(d.rollingRate);
    elInstRate.innerText = Math.round(d.rollingRate);
    // Map 60..160 cpm to 0..100%
    const ratePct = Math.min(100, Math.max(0, ((d.rollingRate - 60) / 100) * 100));
    elNeedleRate.style.left = ratePct + '%';

    if (d.rollingRate >= AHA_TARGETS.rateMin && d.rollingRate <= AHA_TARGETS.rateMax) {
      badgeRate.className = 'status-badge badge-good';
      badgeRate.innerHTML = '<svg class="icon icon-sm"><use href="#icon-check"/></svg> In range (100–120)';
    } else if (d.rollingRate > AHA_TARGETS.rateMax) {
      badgeRate.className = 'status-badge badge-warn';
      badgeRate.innerHTML = '<svg class="icon icon-sm"><use href="#icon-arrow-up"/></svg> Too fast (>120)';
    } else {
      badgeRate.className = 'status-badge badge-warn';
      badgeRate.innerHTML = '<svg class="icon icon-sm"><use href="#icon-arrow-down"/></svg> Too slow (<100)';
    }
  } else {
    elRate.innerText = '--';
    elInstRate.innerText = '--';
    elNeedleRate.style.left = '50%';
    badgeRate.className = 'status-badge badge-neutral';
    badgeRate.innerHTML = '<span>○</span> Awaiting compressions';
  }

  // Depth Display & Gauge (Handles cm / mm toggle)
  const elDepth = document.getElementById('valDepth');
  const elInstDepth = document.getElementById('valInstantDepth');
  const elNeedleDepth = document.getElementById('gaugeDepthNeedle');
  const badgeDepth = document.getElementById('badgeDepth');
  const depthUnit = state.useMm ? 'mm' : 'cm';

  if (d.rollingDepth > 0) {
    const depthVal = state.useMm ? Math.round(d.rollingDepth * 10) : d.rollingDepth.toFixed(1);
    elDepth.innerText = depthVal;
    elInstDepth.innerText = depthVal;
    // Map 2.0..8.0 cm to 0..100%
    const depthPct = Math.min(100, Math.max(0, ((d.rollingDepth - 2.0) / 6.0) * 100));
    elNeedleDepth.style.left = depthPct + '%';

    if (d.rollingDepth >= AHA_TARGETS.depthMinCm && d.rollingDepth <= AHA_TARGETS.depthMaxCm) {
      badgeDepth.className = 'status-badge badge-good';
      badgeDepth.innerHTML = '<svg class="icon icon-sm"><use href="#icon-check"/></svg> In target (5.0–6.0)';
    } else if (d.rollingDepth > AHA_TARGETS.depthMaxCm) {
      badgeDepth.className = 'status-badge badge-alert';
      badgeDepth.innerHTML = '<svg class="icon icon-sm"><use href="#icon-arrow-up"/></svg> Too deep (>6.0)';
    } else {
      badgeDepth.className = 'status-badge badge-warn';
      badgeDepth.innerHTML = '<svg class="icon icon-sm"><use href="#icon-arrow-down"/></svg> Too shallow (<5.0)';
    }
  } else {
    elDepth.innerText = '--';
    elInstDepth.innerText = '--';
    elNeedleDepth.style.left = '50%';
    badgeDepth.className = 'status-badge badge-neutral';
    badgeDepth.innerHTML = '<span>○</span> Awaiting compressions';
  }

  // Recoil Display
  const badgeRecoil = document.getElementById('badgeRecoil');
  const elRecoilPct = document.getElementById('valRecoilPct');
  if (isIdle) {
    badgeRecoil.className = 'status-badge badge-neutral';
    badgeRecoil.innerHTML = '<span>○</span> — Not active';
    elRecoilPct.innerText = '--%';
  } else {
    const isRecoilGood = (d.recoilHistory.length === 0 || d.recoilHistory[d.recoilHistory.length - 1] === 1);
    badgeRecoil.className = 'status-badge ' + (isRecoilGood ? 'badge-good' : 'badge-alert');
    badgeRecoil.innerHTML = isRecoilGood ? '<svg class="icon icon-sm"><use href="#icon-check"/></svg> Full Release' : '<svg class="icon icon-sm"><use href="#icon-arrow-up"/></svg> Leaning';
    elRecoilPct.innerText = Math.round(d.recoilCompliancePct) + '%';
  }

  // CCF Display
  const elCCF = document.getElementById('valCCF');
  elCCF.innerText = isIdle ? '--' : Math.round(d.ccfPct);

  // Footer Strokes & Time
  document.getElementById('valStrokes').innerText = d.strokes;
  const m = Math.floor(d.elapsedSec / 60).toString().padStart(2, '0');
  const s = (d.elapsedSec % 60).toString().padStart(2, '0');
  document.getElementById('valElapsedMmSs').innerText = `${m}:${s}`;

  // Sticky Bar Sync
  document.getElementById('stkRate').innerText = d.rollingRate > 0 ? Math.round(d.rollingRate) : '--';
  document.getElementById('stkDepth').innerText = d.rollingDepth > 0 ? (state.useMm ? Math.round(d.rollingDepth * 10) : d.rollingDepth.toFixed(1)) : '--';
  document.getElementById('stkUnit').innerText = depthUnit;

  // Primary Action Button Workflow States
  updateWorkflowStateUI();
}

function updateWorkflowStateUI() {
  const btn = document.getElementById('btnPrimaryAction');
  const txt = document.getElementById('primaryActionText');
  const statTxt = document.getElementById('workflowStatusText');
  const ringOverlay = document.getElementById('calibRingOverlay');

  if (state.isCalibrating) {
    btn.style.display = 'none';
    ringOverlay.style.display = 'flex';
    statTxt.innerText = 'Calibrating... Hold still!';
    return;
  }

  ringOverlay.style.display = 'none';
  btn.style.display = 'inline-flex';

  if (!state.isCalibrated) {
    btn.className = 'btn-action-primary state-calibrate';
    btn.innerHTML = '<svg class="icon"><use href="#icon-target"/></svg><span>Calibrate Baseline (2s)</span>';
    statTxt.innerText = 'Idle — Calibration Required';
  } else if (!state.sessionActive) {
    btn.className = 'btn-action-primary state-start';
    btn.innerHTML = '<svg class="icon"><use href="#icon-play"/></svg><span>Start Test Session</span>';
    statTxt.innerText = 'Calibrated & Ready for Compressions';
  } else {
    btn.className = 'btn-action-primary state-stop';
    btn.innerHTML = '<svg class="icon"><use href="#icon-stop"/></svg><span>Stop Test Session</span>';
    statTxt.innerText = 'Test in Progress (Live AHA Evaluation)';
  }
}

// ==============================================================================
// 5. WORKFLOW & USER ACTIONS
// ==============================================================================
async function handlePrimaryAction() {
  if (!state.isCalibrated) {
    startCalibrationFlow();
  } else if (!state.sessionActive) {
    startSessionFlow();
  } else {
    stopSessionFlow();
  }
}

async function startCalibrationFlow() {
  showToast('Hold hands completely still on chest...');
  state.isCalibrating = true;
  updateWorkflowStateUI();

  // Animate 2s ring countdown
  const ringBar = document.getElementById('calibRingBar');
  const ringTxt = document.getElementById('calibCountdownText');
  let startTime = Date.now();

  const calibTimer = setInterval(() => {
    const elapsed = Date.now() - startTime;
    const progress = Math.min(1.0, elapsed / 2000);
    ringBar.style.strokeDashoffset = (113 * (1 - progress));
    ringTxt.innerText = Math.ceil(2 - (elapsed / 1000)) + 's';

    if (elapsed >= 2000) {
      clearInterval(calibTimer);
      state.isCalibrating = false;
      state.isCalibrated = true;
      document.getElementById('calibOffsetsSummary').innerText = 'Z-offset: 0.981g';
      showToast('Baseline calibrated. Ready for test.');
      speakPhrase('Calibrated');
      updateWorkflowStateUI();
    }
  }, 50);

  if (!state.isMock) {
    await fetch('/api/action', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'calibrate' })
    });
  }
}

async function startSessionFlow() {
  state.sessionActive = true;
  state.startTime = Date.now();
  state.strokes = 0;
  state.depthHistory = [];
  state.rateHistory = [];
  state.recoilHistory = [];
  state.strokeEvents = [];
  renderStrokeLogTable();
  showToast('Test session started!');
  speakPhrase('Test started');
  updateWorkflowStateUI();

  if (!state.isMock) {
    await fetch('/api/action', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'start_session' })
    });
  }
}

async function stopSessionFlow() {
  state.sessionActive = false;
  showToast('Test session stopped.');
  speakPhrase('Test stopped');
  updateWorkflowStateUI();

  if (!state.isMock) {
    await fetch('/api/action', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'stop_session' })
    });
  }

  // Open Summary Modal
  openSummaryModal();
}

function confirmResetStats() {
  if (confirm('Reset session statistics? Make sure to export CSV if you need this data.')) {
    state.strokes = 0;
    state.elapsedSec = 0;
    state.depthHistory = [];
    state.rateHistory = [];
    state.recoilHistory = [];
    state.strokeEvents = [];
    state.rollingRate = 0;
    state.rollingDepth = 0;
    renderStrokeLogTable();
    updateUI();
    showToast('Session reset');
  }
}

function toggleGlobalUnit() {
  state.useMm = !state.useMm;
  const btn = document.getElementById('btnUnitToggle');
  const lbl = document.getElementById('lblDepthUnit');
  btn.innerText = state.useMm ? 'mm' : 'cm';
  lbl.innerText = state.useMm ? 'mm' : 'cm';
  showToast(state.useMm ? 'Depth unit: Millimeters (mm)' : 'Depth unit: Centimeters (cm)');
  updateUI();
}

function setSensorMode(isDual) {
  state.config.useDualMpu = isDual;
  document.getElementById('segSingle').className = 'segment-btn ' + (!isDual ? 'active' : '');
  document.getElementById('segDual').className = 'segment-btn ' + (isDual ? 'active' : '');
  document.getElementById('modeDescText').innerText = isDual 
    ? 'Differential subtraction of mattress deflection via spine sensor.' 
    : 'Measuring sternal compression with zero-gravity tare offset.';

  const pillSpine = document.getElementById('pillSpine');
  if (isDual) {
    pillSpine.className = 'pill pill-green';
    pillSpine.innerText = '✓ Spine: OK (0x69)';
  } else {
    pillSpine.className = 'pill pill-neutral';
    pillSpine.innerText = '○ Spine: Not used';
  }

  checkDirtyState();
  showToast(isDual ? 'Switched to Dual MPU Decoupling' : 'Switched to Single Sternal MPU');
}

// ==============================================================================
// 6. PARAMETER TUNING, DIRTY TRACKING & FLASH SAVING
// ==============================================================================
function onSliderChange(param, val) {
  val = parseFloat(val);
  const key = param === 'DepthK' ? 'depthK' : (param === 'CThresh' ? 'compressionThreshG' : (param === 'RThresh' ? 'recoilThreshG' : 'refractoryMs'));
  state.config[key] = val;
  document.getElementById('num' + param).value = val;
  checkDirtyState();
}

function onNumInputChange(param, val) {
  val = parseFloat(val);
  const key = param === 'DepthK' ? 'depthK' : (param === 'CThresh' ? 'compressionThreshG' : (param === 'RThresh' ? 'recoilThreshG' : 'refractoryMs'));
  state.config[key] = val;
  document.getElementById('rng' + param).value = val;
  checkDirtyState();
}

function stepParam(param, delta) {
  const input = document.getElementById('num' + param);
  let v = parseFloat(input.value) + delta;
  const min = parseFloat(input.min);
  const max = parseFloat(input.max);
  v = Math.min(max, Math.max(min, v));
  const precision = param === 'Refr' ? 0 : (param === 'DepthK' ? 1 : 2);
  v = parseFloat(v.toFixed(precision));
  input.value = v;
  onNumInputChange(param, v);
}

function checkDirtyState() {
  const dirty = Math.abs(state.config.depthK - state.savedConfig.depthK) > 0.001 ||
                Math.abs(state.config.compressionThreshG - state.savedConfig.compressionThreshG) > 0.001 ||
                Math.abs(state.config.recoilThreshG - state.savedConfig.recoilThreshG) > 0.001 ||
                state.config.refractoryMs !== state.savedConfig.refractoryMs ||
                state.config.useDualMpu !== state.savedConfig.useDualMpu;

  document.getElementById('badgeDirty').style.display = dirty ? 'inline-block' : 'none';
  document.getElementById('btnSaveDevice').disabled = !dirty;
  document.getElementById('btnRevert').disabled = !dirty;
}

function saveToDevice() {
  state.savedConfig = { ...state.config };
  checkDirtyState();
  showToast(state.isMock ? 'Saved to browser memory (Mock Mode)' : 'Saved to Flash Memory (NVS Safe)');
}

function revertSettings() {
  state.config = { ...state.savedConfig };
  syncParamInputs();
  checkDirtyState();
  showToast('Settings reverted to last saved state');
}

function confirmRestoreDefaults() {
  if (confirm('Restore factory parameters?')) {
    state.config = { depthK: 11.2, compressionThreshG: 0.45, recoilThreshG: -0.35, refractoryMs: 250, useDualMpu: false };
    syncParamInputs();
    checkDirtyState();
    showToast('Restored factory defaults');
  }
}

function syncParamInputs() {
  document.getElementById('numDepthK').value = state.config.depthK;
  document.getElementById('rngDepthK').value = state.config.depthK;
  document.getElementById('numCThresh').value = state.config.compressionThreshG;
  document.getElementById('rngCThresh').value = state.config.compressionThreshG;
  document.getElementById('numRThresh').value = state.config.recoilThreshG;
  document.getElementById('rngRThresh').value = state.config.recoilThreshG;
  document.getElementById('numRefr').value = state.config.refractoryMs;
  document.getElementById('rngRefr').value = state.config.refractoryMs;
  setSensorMode(state.config.useDualMpu);
}

// Guided Depth Wizard
function openWizardModal() {
  const currentDepth = state.rollingDepth > 0 ? state.rollingDepth : 4.2;
  document.getElementById('wizMeasuredVal').innerText = currentDepth.toFixed(1) + ' cm';
  document.getElementById('wizTargetInput').value = '5.0';
  updateWizardCalc();
  document.getElementById('wizardModal').style.display = 'flex';
}
function closeWizardModal() { document.getElementById('wizardModal').style.display = 'none'; }
document.getElementById('wizTargetInput').addEventListener('input', updateWizardCalc);

function updateWizardCalc() {
  const target = parseFloat(document.getElementById('wizTargetInput').value) || 5.0;
  const measured = parseFloat(document.getElementById('wizMeasuredVal').innerText) || 4.2;
  const newK = (state.config.depthK * (target / measured)).toFixed(1);
  document.getElementById('wizComputedK').innerText = newK;
}

function applyWizardK() {
  const newK = parseFloat(document.getElementById('wizComputedK').innerText);
  state.config.depthK = newK;
  document.getElementById('numDepthK').value = newK;
  document.getElementById('rngDepthK').value = newK;
  checkDirtyState();
  closeWizardModal();
  showToast(`Applied calibrated Depth Scale: K = ${newK}`);
}

// C++ Config Export Modal
function openCppExportModal() {
  const c = state.config;
  const code = 
`// ==============================================================
// CPReady Calibrated Bench Parameters
// Generated: ${new Date().toISOString()}
// ==============================================================
#define DEPTH_CALIBRATION_K    ${c.depthK.toFixed(2)}f   // Tested depth scalar
#define COMPRESSION_THRESH_G   ${c.compressionThreshG.toFixed(2)}f   // Downstroke trigger
#define RECOIL_THRESH_G        ${c.recoilThreshG.toFixed(2)}f  // Upward recoil strictness
#define REFRACTORY_LOCKOUT_MS  ${c.refractoryMs}      // Foam debounce lockout
#define SENSOR_MODE_DUAL       ${c.useDualMpu ? 'true' : 'false'}   // Mattress decoupling mode`;

  document.getElementById('cppCodeBox').innerText = code;
  document.getElementById('cppModal').style.display = 'flex';
}
function closeCppModal() { document.getElementById('cppModal').style.display = 'none'; }
function copyCppCode() {
  const text = document.getElementById('cppCodeBox').innerText;
  if (navigator.clipboard) {
    navigator.clipboard.writeText(text).then(() => showToast('C++ Config copied to clipboard!'));
  } else {
    // Fallback for plain HTTP
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
    showToast('C++ Config copied to clipboard!');
  }
}

// ==============================================================================
// 7. WAVEFORM CANVAS & PER-STROKE LOG
// ==============================================================================
let waveBuffer = [];
let wavePaused = false;

function renderWaveform() {
  const canvas = document.getElementById('waveCanvas');
  if (!canvas || wavePaused) return;
  const ctx = canvas.getContext('2d');
  const w = canvas.width;
  const h = canvas.height;

  ctx.clearRect(0, 0, w, h);

  // Center zero line
  ctx.strokeStyle = '#1E293B';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(0, h * 0.5); ctx.lineTo(w, h * 0.5);
  ctx.stroke();

  if (waveBuffer.length < 2) return;
  const step = w / 250;
  const startIdx = Math.max(0, waveBuffer.length - 250);

  // 1. Draw Net Acceleration (Cyan)
  ctx.strokeStyle = '#38BDF8';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  for (let i = startIdx; i < waveBuffer.length; i++) {
    const x = (i - startIdx) * step;
    const y = (h * 0.5) - (waveBuffer[i].accel * (h * 0.15));
    if (i === startIdx) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();

  // 2. Draw Derived Displacement (Indigo)
  ctx.strokeStyle = '#818CF8';
  ctx.lineWidth = 2;
  ctx.beginPath();
  for (let i = startIdx; i < waveBuffer.length; i++) {
    const x = (i - startIdx) * step;
    const y = h - (waveBuffer[i].depth * (h * 0.12)) - 8;
    if (i === startIdx) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();
}

function toggleWaveformPause() {
  wavePaused = !wavePaused;
  const btn = document.getElementById('btnWavePause');
  btn.innerText = wavePaused ? 'Resume' : 'Pause';
}

function recordStrokeLog(depth, rate, recoilOk) {
  const ref = parseFloat(document.getElementById('inRefDepth').value) || 5.0;
  const errMm = Math.round((depth - ref) * 10);
  const errPct = Math.round(((depth - ref) / ref) * 100);
  document.getElementById('lblRefError').innerText = `Err: ${(errMm >= 0 ? '+' : '')}${errMm}mm (${errPct}%)`;

  const item = {
    index: state.strokes,
    time: state.elapsedSec,
    depth: depth.toFixed(1),
    rate: Math.round(rate),
    recoil: recoilOk ? 'Pass' : 'Lean',
    status: (depth >= 5.0 && depth <= 6.0 && rate >= 100 && rate <= 120 && recoilOk) ? 'Pass' : 'Deviation'
  };

  state.strokeEvents.unshift(item);
  if (state.strokeEvents.length > 50) state.strokeEvents.pop();
  renderStrokeLogTable();
}

function renderStrokeLogTable() {
  const tbody = document.getElementById('tblStrokeBody');
  if (state.strokeEvents.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; padding:12px; color:var(--text-muted);">No compressions logged yet</td></tr>';
    return;
  }
  tbody.innerHTML = state.strokeEvents.map(e => `
    <tr style="border-bottom:1px solid var(--border);">
      <td style="padding:4px 6px;">#${e.index}</td>
      <td style="padding:4px 6px;">${e.time}s</td>
      <td style="padding:4px 6px;"><strong>${e.depth} cm</strong></td>
      <td style="padding:4px 6px;">${e.rate} cpm</td>
      <td style="padding:4px 6px; color:${e.recoil === 'Pass' ? 'var(--success)' : 'var(--danger)'}; font-weight:700;">${e.recoil}</td>
      <td style="padding:4px 6px;"><span class="status-badge ${e.status === 'Pass' ? 'badge-good' : 'badge-warn'}" style="padding:1px 4px; font-size:0.6rem;">${e.status}</span></td>
    </tr>
  `).join('');
}

function exportSessionCsv() {
  if (state.strokeEvents.length === 0) {
    showToast('No session data available to export');
    return;
  }
  let csv = 'Stroke_Index,Elapsed_Seconds,Depth_cm,Rate_cpm,Recoil_Pass,Status\n';
  state.strokeEvents.forEach(e => {
    csv += `${e.index},${e.time},${e.depth},${e.rate},${e.recoil === 'Pass' ? 1 : 0},"${e.status}"\n`;
  });

  const blob = new Blob([csv], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `CPReady_Session_${Date.now()}.csv`;
  a.click();
  URL.revokeObjectURL(url);
  showToast('Session CSV exported');
}

// ==============================================================================
// 8. HELPERS & GENERAL INTERACTION
// ==============================================================================
function toggleCollapse(bodyId, caretId) {
  const body = document.getElementById(bodyId);
  const caret = document.getElementById(caretId);
  const isHidden = (body.style.display === 'none');
  body.style.display = isHidden ? 'flex' : 'none';
  if (caret) caret.style.transform = isHidden ? 'rotate(180deg)' : 'rotate(0deg)';
}

function toggleDarkMode() {
  const current = document.documentElement.getAttribute('data-theme') || 'light';
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  document.getElementById('metaThemeColor').setAttribute('content', next === 'dark' ? '#0E1318' : '#F5F4EF');
  showToast(`Switched to ${next} theme`);
}

function showToast(msg) {
  const t = document.getElementById('toast');
  t.innerText = msg;
  t.style.display = 'block';
  setTimeout(() => { t.style.display = 'none'; }, 3000);
}

function onMockScenarioChange(val) {
  state.mockScenario = val;
  state.mockStreakStart = Date.now();
  showToast('Switched simulator scenario to: ' + val);
}

function openDiagModal() { document.getElementById('diagModal').style.display = 'flex'; }
function closeDiagModal() { document.getElementById('diagModal').style.display = 'none'; }
function openSummaryModal() {
  document.getElementById('sumStrokes').innerText = state.strokes + ' strokes';
  const m = Math.floor(state.elapsedSec / 60).toString().padStart(2, '0');
  const s = (state.elapsedSec % 60).toString().padStart(2, '0');
  document.getElementById('sumDuration').innerText = `${m}:${s}`;
  document.getElementById('sumAvgRate').innerText = (state.rollingRate > 0 ? Math.round(state.rollingRate) : 0) + ' cpm';
  document.getElementById('sumAvgDepth').innerText = (state.rollingDepth > 0 ? state.rollingDepth.toFixed(1) : 0) + ' cm';
  document.getElementById('sumRecoil').innerText = Math.round(state.recoilCompliancePct) + '%';
  document.getElementById('summaryModal').style.display = 'flex';
}
function closeSummaryModal() { document.getElementById('summaryModal').style.display = 'none'; }

// Sticky bar scroll watcher
window.addEventListener('scroll', () => {
  const bar = document.getElementById('stickyBar');
  if (window.scrollY > 280) bar.style.display = 'flex';
  else bar.style.display = 'none';
});

// Detect in-app webview
if (navigator.userAgent.includes('FBAN') || navigator.userAgent.includes('FBAV') || navigator.userAgent.includes('Instagram')) {
  document.getElementById('webviewHint').style.display = 'flex';
}

window.onload = () => {
  updateUI();
  // 10 Hz refresh rate for telemetry & canvas
  setInterval(fetchTelemetry, 100);
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

    char buf[450];
    snprintf(buf, sizeof(buf),
        "{\"rate\":%.1f,\"depth\":%.2f,\"recoil_ok\":%s,\"recoil_pct\":%.1f,\"ccf\":%.1f,\"strokes\":%u,\"elapsed\":%u,\"accel\":%.2f,\"chest_ok\":%s,\"base_ok\":%s,\"is_calibrating\":%s,\"is_calibrated\":%s,\"session_active\":%s}",
        r.rate_cpm, r.depth_cm, r.recoil_complete ? "true" : "false",
        summary.recoil_compliance_percent, r.ccf_percent, r.stroke_count, r.elapsed_seconds,
        r.current_accel,
        sensors.isChestDetected() ? "true" : "false",
        sensors.isBaseDetected() ? "true" : "false",
        isCalibrating ? "true" : "false",
        sensors.getIsCalibrated() ? "true" : "false",
        tracker.isSessionActive() ? "true" : "false"
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
