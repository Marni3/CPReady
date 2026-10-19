/// Component themes (buttons, cards, inputs, bottom nav) assembled from config.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Button theme data derived from config colors/sizes/typography.
ButtonThemeData cpReadyButtonTheme() {
  return ButtonThemeData(
    textTheme: ButtonTextTheme.primary,
    height: 48.0,
    minWidth: 88.0,
    alignedDropdown: false,
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.borderRadiusCard),
    ),
  );
}

/// Card theme derived from config.
CardThemeData cpReadyCardTheme() {
  return CardThemeData(
    elevation: AppSizes.elevationCard,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.borderRadiusCard),
    ),
    color: AppColors.surfaceCard,
    margin: const EdgeInsets.all(0),
  );
}

/// Input decoration theme derived from config.
InputDecorationTheme cpReadyInputDecorationTheme() {
  return InputDecorationTheme(
    border: const OutlineInputBorder(),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
  );
}

/// Bottom navigation bar theme derived from config.
BottomNavigationBarThemeData cpReadyBottomNavigationBarTheme() {
  return BottomNavigationBarThemeData(
    backgroundColor: AppColors.surfaceScaffold,
    selectedItemColor: AppColors.brandPrimary,
    unselectedItemColor: AppColors.onSurfaceVariant,
    type: BottomNavigationBarType.fixed,
  );
}
