/// Aggregated theme data exposed to widgets via [CpReadyTheme].
///
/// Carries config subsystems plus the Flutter [ThemeData] so any widget can
/// read colors, sizes, spacing, typography, durations, and strings from the
/// build context without knowing where they come from.

import 'package:flutter/material.dart';

import '../config/config.dart';
import 'color_scheme.dart';
import 'component_themes.dart';
import 'text_theme.dart';

/// Full theme data consumed by the app.
class AppThemeData {
  const AppThemeData({
    required this.colors,
    required this.sizes,
    required this.spacing,
    required this.typography,
    required this.durations,
    required this.strings,
    required this.theme,
  });

  final AppColors colors;
  final AppSizes sizes;
  final AppSpacing spacing;
  final AppTypography typography;
  final AppDurations durations;
  final AppStrings strings;

  /// The Flutter [ThemeData] built from config.
  final ThemeData theme;

  /// Convenience access to config via the static AppConfig (same values).
  static AppThemeData of(BuildContext context) {
    final cpReadyTheme = context
        .dependOnInheritedWidgetOfExactType<CpReadyTheme>()!;
    return cpReadyTheme.data;
  }
}

/// InheritedWidget that exposes [AppThemeData] down the tree.
class CpReadyTheme extends InheritedWidget {
  final AppThemeData data;

  const CpReadyTheme({
    super.key,
    required this.data,
    required super.child,
  });

  @override
  bool updateShouldNotify(CpReadyTheme oldWidget) =>
      data.theme != oldWidget.data.theme;
}

/// Builds the light [ThemeData] and [AppThemeData] from config.
ThemeData buildAppTheme() {
  final colorScheme = cpReadyLightColorScheme();
  final textTheme = cpReadyTextTheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    fontFamily: AppTypography.fontFamily,
    primaryColor: colorScheme.primary,
    buttonTheme: cpReadyButtonTheme(),
    cardTheme: cpReadyCardTheme(),
    inputDecorationTheme: cpReadyInputDecorationTheme(),
    bottomNavigationBarTheme: cpReadyBottomNavigationBarTheme(),
    scaffoldBackgroundColor: AppColors.surfaceScaffold,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
    ),
  );
}

/// Assembles an [AppThemeData] from config + [ThemeData].
AppThemeData appThemeData() {
  return AppThemeData(
    colors: AppColors(),
    sizes: AppSizes(),
    spacing: AppSpacing(),
    typography: AppTypography(),
    durations: AppDurations(),
    strings: AppStrings(),
    theme: buildAppTheme(),
  );
}
