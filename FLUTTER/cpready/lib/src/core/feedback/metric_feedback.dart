/// Grading and display formatting for the live and summary metric values.
///
/// Target ranges live in [AppTargets] and the unit suffixes in [AppStrings];
/// this file only applies them.

import '../../config/config.dart';
import '../history/history_format.dart';

/// How a value compares with its target range.
enum MetricRating {
  /// Inside the target range (green).
  good,

  /// Outside the target range (red).
  poor,
}

/// Grade for the compression rate, or null when there is no value yet.
MetricRating? rateRating(int? cpm) {
  if (cpm == null || cpm <= 0) return null;
  final bool inRange =
      cpm >= AppTargets.rateMinCpm && cpm <= AppTargets.rateMaxCpm;
  return inRange ? MetricRating.good : MetricRating.poor;
}

/// Grade for the compression depth, or null when there is no value yet.
///
/// The target is a band, not a floor: a stroke that is too deep is graded poor
/// just like one that is too shallow.
MetricRating? depthRating(double? cm) {
  if (cm == null || cm <= 0.0) return null;
  final bool inRange =
      cm >= AppTargets.depthMinCm && cm <= AppTargets.depthMaxCm;
  return inRange ? MetricRating.good : MetricRating.poor;
}

/// Grade for recoil, or null when there is no value yet.
///
/// 0 is a real value (no full release), so it grades poor rather than neutral.
/// Pass [estimated] for firmware that marks recoil as an acceleration estimate:
/// that value cannot see leaning, so it is shown but not graded.
MetricRating? recoilRating(int? percent, {bool estimated = false}) {
  if (percent == null || estimated) return null;
  return percent >= AppTargets.recoilGoodPercent
      ? MetricRating.good
      : MetricRating.poor;
}

/// Grade for chest compression fraction against the AHA minimum, or null when
/// there is no value.
MetricRating? ccfRating(int? percent) {
  if (percent == null) return null;
  return percent >= AppTargets.ccfMinPercent
      ? MetricRating.good
      : MetricRating.poor;
}

/// "110cpm", or the placeholder when there is nothing to show yet.
String rateText(int? cpm) =>
    (cpm == null || cpm <= 0) ? AppStrings.liveNoValue : '$cpm${AppStrings.liveRateUnit}';

/// "5.4cm", or the placeholder. One decimal matches the tenths-of-a-millimetre
/// resolution the firmware sends.
String depthText(double? cm) => (cm == null || cm <= 0.0)
    ? AppStrings.liveNoValue
    : '${cm.toStringAsFixed(1)}${AppStrings.liveDepthUnit}';

/// "Full" / "Partial", or the placeholder.
String recoilText(int? percent) {
  if (percent == null) return AppStrings.liveNoValue;
  return percent >= AppTargets.recoilFullPercent
      ? AppStrings.liveRecoilFull
      : AppStrings.liveRecoilPartial;
}

/// "74%", or the placeholder.
String percentText(int? percent) => percent == null
    ? AppStrings.liveNoValue
    : '$percent${AppStrings.livePercentUnit}';

/// "02:05" — the shared clock format, also used by the History list.
String durationText(int seconds) => formatHistoryDuration(seconds);
