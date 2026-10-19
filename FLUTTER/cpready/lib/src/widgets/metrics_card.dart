/// Card displaying decoded CPReady metrics (live packet or final summary).

import 'package:flutter/material.dart';

import 'metric_row.dart';
import '../core/metrics/cpr_metrics.dart';

/// Metrics card with config-driven spacing and strings.
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
