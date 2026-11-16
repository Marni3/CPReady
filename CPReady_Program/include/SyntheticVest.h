#ifndef SYNTHETIC_VEST_H
#define SYNTHETIC_VEST_H

#include <Arduino.h>

#include "CPReadyConfig.h"
#include "SimulationConfig.h"

/**
 * Acceleration source that stands in for the chest/base MPU-6050 pair.
 *
 * Each stroke is a physical chest motion, and the signal is its exact second
 * derivative, so the production tracker measures the simulated depth the same
 * way it measures the vest. One cycle of period T:
 *
 *   0 .. P          push    x = D/2 (1 - cos(pi t / P))         P = pushFraction * T
 *   P .. P+R        release x moves back toward baseline           R = releaseFraction * T
 *   rest            no motion at all (a separate depth-0 phase)
 *
 * x is downward displacement in cm; the returned acceleration is x'' in g,
 * positive downward, matching the sign of SensorManager's net acceleration.
 *
 * Profiles:
 *   - phase array (PHASES, BURST_PHASES, TEST_PHASES): the array loops until the
 *     session ends. A depth-0 phase emits no motion, which is a real hands-off
 *     pause for the CCF envs.
 *   - random: every cycle picks new rate/depth/recoil/duty values and random
 *     hands-off gaps, including invalid compressions. The first cycles always
 *     produce target strokes so the session has at least one compression.
 */
class SyntheticVest {
public:
    /**
     * Starts a new session from a phase array.
     *
     * @param nowMs       Session start timestamp.
     * @param steadyOnly  Hold the last (target-depth) phase for the whole session.
     * @param phases      Phase array to use (defaults to SimConfig::PHASES).
     * @param phaseCount  Number of entries in @p phases.
     */
    void begin(uint32_t nowMs, bool steadyOnly,
               const SimConfig::Phase* phases = SimConfig::PHASES,
               uint8_t phaseCount = SimConfig::PHASE_COUNT) {
        _randomMode = false;
        _steadyOnly = steadyOnly;
        _phases = phases;
        _phaseCount = phaseCount;
        _phaseIndex = steadyOnly ? (uint8_t)(_phaseCount - 1) : 0;
        _sessionStartMs = nowMs;
        _cycleStartMs = (float)SimConfig::START_DELAY_MS;
        _phaseStartMs = _cycleStartMs;
        _cycleCount = 0;
        _restUntilMs = 0.0f;
        _effective = _phases[_phaseIndex];
    }

    /** Starts the random inconsistent profile (fresh seed every session). */
    void beginRandom(uint32_t nowMs) {
        _randomMode = true;
        _steadyOnly = false;
        _phases = SimConfig::PHASES;
        _phaseCount = SimConfig::PHASE_COUNT;
        _phaseIndex = 0;
        _sessionStartMs = nowMs;
        _cycleStartMs = (float)SimConfig::START_DELAY_MS;
        _phaseStartMs = _cycleStartMs;
        _cycleCount = 0;
        _restUntilMs = 0.0f;
        _effective = SimConfig::RANDOM_FIRST_PHASE;
        randomSeed((uint32_t)micros() ^ (uint32_t)millis());
    }

    /** Net vertical acceleration in g at @p nowMs. Call with increasing times. */
    float netAccelAt(uint32_t nowMs) {
        const float t = advanceTo(nowMs);
        if (t < _cycleStartMs) return 0.0f;
        if (_randomMode && t < _restUntilMs) return 0.0f;

        const SimConfig::Phase& phase = _effective;
        const float periodMs = 60000.0f / (float)phase.rateCpm;
        const float pushMs = phase.pushFraction * periodMs;
        const float releaseMs = phase.releaseFraction * periodMs;
        const float pauseMs = phase.pauseMs;
        const float inCycleMs = t - _cycleStartMs;
        const float halfDepth = 0.5f * phase.depthCm;

        float accelCmS2 = 0.0f;
        if (inCycleMs < pushMs) {
            // Push phase: chest moves down (positive acceleration during downstroke)
            const float w = PI / (pushMs / 1000.0f);
            accelCmS2 = halfDepth * w * w * cosf(PI * inCycleMs / pushMs);
        } else if (inCycleMs < pushMs + releaseMs) {
            // Release phase: chest moves back toward baseline.
            const float w = PI / (releaseMs / 1000.0f);
            const float releaseEnd = halfDepth * (1.0f - phase.recoilFraction);
            const float releaseAmp = halfDepth - releaseEnd;
            accelCmS2 = -releaseAmp * w * w * cosf(PI * (inCycleMs - pushMs) / releaseMs);
        } else if (inCycleMs < pushMs + releaseMs + pauseMs) {
            // Reserved pause window; all current phases set pauseMs = 0.
            accelCmS2 = 0.0f;
        }
        // Dwell phase (remaining time): x is constant, acceleration = 0.
        return accelCmS2 / CM_S2_PER_G;
    }

    /** Index of the phase active at @p nowMs, advancing the scenario. */
    uint8_t phaseIndexAt(uint32_t nowMs) {
        advanceTo(nowMs);
        return _phaseIndex;
    }

