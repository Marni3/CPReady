import 'dart:async';

import 'package:flutter/material.dart';

import '../cpr_metrics.dart';
import '../main.dart';
import 'live_practice_screen.dart';

/// Baseline calibration step of the practice flow.
///
/// START is sent when this screen opens (the firmware only calibrates after
/// receiving START) and AGAIN when Begin Session is tapped.
class CalibrationScreen extends StatefulWidget {
  final String traineeName;

  const CalibrationScreen({super.key, required this.traineeName});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

enum _CalibState { waiting, calibrating, ready, error }

class _CalibrationScreenState extends State<CalibrationScreen> {
  StreamSubscription<CprMetrics>? _sub;
  _CalibState _state = _CalibState.waiting;
  bool _busy = false;
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    _startCalibration();
  }

  Future<void> _startCalibration() async {
    final controller = AppScope.of(context);

    await _sub?.cancel();
    _sub = controller.packets.listen(_onPacket);

    try {
      // Kick off firmware calibration.
      await controller.sendCommand('START');
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _CalibState.error;
        });
      }
    }
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;
    switch (metrics.packetType) {
      case 2:
        setState(() => _state = _CalibState.calibrating);
      case 3:
        setState(() => _state = _CalibState.ready);
      case 5:
        setState(() => _state = _CalibState.error);
      default:
        break; // realtime packets are ignored here
    }
  }

  Future<void> _beginSession() async {
    if (_busy || _state != _CalibState.ready) return;
    final controller = AppScope.of(context);

    setState(() => _busy = true);
    try {
      // START again to arm the session (firmware briefly re-calibrates).
      await controller.sendCommand('START');
    } catch (_) {
      // Still navigate; the live screen surfaces connection problems.
    }
    if (!mounted) return;
    setState(() => _busy = false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BeginCompressionScreen(traineeName: widget.traineeName),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _state == _CalibState.ready;

    final String statusText = switch (_state) {
      _CalibState.waiting => 'Starting calibration\u2026',
      _CalibState.calibrating => 'Calibrating\u2026',
      _CalibState.ready => 'Baseline ready.',
      _CalibState.error => 'Calibration problem.',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Baseline Calibration')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.fingerprint, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (!ready)
                        Text(
                          'Not ready. Keep hands still and release downward '
                          'pressure.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: ready && !_busy ? _beginSession : null,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Begin Session'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Short prompt shown after Begin Session; auto-advances to live practice.
class BeginCompressionScreen extends StatefulWidget {
  final String traineeName;

  const BeginCompressionScreen({super.key, required this.traineeName});

  @override
  State<BeginCompressionScreen> createState() => _BeginCompressionScreenState();
}

class _BeginCompressionScreenState extends State<BeginCompressionScreen> {
  Timer? _timer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), _go);
  }

  void _go() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LivePracticeScreen(traineeName: widget.traineeName),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.accessibility_new, size: 80),
                const SizedBox(height: 24),
                Text(
                  'Begin Compression Now',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Get into position. The live session starts automatically.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _go,
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
