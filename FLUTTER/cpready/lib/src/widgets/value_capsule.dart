/// Rounded value pill ("110cpm", "Full", "74%").
///
/// Used by the live metric sections and the Session Summary rows; geometry,
/// colors and type come from config so the two call sites can differ.

import 'package:flutter/material.dart';

import '../config/config.dart';
import '../core/feedback/metric_feedback.dart';

/// Rounded pill holding a single value.
class ValueCapsule extends StatelessWidget {
  const ValueCapsule({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    required this.height,
    required this.radius,
    required this.textSize,
    this.textWeight = FontWeight.bold,
    this.width,
  });

  /// Value shown inside the pill.
  final String text;

  /// Pill fill.
  final Color background;

  /// Value color.
  final Color foreground;

  /// Pill height.
  final double height;

  /// Corner radius (half the height for a pill).
  final double radius;

  /// Value font size.
  final double textSize;

  /// Value font weight.
  final FontWeight textWeight;

  /// Optional fixed width. The live sections omit it, so the capsule fills the
  /// section; the summary rows set it so all five capsules match.
  final double? width;

  /// Fill for a graded capsule: green in range, red out of range, grey when
  /// there is no value yet.
  static Color gradedBackground(MetricRating? rating) => switch (rating) {
    MetricRating.good => AppColors.liveCapsulePositive,
    MetricRating.poor => AppColors.liveCapsuleNegative,
    null => AppColors.liveCapsuleNeutral,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.liveCapsulePaddingH,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: AppTypography.style(
            size: textSize,
            weight: textWeight,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
