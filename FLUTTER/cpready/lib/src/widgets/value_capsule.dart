/// Rounded value pill ("110cpm", "Full", "74%").
///
/// Used by the live metric sections and the Session Summary rows; geometry,
/// colors and type come from config so the two call sites can differ.
///
/// The pill grows with its label: [minHeight] and [minWidth] are floors, not
/// fixed sizes, so a larger rendered text size makes the pill taller and
/// wider instead of clipping the value.

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
    required this.minHeight,
    required this.radius,
    required this.textSize,
    this.textWeight = FontWeight.bold,
    this.minWidth = 0,
  });

  /// Value shown inside the pill.
  final String text;

  /// Pill fill.
  final Color background;

  /// Value color.
  final Color foreground;

  /// Smallest pill height; the pill grows when its text needs more room.
  final double minHeight;

  /// Corner radius (half the height for a pill).
  final double radius;

  /// Value font size.
  final double textSize;

  /// Value font weight.
  final FontWeight textWeight;

  /// Smallest pill width. The live sections omit it; the summary rows pass one
  /// so all five capsules share a left edge.
  final double minWidth;

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
      constraints: BoxConstraints(minWidth: minWidth, minHeight: minHeight),
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.liveCapsulePaddingH,
        vertical: AppSpacing.tiny,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.style(
          size: textSize,
          weight: textWeight,
          color: foreground,
        ),
      ),
    );
  }
}
