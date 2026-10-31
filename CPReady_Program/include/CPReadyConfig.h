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
#define DEMO_CCF_PERCENT       85        // AHA: CCF >= 60%, ideally > 80%
// ---- Hardware Sensor Configuration ----
#define USE_DUAL_MPU           true      // Set true for 2 MPUs (chest + base); false for 1 MPU (chest only)


// ==============================================================================
// ADVANCED / INTERNAL SYSTEM CONSTANTS
// (Maintained for firmware subsystem compatibility; no need to edit for testing)
// ==============================================================================
namespace CPReadyConfig {
    // Hardware Sensor Mode
    constexpr bool        USE_DUAL_MPU_MODE             = USE_DUAL_MPU;

    // Kinematic Sensitivity Profiles
    enum class KinematicProfile : uint8_t {
        MANIKIN_STANDARD = 0, // Default adult AHA manikin thresholds (0.45g start, -0.35g recoil, K=11.2)
        BENCH_TEST       = 1  // Relaxed hand bench testing thresholds (0.25g start, -0.18g recoil, K=9.5)
    };

    // BLE & Identity Parameters
    constexpr const char* BLE_DEVICE_NAME               = "CPReady";                                // Advertised name in BLE scan
    constexpr const char* BLE_SERVICE_UUID              = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";  // Primary GATT service UUID
    constexpr const char* BLE_CHAR_NOTIFY_UUID          = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";  // Telemetry notification characteristic
    constexpr const char* BLE_CHAR_COMMAND_UUID         = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";  // Mobile app command write characteristic
    constexpr uint32_t    BLE_UPDATE_HZ                 = 5;                                        // Telemetry update rate in Hz
    constexpr uint32_t    BLE_NOTIFY_INTERVAL_MS        = 1000 / BLE_UPDATE_HZ;                     // Telemetry push rate (default 200 ms / 5 Hz)

    // Session & Tuning Parameters (Standard Adult Manikin Profile)
    constexpr uint32_t    DEFAULT_PRACTICE_DURATION_SEC       = 120;       // Total trial duration before auto-stop (0 = manual STOP)
    // Depth is integrated from acceleration (DepthEstimator.h), so it needs no scalar.
    // K is kept as the user-facing calibration value: reported depth = integrated depth
    // x (K / profile default K). At the default K the integrated depth is reported as is;
    // Manikin Calibration and SET_K still scale it proportionally.
    constexpr float       DEPTH_CALIBRATION_K                 = 11.2f;     // Manikin profile default K (scale 1.0)
    constexpr float       COMPRESSION_START_THRESHOLD_G       = 0.45f;     // Downstroke acceleration trigger threshold (g)
    constexpr float       RECOIL_THRESHOLD_G                  = -0.35f;    // Upward rebound threshold to confirm release (g)

    // Bench Testing Sensitivity Parameters (Alternative Relaxed Profile)
    constexpr float       BENCH_COMPRESSION_START_THRESHOLD_G = 0.25f;     // Relaxed start trigger for hand bench testing (g)
    constexpr float       BENCH_RECOIL_THRESHOLD_G            = -0.18f;    // Relaxed upward recoil threshold for bench testing (g)
    constexpr float       BENCH_DEPTH_CALIBRATION_K           = 9.5f;      // Bench profile default K (scale 1.0)

    // Accepted range for any depth scalar K (runtime SET_K, CALIBRATE_TARGET and NVS restore)
    constexpr float       DEPTH_K_MIN                         = 1.0f;
    constexpr float       DEPTH_K_MAX                         = 100.0f;

    // Version of the depth model that saved K values belong to. K values saved under the
    // old K * da * T^2 model would mis-scale the integrated depth, so they are discarded
    // once when this number changes.
    constexpr uint8_t     DEPTH_MODEL_VERSION                 = 2;

    // A detection whose integrated motion is smaller than this is a bump (hands
    // repositioned, vest knocked), not a compression, and is not counted.
    constexpr float       MIN_STROKE_DEPTH_CM                 = 1.0f;

    // Cadence Consistency
    constexpr float       MAX_CADENCE_JITTER_RATIO      = 0.25f;    // 25% period variance threshold to flag unsteady rhythm
    constexpr uint8_t     RATE_MEDIAN_STROKES           = 3;        // Live rate = median of this many recent stroke periods

    // 15-Second Comparative Manikin Calibration & Storage
    constexpr uint32_t    CALIBRATION_RUN_DURATION_SEC        = 15;        // Standard comparative calibration trial duration (15s)
    constexpr const char* NVS_NAMESPACE                       = "cpready"; // Flash non-volatile storage partition namespace

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
    constexpr uint8_t     I2C_SDA_PIN                   = 21;        // ESP32 I2C Serial Data pin
    constexpr uint8_t     I2C_SCL_PIN                   = 22;        // ESP32 I2C Serial Clock pin

