#ifndef SIMULATION_CONFIG_H
#define SIMULATION_CONFIG_H

#include <Arduino.h>

#include "CPReadyConfig.h"

/**
 * Parameters for the synthetic stroke signal used by the `simulation`
 * PlatformIO environment.
 *
 * Each phase describes the physical stroke the simulated vest performs: the
 * cadence and the chest displacement per stroke. SyntheticVest turns that
 * motion into the acceleration the sensors would measure, so the production
 * tracker measures depth exactly as it does on the vest.
 *
 * Phases run back to back. The last phase repeats until the session ends, which
 * keeps a session that outlasts the table producing valid target-range strokes.
 */
namespace SimConfig {

struct Phase {
    uint16_t    rateCpm;     // Cadence the tracker should measure.
    float       depthCm;     // Chest displacement of each stroke.
    uint16_t    durationMs;  // Time this phase is held.
    const char* label;
    float       pushFraction;     // Fraction of cycle spent pushing down (default 0.35).
    float       releaseFraction;  // Fraction of cycle spent releasing (default 0.35).
    float       recoilFraction;   // 1.0 = full release to baseline, <1.0 = partial release (default 1.0).
};

/**
 * One pass through every coaching cue the firmware can give:
 *
 *   warm-up  - first five seconds are silenced by the prompt grace period
 *   shallow  - depth below 5 cm                         -> "push harder"
 *   deep     - depth above 6 cm                         -> "push shallower"
 *   slow     - 85 cpm                                   -> "speed up"
 *   fast     - 145 cpm                                  -> "slow down"
 *   good     - 15 s of target-range strokes             -> "good compressions"
 *
 * There is no leaning phase: leaning is a static load that accelerometers cannot
 * see, so the firmware no longer issues "release chest completely".
 *
 * Error phases are 7 s: long enough for the six strokes or 3.5 s the tracker
 * needs to confirm an error, short enough that the 5 s prompt cooldown has not
 * expired before the next phase begins, so each error produces one prompt.
 */
constexpr Phase PHASES[] = {
    {110, 5.5f,  5000, "warm-up",    0.35f, 0.35f, 1.0f},
    {110, 4.0f,  7000, "shallow",    0.35f, 0.35f, 1.0f},
    {110, 7.0f,  7000, "deep",       0.35f, 0.35f, 1.0f},
    { 85, 5.5f,  7000, "slow",       0.35f, 0.35f, 1.0f},
    {145, 5.5f,  7000, "fast",       0.35f, 0.35f, 1.0f},
    {110, 5.5f, 20000, "good",       0.35f, 0.35f, 1.0f},
};

/**
 * Test phases for validating specific input values through the production
 * CompressionTracker algorithm. Each phase runs long enough to observe
 * classification, corresponding color, and audio feedback. Each value appears
 * three times per testing session.
 *
 * Values are not hardcoded: the synthetic acceleration signal is processed by
 * the same tracker logic that runs on the vest, so classification, color, and
 * audio feedback are genuinely computed, not printed.
 */
constexpr Phase TEST_PHASES[] = {
    // Depth tests - each value 3x per session
    {110, 4.99f, 4000, "Depth 4.99cm (Too Shallow)", 0.35f, 0.35f, 1.0f},
    {110, 4.99f, 4000, "Depth 4.99cm (Too Shallow)", 0.35f, 0.35f, 1.0f},
    {110, 4.99f, 4000, "Depth 4.99cm (Too Shallow)", 0.35f, 0.35f, 1.0f},
    {110, 5.00f, 4000, "Depth 5.00cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 5.00f, 4000, "Depth 5.00cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 5.00f, 4000, "Depth 5.00cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 5.50f, 4000, "Depth 5.50cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 5.50f, 4000, "Depth 5.50cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 5.50f, 4000, "Depth 5.50cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 6.00f, 4000, "Depth 6.00cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 6.00f, 4000, "Depth 6.00cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 6.00f, 4000, "Depth 6.00cm (Target)",     0.35f, 0.35f, 1.0f},
    {110, 6.01f, 4000, "Depth 6.01cm (Too Deep)",   0.35f, 0.35f, 1.0f},
    {110, 6.01f, 4000, "Depth 6.01cm (Too Deep)",   0.35f, 0.35f, 1.0f},
    {110, 6.01f, 4000, "Depth 6.01cm (Too Deep)",   0.35f, 0.35f, 1.0f},

    // Rate tests - each value 3x per session
    { 99, 5.5f, 4000, "Rate 99cpm (Slow)",          0.35f, 0.35f, 1.0f},
    { 99, 5.5f, 4000, "Rate 99cpm (Slow)",          0.35f, 0.35f, 1.0f},
    { 99, 5.5f, 4000, "Rate 99cpm (Slow)",          0.35f, 0.35f, 1.0f},
    {100, 5.5f, 4000, "Rate 100cpm (Target)",       0.35f, 0.35f, 1.0f},
    {100, 5.5f, 4000, "Rate 100cpm (Target)",       0.35f, 0.35f, 1.0f},
    {100, 5.5f, 4000, "Rate 100cpm (Target)",       0.35f, 0.35f, 1.0f},
    {110, 5.5f, 4000, "Rate 110cpm (Target)",       0.35f, 0.35f, 1.0f},
    {110, 5.5f, 4000, "Rate 110cpm (Target)",       0.35f, 0.35f, 1.0f},
    {110, 5.5f, 4000, "Rate 110cpm (Target)",       0.35f, 0.35f, 1.0f},
    {120, 5.5f, 4000, "Rate 120cpm (Target)",       0.35f, 0.35f, 1.0f},
    {120, 5.5f, 4000, "Rate 120cpm (Target)",       0.35f, 0.35f, 1.0f},
    {120, 5.5f, 4000, "Rate 120cpm (Target)",       0.35f, 0.35f, 1.0f},
    {121, 5.5f, 4000, "Rate 121cpm (Fast)",         0.35f, 0.35f, 1.0f},
    {121, 5.5f, 4000, "Rate 121cpm (Fast)",         0.35f, 0.35f, 1.0f},
    {121, 5.5f, 4000, "Rate 121cpm (Fast)",         0.35f, 0.35f, 1.0f},

    // Recoil tests - each value 3x per session
    {110, 5.5f, 4000, "Recoil 89.9% (Bad)",         0.35f, 0.35f, 0.899f},
    {110, 5.5f, 4000, "Recoil 89.9% (Bad)",         0.35f, 0.35f, 0.899f},
    {110, 5.5f, 4000, "Recoil 89.9% (Bad)",         0.35f, 0.35f, 0.899f},
    {110, 5.5f, 4000, "Recoil 90% (OK)",            0.35f, 0.35f, 0.90f},
    {110, 5.5f, 4000, "Recoil 90% (OK)",            0.35f, 0.35f, 0.90f},
    {110, 5.5f, 4000, "Recoil 90% (OK)",            0.35f, 0.35f, 0.90f},

    // CCF tests - each value 3x per session
    {100, 5.5f, 4000, "CCF 59.9% (Low)",            0.2995f, 0.2995f, 1.0f},
    {100, 5.5f, 4000, "CCF 59.9% (Low)",            0.2995f, 0.2995f, 1.0f},
    {100, 5.5f, 4000, "CCF 59.9% (Low)",            0.2995f, 0.2995f, 1.0f},
    {100, 5.5f, 4000, "CCF 60% (Target)",           0.30f,   0.30f,   1.0f},
    {100, 5.5f, 4000, "CCF 60% (Target)",           0.30f,   0.30f,   1.0f},
    {100, 5.5f, 4000, "CCF 60% (Target)",           0.30f,   0.30f,   1.0f},
};

constexpr uint8_t PHASE_COUNT = sizeof(PHASES) / sizeof(PHASES[0]);
constexpr uint8_t TEST_PHASE_COUNT = sizeof(TEST_PHASES) / sizeof(TEST_PHASES[0]);

/**
 * Shape of one stroke cycle, as fractions of the period: push down, release, then
 * hands still at the top. A dwell at the top is typical of trained rescuers and
 * keeps consecutive strokes clearly separated.
 */
constexpr float PUSH_FRACTION    = 0.35f;
constexpr float RELEASE_FRACTION = 0.35f;

/** Hands rest on the chest this long after START before the first push. */
constexpr uint32_t START_DELAY_MS = 400;

/** Simulated calibration sample rate, matching SensorManager's 100 Hz loop. */
constexpr uint32_t SAMPLE_INTERVAL_MICROS = CPReadyConfig::SAMPLE_INTERVAL_MICROS;

/**
 * Sessions at or below this length are the manikin depth trial
 * (`CALIBRATION_RUN_DURATION_SEC`). They hold the target-depth phase for their
 * whole duration so the trial measures a stable depth instead of a cue drill.
 */
constexpr uint32_t STEADY_TRIAL_MAX_SEC = CPReadyConfig::CALIBRATION_RUN_DURATION_SEC;

/** Flash namespace kept separate from the sensor build's calibration store. */
constexpr const char* NVS_NAMESPACE = "cpready_sim";

} // namespace SimConfig

#endif // SIMULATION_CONFIG_H
