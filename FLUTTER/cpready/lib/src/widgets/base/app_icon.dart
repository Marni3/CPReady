/// An [Icon] sized/colored from config.

import 'package:flutter/material.dart';

import '../../config/config.dart';

/// Icon using a configured size and optional color.
class AppIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;

  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size ?? AppSizes.iconMedium,
      color: color,
    );
  }
}
