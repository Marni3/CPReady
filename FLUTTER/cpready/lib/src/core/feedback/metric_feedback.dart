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
  if (cpm == null) return null;
  final bool inRange =
      cpm >= AppTargets.rateMinCpm && cpm <= AppTargets.rateMaxCpm;
  return inRange ? MetricRating.good : MetricRating.poor;
}

/// Grade for the compression depth, or null when there is no value yet.
MetricRating? depthRating(double? cm) {
  if (cm == null) return null;
  return cm >= AppTargets.depthMinCm ? MetricRating.good : MetricRating.poor;
}

/// Grade for recoil, or null when there is no value yet.
MetricRating? recoilRating(int? percent) {
  if (percent == null) return null;
  return percent >= AppTargets.recoilFullPercent
      ? MetricRating.good
      : MetricRating.poor;
}

/// "110cpm", or the placeholder when there is nothing to show yet.
String rateText(int? cpm) =>
    cpm == null ? AppStrings.liveNoValue : '$cpm${AppStrings.liveRateUnit}';

/// "5.4cm", or the placeholder. One decimal matches the tenths-of-a-millimetre
/// resolution the firmware sends.
String depthText(double? cm) => cm == null
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
