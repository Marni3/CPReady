/// Press-and-hold button that fills from left to right while held and fires
/// [onComplete] once the hold reaches [duration]. Releasing early drains the
/// fill back to empty.
///
/// The label sits on the brand gradient; the fill is a translucent overlay, so
/// it reads as a loading indicator rather than a second background.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Gradient "hold to confirm" button.
class HoldFillButton extends StatefulWidget {
  final String label;
  final Duration duration;
  final Future<void> Function()? onComplete;
  final bool enabled;

  const HoldFillButton({
    super.key,
    required this.label,
    this.duration = const Duration(seconds: 3),
    this.onComplete,
    this.enabled = true,
  });

  @override
  State<HoldFillButton> createState() => _HoldFillButtonState();
}

class _HoldFillButtonState extends State<HoldFillButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_fired) {
      _fired = true;
      widget.onComplete?.call();
    }
  }

  void _start() {
    if (!widget.enabled) return;
    _fired = false;
    _controller.forward(from: 0);
  }

  void _cancel() {
    if (_controller.isAnimating && !_fired) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.5,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: AppSizes.liveHoldButtonHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.liveHoldButtonRadius),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _start(),
            onTapUp: (_) => _cancel(),
            onTapCancel: _cancel,
            child: Stack(
              children: <Widget>[
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.brandHorizontal,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _controller.value,
                        heightFactor: 1,
                        child: const ColoredBox(
                          color: AppColors.liveHoldFillOverlay,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.flowActionLabelInsetH,
                    vertical: AppSpacing.flowActionLabelInsetV,
                  ),
                  child: Center(
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: AppTypography.style(
                        size: AppTypography.flowActionSize,
                        weight: AppTypography.headingWeight,
                        color: AppColors.homeWelcomeText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
