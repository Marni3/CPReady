import 'package:flutter/material.dart';

import 'ble_controller.dart';
import 'cpr_metrics.dart';

/// Color-coded BLE connection status chip.
class ConnectionStatusChip extends StatelessWidget {
  final BleController controller;

  const ConnectionStatusChip({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final (label, color) = switch (controller.status) {
          BleStatus.disconnected => ('Disconnected', Colors.grey),
          BleStatus.scanning => ('Scanning\u2026', Colors.blue),
          BleStatus.connecting => ('Connecting\u2026', Colors.orange),
          BleStatus.connected => ('Connected', Colors.green),
          BleStatus.error => (
              'Error: ${controller.lastError}',
              Colors.red,
            ),
        };

        return Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Connect / reconnect button with busy states.
class ConnectButton extends StatelessWidget {
  final BleController controller;

  const ConnectButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.isBusy;
        final connected = controller.status == BleStatus.connected;

        final String label;
        if (busy) {
          label = controller.status == BleStatus.scanning
              ? 'Scanning\u2026'
              : 'Connecting\u2026';
        } else if (connected) {
          label = 'Connected \u2713 \u2014 Tap to reconnect';
        } else {
          label = 'Connect to CPReady';
        }

        return ElevatedButton(
          onPressed: busy ? null : controller.connect,
          child: busy
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(label),
                  ],
                )
              : Text(label),
        );
      },
    );
  }
}

/// Press-and-hold button that fills a circular progress ring; fires
/// [onComplete] when the hold reaches [duration].
class HoldToConfirmButton extends StatefulWidget {
  final String label;

  /// Label shown while the hold is active (falls back to [label]).
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

    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _cancel(),
      onLongPressCancel: _cancel,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 160,
                height: 160,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CircularProgressIndicator(
                    value: _controller.value,
                    strokeWidth: 6,
                    backgroundColor: scheme.errorContainer,
                    color: scheme.error,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop_circle_outlined, color: scheme.error),
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

/// A single label/value row used in metrics cards.
class MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const MetricRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Card displaying decoded CPReady metrics (live packet or final summary).
class MetricsCard extends StatelessWidget {
  final CprMetrics metrics;

  const MetricsCard({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final isSummary = metrics.packetType == 4;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSummary ? 'Session Summary' : 'Live Metrics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            MetricRow('Type', packetTypeLabel(metrics.packetType)),
            MetricRow('Rate', '${metrics.rateCpm} cpm'),
            MetricRow(
              'Depth',
              '${metrics.depthCm.toStringAsFixed(2)} cm / '
              '${metrics.depthMm.toStringAsFixed(1)} mm',
            ),
            MetricRow(
              'Recoil',
              isSummary
                  ? '${metrics.recoilPercentage}%'
                  : (metrics.recoilComplete ? 'Full' : 'Leaning'),
            ),
            MetricRow('CCF', '${metrics.ccfPercent}%'),
            MetricRow('Audio Cue', audioPromptText(metrics.audioPromptCode)),
            MetricRow('Compressions', '${metrics.totalCompressions}'),
            MetricRow('Elapsed', '${metrics.elapsedSeconds}s'),
          ],
        ),
      ),
    );
  }
}
