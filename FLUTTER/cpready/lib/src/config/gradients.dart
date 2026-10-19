/// Reusable gradients assembled from [AppColors].
///
/// Gradient stop colors live in `colors.dart`; this file only wires them into
/// [LinearGradient]s so widgets never hardcode a gradient.

import 'package:flutter/material.dart';

import 'colors.dart';

class AppGradients {
  /// Brand gradient, top → bottom. Used by the splash background and the home
  /// welcome card.
  static const LinearGradient brandVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      AppColors.brandGradientTop,
      AppColors.brandGradientBottom,
    ],
  );

  /// Brand gradient, left → right. Same stops, horizontal direction.
  static const LinearGradient brandHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[
      AppColors.brandGradientTop,
      AppColors.brandGradientBottom,
    ],
  );

  /// Splash / loading screen background (alias of [brandVertical]).
  static const LinearGradient splash = brandVertical;
}
