#ifndef CPREADY_CONFIG_H
#define CPREADY_CONFIG_H

#include <Arduino.h>

// ==============================================================================
// CPReady User Configuration & Testing Parameters
// ==============================================================================

// ---- Demo / Benchmark targets ----
#define ENABLE_DEMO_MODE       false     // Set true to simulate live telemetry without sensors
#define DEMO_DEPTH_MM          55        // AHA adult target: 50-60 mm
#define DEMO_RATE_CPM          110       // AHA target: 100-120 /min
#define DEMO_RECOIL_OK         true      // AHA: full recoil required
#define DEMO_CCF_PERCENT       74        // AHA target: >=60%, ideally >80%


// ==============================================================================
// ADVANCED / INTERNAL SYSTEM CONSTANTS
// (Maintained for firmware subsystem compatibility; no need to edit for testing)
// ==============================================================================
namespace CPReadyConfig {
    // BLE & Identity Parameters
    constexpr const char* BLE_DEVICE_NAME               = "CPReady";                                // Advertised name in BLE scan
    constexpr const char* BLE_SERVICE_UUID              = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";  // Primary GATT service UUID
    constexpr const char* BLE_CHAR_NOTIFY_UUID          = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";  // 11-byte telemetry notification characteristic
    constexpr const char* BLE_CHAR_COMMAND_UUID         = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";  // Mobile app command write characteristic
    constexpr uint32_t    BLE_UPDATE_HZ                 = 5;                                        // Telemetry update rate in Hz
    constexpr uint32_t    BLE_NOTIFY_INTERVAL_MS        = 1000 / BLE_UPDATE_HZ;                     // Telemetry push rate (default 200 ms / 5 Hz)

    // Session & Tuning Parameters
    constexpr uint32_t    DEFAULT_PRACTICE_DURATION_SEC       = 120;       // Total trial duration before auto-stop (0 = manual STOP)
    constexpr float       DEPTH_CALIBRATION_K                 = 11.2f;     // Harmonic depth scalar (depth = K * da * T^2)
    constexpr float       COMPRESSION_START_THRESHOLD_G       = 0.45f;     // Downstroke acceleration trigger threshold (g)
    constexpr float       RECOIL_THRESHOLD_G                  = -0.35f;    // Upward rebound threshold to confirm release (g)

    // Pre-Session Calibration & Stability Verification Parameters
    constexpr uint32_t    CALIBRATION_DURATION_MS             = 2000;      // Stationary baseline calibration window (ms)
    constexpr uint16_t    CALIBRATION_SAMPLE_COUNT            = 200;       // Target sample count (100 Hz * 2.0s)
    constexpr uint16_t    CALIBRATION_MIN_SAMPLE_COUNT        = 150;       // Minimum samples required (75% completeness threshold)
    constexpr uint32_t    CALIBRATION_PROGRESS_INTERVAL_MS    = 500;       // Packet Type 2 progress update cadence (ms)
    constexpr float       CALIBRATION_MAX_NET_SPREAD_G        = 0.30f;     // Max allowable peak-to-peak differential motion (g)
    constexpr float       CALIBRATION_MAX_CHEST_SPREAD_G      = 0.25f;     // Max allowable single chest sensor motion (g)
    constexpr float       CALIBRATION_MAX_BASE_SPREAD_G       = 0.20f;     // Max allowable single spine sensor motion (g)
    constexpr float       CALIBRATION_GRAVITY_MIN_G           = 0.65f;     // Plausible static gravity lower bound (g)
    constexpr float       CALIBRATION_GRAVITY_MAX_G           = 1.35f;     // Plausible static gravity upper bound (g)
    constexpr float       CALIBRATION_MAX_ALIGNMENT_DIFF_G    = 0.35f;     // Max allowable chest vs base tilt/pre-pressure divergence (g)

    // Audio Guidance & Coaching (Phone Speaker)
    constexpr bool        ENABLE_AUDIO_COACHING_PROMPTS = true;      // Master toggle for phone audio cue codes
    constexpr uint32_t    AUDIO_PROMPT_WINDOW_MS        = 3500;      // Sustained error window in milliseconds (3.5s)
    constexpr uint8_t     AUDIO_PROMPT_CONSECUTIVE_ERR  = 6;         // Minimum error strokes required to trigger voice
    constexpr uint32_t    AUDIO_PROMPT_COOLDOWN_MS      = 5000;      // Lockout duration between voice prompts (5.0s)
    constexpr uint32_t    AUDIO_PROMPT_PRAISE_INTERVAL  = 15000;     // Interval before positive reinforcement (15s)
    constexpr uint32_t    BLE_FINAL_RESULT_TIMEOUT_MS   = 2000;      // Timeout waiting for final results packet (2.0s)

