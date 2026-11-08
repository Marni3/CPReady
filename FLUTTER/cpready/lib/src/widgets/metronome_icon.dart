/// The live-header metronome toggle glyph.
///
/// Uses the supplied artwork (`assets/images/metronome.png`) rather than a
/// font icon, so it keeps the picture's navy body and white tick detail. The
/// switched-off state dims the artwork and draws a slash across it.

import 'package:flutter/material.dart';

import '../config/config.dart';

class MetronomeIcon extends StatelessWidget {
  const MetronomeIcon({super.key, required this.enabled, this.size, this.color});

  /// Whether the metronome is on; the off state dims the glyph and adds a
  /// slash.
  final bool enabled;

  /// Icon box size; defaults to [AppSizes.iconMedium].
  final double? size;

  /// Slash color; defaults to the ambient [IconTheme] color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final double box = size ?? AppSizes.iconMedium;
    final Color slash =
        color ?? IconTheme.of(context).color ?? AppColors.liveLabelText;

    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: Image.asset(
              AppAssets.iconMetronome,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
          if (!enabled)
            CustomPaint(
              painter: _SlashPainter(
                color: slash,
                strokeWidth: box * 0.09,
              ),
            ),
        ],
      ),
    );
  }
}

class _SlashPainter extends CustomPainter {
  const _SlashPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.14, size.height * 0.90),
      Offset(size.width * 0.86, size.height * 0.10),
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
