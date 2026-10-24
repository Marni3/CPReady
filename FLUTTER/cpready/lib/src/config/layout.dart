/// Responsive layout rules: breakpoints, page padding and content bounds.
///
/// Screens read these instead of hardcoding their own thresholds, so the
/// adaptation policy lives in one place.

class AppBreakpoints {
  /// Widest screen classed as compact (small phones).
  static const double compactMax = 359.0;
}

class AppLayout {
  /// Side padding on regular screens (360 dp and wider).
  static const double pagePadding = 24.0;

  /// Side padding on compact screens, to keep the content width usable.
  static const double compactPagePadding = 16.0;

  /// Widest content column; extra width becomes side margin.
  static const double contentMaxWidth = 520.0;

  /// Ceiling applied to the system text scale.
  static const double maxTextScale = 1.3;

  /// Narrowest a metric section may get before a side-by-side pair stacks.
  static const double minSectionWidth = 150.0;

  static bool isCompact(double width) => width <= AppBreakpoints.compactMax;

  /// Side padding for a screen of [width].
  static double pagePaddingFor(double width) =>
      isCompact(width) ? compactPagePadding : pagePadding;
}
