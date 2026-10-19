/// Flat action button: an edge-less [AppColors.flowActionBackground] fill with
/// thick blue text.
///
/// Used by the practice flow (Continue, Begin Session) and by the Session
/// Summary (Return to Home). It has no ripple, matching the flow screens.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Full-width flat action button.
class FlatActionButton extends StatelessWidget {
  const FlatActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.textWeight = AppTypography.headingWeight,
  });

  /// Button label.
  final String label;

  /// Tap handler; the button renders disabled when null.
  final VoidCallback? onPressed;

  /// Label weight (the flow screens use the thick weight).
  final FontWeight textWeight;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return SizedBox(
      width: double.infinity,
      height: AppSizes.flowActionHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.flowActionBackground,
          borderRadius: BorderRadius.circular(AppSizes.flowActionRadius),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: AppTypography.style(
                size: AppTypography.flowActionSize,
                weight: textWeight,
                color: enabled
                    ? AppColors.flowActionText
                    : AppColors.flowActionDisabledText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
