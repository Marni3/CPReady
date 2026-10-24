/// Responsive layout rules: breakpoints, page padding and content bounds.
///
/// Screens read these instead of hardcoding their own thresholds, so the
/// adaptation policy lives in one place.

import 'scale.dart';

class AppBreakpoints {
  /// Widest screen classed as compact (small phones). A breakpoint compares
  /// against the real window, so it is never scaled.
  static const double compactMax = 359.0;
}

class AppLayout {
  /// Side padding on regular screens (360 dp and wider).
  static double get pagePadding => AppScale.w(24.0);

  /// Side padding on compact screens, to keep the content width usable.
  static double get compactPagePadding => AppScale.w(16.0);

  /// Widest content column; extra width becomes side margin. This is a cap on
  /// the reading width, not a design dimension, so it stays fixed.
  static const double contentMaxWidth = 520.0;

  /// Narrowest a metric section may get before a side-by-side pair stacks.
  static double get minSectionWidth => AppScale.w(150.0);

  static bool isCompact(double width) => width <= AppBreakpoints.compactMax;

  /// Side padding for a screen of [width].
  static double pagePaddingFor(double width) =>
      isCompact(width) ? compactPagePadding : pagePadding;
}
