/// Spacer sized from the [AppSpacing] scale.
///
/// Replaces inline [SizedBox] magic numbers so density is configured once.

import 'package:flutter/material.dart';

import '../../config/config.dart';

/// Vertical space.
class AppVSpacer extends StatelessWidget {
  final double size;

  const AppVSpacer(this.size, {super.key});

  /// Named spacing from the config scale.
  AppVSpacer.page({super.key}) : size = AppSpacing.page;
  AppVSpacer.section({super.key}) : size = AppSpacing.section;
  AppVSpacer.item({super.key}) : size = AppSpacing.item;
  AppVSpacer.small({super.key}) : size = AppSpacing.small;
  AppVSpacer.tiny({super.key}) : size = AppSpacing.tiny;
  AppVSpacer.card({super.key}) : size = AppSpacing.card;

  @override
  Widget build(BuildContext context) => SizedBox(height: size);
}

/// Horizontal space.
class AppHSpacer extends StatelessWidget {
  final double size;

  const AppHSpacer(this.size, {super.key});

  AppHSpacer.page({super.key}) : size = AppSpacing.page;
  AppHSpacer.section({super.key}) : size = AppSpacing.section;
  AppHSpacer.item({super.key}) : size = AppSpacing.item;
  AppHSpacer.small({super.key}) : size = AppSpacing.small;
  AppHSpacer.tiny({super.key}) : size = AppSpacing.tiny;
  AppHSpacer.card({super.key}) : size = AppSpacing.card;

  @override
  Widget build(BuildContext context) => SizedBox(width: size);
}
