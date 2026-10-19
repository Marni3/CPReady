/// Status chip: colored dot + label, built from config colors/sizes.

import 'package:flutter/material.dart';



/// Connection status chip rendered as a dot + text label.
class AppChip extends StatelessWidget {
  final String label;
  final Color color;
  final double dotRadius;

  const AppChip({
    super.key,
    required this.label,
    required this.color,
    this.dotRadius = 6.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotRadius * 2,
          height: dotRadius * 2,
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
  }
}
