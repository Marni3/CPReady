/// Dynamic App-Side Voice Coaching Engine (v1) for CPReady.
///
/// ## Architecture & Rationale
/// Historically, audio coaching cue selection (`audio_prompt_code`, Byte 7) was
/// evaluated on the ESP32 inside `CompressionTracker::evaluateAudioGuidance`.
/// Moving this decision engine to the Flutter application provides four major
/// advantages:
/// 1. **Unsteady-Rhythm Depth-Cue Suppression**: Single-MPU closed-cycle
///    double integration exhibits temporary boundary-velocity fluctuations
///    ($\Delta v \neq 0$) when compression rhythm is unsteady (`!isSteadyCadence`).
///    Evaluating cues in the app allows depth prompts ("Compression too shallow"
///    / "Compression too deep") to be dynamically suppressed whenever cadence is
///    unsteady, while keeping rate prompts ("Compression rate too slow" /
///    "Compression rate too fast") active to guide the trainee back to a steady
///    rhythm first.
/// 2. **Packet-Loss Immunity**: Firmware cues were emitted on a single BLE
///    packet and immediately cleared (`clearAudioPrompt()`). Evaluating cues
///    from the cumulative stroke stream in Dart guarantees that a single dropped
///    BLE notification cannot swallow a coaching prompt.
/// 3. **Rapid Iteration Without Re-Flashing**: Researchers can tune streak
///    counts, persistence windows, cooldown intervals, and priority order
///    entirely in Dart.
/// 4. **Clean Separation of Concerns**: The ESP32 acts as a dedicated kinematic
///    sensor processor, while the mobile app owns user-facing coaching UX.
///
/// > **Note for Researchers**: This v1 app-side coaching engine is a solid
/// > production baseline, not a frozen final ceiling. Thresholds, hysteresis
/// > windows, and priority rules are parameterized in [LiveCoachingConfig] so
/// > future studies can experiment with adaptive or personalized coaching.

import '../../config/config.dart';
import '../metrics/cpr_metrics.dart';

/// Tunable parameters for [LiveCoachingController].
class LiveCoachingConfig {
  /// Minimum consecutive strokes with the same error required to trigger a cue.
  final int consecutiveErrorStrokes;

  /// Sustained time window (ms) with the same error that also triggers a cue.
  final int sustainedErrorWindowMs;

  /// Minimum cooldown interval (ms) between any two spoken coaching prompts.
  final int promptCooldownMs;

  /// Sustained on-target duration (ms) required before positive praise
  /// ("Correct compressions") is spoken.
  final int positivePraiseIntervalMs;

  /// Minimum target compression depth in cm (AHA adult standard: 5.0 cm).
  final double targetDepthMinCm;

  /// Maximum target compression depth in cm (AHA adult standard: 6.0 cm).
  final double targetDepthMaxCm;

  /// Minimum target compression rate in CPM (AHA adult standard: 100 CPM).
  final int targetRateMinCpm;

  /// Maximum target compression rate in CPM (AHA adult standard: 120 CPM).
  final int targetRateMaxCpm;

  /// Whether incomplete-recoil voice prompts are allowed when recoil is
  /// estimated solely from acceleration (false on 1-MPU without force sensor).
  final bool allowEstimatedRecoilPrompts;

  const LiveCoachingConfig({
    this.consecutiveErrorStrokes = 5,
    this.sustainedErrorWindowMs = 3000,
    this.promptCooldownMs = 5000,
    this.positivePraiseIntervalMs = 15000,
    this.targetDepthMinCm = AppTargets.depthMinCm,
    this.targetDepthMaxCm = AppTargets.depthMaxCm,
    this.targetRateMinCpm = AppTargets.rateMinCpm,
    this.targetRateMaxCpm = AppTargets.rateMaxCpm,
    this.allowEstimatedRecoilPrompts = false,
  });
}

/// Evaluates incoming [CprMetrics] packets per completed stroke and decides
/// which voice coaching cue code (if any) should be spoken.
class LiveCoachingController {
  final LiveCoachingConfig config;
  final DateTime Function() _clock;

  int _lastEvaluatedStrokeCount = 0;
  DateTime? _lastPromptAt;
  DateTime? _lastPraiseAt;
  DateTime? _targetStartAt;

