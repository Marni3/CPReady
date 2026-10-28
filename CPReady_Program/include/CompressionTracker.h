#ifndef COMPRESSION_TRACKER_H
#define COMPRESSION_TRACKER_H

#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"
#include "DepthEstimator.h"

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

    // Stroke detector state
    bool     recoilArmed;          // Recoil phase has swung far enough below zero to be allowed to finish
    float    signalEnvelopeG;      // Decaying peak of |netAccel|; scales the adaptive start threshold
    uint32_t pausedAtMillis;       // Non-zero while the session is paused
    bool     forcePostPause;       // Next stroke follows a resume and must not be read as a cadence

    // Depth reconstruction: raw samples by index, the current stroke's onset and the
    // previous stroke's completion (the start of the next stroke's cycle window).
    DepthEstimator depthEstimator;
    uint32_t onsetSampleIndex;
    uint32_t lastStrokeEndSampleIndex;

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
    uint32_t cumulativeDepthCount;  // Strokes whose depth was measured
    float    cumulativeRateSum;
    float    validDepthSum;
    uint32_t validStrokeCount;
    uint32_t validPeriodSumMs;     // Periods of strokes with a real cadence (not first / post-pause)
    uint32_t validRateCount;
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

        recoilArmed = false;
        signalEnvelopeG = 0.0f;
        pausedAtMillis = 0;
        forcePostPause = false;

        depthEstimator.reset();
        onsetSampleIndex = 0;
        lastStrokeEndSampleIndex = 0;

        periodHistoryCount = 0;
        periodHistoryIndex = 0;

        totalStrokeCount = 0;
        goodRecoilCount = 0;
        cumulativeDepthSum = 0.0f;
        cumulativeDepthCount = 0;
        cumulativeRateSum = 0.0f;
        validDepthSum = 0.0f;
        validStrokeCount = 0;
        validPeriodSumMs = 0;
        validRateCount = 0;
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

    bool isSessionActive() const { return sessionStartMillis != 0; }
    bool isPaused() const { return pausedAtMillis != 0; }

    // Freezes the session clock: paused time counts toward neither elapsed time nor CCF.
    void pauseSession(uint32_t currentMillis) {
        if (sessionStartMillis == 0 || pausedAtMillis != 0) return;
        pausedAtMillis = currentMillis;
        state = StrokeState::WAITING_FOR_DOWNSLICK;
    }

    void resumeSession(uint32_t currentMillis) {
        if (pausedAtMillis == 0) return;
        uint32_t pausedMs = currentMillis - pausedAtMillis;
        sessionStartMillis += pausedMs;
        lastStrokePeakMillis += pausedMs;
        lastCompressionDetectedMillis += pausedMs;
        lastAudioPromptMillis += pausedMs;
        lastTargetPraiseMillis += pausedMs;
        if (targetStartTime > 0) targetStartTime += pausedMs;
        strokeStartMillis = 0;
        pausedAtMillis = 0;
        forcePostPause = true;
        // No sample was recorded while paused, so the buffer would join two unrelated
        // stretches of signal. The first stroke after resuming starts from rest instead.
        depthEstimator.reset();
        lastStrokeEndSampleIndex = 0;
    }

    // Marks the session finished so a stray sample or RESUME cannot reopen it.
    // The last summary stays available for GET_RESULTS and CALIBRATE_TARGET.
    void endSession() {
        sessionStartMillis = 0;
        pausedAtMillis = 0;
        state = StrokeState::WAITING_FOR_DOWNSLICK;
    }

    // A voice cue is announced in exactly one packet; call after that packet is sent.
    void clearAudioPrompt() { reading.audio_prompt_code = PROMPT_NONE; }

    // Dynamic Runtime Tuning APIs
    void setDepthK(float k) {
        if (k >= CPReadyConfig::DEPTH_K_MIN && k <= CPReadyConfig::DEPTH_K_MAX) {
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
    void setManikinK(float k) { if (k >= CPReadyConfig::DEPTH_K_MIN && k <= CPReadyConfig::DEPTH_K_MAX) manikinDepthK = k; }
    void setBenchK(float k) { if (k >= CPReadyConfig::DEPTH_K_MIN && k <= CPReadyConfig::DEPTH_K_MAX) benchDepthK = k; }
    void setManikinDepthK(float k) { setManikinK(k); }
    void setBenchDepthK(float k) { setBenchK(k); }

    float getRunningAverageDepth() const {
        if (validStrokeCount > 0) return validDepthSum / (float)validStrokeCount;
        return cumulativeDepthCount > 0 ? (cumulativeDepthSum / (float)cumulativeDepthCount) : 0.0f;
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
        if (newK >= CPReadyConfig::DEPTH_K_MIN && newK <= CPReadyConfig::DEPTH_K_MAX) {
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
    // netAccel is the low-pass filtered signal, used to detect strokes. rawNetAccel is
    // the same sample before filtering, used for depth: the filter would shrink and
    // delay the motion it integrates.
    bool processSample(float netAccel, float rawNetAccel, uint32_t currentMillis) {
        if (sessionStartMillis == 0 || pausedAtMillis != 0) return false;

        depthEstimator.push(rawNetAccel);
        const uint32_t sampleIndex = depthEstimator.sampleCount() - 1;

        uint32_t totalSessionTime = currentMillis - sessionStartMillis;
        reading.elapsed_seconds = totalSessionTime / 1000;

        // Live CCF is refreshed every sample so it decays during a pause instead of
        // freezing at the value of the last completed stroke.
        if (totalSessionTime > 0) {
            reading.ccf_percentage = ((float)totalActiveCompressionMillis / (float)totalSessionTime) * 100.0f;
            if (reading.ccf_percentage > 100.0f) reading.ccf_percentage = 100.0f;
        }

        // Decaying peak of |netAccel|, used to scale the downstroke threshold to the
        // strength of the trainee's own strokes.
        signalEnvelopeG *= CPReadyConfig::ENVELOPE_DECAY_PER_SAMPLE;
        if (fabsf(netAccel) > signalEnvelopeG) signalEnvelopeG = fabsf(netAccel);

        // Stroke timeout watchdog: recover from a stalled or incomplete stroke state
        if ((state == StrokeState::COMPRESSING || state == StrokeState::RECOILING) &&
            strokeStartMillis > 0 && (currentMillis - strokeStartMillis > 2000)) {
            state = StrokeState::WAITING_FOR_DOWNSLICK;
            peakAccel = 0.0f;
            troughAccel = 0.0f;
        }

        switch (state) {
            case StrokeState::WAITING_FOR_DOWNSLICK: {
                // The lockout runs from the previous stroke's onset. Timing it from the
                // stroke's end swallowed every second downstroke above ~110 cpm.
                bool onsetLockoutOver = (strokeStartMillis == 0) ||
                    (currentMillis - strokeStartMillis > CPReadyConfig::REFRACTORY_LOCKOUT_MS);
                bool quietAfterEnd =
                    (currentMillis - lastStrokePeakMillis > CPReadyConfig::MIN_END_TO_ONSET_MS);
                if (netAccel > startThreshold() && onsetLockoutOver && quietAfterEnd) {
                    state = StrokeState::COMPRESSING;
                    strokeStartMillis = currentMillis;
                    onsetSampleIndex = sampleIndex;
                    peakAccel = netAccel;
                    troughAccel = netAccel;
                    recoilArmed = false;
                }
                break;
            }

            case StrokeState::COMPRESSING:
                if (netAccel > peakAccel) {
                    peakAccel = netAccel;
                }
                // Transition to recoil when acceleration peaks and starts swinging negative
                if (netAccel < 0.0f) {
                    state = StrokeState::RECOILING;
                    troughAccel = netAccel;
                    recoilArmed = false;
                }
                break;

            case StrokeState::RECOILING:
                if (netAccel < troughAccel) {
                    troughAccel = netAccel;
                }
                // Only a real upward swing arms the exit. Without it the first sample
                // just below zero already passes the finish test and the stroke ends
                // mid-downstroke with its trough unmeasured.
                if (netAccel < recoilArmLevel()) {
                    recoilArmed = true;
                }
                // When net acceleration crosses back upward near zero, stroke is finished
                if (recoilArmed && netAccel >= CPReadyConfig::STROKE_FINISH_THRESHOLD_G) {
                    uint32_t rawPeriodMs = currentMillis - lastStrokePeakMillis;
                    bool isPostPause = (rawPeriodMs > CPReadyConfig::PAUSE_DETECTION_TIMEOUT_MS ||
                                        totalStrokeCount == 0 || forcePostPause);

                    // Depth comes first: a detection without real chest motion is a bump
                    // (hands repositioned during a pause), not a compression.
                    const uint32_t strokeEndIndex = sampleIndex + 1;
                    float physicalDepthCm = 0.0f;
                    bool depthKnown = false;
                    if (!isPostPause) {
                        depthKnown = depthEstimator.closedCycleDepthCm(
                            lastStrokeEndSampleIndex, strokeEndIndex, physicalDepthCm);
                    }
                    if (!depthKnown) {
                        depthKnown = depthEstimator.fromRestDepthCm(
                            onsetSampleIndex, strokeEndIndex, physicalDepthCm);
                    }
                    if (depthKnown && physicalDepthCm < CPReadyConfig::MIN_STROKE_DEPTH_CM) {
                        state = StrokeState::WAITING_FOR_DOWNSLICK;
                        break;
                    }

                    lastStrokePeakMillis = currentMillis;
                    lastCompressionDetectedMillis = currentMillis;
                    lastStrokeEndSampleIndex = strokeEndIndex;
                    forcePostPause = false;
                    bool rateValid = !isPostPause && rawPeriodMs >= CPReadyConfig::MIN_VALID_PERIOD_MS;

                    // 1. Cadence Jitter & Consistency Estimation
                    bool isCadenceSteady = true;
                    if (rateValid) {
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
                    if (!CPReadyConfig::RECOIL_MEASURED_BY_FORCE_SENSOR) flags |= CADENCE_FLAG_RECOIL_ESTIMATED;
                    reading.quality_flags = flags;

                    // 2. Rate. The first stroke and the stroke after a pause have no
                    // cadence, so they report no rate (0) instead of a stale value or the
                    // 30-40 cpm a long gap would produce, and earn no CCF time. Otherwise
                    // the rate is the median of the last few periods, so one uneven
                    // stroke does not swing the display or start a "speed up" streak.
                    if (rateValid) {
                        reading.rate_cpm = 60000.0f / medianRecentPeriodMs();
                        totalActiveCompressionMillis += rawPeriodMs;
                    } else {
                        reading.rate_cpm = 0.0f;
                    }

                    // 3. Depth: the integrated chest motion, scaled by the calibration K
                    // (1.0 at the profile default). A first stroke that did not start
                    // from rest has no measurable depth; the previous value stays.
                    if (depthKnown) {
                        reading.depth_cm = physicalDepthCm * depthScale();
                        if (reading.depth_cm < CPReadyConfig::DEPTH_MIN_LIMIT_CM) {
                            reading.depth_cm = CPReadyConfig::DEPTH_MIN_LIMIT_CM;
                        }
                        if (reading.depth_cm > CPReadyConfig::DEPTH_MAX_LIMIT_CM) {
                            reading.depth_cm = CPReadyConfig::DEPTH_MAX_LIMIT_CM;
                        }
                    }

                    // 4. Evaluate Recoil
                    reading.recoil_complete = (troughAccel < recoilThresholdG);

                    // 5. Update Chest Compression Fraction
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
                    if (depthKnown) {
                        cumulativeDepthSum += reading.depth_cm;
                        cumulativeDepthCount++;
                    }
                    cumulativeRateSum += reading.rate_cpm;
                    if (rateValid) {
                        validPeriodSumMs += rawPeriodMs;
                        validRateCount++;
                    }

                    // Stroke-Qualified Mean accumulation: exclude first-strokes, unmeasured
                    // strokes and clamped limit saturation
                    if (depthKnown && !(flags & CADENCE_FLAG_FIRST_STROKE) &&
                        reading.depth_cm < CPReadyConfig::DEPTH_MAX_LIMIT_CM) {
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
                    evaluateAudioGuidance(currentMillis, rateValid, depthKnown);

                    state = StrokeState::WAITING_FOR_DOWNSLICK;
                    return true; // Stroke complete, fresh metrics and audio cue ready
                }
                break;
        }

        return false;
    }

private:
    // Reported depth = integrated depth x (K / profile default K).
    float depthScale() const {
        float defaultK = (currentProfile == CPReadyConfig::KinematicProfile::BENCH_TEST)
            ? CPReadyConfig::BENCH_DEPTH_CALIBRATION_K
            : CPReadyConfig::DEPTH_CALIBRATION_K;
        return depthCalibrationK / defaultK;
    }

    // Median of the last RATE_MEDIAN_STROKES valid periods (mean of two when only two exist).
    float medianRecentPeriodMs() const {
        uint8_t n = periodHistoryCount < CPReadyConfig::RATE_MEDIAN_STROKES
            ? periodHistoryCount : CPReadyConfig::RATE_MEDIAN_STROKES;
        if (n == 0) return 1.0f;
        uint16_t p[PERIOD_HISTORY_SIZE];
        for (uint8_t i = 0; i < n; i++) {
            p[i] = recentCyclePeriods[(periodHistoryIndex + PERIOD_HISTORY_SIZE - 1 - i) % PERIOD_HISTORY_SIZE];
        }
        for (uint8_t i = 1; i < n; i++) {
            for (uint8_t j = i; j > 0 && p[j - 1] > p[j]; j--) {
                uint16_t t = p[j]; p[j] = p[j - 1]; p[j - 1] = t;
            }
        }
        if (n % 2 == 0) return 0.5f * ((float)p[n / 2 - 1] + (float)p[n / 2]);
        return (float)p[n / 2];
    }

    // Downstroke trigger level: a fraction of the recent signal envelope, never below
    // MIN_START_THRESHOLD_G and never above the profile threshold. A fixed 0.45 g missed
    // smooth and shallow strokes entirely, which are exactly the ones needing feedback.
    float startThreshold() const {
        float threshold = CPReadyConfig::ADAPTIVE_START_FRACTION * signalEnvelopeG;
        if (threshold < CPReadyConfig::MIN_START_THRESHOLD_G) threshold = CPReadyConfig::MIN_START_THRESHOLD_G;
        return threshold < compressionStartThresholdG ? threshold : compressionStartThresholdG;
    }

    // Level the recoil swing must pass before the stroke may finish.
    float recoilArmLevel() const {
        float level = CPReadyConfig::RECOIL_ARM_FRACTION * peakAccel;
        if (level < CPReadyConfig::RECOIL_ARM_MIN_G) level = CPReadyConfig::RECOIL_ARM_MIN_G;
        return -level;
    }

    void evaluateAudioGuidance(uint32_t currentMillis, bool rateValid, bool depthKnown) {
        if (!CPReadyConfig::ENABLE_AUDIO_COACHING_PROMPTS) return;

        bool isShallow = depthKnown && (reading.depth_cm < CPReadyConfig::TARGET_DEPTH_MIN_CM);
        bool isTooDeep = depthKnown && (reading.depth_cm > CPReadyConfig::TARGET_DEPTH_MAX_CM);
        // The acceleration recoil proxy cannot see leaning, so it only coaches when
        // explicitly enabled or when recoil comes from a force sensor.
        bool recoilTrusted = CPReadyConfig::RECOIL_MEASURED_BY_FORCE_SENSOR ||
                             CPReadyConfig::ENABLE_ESTIMATED_RECOIL_PROMPT;
        bool isLeaning = recoilTrusted && !reading.recoil_complete;
        bool isSlow    = rateValid && (reading.rate_cpm < (float)CPReadyConfig::TARGET_RATE_MIN_CPM);
        bool isFast    = rateValid && (reading.rate_cpm > (float)CPReadyConfig::TARGET_RATE_MAX_CPM);
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
    // Ends the session as well: afterwards isSessionActive() is false.
    CPRSessionSummary finalizeSession(uint32_t endMillis) {
        // A paused session's clock stopped when it was paused.
        if (pausedAtMillis != 0) endMillis = pausedAtMillis;

        CPRSessionSummary s;
        s.total_compressions = (uint16_t)totalStrokeCount;
        s.total_duration_sec = sessionStartMillis > 0 ? (uint16_t)((endMillis - sessionStartMillis) / 1000) : 0;
        s.quality_flags = CADENCE_FLAG_STEADY;
        if (currentProfile == CPReadyConfig::KinematicProfile::BENCH_TEST) s.quality_flags |= CADENCE_FLAG_BENCH_MODE;
        if (!CPReadyConfig::RECOIL_MEASURED_BY_FORCE_SENSOR) s.quality_flags |= CADENCE_FLAG_RECOIL_ESTIMATED;

        if (totalStrokeCount > 0) {
            // Stroke-qualified mean ignores hesitant first strokes and physical ceiling clamp artifacts
            s.avg_depth_cm = (validStrokeCount > 0) ? (validDepthSum / (float)validStrokeCount)
                           : (cumulativeDepthCount > 0) ? (cumulativeDepthSum / (float)cumulativeDepthCount)
                           : 0.0f;
            // Strokes per minute of steady compressing: only strokes with a real cadence
            // (first and post-pause strokes carry no period).
            s.avg_rate_cpm = (validPeriodSumMs > 0)
                ? (60000.0f * (float)validRateCount / (float)validPeriodSumMs) : 0.0f;
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
        endSession();
        return s;
    }

    const CPRReading& getReading() const { return reading; }
    CPRSessionSummary getLastSummary() const { return lastFinalSummary; }
};

#endif // COMPRESSION_TRACKER_H
