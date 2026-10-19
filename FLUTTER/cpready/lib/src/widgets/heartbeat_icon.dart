/// A plain heartbeat (ECG) line icon — no background, no frame.
///
/// Tinted by the ambient [IconTheme] so it follows the bottom-nav
/// selected/unselected colors automatically.

import 'package:flutter/material.dart';

import '../config/config.dart';

class HeartbeatIcon extends StatelessWidget {
  const HeartbeatIcon({super.key, this.size = AppSizes.iconMedium});

  /// Icon box size.
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color color = IconTheme.of(context).color ?? AppColors.navSelected;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HeartbeatPainter(
          color: color,
          strokeWidth: AppSizes.heartbeatStrokeWidth,
        ),
      ),
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  const _HeartbeatPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;
    final double mid = h / 2;

    final Path path = Path()
      ..moveTo(w * 0.04, mid)
      ..lineTo(w * 0.32, mid)
      ..lineTo(w * 0.44, mid - h * 0.38)
      ..lineTo(w * 0.56, mid + h * 0.32)
      ..lineTo(w * 0.66, mid)
      ..lineTo(w * 0.96, mid);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeartbeatPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
