#ifndef DEPTH_ESTIMATOR_H
#define DEPTH_ESTIMATOR_H

#include <stdint.h>
#include <math.h>
#include "CPReadyConfig.h"

/**
 * Compression depth from the raw net acceleration, by integrating each stroke twice.
 *
 * The previous estimate, K * (a_max - a_min) * T^2, is exact only for a pure sine.
 * Real strokes have sharp turnarounds that inflate the acceleration peaks without
 * adding depth, so the same 5.5 cm push read anywhere from 1.9 to 4.2 cm depending on
 * technique, and no single K could correct it. Integrating the acceleration is exact
 * for any stroke shape. Drift cannot build up because every stroke is solved on its
 * own window, with boundary conditions instead of open-ended integration
 * (ALGORITHM_RESEARCH.md section 3.3).
 *
 * The estimator keeps the last CAPACITY samples. The tracker pushes one raw sample
 * per 100 Hz tick and asks for a depth when a stroke completes, by sample index.
 */
class DepthEstimator {
public:
    // 2.56 s at 100 Hz: one stroke cycle up to the pause timeout (1.5 s), or a
    // first stroke (up to the 2 s stroke watchdog) plus its resting lead-in.
    static constexpr uint16_t CAPACITY = 256;

    void reset() { count = 0; }

    void push(float rawNetG) {
        buffer[count % CAPACITY] = rawNetG;
        count++;
    }

    // Index the next pushed sample will get; the latest sample is sampleCount() - 1.
    uint32_t sampleCount() const { return count; }

    /**
     * Depth over one full stroke cycle, samples [from, to).
     *
     * Over a whole cycle the chest ends where it started, so the mean acceleration and
     * the mean velocity are both zero. Removing the mean acceleration cancels sensor
     * offset and tilt leakage; removing the mean velocity supplies the unknown velocity
     * at the window edge. Neither edge needs to be at rest, which is why the window can
     * run between two stroke completions (mid-upstroke).
     */
    bool closedCycleDepthCm(uint32_t from, uint32_t to, float& outCm) const {
        if (!available(from, to) || (to - from) < MIN_CYCLE_SAMPLES) return false;
        const float n = (float)(to - from);

        float meanA = 0.0f;
        for (uint32_t i = from; i < to; i++) meanA += at(i);
        meanA /= n;

        float v = 0.0f;
        float sumV = 0.0f;
        for (uint32_t i = from; i < to; i++) {
            v += (at(i) - meanA) * DT;
            sumV += v;
        }
        const float meanV = sumV / n;

        v = 0.0f;
        float x = 0.0f, lo = 0.0f, hi = 0.0f;
        for (uint32_t i = from; i < to; i++) {
            v += (at(i) - meanA) * DT;
            x += (v - meanV) * DT;
            if (x < lo) lo = x;
            if (x > hi) hi = x;
        }
        outCm = (hi - lo) * G_TO_CM_S2;
        return true;
    }

    /**
     * Depth of a stroke that starts from rest: the first stroke of a session or the
     * first after a pause. There is no previous cycle to close against, but the chest
     * is still before the push, so velocity and displacement start at zero. The window
     * opens PRE_ONSET_SAMPLES before the detector fired, because the filtered signal
     * crosses the threshold after the push has begun. The resting level just before
     * that is taken as zero acceleration.
     *
     * Returns false when the chest was not actually still before the push (for example
     * the previous stroke went undetected): integrating from a moving start gives a
     * wrong depth, and no depth is better than a wrong one.
     */
    bool fromRestDepthCm(uint32_t onset, uint32_t to, float& outCm) const {
        if (to <= onset || to > count) return false;
        uint32_t start = onset >= PRE_ONSET_SAMPLES ? onset - PRE_ONSET_SAMPLES : 0;
        if (start < oldest()) start = oldest();
        if (!available(start, to)) return false;

        uint32_t restFrom = start >= REST_SAMPLES ? start - REST_SAMPLES : 0;
        if (restFrom < oldest()) restFrom = oldest();
        if (start - restFrom < MIN_REST_SAMPLES) return false;
        float baseline = 0.0f;
        for (uint32_t i = restFrom; i < start; i++) baseline += at(i);
        baseline /= (float)(start - restFrom);
        for (uint32_t i = restFrom; i < start; i++) {
            if (fabsf(at(i) - baseline) > REST_LIMIT_G) return false;
        }

        float v = 0.0f, x = 0.0f, lo = 0.0f, hi = 0.0f;
        for (uint32_t i = start; i < to; i++) {
            v += (at(i) - baseline) * DT;
            x += v * DT;
            if (x < lo) lo = x;
            if (x > hi) hi = x;
        }
        outCm = (hi - lo) * G_TO_CM_S2;
        return true;
    }

private:
    static constexpr float DT = 1.0f / (float)CPReadyConfig::SAMPLING_RATE_HZ;
    static constexpr float G_TO_CM_S2 = 980.665f;
    static constexpr uint32_t MIN_CYCLE_SAMPLES = 20;  // 0.2 s; shorter is not a stroke cycle
    static constexpr uint32_t PRE_ONSET_SAMPLES = 20;  // Push start precedes the filtered trigger
    static constexpr uint32_t REST_SAMPLES = 20;       // Resting level before the push
    static constexpr uint32_t MIN_REST_SAMPLES = 5;    // Fewer cannot show that the chest was still
    static constexpr float REST_LIMIT_G = 0.05f;       // About 10x MPU-6050 noise: larger means motion

    float buffer[CAPACITY];
    uint32_t count = 0;

    uint32_t oldest() const { return count > CAPACITY ? count - CAPACITY : 0; }
    bool available(uint32_t from, uint32_t to) const {
        return from < to && to <= count && from >= oldest();
    }
    float at(uint32_t index) const { return buffer[index % CAPACITY]; }
};

#endif // DEPTH_ESTIMATOR_H
