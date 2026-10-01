#ifndef CPREADY_CONFIG_H
#define CPREADY_CONFIG_H

#include <Arduino.h>

// ==============================================================================
// CPReady User Configuration & Testing Parameters
// ==============================================================================

// ---- BLE identity ----
#define BLE_DEVICE_NAME        "CPReady"
#define SERVICE_UUID           "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define METRICS_CHAR_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define COMMAND_CHAR_UUID      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

// ---- Update rate ----
#define BLE_UPDATE_HZ          5
#define BLE_UPDATE_INTERVAL_MS (1000 / BLE_UPDATE_HZ)

// ---- Demo / Benchmark targets ----
#define ENABLE_DEMO_MODE       false     // Set true to simulate live telemetry without sensors
#define DEMO_DEPTH_MM          55        // AHA adult target: 50-60 mm
#define DEMO_RATE_CPM          110       // AHA target: 100-120 /min
#define DEMO_RECOIL_OK         true      // AHA: full recoil required
#define DEMO_CCF_PERCENT       74        // AHA target: >=60%, ideally >80%

// ---- Testing & Manikin Tuning ----
#define PRACTICE_DURATION_SEC  120       // Trial duration in seconds (e.g., 30, 60, 120; 0 = run until STOP)
#define CALIBRATION_TIME_MS    2000      // Hands-idle baseline measurement window (ms)
#define DEPTH_CALIBRATION_K    11.2f     // Adjust if ruler != app: New_K = Current_K * (Ruler / App)
#define COMPRESSION_THRESH_G   0.45f     // Downward sensitivity (lower = more sensitive; higher = rejects bumps)
#define RECOIL_THRESH_G        -0.35f    // Recoil / leaning threshold (more negative = stricter recoil check)

// ---- Audio Guidance & Coaching (Phone Speaker) ----
#define ENABLE_AUDIO_COACHING  true      // Set true to generate phone voice guidance cue codes
#define AUDIO_PROMPT_WINDOW_MS 3500      // Error persistence duration (ms): errors must persist this long (3-5s)
#define AUDIO_PROMPT_MIN_ERRS  6         // Minimum consecutive bad strokes before voice prompt triggers
#define AUDIO_PROMPT_COOLDOWN  5000      // Silence lockout between voice prompts (ms): prevents speech overlap
#define AUDIO_PRAISE_INTERVAL  15000     // Minimum duration of perfect compressions before 'Good job' praise (ms)
#define BLE_STOP_TIMEOUT_MS    2000      // Agreed Flutter timeout waiting for final summary after STOP (ms)

// ---- Hardware Pins ----
#define BUZZER_PIN             25        // Piezo buzzer GPIO pin
#define I2C_SDA_PIN            21        // ESP32 default I2C Data pin
#define I2C_SCL_PIN            22        // ESP32 default I2C Clock pin


// ==============================================================================
// ADVANCED / INTERNAL SYSTEM CONSTANTS
// (Maintained for firmware subsystem compatibility; no need to edit for testing)
// ==============================================================================
namespace CPReadyConfig {
    // BLE & Identity Aliases
    constexpr const char* BLE_DEVICE_NAME               = ::BLE_DEVICE_NAME;        // Advertised name in BLE scan
    constexpr const char* BLE_SERVICE_UUID              = ::SERVICE_UUID;           // Primary GATT service UUID
    constexpr const char* BLE_CHAR_NOTIFY_UUID          = ::METRICS_CHAR_UUID;      // 11-byte telemetry notification characteristic
    constexpr const char* BLE_CHAR_COMMAND_UUID         = ::COMMAND_CHAR_UUID;      // Mobile app command write characteristic

    // Session & Tuning Aliases
    constexpr uint32_t    BLE_NOTIFY_INTERVAL_MS        = BLE_UPDATE_INTERVAL_MS;   // Telemetry push rate (default 200 ms / 5 Hz)
    constexpr uint32_t    DEFAULT_PRACTICE_DURATION_SEC = PRACTICE_DURATION_SEC;    // Total trial duration before auto-stop
    constexpr uint32_t    CALIBRATION_DURATION_MS       = CALIBRATION_TIME_MS;      // Initial stationary baseline calibration window
    constexpr float       DEPTH_CALIBRATION_K           = ::DEPTH_CALIBRATION_K;    // Harmonic depth scalar (depth = K * da * T^2)
    constexpr float       COMPRESSION_START_THRESHOLD_G = COMPRESSION_THRESH_G;     // Downstroke acceleration trigger threshold
    constexpr float       RECOIL_THRESHOLD_G            = RECOIL_THRESH_G;          // Upward rebound threshold to confirm release

    // Audio Guidance Aliases
    constexpr bool        ENABLE_AUDIO_COACHING_PROMPTS = ::ENABLE_AUDIO_COACHING;  // Master toggle for phone audio cue codes
    constexpr uint32_t    AUDIO_PROMPT_WINDOW_MS        = ::AUDIO_PROMPT_WINDOW_MS; // Sustained error window in milliseconds (3.5s)
    constexpr uint8_t     AUDIO_PROMPT_CONSECUTIVE_ERR  = ::AUDIO_PROMPT_MIN_ERRS;  // Minimum error strokes required to trigger voice
    constexpr uint32_t    AUDIO_PROMPT_COOLDOWN_MS      = ::AUDIO_PROMPT_COOLDOWN;  // Lockout duration between voice prompts (5.0s)
    constexpr uint32_t    AUDIO_PROMPT_PRAISE_INTERVAL  = ::AUDIO_PRAISE_INTERVAL;  // Interval before positive reinforcement
    constexpr uint32_t    BLE_FINAL_RESULT_TIMEOUT_MS   = ::BLE_STOP_TIMEOUT_MS;    // Timeout waiting for final results packet

    // Hardware Pin Aliases
    constexpr uint8_t     BUZZER_PIN                    = ::BUZZER_PIN;             // ESP32 GPIO pin driving the buzzer
    constexpr uint8_t     I2C_SDA_PIN                   = ::I2C_SDA_PIN;            // ESP32 I2C Serial Data pin
    constexpr uint8_t     I2C_SCL_PIN                   = ::I2C_SCL_PIN;            // ESP32 I2C Serial Clock pin

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
    constexpr uint16_t    CALIBRATION_SAMPLE_COUNT      = 200;     // Number of gravity samples averaged during 2.0s calibration
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
