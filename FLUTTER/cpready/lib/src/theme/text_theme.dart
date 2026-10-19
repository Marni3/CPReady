/// TextTheme assembled from [AppTypography].

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Builds the light [TextTheme] from semantic config typography.
TextTheme cpReadyTextTheme() {
  return TextTheme(
    displaySmall: AppTypography.style(
      size: AppTypography.displaySmallSize,
      weight: AppTypography.displaySmallWeight,
      color: AppColors.onSurface,
    ),
    headlineSmall: AppTypography.style(
      size: AppTypography.headlineSmallSize,
      weight: AppTypography.headlineSmallWeight,
      color: AppColors.onSurface,
    ),
    titleLarge: AppTypography.style(
      size: AppTypography.titleLargeSize,
      weight: AppTypography.titleLargeWeight,
      color: AppColors.onSurface,
    ),
    titleMedium: AppTypography.style(
      size: AppTypography.titleMediumSize,
      weight: AppTypography.titleMediumWeight,
      color: AppColors.onSurface,
    ),
    titleSmall: AppTypography.style(
      size: AppTypography.titleSmallSize,
      weight: AppTypography.titleSmallWeight,
      color: AppColors.onSurface,
    ),
    bodyLarge: AppTypography.style(
      size: AppTypography.bodyLargeSize,
      weight: AppTypography.bodyLargeWeight,
      color: AppColors.onSurface,
    ),
    bodyMedium: AppTypography.style(
      size: AppTypography.bodyMediumSize,
      weight: AppTypography.bodyMediumWeight,
      color: AppColors.onSurface,
    ),
    bodySmall: AppTypography.style(
      size: AppTypography.bodySmallSize,
      weight: AppTypography.bodySmallWeight,
      color: AppColors.onSurfaceVariant,
    ),
    labelLarge: AppTypography.style(
      size: AppTypography.labelLargeSize,
      weight: AppTypography.labelLargeWeight,
      color: AppColors.onSurface,
    ),
  );
}
