/// AHA target ranges that the live and summary feedback is graded against.
///
/// Mirrors the firmware's constants in
/// `CPReady_Program/include/CPReadyConfig.h` (`TARGET_RATE_MIN_CPM`,
/// `TARGET_RATE_MAX_CPM`, `TARGET_DEPTH_MIN_CM`, `TARGET_DEPTH_MAX_CM`) so the
/// app and the device agree on what "in range" means. Grading logic lives in
/// `lib/src/core/feedback/metric_feedback.dart`.

class AppTargets {
  /// AHA adult lower bound for compression rate (compressions per minute).
  static const int rateMinCpm = 100;

  /// AHA adult upper bound for compression rate (compressions per minute).
  static const int rateMaxCpm = 120;

  /// AHA minimum compression depth, in centimetres.
  static const double depthMinCm = 5.0;

  /// AHA maximum compression depth, in centimetres.
  ///
  /// Compressions deeper than this are over-compression and are graded poor,
  /// the same way the firmware prompts "push shallower" above 6.0 cm.
  static const double depthMaxCm = 6.0;

  /// Recoil percentage that counts as a full release.
  static const int recoilFullPercent = 100;

  /// Share of strokes with full recoil that grades a session's recoil as good.
  /// A live stroke is 0 or 100, so it is graded by the same rule.
  static const int recoilGoodPercent = 90;

  /// AHA minimum chest compression fraction, in percent.
  static const int ccfMinPercent = 60;
}
