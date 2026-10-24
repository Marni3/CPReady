/// Flat action button: an edge-less [AppColors.flowActionBackground] fill with
/// thick blue text.
///
/// Used by the practice flow (Continue, Begin Session) and by the Session
/// Summary (Return to Home). It has no ripple, matching the flow screens.
///
/// [AppSizes.flowActionHeight] is a minimum: a label that does not fit on one
/// line wraps and the button grows with it, so the text is never clipped.

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

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: AppSizes.flowActionHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.flowActionBackground,
          borderRadius: BorderRadius.circular(AppSizes.flowActionRadius),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.flowActionLabelInsetH,
                vertical: AppSpacing.flowActionLabelInsetV,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
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
      ),
    );
  }
}
