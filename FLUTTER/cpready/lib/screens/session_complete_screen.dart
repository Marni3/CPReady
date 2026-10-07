import 'package:flutter/material.dart';

import '../cpr_metrics.dart';
import '../shared_widgets.dart';

/// Result screen shown after a session ends (End Session hold complete)
/// or after an unexpected disconnect (session not saved).
class SessionCompleteScreen extends StatelessWidget {
  final String traineeName;
  final bool saved;
  final CprMetrics? summary;
  final int recordedPackets;

  const SessionCompleteScreen({
    super.key,
    required this.traineeName,
    required this.saved,
    required this.summary,
    required this.recordedPackets,
  });

  void _returnToPractice(BuildContext context) {
    // Remove every pushed route; land on the root shell (Practice tab
    // was active when the flow started).
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false, // explicit return only, never back into the session
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session Complete'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: saved ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          saved ? Icons.check_circle : Icons.error,
                          size: 48,
                          color: saved ? Colors.green : scheme.error,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          saved
                              ? 'Session Saved'
                              : 'Session Not Saved (disconnected)',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          saved
                              ? 'Final summary received from CPReady.'
                              : 'BLE link was lost \u2014 this session was '
                                  'discarded.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Trainee: $traineeName',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Packets recorded: $recordedPackets',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (summary != null)
                  Expanded(child: SingleChildScrollView(child: MetricsCard(metrics: summary!)))
                else
                  const Spacer(),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _returnToPractice(context),
                  child: const Text('Return to Practice'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
