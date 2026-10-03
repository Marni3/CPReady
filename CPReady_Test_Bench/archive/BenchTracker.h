#ifndef BENCH_TRACKER_H
#define BENCH_TRACKER_H

#include <Arduino.h>
#include "BenchConfig.h"

enum class BenchStrokeState : uint8_t {
    WAITING_FOR_DOWNSLICK = 0,
    COMPRESSING = 1,
    RECOILING = 2
};

struct BenchReading {
    float    rate_cpm;
    float    depth_cm;
    bool     recoil_complete;
    float    ccf_percent;
    uint32_t elapsed_seconds;
    uint16_t stroke_count;
    float    current_accel;
};

struct BenchSummary {
    float    avg_rate_cpm;
    float    avg_depth_cm;
    float    recoil_compliance_percent;
    float    final_ccf_percent;
    uint16_t total_compressions;
    uint16_t total_duration_sec;
};

/**
 * Kinematic Compression Engine
 * Ported directly from CPReady production ground truth (CompressionTracker.h).
 */
class BenchTracker {
private:
    BenchStrokeState state;
    BenchReading reading;
    BenchSummary lastSummary;

    float peakAccel;
    float troughAccel;
    uint32_t lastStrokePeakMillis;
    uint32_t strokeStartMillis;
    uint32_t sessionStartMillis;
    uint32_t totalActiveCompressionMillis;
    uint32_t lastCompressionDetectedMillis;

    // Cumulative aggregators
    uint32_t totalStrokeCount;
    uint32_t goodRecoilCount;
    float    cumulativeDepthSum;
    float    cumulativeRateSum;

public:
    BenchTracker() : state(BenchStrokeState::WAITING_FOR_DOWNSLICK) {
        reset();
    }

    void reset() {
        state = BenchStrokeState::WAITING_FOR_DOWNSLICK;
        peakAccel = 0.0f;
        troughAccel = 0.0f;
        lastStrokePeakMillis = 0;
        strokeStartMillis = 0;
        sessionStartMillis = 0;
        totalActiveCompressionMillis = 0;
        lastCompressionDetectedMillis = 0;

        totalStrokeCount = 0;
        goodRecoilCount = 0;
        cumulativeDepthSum = 0.0f;
        cumulativeRateSum = 0.0f;

        reading = {0.0f, 0.0f, true, 0.0f, 0, 0, 0.0f};
        lastSummary = {0.0f, 0.0f, 100.0f, 0.0f, 0, 0};
    }

    void startSession(uint32_t currentMillis) {
        reset();
        sessionStartMillis = currentMillis;
    }

    bool isSessionActive() const {
        return sessionStartMillis > 0;
    }

    // Called on every 100 Hz filtered sample
    // Returns true when a full compression cycle completes
    bool processSample(float netAccel, uint32_t currentMillis, const BenchSettings& cfg) {
        reading.current_accel = netAccel;

        if (sessionStartMillis == 0) return false;

        reading.elapsed_seconds = (currentMillis - sessionStartMillis) / 1000;

        switch (state) {
            case BenchStrokeState::WAITING_FOR_DOWNSLICK:
                if (netAccel > cfg.compressionThreshG && 
                    (currentMillis - lastStrokePeakMillis > cfg.refractoryMs)) {
                    state = BenchStrokeState::COMPRESSING;
                    strokeStartMillis = currentMillis;
                    peakAccel = netAccel;
                    troughAccel = netAccel;
                }
                break;

            case BenchStrokeState::COMPRESSING:
                if (netAccel > peakAccel) {
                    peakAccel = netAccel;
                }
                // Transition to recoil when acceleration starts swinging downward/negative
                if (netAccel < 0.0f) {
                    state = BenchStrokeState::RECOILING;
                    troughAccel = netAccel;
                }
                break;

            case BenchStrokeState::RECOILING:
                if (netAccel < troughAccel) {
                    troughAccel = netAccel;
                }
                // When net acceleration crosses back upward near zero (-0.05g), stroke is complete
                if (netAccel >= -0.05f) {
                    uint32_t cyclePeriodMs = currentMillis - lastStrokePeakMillis;
                    lastStrokePeakMillis = currentMillis;
                    lastCompressionDetectedMillis = currentMillis;

                    // 1. Instantaneous Compression Rate
                    if (cyclePeriodMs > 0 && cyclePeriodMs < 2000) {
                        reading.rate_cpm = 60000.0f / (float)cyclePeriodMs;
                        totalActiveCompressionMillis += cyclePeriodMs;
                    }

                    // 2. Algebraic Harmonic Depth: D = K * a_pp * T^2
                    float peakToPeakAccel = peakAccel - troughAccel;
                    float cyclePeriodSec = (float)cyclePeriodMs / 1000.0f;
                    reading.depth_cm = cfg.depthK * (peakToPeakAccel * cyclePeriodSec * cyclePeriodSec);

                    // Physical limits clamp (0.0 to 10.0 cm)
                    if (reading.depth_cm < 0.0f)  reading.depth_cm = 0.0f;
                    if (reading.depth_cm > 10.0f) reading.depth_cm = 10.0f;

                    // 3. Chest Recoil Verification
                    reading.recoil_complete = (troughAccel < cfg.recoilThreshG);

                    // 4. Chest Compression Fraction (CCF)
                    uint32_t totalSessionTime = currentMillis - sessionStartMillis;
                    if (totalSessionTime > 0) {
                        reading.ccf_percent = ((float)totalActiveCompressionMillis / (float)totalSessionTime) * 100.0f;
                        if (reading.ccf_percent > 100.0f) reading.ccf_percent = 100.0f;
                    }

                    // 5. Accumulate Session Statistics
                    totalStrokeCount++;
                    reading.stroke_count = (uint16_t)totalStrokeCount;
                    if (reading.recoil_complete) {
                        goodRecoilCount++;
                    }
                    cumulativeDepthSum += reading.depth_cm;
                    cumulativeRateSum  += reading.rate_cpm;

                    state = BenchStrokeState::WAITING_FOR_DOWNSLICK;
                    return true;
                }
                break;
        }

        return false;
    }

    BenchSummary finalizeSession(uint32_t endMillis) {
        BenchSummary s;
        s.total_compressions = (uint16_t)totalStrokeCount;
        s.total_duration_sec = sessionStartMillis > 0 ? (uint16_t)((endMillis - sessionStartMillis) / 1000) : 0;

        if (totalStrokeCount > 0) {
            s.avg_depth_cm = cumulativeDepthSum / (float)totalStrokeCount;
            s.avg_rate_cpm = cumulativeRateSum / (float)totalStrokeCount;
            s.recoil_compliance_percent = ((float)goodRecoilCount / (float)totalStrokeCount) * 100.0f;
        } else {
            s.avg_depth_cm = 0.0f;
            s.avg_rate_cpm = 0.0f;
            s.recoil_compliance_percent = 100.0f;
        }

        s.final_ccf_percent = reading.ccf_percent;
        lastSummary = s;
        sessionStartMillis = 0; // mark stopped
        return s;
    }

    const BenchReading& getReading() const { return reading; }
    const BenchSummary& getLastSummary() const { return lastSummary; }
};

#endif // BENCH_TRACKER_H
