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

    // Cumulative Session Aggregators
    uint32_t totalStrokeCount;
    uint32_t goodRecoilCount;
    float    cumulativeDepthSum;
    float    cumulativeRateSum;
    CPRSessionSummary lastFinalSummary;

    // Audio Coaching Tracking & Hysteresis
    uint32_t lastAudioPromptMillis;
    uint32_t lastTargetPraiseMillis;
    uint8_t  shallowStreak;
    uint8_t  deepStreak;
    uint8_t  leaningStreak;
    uint8_t  slowRateStreak;
    uint8_t  fastRateStreak;
    uint32_t shallowStartTime;
    uint32_t deepStartTime;
    uint32_t leaningStartTime;
    uint32_t slowRateStartTime;
    uint32_t fastRateStartTime;
    uint32_t targetStartTime;

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

        totalStrokeCount = 0;
        goodRecoilCount = 0;
        cumulativeDepthSum = 0.0f;
        cumulativeRateSum = 0.0f;

        lastAudioPromptMillis = 0;
        lastTargetPraiseMillis = 0;
        shallowStreak = 0;
        deepStreak = 0;
        leaningStreak = 0;
        slowRateStreak = 0;
        fastRateStreak = 0;
        shallowStartTime = 0;
        deepStartTime = 0;
        leaningStartTime = 0;
        slowRateStartTime = 0;
        fastRateStartTime = 0;
        targetStartTime = 0;

        reading = {0.0f, 0.0f, true, 0.0f, 0, PROMPT_NONE, 0};
        lastFinalSummary = {0.0f, 0.0f, 100.0f, 0.0f, 0, 0};
    }

    void startSession(uint32_t currentMillis) {
        reset();
        sessionStartMillis = currentMillis;
        lastAudioPromptMillis = currentMillis; // Grace period at start
        lastTargetPraiseMillis = currentMillis;
        targetStartTime = currentMillis;
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

                    // 5. Update Session Accumulators
                    totalStrokeCount++;
                    reading.stroke_count = (uint16_t)totalStrokeCount;
                    if (reading.recoil_complete) {
                        goodRecoilCount++;
                    }
                    cumulativeDepthSum += reading.depth_cm;
                    cumulativeRateSum += reading.rate_cpm;

                    // 6. Audio Coaching Engine Evaluation
                    reading.audio_prompt_code = PROMPT_NONE;
                    evaluateAudioGuidance(currentMillis);

                    state = StrokeState::WAITING_FOR_DOWNSLICK;
                    return true; // Stroke complete, fresh metrics and audio cue ready
                }
                break;
        }

        return false;
    }

