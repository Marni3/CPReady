/// Progress indicators (linear & circular) sized from config.

import 'package:flutter/material.dart';

import '../../config/config.dart';

/// Circular progress indicator using config stroke width.
class AppCircularProgress extends StatelessWidget {
  final double? value;
  final double? strokeWidth;
  final Color? color;
  final Color? backgroundColor;

  const AppCircularProgress({
    super.key,
    this.value,
    this.strokeWidth,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircularProgressIndicator(
      value: value,
      strokeWidth: strokeWidth ?? AppSizes.progressStrokeWidth,
      color: color ?? scheme.primary,
      backgroundColor: backgroundColor ?? scheme.surface,
    );
  }
}

/// Linear progress indicator using config stroke width.
class AppLinearProgress extends StatelessWidget {
  final double? value;
  final Color? color;
  final Color? backgroundColor;

  const AppLinearProgress({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LinearProgressIndicator(
      value: value,
      color: color ?? scheme.primary,
      backgroundColor: backgroundColor ?? scheme.surface,
      minHeight: AppSizes.progressStrokeWidthSmall,
    );
  }
}
