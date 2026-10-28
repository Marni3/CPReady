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
    {110, 5.5f,  5000, "warm-up"},
    {110, 4.0f,  7000, "shallow"},
    {110, 7.0f,  7000, "deep"},
    { 85, 5.5f,  7000, "slow"},
    {145, 5.5f,  7000, "fast"},
    {110, 5.5f, 20000, "good"},
};

constexpr uint8_t PHASE_COUNT = sizeof(PHASES) / sizeof(PHASES[0]);

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
