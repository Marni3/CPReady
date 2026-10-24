#ifndef SIMULATION_CONFIG_H
#define SIMULATION_CONFIG_H

#include <Arduino.h>

#include "CPReadyConfig.h"

/**
 * Parameters for the synthetic stroke signal used by the `simulation`
 * PlatformIO environment.
 *
 * Each phase describes the physical stroke the simulated vest performs: the
 * cadence, the peak-to-peak depth it is meant to represent, and the trough of
 * the acceleration swing. The downstroke peak is derived from the depth target
 * and the trough, so the depth reading stays fixed when the trough is raised to
 * withhold recoil.
 *
 * Phases run back to back. The last phase repeats until the session ends, which
 * keeps a session that outlasts the table producing valid target-range strokes.
 */
namespace SimConfig {

struct Phase {
    uint16_t    rateCpm;     // Cadence the tracker should measure.
    float       depthCm;     // Peak-to-peak depth the stroke should represent.
    float       troughG;     // Minimum of the acceleration swing.
    uint16_t    durationMs;  // Time this phase is held.
    const char* label;
};

/**
 * Reference scalar used to convert a depth target into an acceleration
 * amplitude.
 *
 * The tracked depth is `K * delta_g * T^2`, so the swing behind a fixed depth
 * target depends on the profile's default scalar (11.2 g-s^2 for the manikin
 * profile, 9.5 for the bench profile). Using the profile default as reference
 * keeps the simulated stroke physically constant while the tracker scalar is
 * retuned, which is what makes a retune observable in the reported depth.
 */
constexpr float REFERENCE_DEPTH_K = CPReadyConfig::DEPTH_CALIBRATION_K;

/**
 * One pass through every coaching cue:
 *
 *   warm-up  - first five seconds are silenced by the prompt grace period
 *   shallow  - depth below 5 cm, full recoil            -> "push harder"
 *   deep     - depth above 6 cm, full recoil            -> "push shallower"
 *   leaning  - trough above the recoil threshold        -> "release chest completely"
 *   slow     - 85 cpm                                   -> "speed up"
 *   fast     - 145 cpm                                  -> "slow down"
 *   good     - 15 s of target-range strokes             -> "good compressions"
 *
 * Error phases are 7 s: long enough for the six strokes or 3.5 s the tracker
 * needs to confirm an error, short enough that the 5 s prompt cooldown has not
 * expired before the next phase begins, so each error produces one prompt.
 */
constexpr Phase PHASES[] = {
    {110, 5.5f, -0.73f,  5000, "warm-up"},
    {110, 4.0f, -0.50f,  7000, "shallow"},
    {110, 7.0f, -0.95f,  7000, "deep"},
    {110, 5.5f, -0.17f,  7000, "leaning"},
    { 85, 5.5f, -0.44f,  7000, "slow"},
    {145, 5.5f, -1.33f,  7000, "fast"},
    {110, 5.5f, -0.73f, 20000, "good"},
};

constexpr uint8_t PHASE_COUNT = sizeof(PHASES) / sizeof(PHASES[0]);

/**
 * Share of a stroke cycle taken by one acceleration lobe. The two lobes
 * (downstroke and recoil) each occupy this fraction, leaving the rest of the
 * cycle at the baseline. The quiet tail is what separates one downstroke from
 * the next by more than REFRACTORY_LOCKOUT_MS at every supported cadence.
 */
constexpr float LOBE_FRACTION = 0.18f;

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
