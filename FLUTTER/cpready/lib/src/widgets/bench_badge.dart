/// Capsule marking a session that runs the relaxed bench profile.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Shared bench-mode badge used by the live screen and the result screen.
class BenchBadge extends StatelessWidget {
  const BenchBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.liveBenchBadgePaddingH,
        vertical: AppSpacing.liveBenchBadgePaddingV,
      ),
      decoration: BoxDecoration(
        color: AppColors.liveBenchBadgeBackground,
        borderRadius: BorderRadius.circular(AppSizes.liveBenchBadgeRadius),
      ),
      child: Text(
        AppStrings.liveBenchBadge,
        style: AppTypography.style(
          size: AppTypography.liveBenchBadgeSize,
          weight: FontWeight.bold,
          color: AppColors.liveBenchBadgeText,
        ),
      ),
    );
  }
}
