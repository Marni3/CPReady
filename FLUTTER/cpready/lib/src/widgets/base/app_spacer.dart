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
  const AppVSpacer.page({super.key}) : size = AppSpacing.page;
  const AppVSpacer.section({super.key}) : size = AppSpacing.section;
  const AppVSpacer.item({super.key}) : size = AppSpacing.item;
  const AppVSpacer.small({super.key}) : size = AppSpacing.small;
  const AppVSpacer.tiny({super.key}) : size = AppSpacing.tiny;
  const AppVSpacer.card({super.key}) : size = AppSpacing.card;

  @override
  Widget build(BuildContext context) => SizedBox(height: size);
}

/// Horizontal space.
class AppHSpacer extends StatelessWidget {
  final double size;

  const AppHSpacer(this.size, {super.key});

  const AppHSpacer.page({super.key}) : size = AppSpacing.page;
  const AppHSpacer.section({super.key}) : size = AppSpacing.section;
  const AppHSpacer.item({super.key}) : size = AppSpacing.item;
  const AppHSpacer.small({super.key}) : size = AppSpacing.small;
  const AppHSpacer.tiny({super.key}) : size = AppSpacing.tiny;
  const AppHSpacer.card({super.key}) : size = AppSpacing.card;

  @override
  Widget build(BuildContext context) => SizedBox(width: size);
}
