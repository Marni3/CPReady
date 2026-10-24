/// Small, transparent back arrow that sits on the same line as a screen title.
///
/// Used by the practice flow screens (Practice Setup, Hand Placement,
/// Calibration); tapping it returns to the screen that opened it.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/config.dart';

/// Back arrow for the practice flow screens.
class FlowBackButton extends StatelessWidget {
  const FlowBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.pop(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(
          top: AppSpacing.flowBackTapV,
          bottom: AppSpacing.flowBackTapV,
          right: AppSpacing.flowBackTapRight,
        ),
        child: Icon(
          Icons.arrow_back,
          size: AppSizes.flowBackIconSize,
          color: AppColors.flowBackIcon,
        ),
      ),
    );
  }
}
