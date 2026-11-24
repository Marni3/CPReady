#ifndef SIMULATION_CONFIG_H
#define SIMULATION_CONFIG_H

#include <Arduino.h>

#include "CPReadyConfig.h"

/**
 * Pause length for the burst profile, in milliseconds.
 *
 * Each CCF demo env sets this to a different value. The burst profile runs
 * compressions for (BURST_CYCLE_MS - SIM_PAUSE_MS), then holds the chest at
 * baseline (a real hands-off pause) for SIM_PAUSE_MS, and repeats. The tracker
 * needs a gap above PAUSE_DETECTION_TIMEOUT_MS (1500 ms) to treat it as a pause,
 * which every CCF env satisfies.
 */
#ifndef SIM_PAUSE_MS
#define SIM_PAUSE_MS 0
#endif

namespace SimConfig {

struct Phase {
    uint16_t    rateCpm;     // Cadence the tracker should measure.
    float       depthCm;     // Chest displacement of each stroke.
    uint32_t    durationMs;  // Time this phase is held.
    const char* label;
    float       pushFraction;     // Fraction of cycle spent pushing down.
    float       releaseFraction;  // Fraction of cycle spent releasing.
    float       recoilFraction;   // 1.0 = full release, <1.0 = partial release.
    float       pauseMs;          // Reserved; hands-off time is a separate phase.
    float       altRateCpm;       // Alternate rate for inconsistent rhythm (0 = same).
    float       altDepthCm;       // Alternate depth for inconsistent depth (0 = same).
    float       altRecoilFraction;// Alternate recoil fraction (<0 = same as recoilFraction).
};

/**
 * One pass through every coaching cue the firmware can give, plus every recoil
 * release value the production tracker classifies:
 *
 *   warm-up  - first five seconds are silenced by the prompt grace period
 *   shallow  - depth below 5 cm                         -> "push harder"
 *   deep     - depth above 6 cm                         -> "push shallower"
 *   slow     - 85 cpm                                   -> "speed up"
 *   fast     - 145 cpm                                  -> "slow down"
 *   good     - 20 s of target-range strokes             -> "good compressions"
 *
 * The recoil sweep lives in RECOIL_PHASES and the separate `simulation_recoil_partial`
 * env. Keeping it out of this profile means the cue demo does not spend its
 * session time on recoil strokes.
 *
 * Error phases are 7 s: long enough for the six strokes or 3.5 s the tracker
 * needs to confirm an error, short enough that the 5 s prompt cooldown has not
 * expired before the next phase begins, so each error produces one prompt.
 *
 * This profile is used only by the `simulation` env (and the 15 s steady trial,
 * which holds the final "good" phase). The CCF burst/continuous profiles stay at
 * 100% recoil so their CCF values are unaffected.
 */
constexpr Phase PHASES[] = {
    {110, 5.5f,  5000, "warm-up",    0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 4.0f,  7000, "shallow",    0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 7.0f,  7000, "deep",       0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    { 85, 5.5f,  7000, "slow",       0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {145, 5.5f,  7000, "fast",       0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},

    {110, 5.5f, 20000, "good",       0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
};

constexpr uint8_t PHASE_COUNT = sizeof(PHASES) / sizeof(PHASES[0]);

/**
 * Dedicated recoil sweep for the `simulation_recoil_partial` env.
 *
 * Every release value the bench tests use, in order. Each value runs 4 s,
 * about eight strokes, so a 60 s session covers the whole sweep (~48 s) and
 * loops. The final summary is one aggregate compliance percentage; the live
 * packet carries a per-stroke Full/Partial flag.
 *
 * The push is deliberately longer than the release (0.51 vs 0.49 of the
 * 100 cpm, 5.0 cm cycle). A slower push keeps its deceleration above the
 * -0.25 g recoil threshold (~-0.237 g); the release then sets the trough:
 * 30-89.9% read Partial and 91-100% read Full with the production tracker.
 * The 89.9/90 boundary sits directly on the -0.25 g threshold, so 90 can read
 * either way; that is the nature of a per-stroke threshold, not a bug.
 */
constexpr Phase RECOIL_PHASES[] = {
    {100, 5.0f, 4000, "Recoil 30% (Very Poor)",   0.51f, 0.49f, 0.300f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 50% (Poor)",        0.51f, 0.49f, 0.500f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 70% (Marginal)",    0.51f, 0.49f, 0.700f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 80% (Marginal)",    0.51f, 0.49f, 0.800f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 85% (Borderline)",  0.51f, 0.49f, 0.850f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 89% (Just Below)",  0.51f, 0.49f, 0.890f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 89.9% (Bad)",       0.51f, 0.49f, 0.899f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 90% (OK)",          0.51f, 0.49f, 0.900f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 91% (Just Above)",  0.51f, 0.49f, 0.910f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 95% (Good)",        0.51f, 0.49f, 0.950f, 0.0f, 0.0f, -1.0f},
    {100, 5.0f, 4000, "Recoil 100% (Perfect)",    0.51f, 0.49f, 1.000f, 0.0f, 0.0f, -1.0f},
};
constexpr uint8_t RECOIL_PHASE_COUNT = sizeof(RECOIL_PHASES) / sizeof(RECOIL_PHASES[0]);

/**
 * Continuous target profile: 110 cpm, 5.5 cm, no pause. CCF computes to ~100%.
 * Used by the `simulation_ccf_100` env and by the 15 s manikin depth trial.
 */
constexpr Phase CONTINUOUS_PHASE = {
    110, 5.5f, 3600000, "Continuous target", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f,
};

/** First cycle of the random profile: a valid target stroke burst. */
constexpr Phase RANDOM_FIRST_PHASE = {
    110, 5.5f, 0, "Random", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f,
};

/**
 * Burst profile used by the `simulation_ccf_*` envs.
 *
 * One 15 s cycle: compressions for BURST_ON_MS, then the chest sits at baseline
 * with no motion for SIM_PAUSE_MS. 15 s divides 30 s, 60 s and 120 s evenly, so
 * every app duration ends on a cycle boundary. The final CCF is computed from
 * the pauses by the tracker and by the app's refinement - it is not sent as a
 * constant.
 *
 * The rest phase has depthCm = 0, so it emits no stroke signal at all.
 */
constexpr uint32_t BURST_CYCLE_MS = 15000;
constexpr uint32_t BURST_PAUSE_MS = SIM_PAUSE_MS;
constexpr uint32_t BURST_ON_MS    = BURST_CYCLE_MS - BURST_PAUSE_MS;

static_assert(SIM_PAUSE_MS < BURST_CYCLE_MS, "SIM_PAUSE_MS must be shorter than the 15 s cycle");

constexpr Phase BURST_PHASES[] = {
    {110, 5.5f, BURST_ON_MS,    "Compressions", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {110, 0.0f, BURST_PAUSE_MS, "Hands off",    0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
};
constexpr uint8_t BURST_PHASE_COUNT = sizeof(BURST_PHASES) / sizeof(BURST_PHASES[0]);

// The CCF envs must keep full recoil: a partial release changes stroke detection
// and would make the CCF values depend on recoil as well as on the pauses.
static_assert(BURST_PHASES[0].recoilFraction == 1.0f &&
              BURST_PHASES[1].recoilFraction == 1.0f,
              "CCF burst phases must use full recoil");
static_assert(CONTINUOUS_PHASE.recoilFraction == 1.0f,
              "CCF continuous phase must use full recoil");

/**
 * Test phases for validating specific input values through the production
 * CompressionTracker algorithm. Each phase runs long enough to observe
 * classification, corresponding color, and audio feedback.
 *
 * These are bench checks driven by the SIM:TEST:* serial commands, not the
 * demo mechanism. The CCF demo envs use BURST_PHASES above.
 */
constexpr Phase TEST_PHASES[] = {
    // Depth tests
    {110, 4.95f, 4000, "Depth 4.95cm (Too Shallow)", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 4.99f, 4000, "Depth 4.99cm (Too Shallow)", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 5.00f, 4000, "Depth 5.00cm (Target)",     0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 5.05f, 4000, "Depth 5.05cm (Target)",     0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 5.50f, 4000, "Depth 5.50cm (Target)",     0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 5.95f, 4000, "Depth 5.95cm (Target)",     0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 6.00f, 4000, "Depth 6.00cm (Target)",     0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 6.05f, 4000, "Depth 6.05cm (Too Deep)",   0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110, 6.01f, 4000, "Depth 6.01cm (Too Deep)",   0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},

    // Rate tests
    { 99,  5.5f, 4000, "Rate  99cpm (Slow)",          0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {100,  5.5f, 4000, "Rate 100cpm (Target)",       0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {110,  5.5f, 4000, "Rate 110cpm (Target)",       0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {120,  5.5f, 4000, "Rate 120cpm (Target)",       0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},
    {121,  5.5f, 4000, "Rate 121cpm (Fast)",         0.35f, 0.35f, 1.0f, 0.0f, 0.0f, -1.0f},

    // Recoil tests
    {110, 5.5f, 4000, "Recoil 30% (Very Poor)",    0.35f, 0.35f, 0.30f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 50% (Poor)",         0.35f, 0.35f, 0.50f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 70% (Marginal)",     0.35f, 0.35f, 0.70f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 80% (Marginal)",     0.35f, 0.35f, 0.80f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 85% (Borderline)",   0.35f, 0.35f, 0.85f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 89% (Just Below)",   0.35f, 0.35f, 0.89f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 89.9% (Bad)",        0.35f, 0.35f, 0.899f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 90% (OK)",           0.35f, 0.35f, 0.90f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 91% (Just Above)",   0.35f, 0.35f, 0.91f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 95% (Good)",         0.35f, 0.35f, 0.95f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 4000, "Recoil 100% (Perfect)",     0.35f, 0.35f, 1.00f, 0.0f, 0.0f, -1.0f},
};
constexpr uint8_t TEST_PHASE_COUNT = sizeof(TEST_PHASES) / sizeof(TEST_PHASES[0]);

/**
 * Fixed alternation used by the SIM:TEST:INCONSISTENT bench command. The
 * `simulation_inconsistent` env uses the random profile instead.
 */
constexpr Phase INCONSISTENT_PHASES[] = {
    // Depth alternates 4.0 cm / 6.0 cm on consecutive phases.
    {110, 4.0f, 800, "Inconsistent Depth 4.0/6.0cm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {110, 6.0f, 800, "Inconsistent Depth 4.0/6.0cm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {110, 4.0f, 800, "Inconsistent Depth 4.0/6.0cm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {110, 6.0f, 800, "Inconsistent Depth 4.0/6.0cm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {110, 4.0f, 800, "Inconsistent Depth 4.0/6.0cm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {110, 6.0f, 800, "Inconsistent Depth 4.0/6.0cm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},

    // Rate alternates 80 / 120 cpm on consecutive phases.
    { 80, 5.5f, 750, "Inconsistent Rate 80/120cpm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {120, 5.5f, 500, "Inconsistent Rate 80/120cpm", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},

    // Recoil alternates full / partial on consecutive phases.
    {110, 5.5f, 700, "Inconsistent Recoil Full/Partial", 0.35f, 0.35f, 1.0f, 0.0f, 0.0f, 0.0f, -1.0f},
    {110, 5.5f, 700, "Inconsistent Recoil Full/Partial", 0.35f, 0.35f, 0.5f, 0.0f, 0.0f, 0.0f, -1.0f},
};

constexpr uint8_t INCONSISTENT_PHASE_COUNT = sizeof(INCONSISTENT_PHASES) / sizeof(INCONSISTENT_PHASES[0]);

/**
 * Shape of one stroke cycle, as fractions of the period: push down, release, then
 * hands still at the top. A dwell at the top is typical of trained rescuers and
 * keeps consecutive strokes clearly separated.
 *
 * recoilFraction controls how far the chest releases toward baseline:
 *   1.0 = full release (x returns to 0), <1.0 = partial release (leaning).
 * Hands-off time is a separate phase (depth 0) in BURST_PHASES, not this field.
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
