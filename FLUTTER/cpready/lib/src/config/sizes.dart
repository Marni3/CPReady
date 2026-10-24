/// Geometric sizes: radii, border widths, elevations, icon sizes.

class AppSizes {
  // -----------------------------------------------------------------------
  // Component dimensions
  // -----------------------------------------------------------------------

  /// Diameter of the connection status dot.
  static const double statusDotRadius = 6.0;

  /// Width/height of the press-and-hold confirmation button.
  static const double buttonHoldSize = 160.0;

  /// Icon size inside the hold-to-confirm button.
  static const double buttonHoldIconSize = 18.0;

  // -----------------------------------------------------------------------
  // Progress indicators
  // -----------------------------------------------------------------------

  static const double progressStrokeWidth = 6.0;
  static const double progressStrokeWidthSmall = 2.0;

  // -----------------------------------------------------------------------
  // Icons
  // -----------------------------------------------------------------------

  static const double iconSmall = 18.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 48.0;
  static const double iconXLarge = 64.0;
  static const double iconXXLarge = 80.0;

  // -----------------------------------------------------------------------
  // Borders & elevation
  // -----------------------------------------------------------------------

  static const double borderRadiusCard = 12.0;
  static const double borderRadiusChip = 12.0;
  static const double elevationCard = 1.0;

  // -----------------------------------------------------------------------
  // Splash / loading screen
  // -----------------------------------------------------------------------

  /// Rendered width of the splash logo (the source image is square).
  static const double splashLogoWidth = 180.0;

  /// Width of the tiny loading line under the "CPReady" wordmark.
  static const double splashLoaderWidth = 200.0;

  /// Thickness of the tiny loading line.
  static const double splashLoaderHeight = 4.0;

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// Rendered size of the small logo in the home header.
  static const double homeLogoSize = 52.0;

  /// Thickness of the thin black divider (home header + bottom nav).
  static const double dividerThickness = 1.5;

  /// Corner radius of the home cards.
  static const double homeCardRadius = 20.0;

  /// Minimum height of the gradient welcome card; it grows with its text.
  static const double homeWelcomeCardMinHeight = 132.0;

  /// Border width of the home cards.
  static const double homeCardBorderWidth = 1.5;

  /// Rendered size of the bluetooth illustration on the device card.
  static const double homeBluetoothImageSize = 70.0;

  /// Height of the gradient call-to-action button.
  static const double homeButtonHeight = 54.0;

  /// Corner radius of the gradient call-to-action button.
  static const double homeButtonRadius = 14.0;

  /// Dash length of the dotted info-card border.
  static const double homeDottedDash = 1.5;

  /// Gap between dashes of the dotted info-card border.
  static const double homeDottedGap = 2.0;

  /// Stroke width of the heartbeat (ECG) nav icon.
  static const double heartbeatStrokeWidth = 1.0;

  /// Rendered size of the bottom-nav icons.
  static const double navIconSize = 28.0;

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  /// Corner radius of the gradient option cards.
  static const double practiceCardRadius = 20.0;

  /// Corner radius of the slim dotted option box.
  static const double practiceDottedRadius = 12.0;

  /// Thickness of the dotted border around the option box.
  static const double practiceDottedThickness = 1.5;

  /// Dash length of the dotted option box border.
  static const double practiceDottedDash = 1.5;

  /// Gap between dashes of the dotted option box border.
  static const double practiceDottedGap = 2.0;

  /// Width reserved on the right of an option card for its logo. The logo is
  /// scaled to the height of the text block beside it.
  static const double practiceOptionIconWidth = 72.0;

  // -----------------------------------------------------------------------
  // Step-by-step guide screen
  // -----------------------------------------------------------------------

  /// Size of the transparent back button glyph.
  static const double guideBackIconSize = 18.0;

  /// Thickness of the black edge around each step card.
  static const double guideStepCardBorderWidth = 1.0;

  /// Diameter of the red numbered circle.
  static const double guideNumberCircleSize = 28.0;

  /// Corner radius of the step cards.
  static const double guideStepCardRadius = 16.0;

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// Corner radius of a session row.
  static const double historyRowRadius = 12.0;

