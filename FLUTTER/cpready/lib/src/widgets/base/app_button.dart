/// Buttons: filled, outlined, and text variants styled from config.

import 'package:flutter/material.dart';

import '../../config/config.dart';

/// Button variant.
enum AppButtonVariant { filled, outlined, text }

/// Filled/outlined/text button using config typography/sizes/colors.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final Widget? icon;
  final bool isBusy;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.icon,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isBusy ? null : onPressed;
    final textStyle = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(fontWeight: AppTypography.buttonWeight);

    Widget child;
    if (isBusy) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSizes.buttonHoldIconSize,
            height: AppSizes.buttonHoldIconSize,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(label, style: textStyle),
        ],
      );
    } else {
      final children = <Widget>[];
      if (icon != null) children.add(icon!);
      if (icon != null) children.add(const SizedBox(width: 8));
      children.add(Text(label, style: textStyle));
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    switch (variant) {
      case AppButtonVariant.filled:
        return ElevatedButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
      case AppButtonVariant.outlined:
        return OutlinedButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
      case AppButtonVariant.text:
        return TextButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
    }
  }
}
