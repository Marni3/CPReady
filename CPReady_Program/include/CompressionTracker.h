#ifndef COMPRESSION_TRACKER_H
#define COMPRESSION_TRACKER_H

#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"

class CompressionTracker {
private:
    StrokeState state;
    CPRReading reading;
    float peakAccel;
    float troughAccel;
    uint32_t lastStrokePeakMillis;
    uint32_t strokeStartMillis;
    uint32_t sessionStartMillis;
    uint32_t totalActiveCompressionMillis;
    uint32_t lastCompressionDetectedMillis;

public:
    CompressionTracker() : state(StrokeState::WAITING_FOR_DOWNSLICK) {
        reset();
    }

    void reset() {
        state = StrokeState::WAITING_FOR_DOWNSLICK;
        peakAccel = 0.0f;
        troughAccel = 0.0f;
        lastStrokePeakMillis = 0;
        strokeStartMillis = 0;
        sessionStartMillis = 0;
        totalActiveCompressionMillis = 0;
        lastCompressionDetectedMillis = 0;
        reading = {0.0f, 0.0f, true, 0.0f, 0};
    }

    void startSession(uint32_t currentMillis) {
        reset();
        sessionStartMillis = currentMillis;
    }

    // Called for each 100 Hz sample. Returns true whenever a stroke completes.
    bool processSample(float netAccel, uint32_t currentMillis) {
        if (sessionStartMillis == 0) return false;

        reading.elapsed_seconds = (currentMillis - sessionStartMillis) / 1000;

        switch (state) {
            case StrokeState::WAITING_FOR_DOWNSLICK:
                if (netAccel > CPReadyConfig::COMPRESSION_START_THRESHOLD_G && 
                    (currentMillis - lastStrokePeakMillis > CPReadyConfig::REFRACTORY_LOCKOUT_MS)) {
                    state = StrokeState::COMPRESSING;
                    strokeStartMillis = currentMillis;
                    peakAccel = netAccel;
                    troughAccel = netAccel;
                }
                break;

            case StrokeState::COMPRESSING:
                if (netAccel > peakAccel) {
                    peakAccel = netAccel;
                }
                // Transition to recoil when acceleration peaks and starts swinging negative
                if (netAccel < 0.0f) {
                    state = StrokeState::RECOILING;
                    troughAccel = netAccel;
                }
                break;

            case StrokeState::RECOILING:
                if (netAccel < troughAccel) {
                    troughAccel = netAccel;
                }
                // When net acceleration crosses back upward near zero, stroke is finished
                if (netAccel >= CPReadyConfig::STROKE_FINISH_THRESHOLD_G) {
                    uint32_t cyclePeriodMs = currentMillis - lastStrokePeakMillis;
                    lastStrokePeakMillis = currentMillis;
                    lastCompressionDetectedMillis = currentMillis;

                    // 1. Compute Instantaneous Rate
                    if (cyclePeriodMs > 0 && cyclePeriodMs < 2000) {
                        reading.rate_cpm = 60000.0f / (float)cyclePeriodMs;
                        totalActiveCompressionMillis += cyclePeriodMs;
                    }

                    // 2. Compute Algebraic Harmonic Depth: D = K * a_pp * T^2
                    float peakToPeakAccel = peakAccel - troughAccel;
                    float cyclePeriodSec = (float)cyclePeriodMs / 1000.0f;
                    reading.depth_cm = CPReadyConfig::DEPTH_CALIBRATION_K * (peakToPeakAccel * cyclePeriodSec * cyclePeriodSec);

                    // Constrain bounds using configured limits
                    if (reading.depth_cm < CPReadyConfig::DEPTH_MIN_LIMIT_CM) {
                        reading.depth_cm = CPReadyConfig::DEPTH_MIN_LIMIT_CM;
                    }
                    if (reading.depth_cm > CPReadyConfig::DEPTH_MAX_LIMIT_CM) {
                        reading.depth_cm = CPReadyConfig::DEPTH_MAX_LIMIT_CM;
                    }

                    // 3. Evaluate Recoil
                    reading.recoil_complete = (troughAccel < CPReadyConfig::RECOIL_THRESHOLD_G);

                    // 4. Update Chest Compression Fraction
                    uint32_t totalSessionTime = currentMillis - sessionStartMillis;
                    if (totalSessionTime > 0) {
                        reading.ccf_percentage = ((float)totalActiveCompressionMillis / (float)totalSessionTime) * 100.0f;
                        if (reading.ccf_percentage > 100.0f) reading.ccf_percentage = 100.0f;
                    }

                    state = StrokeState::WAITING_FOR_DOWNSLICK;
                    return true; // Stroke complete, fresh metrics ready
                }
                break;
        }

        return false;
    }

    const CPRReading& getReading() const { return reading; }
};

#endif // COMPRESSION_TRACKER_H