private:
    void evaluateAudioGuidance(uint32_t currentMillis) {
        if (!CPReadyConfig::ENABLE_AUDIO_COACHING_PROMPTS) return;

        bool isShallow = (reading.depth_cm < CPReadyConfig::TARGET_DEPTH_MIN_CM);
        bool isTooDeep = (reading.depth_cm > CPReadyConfig::TARGET_DEPTH_MAX_CM);
        bool isLeaning = !reading.recoil_complete;
        bool isSlow    = (reading.rate_cpm < (float)CPReadyConfig::TARGET_RATE_MIN_CPM);
        bool isFast    = (reading.rate_cpm > (float)CPReadyConfig::TARGET_RATE_MAX_CPM);
        bool isTarget  = (!isShallow && !isTooDeep && !isLeaning && !isSlow && !isFast);

        // Update persistence timers and streak counters
        if (isLeaning) {
            if (leaningStreak == 0) leaningStartTime = currentMillis;
            leaningStreak++;
        } else {
            leaningStreak = 0;
            leaningStartTime = 0;
        }

        if (isShallow) {
            if (shallowStreak == 0) shallowStartTime = currentMillis;
            shallowStreak++;
        } else {
            shallowStreak = 0;
            shallowStartTime = 0;
        }

        if (isTooDeep) {
            if (deepStreak == 0) deepStartTime = currentMillis;
            deepStreak++;
        } else {
            deepStreak = 0;
            deepStartTime = 0;
        }

        if (isSlow) {
            if (slowRateStreak == 0) slowRateStartTime = currentMillis;
            slowRateStreak++;
        } else {
            slowRateStreak = 0;
            slowRateStartTime = 0;
        }

        if (isFast) {
            if (fastRateStreak == 0) fastRateStartTime = currentMillis;
            fastRateStreak++;
        } else {
            fastRateStreak = 0;
            fastRateStartTime = 0;
        }

        if (isTarget) {
            if (targetStartTime == 0) targetStartTime = currentMillis;
        } else {
            targetStartTime = 0;
        }

        // Check prompt cooldown window (minimum 5.0 seconds between speech prompts)
        if (currentMillis - lastAudioPromptMillis < CPReadyConfig::AUDIO_PROMPT_COOLDOWN_MS) {
            return;
        }

        // Helper: error is verified if sustained across time window OR minimum consecutive strokes
        auto isSustained = [&](uint32_t startTime, uint8_t streak) {
            if (streak >= CPReadyConfig::AUDIO_PROMPT_CONSECUTIVE_ERR) return true;
            if (startTime > 0 && (currentMillis - startTime >= CPReadyConfig::AUDIO_PROMPT_WINDOW_MS)) return true;
            return false;
        };

        // Priority Arbitration:
        // Priority 1 (Highest): Recoil / Leaning
        if (isSustained(leaningStartTime, leaningStreak)) {
            reading.audio_prompt_code = PROMPT_RELEASE_FULLY;
            lastAudioPromptMillis = currentMillis;
            leaningStreak = 0;
            leaningStartTime = 0;
            return;
        }

        // Priority 2: Compression Depth
        if (isSustained(shallowStartTime, shallowStreak)) {
            reading.audio_prompt_code = PROMPT_PUSH_HARDER;
            lastAudioPromptMillis = currentMillis;
            shallowStreak = 0;
            shallowStartTime = 0;
            return;
        }
        if (isSustained(deepStartTime, deepStreak)) {
            reading.audio_prompt_code = PROMPT_PUSH_LESS;
            lastAudioPromptMillis = currentMillis;
            deepStreak = 0;
            deepStartTime = 0;
            return;
        }

        // Priority 3: Compression Rate
        if (isSustained(slowRateStartTime, slowRateStreak)) {
            reading.audio_prompt_code = PROMPT_SPEED_UP;
            lastAudioPromptMillis = currentMillis;
            slowRateStreak = 0;
            slowRateStartTime = 0;
            return;
        }
        if (isSustained(fastRateStartTime, fastRateStreak)) {
            reading.audio_prompt_code = PROMPT_SLOW_DOWN;
            lastAudioPromptMillis = currentMillis;
            fastRateStreak = 0;
            fastRateStartTime = 0;
            return;
        }

        // Priority 4: Positive Reinforcement (Good compressions every 15s)
        if (isTarget && targetStartTime > 0 && 
            (currentMillis - targetStartTime >= CPReadyConfig::AUDIO_PROMPT_PRAISE_INTERVAL) &&
            (currentMillis - lastTargetPraiseMillis >= CPReadyConfig::AUDIO_PROMPT_PRAISE_INTERVAL)) {
            reading.audio_prompt_code = PROMPT_GOOD_JOB;
            lastAudioPromptMillis = currentMillis;
            lastTargetPraiseMillis = currentMillis;
            targetStartTime = currentMillis;
        }
    }

public:
    // Finalizes metrics across entire session and caches summary
    CPRSessionSummary finalizeSession(uint32_t endMillis) {
        CPRSessionSummary s;
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

        s.final_ccf_percent = reading.ccf_percentage;
        lastFinalSummary = s;
        return s;
    }

    const CPRReading& getReading() const { return reading; }
    CPRSessionSummary getLastSummary() const { return lastFinalSummary; }
};

#endif // COMPRESSION_TRACKER_H
