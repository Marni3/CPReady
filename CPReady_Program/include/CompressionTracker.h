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

    // Runtime Dynamic Configuration
    float depthCalibrationK;
    float manikinDepthK;
    float benchDepthK;
    float compressionStartThresholdG;
    float recoilThresholdG;
    CPReadyConfig::KinematicProfile currentProfile;

    // Cadence Consistency & Jitter Estimator
    static constexpr uint8_t PERIOD_HISTORY_SIZE = 4;
    uint16_t recentCyclePeriods[PERIOD_HISTORY_SIZE];
    uint8_t  periodHistoryCount;
    uint8_t  periodHistoryIndex;

    // Cumulative Session Aggregators
    uint32_t totalStrokeCount;
    uint32_t goodRecoilCount;
    float    cumulativeDepthSum;
    float    cumulativeRateSum;
    float    validDepthSum;
    uint32_t validStrokeCount;
    bool     summaryAlreadyCalibrated;
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
    CompressionTracker() 
        : state(StrokeState::WAITING_FOR_DOWNSLICK),
          depthCalibrationK(CPReadyConfig::DEPTH_CALIBRATION_K),
          manikinDepthK(CPReadyConfig::DEPTH_CALIBRATION_K),
          benchDepthK(CPReadyConfig::BENCH_DEPTH_CALIBRATION_K),
          compressionStartThresholdG(CPReadyConfig::COMPRESSION_START_THRESHOLD_G),
          recoilThresholdG(CPReadyConfig::RECOIL_THRESHOLD_G),
          currentProfile(CPReadyConfig::KinematicProfile::MANIKIN_STANDARD),
          validDepthSum(0.0f),
          validStrokeCount(0),
          summaryAlreadyCalibrated(false) {
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

        periodHistoryCount = 0;
        periodHistoryIndex = 0;

        totalStrokeCount = 0;
        goodRecoilCount = 0;
        cumulativeDepthSum = 0.0f;
        cumulativeRateSum = 0.0f;
        validDepthSum = 0.0f;
        validStrokeCount = 0;
        summaryAlreadyCalibrated = false;

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

        reading = CPRReading(0.0f, 0.0f, true, 0.0f, 0, PROMPT_NONE, 0, CADENCE_FLAG_STEADY);
        lastFinalSummary = CPRSessionSummary(0.0f, 0.0f, 100.0f, 0.0f, 0, 0, CADENCE_FLAG_STEADY);
    }

    void startSession(uint32_t currentMillis) {
        reset();
        sessionStartMillis = currentMillis;
        lastStrokePeakMillis = currentMillis;          // Prevents first-stroke cycle period explosion
        lastCompressionDetectedMillis = currentMillis;
        lastAudioPromptMillis = currentMillis;         // Grace period at start
        lastTargetPraiseMillis = currentMillis;
        targetStartTime = currentMillis;
    }

    // Dynamic Runtime Tuning APIs
    void setDepthK(float k) {
        if (k >= 1.0f && k <= 30.0f) {
            depthCalibrationK = k;
            if (currentProfile == CPReadyConfig::KinematicProfile::BENCH_TEST) {
                benchDepthK = k;
            } else {
                manikinDepthK = k;
            }
        }
    }
    float getDepthK() const { return depthCalibrationK; }
    float getManikinK() const { return manikinDepthK; }
    float getBenchK() const { return benchDepthK; }
    void setManikinK(float k) { if (k >= 1.0f && k <= 30.0f) manikinDepthK = k; }
    void setBenchK(float k) { if (k >= 1.0f && k <= 30.0f) benchDepthK = k; }
    void setManikinDepthK(float k) { setManikinK(k); }
    void setBenchDepthK(float k) { setBenchK(k); }

    float getRunningAverageDepth() const {
        if (validStrokeCount > 0) return validDepthSum / (float)validStrokeCount;
        return totalStrokeCount > 0 ? (cumulativeDepthSum / (float)totalStrokeCount) : 0.0f;
    }

    // Proportional comparative calibration: K_new = K_current * (targetDepth / measuredMeanDepth)
    bool calibrateFromLastSummary(float targetDepthCm, float& outNewK) {
        if (summaryAlreadyCalibrated || targetDepthCm <= 0.0f || lastFinalSummary.avg_depth_cm <= 0.0f) {
            return false;
        }
        if (lastFinalSummary.total_compressions < 5) {
            return false;
        }
        float ratio = targetDepthCm / lastFinalSummary.avg_depth_cm;
        float newK = depthCalibrationK * ratio;
        if (newK >= 1.0f && newK <= 30.0f) {
            setDepthK(newK);
            outNewK = newK;
            summaryAlreadyCalibrated = true;
            return true;
        }
        return false;
    }

    void setCompressionStartThresholdG(float g) {
        if (g >= 0.10f && g <= 1.50f) compressionStartThresholdG = g;
    }
    float getCompressionStartThresholdG() const { return compressionStartThresholdG; }

    void setRecoilThresholdG(float g) {
        if (g <= -0.05f && g >= -1.50f) recoilThresholdG = g;
    }
    float getRecoilThresholdG() const { return recoilThresholdG; }

    void setProfile(CPReadyConfig::KinematicProfile profile) {
        currentProfile = profile;
        if (profile == CPReadyConfig::KinematicProfile::BENCH_TEST) {
            compressionStartThresholdG = CPReadyConfig::BENCH_COMPRESSION_START_THRESHOLD_G;
            recoilThresholdG           = CPReadyConfig::BENCH_RECOIL_THRESHOLD_G;
            depthCalibrationK          = benchDepthK;
        } else {
            compressionStartThresholdG = CPReadyConfig::COMPRESSION_START_THRESHOLD_G;
            recoilThresholdG           = CPReadyConfig::RECOIL_THRESHOLD_G;
            depthCalibrationK          = manikinDepthK;
        }
    }
    CPReadyConfig::KinematicProfile getProfile() const { return currentProfile; }

    // Called for each 100 Hz sample. Returns true whenever a stroke completes.
    bool processSample(float netAccel, uint32_t currentMillis) {
        if (sessionStartMillis == 0) return false;

        reading.elapsed_seconds = (currentMillis - sessionStartMillis) / 1000;

        // Stroke timeout watchdog: recover from a stalled or incomplete stroke state
        if ((state == StrokeState::COMPRESSING || state == StrokeState::RECOILING) &&
            strokeStartMillis > 0 && (currentMillis - strokeStartMillis > 2000)) {
            state = StrokeState::WAITING_FOR_DOWNSLICK;
            peakAccel = 0.0f;
            troughAccel = 0.0f;
        }

        switch (state) {
            case StrokeState::WAITING_FOR_DOWNSLICK:
                if (netAccel > compressionStartThresholdG && 
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
                    uint32_t rawPeriodMs = currentMillis - lastStrokePeakMillis;
                    lastStrokePeakMillis = currentMillis;
                    lastCompressionDetectedMillis = currentMillis;

                    bool isPostPause = (rawPeriodMs > CPReadyConfig::PAUSE_DETECTION_TIMEOUT_MS || totalStrokeCount == 0);

                    // 1. Cadence Jitter & Consistency Estimation
                    bool isCadenceSteady = true;
                    if (!isPostPause && rawPeriodMs >= 250 && rawPeriodMs <= 2000) {
                        recentCyclePeriods[periodHistoryIndex] = (uint16_t)rawPeriodMs;
                        periodHistoryIndex = (periodHistoryIndex + 1) % PERIOD_HISTORY_SIZE;
                        if (periodHistoryCount < PERIOD_HISTORY_SIZE) {
                            periodHistoryCount++;
                        }

                        if (periodHistoryCount >= 3) {
                            float sumPeriod = 0.0f;
                            for (uint8_t i = 0; i < periodHistoryCount; i++) {
                                sumPeriod += (float)recentCyclePeriods[i];
                            }
                            float meanPeriod = sumPeriod / (float)periodHistoryCount;
                            float sumDev = 0.0f;
                            for (uint8_t i = 0; i < periodHistoryCount; i++) {
                                sumDev += fabsf((float)recentCyclePeriods[i] - meanPeriod);
                            }
                            float meanDev = sumDev / (float)periodHistoryCount;
                            float jitterRatio = (meanPeriod > 0.0f) ? (meanDev / meanPeriod) : 0.0f;
                            isCadenceSteady = (jitterRatio <= CPReadyConfig::MAX_CADENCE_JITTER_RATIO);
                        }
                    } else {
                        // After an idle pause or on first stroke, cadence is not yet synchronized
                        periodHistoryCount = 0;
                        periodHistoryIndex = 0;
                        isCadenceSteady = false;
                    }

                    // Build Quality Flags Bitmask
                    uint8_t flags = 0;
                    if (isCadenceSteady) flags |= CADENCE_FLAG_STEADY;
                    if (isPostPause)     flags |= CADENCE_FLAG_FIRST_STROKE;
                    if (currentProfile == CPReadyConfig::KinematicProfile::BENCH_TEST) flags |= CADENCE_FLAG_BENCH_MODE;
                    reading.quality_flags = flags;

                    // 2. Compute Instantaneous Rate
                    if (rawPeriodMs > 0 && rawPeriodMs < 2000) {
                        reading.rate_cpm = 60000.0f / (float)rawPeriodMs;
                        totalActiveCompressionMillis += rawPeriodMs;
                    }

                    // 3. Compute Algebraic Harmonic Depth: D = K * a_pp * T_clamped^2
                    // Clamping and smoothing prevents quadratic explosion during bench testing or cadence jitter
                    float cyclePeriodSec;
                    if (isPostPause) {
                        // Anchor to typical CPR period (~110 CPM = 0.55s) to eliminate false 10 cm ceilings
                        cyclePeriodSec = CPReadyConfig::FALLBACK_CADENCE_PERIOD_SEC;
                    } else if (periodHistoryCount >= 3) {
                        // 3-stroke running median filter on cycle period to reject timing noise
                        uint16_t p0 = recentCyclePeriods[(periodHistoryIndex + PERIOD_HISTORY_SIZE - 1) % PERIOD_HISTORY_SIZE];
                        uint16_t p1 = recentCyclePeriods[(periodHistoryIndex + PERIOD_HISTORY_SIZE - 2) % PERIOD_HISTORY_SIZE];
                        uint16_t p2 = recentCyclePeriods[(periodHistoryIndex + PERIOD_HISTORY_SIZE - 3) % PERIOD_HISTORY_SIZE];
                        uint16_t med = (p0 <= p1) ? ((p1 <= p2) ? p1 : ((p0 <= p2) ? p2 : p0))
                                                   : ((p0 <= p2) ? p0 : ((p1 <= p2) ? p2 : p1));
                        cyclePeriodSec = (float)med / 1000.0f;
                    } else {
                        cyclePeriodSec = (float)rawPeriodMs / 1000.0f;
                    }

                    if (cyclePeriodSec < CPReadyConfig::MIN_CPR_PERIOD_SEC) {
                        cyclePeriodSec = CPReadyConfig::MIN_CPR_PERIOD_SEC;
                    } else if (cyclePeriodSec > CPReadyConfig::MAX_CPR_PERIOD_SEC) {
                        cyclePeriodSec = CPReadyConfig::MAX_CPR_PERIOD_SEC;
                    }

                    float peakToPeakAccel = peakAccel - troughAccel;
                    reading.depth_cm = depthCalibrationK * (peakToPeakAccel * cyclePeriodSec * cyclePeriodSec);

                    // Constrain bounds using configured limits
                    if (reading.depth_cm < CPReadyConfig::DEPTH_MIN_LIMIT_CM) {
                        reading.depth_cm = CPReadyConfig::DEPTH_MIN_LIMIT_CM;
                    }
                    if (reading.depth_cm > CPReadyConfig::DEPTH_MAX_LIMIT_CM) {
                        reading.depth_cm = CPReadyConfig::DEPTH_MAX_LIMIT_CM;
                    }

                    // 4. Evaluate Recoil
                    reading.recoil_complete = (troughAccel < recoilThresholdG);

                    // 5. Update Chest Compression Fraction
                    uint32_t totalSessionTime = currentMillis - sessionStartMillis;
                    if (totalSessionTime > 0) {
                        reading.ccf_percentage = ((float)totalActiveCompressionMillis / (float)totalSessionTime) * 100.0f;
                        if (reading.ccf_percentage > 100.0f) reading.ccf_percentage = 100.0f;
                    }

                    // 6. Update Session Accumulators
                    totalStrokeCount++;
                    reading.stroke_count = (uint16_t)totalStrokeCount;
                    if (reading.recoil_complete) {
                        goodRecoilCount++;
                    }
                    cumulativeDepthSum += reading.depth_cm;
                    cumulativeRateSum += reading.rate_cpm;

                    // Stroke-Qualified Mean accumulation: exclude first-strokes and clamped limit saturation
                    if (!(flags & CADENCE_FLAG_FIRST_STROKE) && reading.depth_cm < CPReadyConfig::DEPTH_MAX_LIMIT_CM) {
                        validDepthSum += reading.depth_cm;
                        validStrokeCount++;
                    }

                    // 7. Audio Coaching Engine Evaluation
                    if (rawPeriodMs > CPReadyConfig::PAUSE_DETECTION_TIMEOUT_MS) {
                        shallowStreak = 0;   shallowStartTime = 0;
                        deepStreak = 0;      deepStartTime = 0;
                        leaningStreak = 0;   leaningStartTime = 0;
                        slowRateStreak = 0;  slowRateStartTime = 0;
                        fastRateStreak = 0;  fastRateStartTime = 0;
                    }
                    reading.audio_prompt_code = PROMPT_NONE;
                    evaluateAudioGuidance(currentMillis, isCadenceSteady, isPostPause);

                    state = StrokeState::WAITING_FOR_DOWNSLICK;
                    return true; // Stroke complete, fresh metrics and audio cue ready
                }
                break;
        }

        return false;
    }