    // AHA Target Standards
    constexpr uint16_t    TARGET_RATE_MIN_CPM           = 100;    // AHA adult lower target rate (100 compressions/min)
    constexpr uint16_t    TARGET_RATE_MAX_CPM           = 120;    // AHA adult upper target rate (120 compressions/min)
    constexpr float       TARGET_DEPTH_MIN_CM           = 5.0f;   // AHA minimum target depth (5.0 cm / 2.0 inches)
    constexpr float       TARGET_DEPTH_MAX_CM           = 6.0f;   // AHA maximum target depth (6.0 cm / 2.4 inches)
    constexpr uint8_t     TARGET_CCF_MIN_PERCENT        = 60;     // AHA minimum chest compression fraction (60% active time)

    // Internal I2C Bus, Multiplexer & Sensor Addresses
    constexpr uint8_t     CHEST_MPU_I2C_ADDR            = 0x68;    // Chest MPU6050 address (AD0 pin tied to GND)
    constexpr uint8_t     BASE_MPU_I2C_ADDR             = 0x68;    // Base MPU6050 address (behind PCA9548A channel, default 0x68)
    constexpr uint8_t     PCA9548A_I2C_ADDR             = 0x70;    // PCA9548A / TCA9548A multiplexer address (A0/A1/A2 low)
    constexpr uint8_t     PCA_CHANNEL_CHEST_DEFAULT     = 3;       // Default multiplexer channel for chest sensor (SD3/SC3)
    constexpr uint8_t     PCA_CHANNEL_BASE_DEFAULT      = 2;       // Default multiplexer channel for base sensor (SD2/SC2)
    constexpr bool        PCA_AUTO_SCAN_CHANNELS        = true;    // Dynamically scan channels 0-7 if sensors are plugged elsewhere
    constexpr uint32_t    I2C_CLOCK_SPEED_HZ            = 400000;  // I2C bus clock in Fast Mode (400 kHz) for 100 Hz sampling integrity
    constexpr uint32_t    I2C_TIMEOUT_MS                = 25;      // Bus read timeout to prevent lockup on wire disconnection

    // Kinematics & Filtering Engine
    constexpr uint32_t    SAMPLING_RATE_HZ              = 100;     // Sensor loop sampling rate (100 samples/sec)
    constexpr uint32_t    SAMPLE_INTERVAL_MICROS        = 1000000 / SAMPLING_RATE_HZ; // Microsecond interval between samples (10,000 us)
    constexpr float       LOWPASS_FILTER_ALPHA          = 0.25f;   // Exponential smoothing factor (~4.5 Hz lowpass cutoff)
    constexpr uint32_t    REFRACTORY_LOCKOUT_MS         = 300;     // Minimum onset-to-onset interval (200 cpm ceiling); timed from stroke START
    constexpr uint32_t    MIN_END_TO_ONSET_MS           = 80;      // Quiet time after a stroke ends before the next onset may start
    constexpr float       STROKE_FINISH_THRESHOLD_G     = -0.05f;  // Upward zero-crossing threshold to mark stroke completion
    constexpr float       RECOIL_ARM_FRACTION           = 0.30f;   // Recoil phase must swing below -(fraction x stroke peak) before it can finish
    constexpr float       RECOIL_ARM_MIN_G              = 0.08f;   // ...and at least this far below zero. Must stay well
                                                                   // below STROKE_FINISH_THRESHOLD_G, or a weak stroke arms
                                                                   // and finishes in the same sample on its way down.
    constexpr float       MIN_START_THRESHOLD_G         = 0.12f;   // Floor of the adaptive downstroke threshold (filtered g)
    constexpr float       ADAPTIVE_START_FRACTION       = 0.40f;   // Adaptive threshold = fraction x recent signal envelope, capped at the profile threshold
    constexpr float       ENVELOPE_DECAY_PER_SAMPLE     = 0.993f;  // Signal-envelope decay at 100 Hz (half-life ~1 s)
    constexpr uint32_t    MIN_VALID_PERIOD_MS           = 300;     // Shortest stroke period accepted as a cadence (200 cpm)
    constexpr uint32_t    PAUSE_DETECTION_TIMEOUT_MS    = 1500;    // A gap longer than this is a pause: no CCF credit, no rate, cue streaks reset

    // Chest recoil source. Without a force sensor the "recoil" flag is an acceleration
    // proxy that cannot see leaning, so it is reported as estimated and does not drive
    // the "release chest completely" voice cue.
    constexpr bool        RECOIL_MEASURED_BY_FORCE_SENSOR = false;
    constexpr bool        ENABLE_ESTIMATED_RECOIL_PROMPT  = false;

    // Sensor health monitoring
    constexpr uint8_t     SENSOR_FAULT_CONSECUTIVE_FAILS = 15;     // Failed reads in a row (150 ms) before the sensor is declared faulty
    constexpr uint16_t    SENSOR_STUCK_SAMPLE_LIMIT      = 250;    // Identical raw readings in a row (2.5 s) that indicate a frozen sensor
    constexpr float       DEPTH_MIN_LIMIT_CM            = 0.0f;    // Minimum allowable depth clamp to reject negative outliers
    constexpr float       DEPTH_MAX_LIMIT_CM            = 10.0f;   // Maximum allowable depth clamp to reject physical artifacts
}

#endif // CPREADY_CONFIG_H
