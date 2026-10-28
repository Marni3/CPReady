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
 *   0 .. P          push    x = D/2 (1 - cos(pi t / P))         P = PUSH_FRACTION * T
 *   P .. P+R        release x = D/2 (1 + cos(pi (t - P) / R))   R = RELEASE_FRACTION * T
 *   P+R .. T        hands still at the top, x = 0
 *
 * x is downward displacement in cm; the returned acceleration is x'' in g,
 * positive downward, matching the sign of SensorManager's net acceleration.
 *
 * Phases change only at a cycle boundary, where the chest is at rest at the top,
 * so the motion stays continuous across a change of rate or depth.
 */
class SyntheticVest {
public:
    /**
     * Starts a new session.
     *
     * @param nowMs       Session start timestamp.
     * @param steadyOnly  Hold the target-depth phase for the whole session.
     */
    void begin(uint32_t nowMs, bool steadyOnly) {
        _steadyOnly = steadyOnly;
        _phaseIndex = steadyOnly ? (SimConfig::PHASE_COUNT - 1) : 0;
        _sessionStartMs = nowMs;
        _cycleStartMs = (float)SimConfig::START_DELAY_MS;
        _phaseStartMs = _cycleStartMs;
    }

    /** Net vertical acceleration in g at @p nowMs. Call with increasing times. */
    float netAccelAt(uint32_t nowMs) {
        const float t = advanceTo(nowMs);
        if (t < _cycleStartMs) return 0.0f;

        const SimConfig::Phase& phase = SimConfig::PHASES[_phaseIndex];
        const float periodMs = 60000.0f / (float)phase.rateCpm;
        const float pushMs = SimConfig::PUSH_FRACTION * periodMs;
        const float releaseMs = SimConfig::RELEASE_FRACTION * periodMs;
        const float inCycleMs = t - _cycleStartMs;
        const float halfDepth = 0.5f * phase.depthCm;

        float accelCmS2 = 0.0f;
        if (inCycleMs < pushMs) {
            const float w = PI / (pushMs / 1000.0f);
            accelCmS2 = halfDepth * w * w * cosf(PI * inCycleMs / pushMs);
        } else if (inCycleMs < pushMs + releaseMs) {
            const float w = PI / (releaseMs / 1000.0f);
            accelCmS2 = -halfDepth * w * w * cosf(PI * (inCycleMs - pushMs) / releaseMs);
        }
        return accelCmS2 / CM_S2_PER_G;
    }

    /** Index of the phase active at @p nowMs, advancing the scenario. */
    uint8_t phaseIndexAt(uint32_t nowMs) {
        advanceTo(nowMs);
        return _phaseIndex;
    }

private:
    static constexpr float CM_S2_PER_G = 980.665f;

    // Moves the cycle (and, at cycle boundaries, the phase) forward to nowMs.
    // Returns nowMs relative to the session start.
    float advanceTo(uint32_t nowMs) {
        const float t = (float)(nowMs - _sessionStartMs);
        for (;;) {
            const float periodMs = 60000.0f / (float)SimConfig::PHASES[_phaseIndex].rateCpm;
            if (t < _cycleStartMs + periodMs) break;
            _cycleStartMs += periodMs;
            const bool phaseOver = !_steadyOnly &&
                _phaseIndex < SimConfig::PHASE_COUNT - 1 &&
                _cycleStartMs - _phaseStartMs >= (float)SimConfig::PHASES[_phaseIndex].durationMs;
            if (phaseOver) {
                _phaseIndex++;
                _phaseStartMs = _cycleStartMs;
            }
        }
        return t;
    }

    uint32_t _sessionStartMs = 0;
    float    _cycleStartMs = 0.0f;   // Relative to the session start
    float    _phaseStartMs = 0.0f;   // Relative to the session start
    uint8_t  _phaseIndex = 0;
    bool     _steadyOnly = false;
};

#endif // SYNTHETIC_VEST_H
