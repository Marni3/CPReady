/// Press-and-hold button that fills a circular progress ring; fires
/// [onComplete] when the hold reaches [duration]. Styled from config.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Press-and-hold confirmation button.
class HoldToConfirmButton extends StatefulWidget {
  final String label;
  final String? pressedLabel;
  final Duration duration;
  final Future<void> Function()? onComplete;
  final bool enabled;

  const HoldToConfirmButton({
    super.key,
    required this.label,
    this.pressedLabel,
    this.duration = const Duration(seconds: 3),
    this.onComplete,
    this.enabled = true,
  });

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _fired = false;
  bool _pressed = false;

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
    setState(() => _pressed = true);
    _controller.forward(from: 0);
  }

  void _cancel() {
    if (_pressed) {
      setState(() => _pressed = false);
    }
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
    final scheme = Theme.of(context).colorScheme;
    final size = AppSizes.buttonHoldSize;
    final iconSize = AppSizes.buttonHoldIconSize;

    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _cancel(),
      onLongPressCancel: _cancel,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CircularProgressIndicator(
                    value: _controller.value,
                    strokeWidth: AppSizes.progressStrokeWidth,
                    backgroundColor: scheme.errorContainer,
                    color: scheme.error,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop_circle_outlined,
                      color: scheme.error, size: iconSize),
                  const SizedBox(height: 4),
                  Text(
                    _pressed
                        ? (widget.pressedLabel ?? widget.label)
                        : widget.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
