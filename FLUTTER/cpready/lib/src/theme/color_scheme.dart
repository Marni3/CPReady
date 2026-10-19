/// Light ColorScheme assembled from [AppColors].

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Builds the light [ColorScheme] from semantic config colors.
ColorScheme cpReadyLightColorScheme() {
  return ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.brandPrimary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.brandSurface,
    onPrimaryContainer: Colors.black,
    secondary: AppColors.brandSecondary,
    onSecondary: Colors.white,
    surface: AppColors.surfaceScaffold,
    onSurface: AppColors.onSurface,
    error: AppColors.statusError,
    onError: Colors.white,
    errorContainer: AppColors.statusError.withValues(alpha: 0.1),
    onErrorContainer: AppColors.onErrorContainer,
  );
}
