import 'dart:async';

import 'package:flutter/material.dart';

import '../ble_controller.dart';
import '../cpr_metrics.dart';
import '../main.dart';
import '../shared_widgets.dart';
import 'session_complete_screen.dart';

/// Active CPR practice session: live metrics, stale-data supervision,
/// and the press-and-hold End Session control.
class LivePracticeScreen extends StatefulWidget {
  final String traineeName;

  const LivePracticeScreen({super.key, required this.traineeName});

  @override
  State<LivePracticeScreen> createState() => _LivePracticeScreenState();
}

class _LivePracticeScreenState extends State<LivePracticeScreen> {
  static const _staleTimeout = Duration(seconds: 3);

  BleController? _controller;
  bool _initialized = false;

  StreamSubscription<CprMetrics>? _packetSub;
  Timer? _staleTimer;

  CprMetrics? _latest;
  bool _stale = false;
  bool _ending = false;
  bool _finished = false;
  int _recorded = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final controller = AppScope.of(context);
    _controller = controller;

    controller.startRecording();
    controller.addListener(_onControllerChanged);

    _packetSub = controller.packets.listen(_onPacket);

    // Stale supervision: no packet for 3 s => suspend feedback.
    _staleTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _finished) return;
      final last = controller.lastPacketAt;
      final stale =
          last != null && DateTime.now().difference(last) > _staleTimeout;
      if (stale != _stale) {
        setState(() => _stale = stale);
      }
    });
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;
    setState(() {
      _latest = metrics;
      _recorded = _controller?.sessionPackets.length ?? 0;
    });

    // Firmware auto-stop: FINAL_SUMMARY arrives without us asking.
    if (metrics.packetType == 4 && !_ending && !_finished) {
      _finish(saved: true, summary: metrics);
    }
  }

  void _onControllerChanged() {
    if (!mounted || _finished || _ending) return;
    // Unexpected BLE disconnect mid-session: do NOT save the session.
    if (_controller?.status == BleStatus.error) {
      _finish(saved: false, summary: null);
    }
  }

  Future<void> _endSession() async {
    if (_ending || _finished) return;
    final controller = _controller;
    if (controller == null) return;

    setState(() => _ending = true);

    // Listen for FINAL_SUMMARY before/while sending STOP (2 s window).
    final summaryFuture = controller.packets
        .where((m) => m.packetType == 4)
        .first
        .then<CprMetrics?>((m) => m)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);

    try {
      await controller.sendCommand('STOP');
    } catch (_) {
      // Connection may already be gone; the timeout below decides.
    }

    final summary = await summaryFuture;

    if (!mounted || _finished) return;
    _finish(saved: summary != null, summary: summary);
  }

  void _finish({required bool saved, required CprMetrics? summary}) {
    if (_finished) return;
    _finished = true;

    final controller = _controller;
    _packetSub?.cancel();
    _staleTimer?.cancel();
    controller?.removeListener(_onControllerChanged);
    final recorded = controller?.stopRecording().length ?? 0;

    if (!mounted || controller == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionCompleteScreen(
          traineeName: widget.traineeName,
          saved: saved,
          summary: summary,
          recordedPackets: recorded,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    _staleTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return PopScope(
      canPop: false, // sessions end only via the End Session hold
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live Practice'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: controller == null
                ? const Center(child: Text('No connection state.'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: ConnectionStatusChip(controller: controller)),
                          const SizedBox(width: 8),
                          _LiveBadge(stale: _stale),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_stale)
                        Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Stale data \u2014 feedback suspended. Waiting '
                              'for BLE packets\u2026',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _latest == null
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 32),
                                  child: Center(
                                    child: Text('Waiting for telemetry\u2026'),
                                  ),
                                )
                              : Opacity(
                                  opacity: _stale ? 0.45 : 1,
                                  child: MetricsCard(metrics: _latest!),
                                ),
                        ),
                      ),
                      Text(
                        'Packets recorded: $_recorded',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      if (_ending) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text(
                          'Stopping session\u2026',
                          textAlign: TextAlign.center,
                        ),
                      ] else
                        Center(
                          child: HoldToConfirmButton(
                            label: 'End Session',
                            pressedLabel: 'Hold to End Session',
                            duration: const Duration(seconds: 3),
                            onComplete: _endSession,
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

/// LIVE / STALE badge.
class _LiveBadge extends StatelessWidget {
  final bool stale;

  const _LiveBadge({required this.stale});

  @override
  Widget build(BuildContext context) {
    final color = stale ? Colors.red : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        stale ? 'STALE' : 'LIVE',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
