/// A rounded rectangle outlined with a dotted (dashed) border.
///
/// Wraps [child] in a [CustomPaint] that strokes the border around it. All
/// visual values default to the config-driven home card; pass overrides for
/// other uses (e.g. the slimmer Practice option box).

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../config/config.dart';

class DottedBorder extends StatelessWidget {
  const DottedBorder({
    super.key,
    required this.child,
    this.color = AppColors.homeCardBorder,
    this.strokeWidth = AppSizes.homeCardBorderWidth,
    this.radius = AppSizes.homeCardRadius,
    this.dash = AppSizes.homeDottedDash,
    this.gap = AppSizes.homeDottedGap,
    this.padding = EdgeInsets.zero,
  });

  /// Content placed inside the border.
  final Widget child;

  /// Border color.
  final Color color;

  /// Border thickness.
  final double strokeWidth;

  /// Corner radius of the border.
  final double radius;

  /// Length of each dash.
  final double dash;

  /// Space between dashes.
  final double gap;

  /// Padding between the border and [child].
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        strokeWidth: strokeWidth,
        radius: radius,
        dash: dash,
        gap: gap,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Paints a dashed rounded-rectangle border around its child.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final double inset = strokeWidth / 2;
    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}
