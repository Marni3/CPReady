/// Central app configuration: identity, route names, and feature flags.
///
/// Visual values (colors, sizes, strings, etc.) live in their own config
/// classes and are accessed directly (e.g. [AppColors], [AppStrings]).

/// Application identity.
class AppIdentity {
  static const String name = 'CPReady';
  static const String version = '1.0.0';
  static const String packageName = 'com.example.cpready';
}

/// Route names consumed by GoRouter.
class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String practice = '/practice';
  static const String history = '/history';

  /// A single saved session, opened from the History list.
  static const String historyDetail = '/history/:id';
  static const String guide = '/guide';
  static const String setup = '/setup';
  static const String handPlacement = '/hand_placement';
  static const String calibration = '/calibration';
  static const String beginCompression = '/begin_compression';
  static const String livePractice = '/live_practice';
  static const String sessionComplete = '/session_complete';
  static const String manikinCalibration = '/manikin_calibration';

  static const List<String> all = <String>[
    splash,
    home,
    practice,
    history,
    historyDetail,
    guide,
    setup,
    handPlacement,
    calibration,
    beginCompression,
    livePractice,
    sessionComplete,
    manikinCalibration,
  ];
}

/// Feature flags.
class AppFeatures {
  static const bool requireHoldToEnd = true;
  static const bool showSplash = true;
}

/// Aggregates identity, routes, and features.
class AppConfig {
  static final AppIdentity identity = AppIdentity();
  static final AppRoutes routes = AppRoutes();
  static final AppFeatures features = AppFeatures();
}