private:
    void evaluateAudioGuidance(uint32_t currentMillis, bool isCadenceSteady, bool isPostPause) {
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
        s.quality_flags = (currentProfile == CPReadyConfig::KinematicProfile::BENCH_TEST) ? 
                          (CADENCE_FLAG_STEADY | CADENCE_FLAG_BENCH_MODE) : CADENCE_FLAG_STEADY;
        
        if (totalStrokeCount > 0) {
            // Stroke-qualified mean ignores hesitant first strokes and physical ceiling clamp artifacts
            s.avg_depth_cm = (validStrokeCount > 0) ? (validDepthSum / (float)validStrokeCount) 
                                                    : (cumulativeDepthSum / (float)totalStrokeCount);
            s.avg_rate_cpm = cumulativeRateSum / (float)totalStrokeCount;
            s.recoil_compliance_percent = ((float)goodRecoilCount / (float)totalStrokeCount) * 100.0f;
        } else {
            s.avg_depth_cm = 0.0f;
            s.avg_rate_cpm = 0.0f;
            s.recoil_compliance_percent = 100.0f;
        }

        // Recompute CCF using true total session duration at the moment of finalization
        uint32_t totalSessionMs = (sessionStartMillis > 0) ? (endMillis - sessionStartMillis) : 0;
        s.final_ccf_percent = (totalSessionMs > 0) ?
            min(100.0f, ((float)totalActiveCompressionMillis / (float)totalSessionMs) * 100.0f) : 0.0f;
        lastFinalSummary = s;
        return s;
    }

    const CPRReading& getReading() const { return reading; }
    CPRSessionSummary getLastSummary() const { return lastFinalSummary; }
};

#endif // COMPRESSION_TRACKER_H