  int _leaningStreak = 0;
  int _shallowStreak = 0;
  int _deepStreak = 0;
  int _slowRateStreak = 0;
  int _fastRateStreak = 0;

  DateTime? _leaningStartAt;
  DateTime? _shallowStartAt;
  DateTime? _deepStartAt;
  DateTime? _slowRateStartAt;
  DateTime? _fastRateStartAt;

  LiveCoachingController({
    this.config = const LiveCoachingConfig(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Resets all streak counters and timers at the start of a session.
  void reset() {
    _lastEvaluatedStrokeCount = 0;
    _lastPromptAt = null;
    _lastPraiseAt = null;
    _targetStartAt = null;
    _clearAllStreaks();
  }

  void _clearAllStreaks() {
    _leaningStreak = 0;
    _shallowStreak = 0;
    _deepStreak = 0;
    _slowRateStreak = 0;
    _fastRateStreak = 0;
    _leaningStartAt = null;
    _shallowStartAt = null;
    _deepStartAt = null;
    _slowRateStartAt = null;
    _fastRateStartAt = null;
  }

  void _clearDepthStreaks() {
    _shallowStreak = 0;
    _deepStreak = 0;
    _shallowStartAt = null;
    _deepStartAt = null;
  }

  /// Evaluates a live [metrics] packet and returns a cue code from
  /// [AppBleConfig] (`cuePushHarder`, `cuePushShallower`, `cueReleaseFully`,
  /// `cueSpeedUp`, `cueSlowDown`, `cueGoodJob`), or `0` when no cue should fire.
  ///
  /// Only evaluates when [metrics.packetType] is [AppBleConfig.packetRealtime]
  /// and [metrics.totalCompressions] has advanced past the last evaluated stroke
  /// (ignoring the 5 Hz heartbeat repeats of the same stroke).
  ///
  /// When [cadenceWarningActive] or `!metrics.isSteadyCadence` is true, depth
  /// cues are suppressed and depth streaks are cleared so unsteady transition
  /// spikes/dips never trigger false depth coaching.
  int evaluate(
    CprMetrics metrics, {
    bool cadenceWarningActive = false,
  }) {
    if (metrics.packetType != AppBleConfig.packetRealtime) return 0;

    final int count = metrics.totalCompressions;
    if (count <= 0 || count <= _lastEvaluatedStrokeCount) {
      return 0;
    }
    _lastEvaluatedStrokeCount = count;

    final DateTime now = _clock();

    // Initialize grace timers on the first compression of the session.
    _lastPromptAt ??= now;
    _lastPraiseAt ??= now;

    // A post-pause stroke or sub-period bounce resets error streaks.
    if (metrics.isFirstStroke) {
      _clearAllStreaks();
      _targetStartAt = now;
      return 0;
    }
    if (metrics.isSubPeriodBounce) {
      return 0;
    }

    final bool rhythmUnsteady =
        cadenceWarningActive || !metrics.isSteadyCadence;
    final bool rateValid = !metrics.isFirstStroke && metrics.rateCpm > 0;
    final bool depthKnown = metrics.depthCm > 0.0;

    // 1. Evaluate individual error conditions
    final bool recoilTrusted =
        !metrics.isRecoilEstimated || config.allowEstimatedRecoilPrompts;
    final bool isLeaning = recoilTrusted && !metrics.recoilComplete;

    // Suppress depth error accumulation when rhythm is unsteady
    final bool isShallow =
        !rhythmUnsteady && depthKnown && metrics.depthCm < config.targetDepthMinCm;
    final bool isTooDeep =
        !rhythmUnsteady && depthKnown && metrics.depthCm > config.targetDepthMaxCm;
    if (rhythmUnsteady) {
      _clearDepthStreaks();
    }

    final bool isSlow = rateValid && metrics.rateCpm < config.targetRateMinCpm;
    final bool isFast = rateValid && metrics.rateCpm > config.targetRateMaxCpm;

    final bool isOnTarget = !rhythmUnsteady &&
        depthKnown &&
        rateValid &&
        !isLeaning &&
        !isShallow &&
        !isTooDeep &&
        !isSlow &&
        !isFast;

    // 2. Update persistence timers and streak counters
    if (isLeaning) {
      _leaningStartAt ??= now;
      _leaningStreak++;
    } else {
      _leaningStreak = 0;
      _leaningStartAt = null;
    }

    if (isShallow) {
      _shallowStartAt ??= now;
      _shallowStreak++;
    } else {
      _shallowStreak = 0;
      _shallowStartAt = null;
    }

    if (isTooDeep) {
      _deepStartAt ??= now;
      _deepStreak++;
    } else {
      _deepStreak = 0;
      _deepStartAt = null;
    }

    if (isSlow) {
      _slowRateStartAt ??= now;
      _slowRateStreak++;
    } else {
      _slowRateStreak = 0;
      _slowRateStartAt = null;
    }

    if (isFast) {
      _fastRateStartAt ??= now;
      _fastRateStreak++;
    } else {
      _fastRateStreak = 0;
      _fastRateStartAt = null;
    }

    if (isOnTarget) {
      _targetStartAt ??= now;
    } else {
      _targetStartAt = null;
    }

    // 3. Enforce minimum cooldown window between any two spoken prompts
    if (now.difference(_lastPromptAt!).inMilliseconds <
        config.promptCooldownMs) {
      return 0;
    }

    bool isSustained(DateTime? startAt, int streak) {
      if (streak >= config.consecutiveErrorStrokes) return true;
      if (startAt != null &&
          now.difference(startAt).inMilliseconds >=
              config.sustainedErrorWindowMs) {
        return true;
      }
      return false;
    }

    // 4. Priority Arbitration
    // Priority 1: Incomplete chest recoil (when force sensor / trusted recoil is active)
    if (isSustained(_leaningStartAt, _leaningStreak)) {
      _lastPromptAt = now;
      _leaningStreak = 0;
      _leaningStartAt = null;
      return AppBleConfig.cueReleaseFully;
    }

    // Priority 2 (when unsteady) / Priority 3 (when steady): Rate coaching
    // When rhythm is unsteady, rate cues take priority to stabilize cadence.
    if (rhythmUnsteady) {
      if (isSustained(_slowRateStartAt, _slowRateStreak)) {
        _lastPromptAt = now;
        _slowRateStreak = 0;
        _slowRateStartAt = null;
        return AppBleConfig.cueSpeedUp;
      }
      if (isSustained(_fastRateStartAt, _fastRateStreak)) {
        _lastPromptAt = now;
        _fastRateStreak = 0;
        _fastRateStartAt = null;
        return AppBleConfig.cueSlowDown;
      }
      return 0;
    }

    // Priority 2 (when steady): Compression Depth
    if (isSustained(_shallowStartAt, _shallowStreak)) {
      _lastPromptAt = now;
      _shallowStreak = 0;
      _shallowStartAt = null;
      return AppBleConfig.cuePushHarder;
    }
    if (isSustained(_deepStartAt, _deepStreak)) {
      _lastPromptAt = now;
      _deepStreak = 0;
      _deepStartAt = null;
      return AppBleConfig.cuePushShallower;
    }

    // Priority 3 (when steady): Compression Rate
    if (isSustained(_slowRateStartAt, _slowRateStreak)) {
      _lastPromptAt = now;
      _slowRateStreak = 0;
      _slowRateStartAt = null;
      return AppBleConfig.cueSpeedUp;
    }
    if (isSustained(_fastRateStartAt, _fastRateStreak)) {
      _lastPromptAt = now;
      _fastRateStreak = 0;
      _fastRateStartAt = null;
      return AppBleConfig.cueSlowDown;
    }

    // Priority 4: Positive reinforcement ("Correct compressions") every 15s on target
    if (isOnTarget &&
        _targetStartAt != null &&
        now.difference(_targetStartAt!).inMilliseconds >=
            config.positivePraiseIntervalMs &&
        now.difference(_lastPraiseAt!).inMilliseconds >=
            config.positivePraiseIntervalMs) {
      _lastPromptAt = now;
      _lastPraiseAt = now;
      _targetStartAt = now;
      return AppBleConfig.cueGoodJob;
    }

    return 0;
  }
}

