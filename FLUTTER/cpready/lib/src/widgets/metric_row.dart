/// A single label/value row used in metrics cards.

import 'package:flutter/material.dart';

/// Label/value row with config-driven text styles.
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