    /** Parameters of the cycle currently being generated. */
    const SimConfig::Phase& currentPhase() const { return _effective; }

private:
    static constexpr float CM_S2_PER_G = 980.665f;

    // Alternate parameters change on odd cycles when the phase defines them.
    SimConfig::Phase effectivePhase(const SimConfig::Phase& base) const {
        if (base.altRateCpm > 0.0f && (_cycleCount % 2u) == 1u) {
            SimConfig::Phase p = base;
            p.rateCpm = (uint16_t)base.altRateCpm;
            if (base.altDepthCm > 0.0f) p.depthCm = base.altDepthCm;
            if (base.altRecoilFraction >= 0.0f) p.recoilFraction = base.altRecoilFraction;
            return p;
        }
        return base;
    }

    // Moves the cycle, and at cycle boundaries the phase, forward to nowMs.
    float advanceTo(uint32_t nowMs) {
        const float t = (float)(nowMs - _sessionStartMs);
        if (_randomMode) {
            advanceRandom(t);
            return t;
        }

        for (;;) {
            const SimConfig::Phase& base = _phases[_phaseIndex];
            const SimConfig::Phase eff = effectivePhase(base);
            const float periodMs = 60000.0f / (float)eff.rateCpm;
            if (t < _cycleStartMs + periodMs) break;

            _cycleStartMs += periodMs;
            _cycleCount++;

            // Loop the array. The last phase wraps to the first, so a profile
            // keeps running for 30 s, 120 s or an unlimited session.
            if (!_steadyOnly &&
                _cycleStartMs - _phaseStartMs >= (float)_phases[_phaseIndex].durationMs) {
                _phaseIndex = (uint8_t)((_phaseIndex + 1 < _phaseCount) ? (_phaseIndex + 1) : 0);
                _phaseStartMs = _cycleStartMs;
            }
            _effective = effectivePhase(_phases[_phaseIndex]);
        }
        return t;
    }

    // Random profile: advance cycles, occasionally insert a real hands-off gap,
    // and pick new per-cycle parameters.
    void advanceRandom(float t) {
        for (;;) {
            const float periodMs = 60000.0f / (float)_effective.rateCpm;
            if (t < _cycleStartMs + periodMs) break;

            _cycleStartMs += periodMs;
            _cycleCount++;

            if (t < _restUntilMs) continue;   // still in a hands-off gap

            // Keep the first three cycles valid so the session always has
            // compressions before any random pause or invalid stroke.
            if (_cycleCount < 3) continue;

            if (random(0, 100) < 25) {
                _restUntilMs = _cycleStartMs + (float)random(200, 6001);
                continue;
            }
            _effective = randomPhase();
        }
    }

    SimConfig::Phase randomPhase() {
        SimConfig::Phase p = SimConfig::RANDOM_FIRST_PHASE;
        p.label = "Random";

        const long rateRoll = random(0, 100);
        if (rateRoll < 10) {
            p.rateCpm = (uint16_t)random(200, 251);      // sub-300 ms bounce
        } else if (rateRoll < 35) {
            p.rateCpm = (uint16_t)random(40, 81);        // too slow
        } else {
            p.rateCpm = (uint16_t)random(90, 131);       // near target
        }

        const long depthRoll = random(0, 100);
        if (depthRoll < 10) {
            p.depthCm = 0.0f;                            // skipped stroke
        } else if (depthRoll < 30) {
            p.depthCm = random(5, 20) / 10.0f;           // 0.5-1.9 cm
        } else if (depthRoll < 55) {
            p.depthCm = random(20, 50) / 10.0f;          // 2.0-4.9 cm
        } else if (depthRoll < 85) {
            p.depthCm = random(50, 61) / 10.0f;          // 5.0-6.0 cm
        } else {
            p.depthCm = random(61, 96) / 10.0f;          // 6.1-9.5 cm
        }

        p.recoilFraction = (random(0, 100) < 25)
            ? random(20, 61) / 100.0f                     // partial release
            : random(60, 101) / 100.0f;                   // near/full release
        p.pushFraction = random(10, 51) / 100.0f;
        p.releaseFraction = random(10, 51) / 100.0f;
        p.pauseMs = 0.0f;
        p.altRateCpm = 0.0f;
        p.altDepthCm = 0.0f;
        p.altRecoilFraction = -1.0f;
        return p;
    }

    const SimConfig::Phase* _phases = SimConfig::PHASES;
    uint8_t                 _phaseCount = SimConfig::PHASE_COUNT;
    uint32_t                _sessionStartMs = 0;
    float                   _cycleStartMs = 0.0f;   // Relative to the session start
    float                   _phaseStartMs = 0.0f;   // Relative to the session start
    float                   _restUntilMs = 0.0f;    // Random-profile hands-off end
    uint8_t                 _phaseIndex = 0;
    uint32_t                _cycleCount = 0;
    SimConfig::Phase        _effective;             // Effective phase (may alternate)
    bool                    _steadyOnly = false;
    bool                    _randomMode = false;
};

#endif // SYNTHETIC_VEST_H
