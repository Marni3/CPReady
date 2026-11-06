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

    struct Sample {
        float rawNetG;
        float dt; // elapsed time in seconds for this sample
    };

    void reset() { count = 0; }

    static constexpr float nominalDt() {
        return 1.0f / (float)CPReadyConfig::SAMPLING_RATE_HZ;
    }

    void push(float rawNetG, float dtSeconds = nominalDt()) {
        // Guard against abnormal dt (e.g. post-pause or clock glitch)
        if (dtSeconds <= 0.001f || dtSeconds > 0.050f) {
            dtSeconds = nominalDt();
        }
        buffer[count % CAPACITY] = { rawNetG, dtSeconds };
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
     *
     * Double integration uses discrete Riemann sums with each sample's true dt,
     * so depth is invariant to sample rate fluctuations and loop jitter.
     */
    bool closedCycleDepthCm(uint32_t from, uint32_t to, float& outCm) const {
        if (!available(from, to) || (to - from) < MIN_CYCLE_SAMPLES) return false;

        float totalTime = 0.0f;
        float weightedASum = 0.0f;
        for (uint32_t i = from; i < to; i++) {
            const Sample& s = atSample(i);
            totalTime += s.dt;
            weightedASum += s.rawNetG * s.dt;
        }
        if (totalTime <= 0.05f) return false;
        const float meanA = weightedASum / totalTime;

        float v = 0.0f;
        float weightedVSum = 0.0f;
        for (uint32_t i = from; i < to; i++) {
            const Sample& s = atSample(i);
            v += (s.rawNetG - meanA) * s.dt;
            weightedVSum += v * s.dt;
        }
        const float meanV = weightedVSum / totalTime;

        v = 0.0f;
        float x = 0.0f, lo = 0.0f, hi = 0.0f;
        for (uint32_t i = from; i < to; i++) {
            const Sample& s = atSample(i);
            v += (s.rawNetG - meanA) * s.dt;
            x += (v - meanV) * s.dt;
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
     * REST_LIMIT_G (0.15g) allows normal human resting hand tremor and manikin spring
     * noise without declaring motion.
     */
    bool fromRestDepthCm(uint32_t onset, uint32_t to, float& outCm) const {
        if (to <= onset || to > count) return false;
        uint32_t start = onset >= PRE_ONSET_SAMPLES ? onset - PRE_ONSET_SAMPLES : 0;
        if (start < oldest()) start = oldest();
        if (!available(start, to)) return false;

        uint32_t restFrom = start >= REST_SAMPLES ? start - REST_SAMPLES : 0;
        if (restFrom < oldest()) restFrom = oldest();
        if (start - restFrom < MIN_REST_SAMPLES) return false;

        float restMin = atSample(restFrom).rawNetG;
        float restMax = restMin;
        for (uint32_t i = restFrom + 1; i < start; i++) {
            float g = atSample(i).rawNetG;
            if (g < restMin) restMin = g;
            if (g > restMax) restMax = g;
        }
        if ((restMax - restMin) > REST_LIMIT_G) return false;

        return closedCycleDepthCm(start, to, outCm);
    }

    // Accessors for testing and debugging
    const Sample& atSample(uint32_t index) const { return buffer[index % CAPACITY]; }
    float at(uint32_t index) const { return buffer[index % CAPACITY].rawNetG; }
    float atDt(uint32_t index) const { return buffer[index % CAPACITY].dt; }

private:
    static constexpr float G_TO_CM_S2 = 980.665f;
    static constexpr uint32_t MIN_CYCLE_SAMPLES = 20;  // 0.2 s; shorter is not a stroke cycle
    static constexpr uint32_t PRE_ONSET_SAMPLES = 8;   // Push start precedes the filtered trigger
    static constexpr uint32_t REST_SAMPLES = 8;        // Resting level before the push (80 ms)
    static constexpr uint32_t MIN_REST_SAMPLES = 5;    // Fewer cannot show that the chest was still
    static constexpr float REST_LIMIT_G = 0.15f;       // Allows human hand resting tremor without falsely rejecting stillness

    Sample buffer[CAPACITY];
    uint32_t count = 0;

    uint32_t oldest() const { return count > CAPACITY ? count - CAPACITY : 0; }
    bool available(uint32_t from, uint32_t to) const {
        return from < to && to <= count && from >= oldest();
    }
};

#endif // DEPTH_ESTIMATOR_H