    // Hardware Pins
    constexpr uint8_t     BUZZER_PIN                    = 25;        // ESP32 GPIO pin driving the buzzer
    constexpr uint8_t     I2C_SDA_PIN                   = 21;        // ESP32 I2C Serial Data pin
    constexpr uint8_t     I2C_SCL_PIN                   = 22;        // ESP32 I2C Serial Clock pin

    // AHA Target Standards
    constexpr uint16_t    TARGET_RATE_MIN_CPM           = 100;    // AHA adult lower target rate (100 compressions/min)
    constexpr uint16_t    TARGET_RATE_MAX_CPM           = 120;    // AHA adult upper target rate (120 compressions/min)
    constexpr float       TARGET_DEPTH_MIN_CM           = 5.0f;   // AHA minimum target depth (5.0 cm / 2.0 inches)
    constexpr float       TARGET_DEPTH_MAX_CM           = 6.0f;   // AHA maximum target depth (6.0 cm / 2.4 inches)
    constexpr uint8_t     TARGET_CCF_MIN_PERCENT        = 60;     // AHA minimum chest compression fraction (60% active time)

    // Internal I2C Bus & Sensor Addresses
    constexpr uint8_t     CHEST_MPU_I2C_ADDR            = 0x68;    // Chest MPU6050 address (AD0 pin tied to GND)
    constexpr uint8_t     BASE_MPU_I2C_ADDR             = 0x69;    // Base MPU6050 address (AD0 pin pulled up to 3.3V)
    constexpr uint32_t    I2C_CLOCK_SPEED_HZ            = 400000;  // I2C bus clock in Fast Mode (400 kHz)
    constexpr uint32_t    I2C_TIMEOUT_MS                = 25;      // Bus read timeout to prevent lockup on wire disconnection

    // Kinematics & Filtering Engine
    constexpr uint32_t    SAMPLING_RATE_HZ              = 100;     // Sensor loop sampling rate (100 samples/sec)
    constexpr uint32_t    SAMPLE_INTERVAL_MICROS        = 1000000 / SAMPLING_RATE_HZ; // Microsecond interval between samples (10,000 us)
    constexpr float       LOWPASS_FILTER_ALPHA          = 0.25f;   // Exponential smoothing factor (~4.5 Hz lowpass cutoff)
    constexpr uint32_t    REFRACTORY_LOCKOUT_MS         = 250;     // Minimum pause between strokes to reject impact bounces
    constexpr float       STROKE_FINISH_THRESHOLD_G     = -0.05f;  // Upward zero-crossing threshold to mark stroke completion
    constexpr uint32_t    PAUSE_DETECTION_TIMEOUT_MS    = 1500;    // Pause gap threshold before pausing active CCF accumulation
    constexpr float       DEPTH_MIN_LIMIT_CM            = 0.0f;    // Minimum allowable depth clamp to reject negative outliers
    constexpr float       DEPTH_MAX_LIMIT_CM            = 10.0f;   // Maximum allowable depth clamp to reject physical artifacts

    // Acoustic Protocol Timings (ESP32 Onboard Buzzer)
    constexpr uint16_t    BEEP_CALIB_START_ON_MS        = 200;     // Step 1: Calibration start tone duration (1 beep)
    constexpr uint16_t    BEEP_CALIB_START_OFF_MS       = 100;     // Step 1: Post-beep silence duration
    constexpr uint16_t    BEEP_COMPRESS_BEGIN_ON_MS     = 120;     // Step 2: Compressions begin tone duration (2 beeps)
    constexpr uint16_t    BEEP_COMPRESS_BEGIN_OFF_MS    = 100;     // Step 2: Inter-beep silence duration
    constexpr uint16_t    BEEP_SESSION_COMPLETE_ON_MS   = 150;     // Step 3: Session complete tone duration (3 beeps)
    constexpr uint16_t    BEEP_SESSION_COMPLETE_OFF_MS  = 120;     // Step 3: Inter-beep silence duration
    constexpr uint16_t    BEEP_METRONOME_CLICK_MS       = 30;      // Optional per-compression metronome tick click duration
}

#endif // CPREADY_CONFIG_H
