/// Proportional scale for the app's design dimensions.
///
/// The interface is authored against a 393 x 852 canvas. Sizes, spacing and
/// font values are written in design pixels and multiplied here, so a phone
/// reproduces the same proportions instead of showing fixed logical pixels
/// that look smaller on a large screen and cramped on a small one.
///
/// Both factors are bounded: screens narrower than 334 dp keep the 0.85 floor
/// and screens wider than 491 dp keep the 1.25 ceiling, which stops a small
/// phone from becoming unreadable and a large one from looking oversized.
///
/// [update] is called from the app shell whenever the window metrics change,
/// before anything below it builds.

import 'package:flutter/widgets.dart';

class AppScale {
  const AppScale._();

  /// Canvas the config values are authored against.
  static const Size designSize = Size(393.0, 852.0);

  /// Smallest factor applied to a design value.
  static const double minFactor = 0.85;

  /// Largest factor applied to a design value.
  static const double maxFactor = 1.25;

  static double _width = designSize.width;
  static double _height = designSize.height;

  /// Records the current window size in logical pixels.
  static void update(Size size) {
    _width = size.width;
    _height = size.height;
  }

  /// Width-based factor: drives horizontal metrics and typography.
  static double get widthFactor =>
      (_width / designSize.width).clamp(minFactor, maxFactor);

  /// Height-based factor: drives the vertical rhythm.
  static double get heightFactor =>
      (_height / designSize.height).clamp(minFactor, maxFactor);

  /// Horizontal design value: widths, icon boxes, horizontal padding, radii,
  /// border widths and text.
  static double w(num value) => value * widthFactor;

  /// Vertical design value: gaps, vertical padding and anything sized from the
  /// height the screen offers.
  static double h(num value) => value * heightFactor;

  /// Corner radius, scaled with the horizontal factor.
  static double r(num value) => w(value);

  /// Font size. Text follows [widthFactor], never the Android font setting.
  static double sp(num value) => w(value);
}