  /// Thickness of the edge drawn around a session row.
  static const double historyRowBorderWidth = 1.0;

  /// Corner radius of the "Interrupted" label.
  static const double historyInterruptedLabelRadius = 6.0;

  /// Bottom "Clear History" button (matches the home gradient button).
  static const double historyClearButtonHeight = 54.0;
  static const double historyClearButtonRadius = 14.0;

  /// Three-dot session-actions glyph, and the tap box around it.
  static const double historyMoreIconSize = 20.0;
  static const double historyMoreTapSize = 32.0;

  /// Minimum height of the outlined "See more" capsule on a session row (kept
  /// low enough to sit on the same line as the timestamp).
  static const double historySeeMoreMinHeight = 22.0;
  static const double historySeeMoreRadius = 11.0;
  static const double historySeeMoreBorderWidth = 1.0;

  // -----------------------------------------------------------------------
  // Practice flow (setup / hand placement / calibration / countdown)
  // -----------------------------------------------------------------------

  /// Size of the transparent back-arrow glyph on the flow screens.
  static const double flowBackIconSize = 18.0;

  /// Corner radius of the big instructional panel.
  static const double flowPanelRadius = 24.0;

  /// Thickness of the grey edge around the panel and the name field.
  static const double flowPanelBorderWidth = 1.0;

  /// Height of the trainee-name field.
  static const double flowFieldHeight = 56.0;

  /// Corner radius of the name field.
  static const double flowFieldRadius = 12.0;

  /// Height of the flat action button.
  static const double flowActionHeight = 54.0;

  /// Corner radius of the flat action button.
  static const double flowActionRadius = 14.0;

  /// Rendered size of the hand-placement illustration (the source is square).
  /// Also used by Calibration, which shows the same picture.
  static const double flowHandImageSize = 150.0;

  /// Size of the Hand Placement and Calibration cards. The width never exceeds
  /// the space available, and the height is a floor so the card grows when its
  /// text wraps on a narrow screen.
  static const double flowCardWidth = 284.0;
  static const double flowCardMinHeight = 290.0;

  /// Rendered size of the countdown illustration (the source is square).
  static const double countdownImageSize = 190.0;

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  /// Corner radius and edge width of a metric section.
  static const double liveSectionRadius = 12.0;
  static const double liveSectionBorderWidth = 1.0;

  /// Padding between a metric section's edge and its value capsule, so the
  /// capsule stops short of the section instead of spanning it.
  static const double liveSectionPaddingH = 16.0;

  /// Minimum height of the Rate / Recoil / Depth sections.
  static const double liveSectionMinHeight = 96.0;

  /// Value capsule (pill).
  static const double liveCapsuleHeight = 44.0;
  static const double liveCapsuleRadius = 22.0;
  static const double liveCapsulePaddingH = 10.0;

  /// One width for the Rate / Recoil / Depth capsules, so all three read as the
  /// same pill. A narrower section clamps it, so it never overflows.
  static const double liveCapsuleWidth = 132.0;

  /// Compression-count section: narrower than the Depth section.
  static const double liveCounterWidth = 200.0;
  static const double liveCounterHeight = 152.0;
  static const double liveCounterCircleSize = 112.0;

  /// Diameter of the status bullet / cross glyph.
  static const double liveStatusGlyphSize = 14.0;

  /// Gradient "Hold to End Session" button.
  static const double liveHoldButtonHeight = 54.0;
  static const double liveHoldButtonRadius = 14.0;

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  static const double summaryBannerRadius = 24.0;
  static const double summaryPanelRadius = 16.0;
  static const double summaryPanelBorderWidth = 1.0;
  static const double summaryRowRadius = 16.0;
  static const double summaryRowBorderWidth = 1.0;

  /// Minimum height of a metric row; it grows with its label.
  static const double summaryRowMinHeight = 52.0;
  static const double summaryCapsuleHeight = 30.0;
  static const double summaryCapsuleRadius = 15.0;

  /// One fixed width for all five metric capsules, so the rows line up.
  static const double summaryCapsuleWidth = 84.0;

  /// Minimum height of the "Session Saved" banner. Deliberately taller than its
  /// text so the green fill reads as a solid bar.
  static const double summarySavedBannerHeight = 92.0;
}
