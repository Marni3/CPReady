#ifndef SYNTHETIC_VEST_H
#define SYNTHETIC_VEST_H

#include <Arduino.h>

#include "CPReadyConfig.h"
#include "SimulationConfig.h"

/**
 * Acceleration source that stands in for the chest/base MPU-6050 pair.
 *
 * Each stroke is a pulse train rather than a sine, because the tracker closes a
 * stroke when the recoil returns to the baseline and refuses a new downstroke
 * within REFRACTORY_LOCKOUT_MS of that point. A sine returns to the baseline
 * and immediately climbs into the next peak, so every other stroke would be
 * rejected. One cycle is therefore:
 *
 *   0 .. L      positive lobe   (downstroke)  peak    = troughG + 2A
 *   L .. 2L     negative lobe   (recoil)      trough  = troughG
 *   2L .. T     baseline        (hands reset)
 *
 *   L = LOBE_FRACTION * T
 *   T = 60 / rateCpm
 *   A = depthCm / (2 * referenceK * T^2)
 *
 * `peak - trough` is then `depthCm / (referenceK * T^2)`, so the production
 * depth formula (`K * delta_g * T^2`) reports the intended depth. Keeping the
 * trough explicit lets a phase miss the recoil threshold without changing the
 * depth the tracker computes.
 *
 * The tracker derives cadence from the interval between consecutive stroke
 * completions, so a phase change has to respect that interval or the first
 * stroke of the new phase would be reported at the wrong rate and depth. A
 * change is therefore anchored to the next completion of the running phase and
 * starts `0.64 * T_next` afterwards, which puts the following completion
 * exactly `T_next` later. The signal stays at the baseline during that window,
 * where a normal stroke's quiet section already sits.
 */
class SyntheticVest {
public:
    /**
     * Starts a new session.
     *
     * @param nowMs       Session start timestamp.
     * @param referenceK  Profile default scalar used to size the swing.
     * @param steadyOnly  Hold the target-depth phase for the whole session.
     */
    void begin(uint32_t nowMs, float referenceK, bool steadyOnly) {
        _phaseIndex = 0;
        _holdFromMs = 0;
        _switchAtMs = 0;
        _referenceK = referenceK > 0.0f ? referenceK : SimConfig::REFERENCE_DEPTH_K;
        _steadyOnly = steadyOnly;

        // The tracker seeds its stroke clock at session start and refuses a
        // downstroke for REFRACTORY_LOCKOUT_MS. Delaying the first cycle by the
        // quiet part of a stroke places the first completion one full period
        // after that seed, so the opening reading is a normal cadence instead
        // of the shortened interval the lockout would otherwise produce.
        const SimConfig::Phase& firstPhase =
            SimConfig::PHASES[steadyOnly ? (SimConfig::PHASE_COUNT - 1) : 0];
        const float firstPeriodMs = (60.0f / (float)firstPhase.rateCpm) * 1000.0f;

        _signalStartMs = nowMs + (uint32_t)((1.0f - 2.0f * SimConfig::LOBE_FRACTION) * firstPeriodMs);
        _phaseStartMs = _signalStartMs;
    }

    /** Net acceleration in g at @p nowMs. Advances the scenario if due. */
    float netAccelAt(uint32_t nowMs) {
        advanceIfDue(nowMs);

        if (nowMs < _signalStartMs) return 0.0f;
        if (_switchAtMs != 0 && nowMs >= _holdFromMs) return 0.0f;

        const SimConfig::Phase& phase = SimConfig::PHASES[currentPhaseIndex()];

        const float periodSec = 60.0f / (float)phase.rateCpm;
        const float periodMs = periodSec * 1000.0f;
        const float lobeMs = periodMs * SimConfig::LOBE_FRACTION;

        const float halfSwingG = phase.depthCm / (2.0f * _referenceK * periodSec * periodSec);
        const float peakG = phase.troughG + 2.0f * halfSwingG;

        const float phaseElapsedMs = (float)(nowMs - _phaseStartMs);
        const float cycleMs = fmodf(phaseElapsedMs, periodMs);

        if (cycleMs < lobeMs) {
            return peakG * sinf(PI * cycleMs / lobeMs);
        }
        if (cycleMs < 2.0f * lobeMs) {
            return phase.troughG * sinf(PI * (cycleMs - lobeMs) / lobeMs);
        }
        return 0.0f;
    }

    /** Phase currently being played. */
    uint8_t currentPhaseIndex() const {
        return _steadyOnly ? (SimConfig::PHASE_COUNT - 1) : _phaseIndex;
    }

    /** Index of the phase active at @p nowMs, advancing the scenario. */
    uint8_t phaseIndexAt(uint32_t nowMs) {
        advanceIfDue(nowMs);
        return currentPhaseIndex();
    }

private:
    void advanceIfDue(uint32_t nowMs) {
        if (_steadyOnly) return;
        if (nowMs < _signalStartMs) return;

        if (_switchAtMs != 0) {
            if (nowMs < _switchAtMs) return;
            _phaseIndex++;
            _phaseStartMs = nowMs;
            _switchAtMs = 0;
            _holdFromMs = 0;
            return;
        }

        if (_phaseIndex >= SimConfig::PHASE_COUNT - 1) return;

        const SimConfig::Phase& oldPhase = SimConfig::PHASES[_phaseIndex];
        const uint32_t elapsedMs = nowMs - _phaseStartMs;
        if (elapsedMs < oldPhase.durationMs) return;

        const float oldPeriodMs = (60.0f / (float)oldPhase.rateCpm) * 1000.0f;
        const float lobeEndMs = 2.0f * SimConfig::LOBE_FRACTION * oldPeriodMs;
        const float cycleMs = fmodf((float)elapsedMs, oldPeriodMs);

        // The change is scheduled from the next stroke completion, not from the
        // deadline, so the completion that follows the change is exactly one
        // new period later and the tracker reports the new cadence and depth.
        const float untilCompletionMs = (cycleMs < lobeEndMs)
            ? (lobeEndMs - cycleMs)
            : (oldPeriodMs - cycleMs + lobeEndMs);

        const SimConfig::Phase& nextPhase = SimConfig::PHASES[_phaseIndex + 1];
        const float nextPeriodMs = (60.0f / (float)nextPhase.rateCpm) * 1000.0f;
        const float switchAtMs = (float)nowMs + untilCompletionMs
            + (1.0f - 2.0f * SimConfig::LOBE_FRACTION) * nextPeriodMs;

        _holdFromMs = nowMs + (uint32_t)untilCompletionMs;
        _switchAtMs = (uint32_t)switchAtMs;
    }

    uint32_t _signalStartMs = 0;
    uint32_t _phaseStartMs = 0;
    uint32_t _holdFromMs = 0;
    uint32_t _switchAtMs = 0;
    uint8_t  _phaseIndex = 0;
    float    _referenceK = SimConfig::REFERENCE_DEPTH_K;
    bool     _steadyOnly = false;
};

#endif // SYNTHETIC_VEST_H
