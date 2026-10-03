#ifndef BENCH_CONFIG_H
#define BENCH_CONFIG_H

#include <Arduino.h>
#include <Preferences.h>

// ==============================================================================
// CPReady Test Bench - Master Hardware & Default Configuration
// ==============================================================================

// ---- Hardware Pins (ESP32 Standard) ----
#define BENCH_I2C_SDA_PIN          21   // ESP32 default I2C Data pin
#define BENCH_I2C_SCL_PIN          22   // ESP32 default I2C Clock pin
#define BENCH_BUZZER_PIN           25   // Piezo buzzer GPIO pin

// ---- I2C Bus Settings ----
#define BENCH_I2C_CLOCK_HZ         400000 // Fast Mode 400 kHz
#define BENCH_I2C_TIMEOUT_MS       25     // Prevent bus freeze on loose wires
#define BENCH_CHEST_I2C_ADDR       0x68   // Primary chest sensor (AD0 -> GND)
#define BENCH_BASE_I2C_ADDR        0x69   // Secondary spine reference (AD0 -> 3.3V)

// ---- Wi-Fi SoftAP Configuration ----
#define BENCH_WIFI_SSID            "CPReady-TestBench"
#define BENCH_WIFI_PASS            "cpready123" // WPA2 password (min 8 chars)
#define BENCH_WEB_PORT             80

// ---- Kinematics Defaults (Ground Truth CPReadyConfig) ----
#define DEFAULT_DEPTH_K            11.2f  // Depth calibration scalar: D = K * da * T^2
#define DEFAULT_COMPRESS_THRESH_G  0.45f  // Downward trigger threshold in g
#define DEFAULT_RECOIL_THRESH_G    -0.35f // Upward rebound threshold to confirm release in g
#define DEFAULT_REFRACTORY_MS      250    // Lockout ms between strokes (rejects bounces, max 240 cpm)
#define DEFAULT_CALIB_TIME_MS      2000   // Hands-idle resting baseline measurement duration (ms)
#define DEFAULT_PRACTICE_SEC       60     // Default practice trial timer duration (0 = unlimited)
#define DEFAULT_USE_DUAL_MPU       false  // Default to single MPU for ease of student bench testing

// ---- AHA Target Standards ----
#define AHA_TARGET_RATE_MIN_CPM    100
#define AHA_TARGET_RATE_MAX_CPM    120
#define AHA_TARGET_DEPTH_MIN_CM    5.0f
#define AHA_TARGET_DEPTH_MAX_CM    6.0f
#define AHA_TARGET_CCF_MIN_PERCENT 60

/**
 * Runtime Settings Struct
 * Holds active parameters and exposes NVS (Flash) persistence.
 */
struct BenchSettings {
    float    depthK;
    float    compressionThreshG;
    float    recoilThreshG;
    uint32_t refractoryMs;
    uint32_t calibTimeMs;
    uint32_t practiceSec;
    bool     useDualMpu;

    // Load from ESP32 Preferences (Flash Memory)
    void loadFromNVS() {
        Preferences prefs;
        prefs.begin("cpready_bench", true); // read-only mode

        depthK             = prefs.getFloat("depth_k", DEFAULT_DEPTH_K);
        compressionThreshG = prefs.getFloat("c_thresh", DEFAULT_COMPRESS_THRESH_G);
        recoilThreshG      = prefs.getFloat("r_thresh", DEFAULT_RECOIL_THRESH_G);
        refractoryMs       = prefs.getUInt("refr_ms", DEFAULT_REFRACTORY_MS);
        calibTimeMs        = prefs.getUInt("calib_ms", DEFAULT_CALIB_TIME_MS);
        practiceSec        = prefs.getUInt("prac_sec", DEFAULT_PRACTICE_SEC);
        useDualMpu         = prefs.getBool("dual_mpu", DEFAULT_USE_DUAL_MPU);

        prefs.end();
    }

    // Save current tuned settings to ESP32 Flash Memory
    bool saveToNVS() {
        Preferences prefs;
        if (!prefs.begin("cpready_bench", false)) { // read-write mode
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
        return true;
    }

    // Reset settings to default values and update NVS
    void resetToDefaults() {
        depthK             = DEFAULT_DEPTH_K;
        compressionThreshG = DEFAULT_COMPRESS_THRESH_G;
        recoilThreshG      = DEFAULT_RECOIL_THRESH_G;
        refractoryMs       = DEFAULT_REFRACTORY_MS;
        calibTimeMs        = DEFAULT_CALIB_TIME_MS;
        practiceSec        = DEFAULT_PRACTICE_SEC;
        useDualMpu         = DEFAULT_USE_DUAL_MPU;
        saveToNVS();
    }
};

#endif // BENCH_CONFIG_H
