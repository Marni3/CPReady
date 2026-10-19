/// A [Card] styled from config sizes/spacing.

import 'package:flutter/material.dart';

import '../../config/config.dart';

/// Standard app card with configured elevation, radius, and padding.
class AppCard extends StatelessWidget {
  final Widget child;
  final double? elevation;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const AppCard(
    this.child, {
    super.key,
    this.elevation,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation ?? AppSizes.elevationCard,
      color: color ?? AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadiusCard),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(24.0),
        child: child,
      ),
    );
  }
}
