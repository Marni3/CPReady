/// Geometric sizes: radii, border widths, elevations, icon sizes.

import 'scale.dart';

class AppSizes {
  // -----------------------------------------------------------------------
  // Component dimensions
  // -----------------------------------------------------------------------

  /// Diameter of the connection status dot.
  static double get statusDotRadius => AppScale.w(6.0);

  /// Width/height of the press-and-hold confirmation button.
  static double get buttonHoldSize => AppScale.w(160.0);

  /// Icon size inside the hold-to-confirm button.
  static double get buttonHoldIconSize => AppScale.w(18.0);

  // -----------------------------------------------------------------------
  // Progress indicators
  // -----------------------------------------------------------------------

  static double get progressStrokeWidth => AppScale.w(6.0);
  static double get progressStrokeWidthSmall => AppScale.w(2.0);

  // -----------------------------------------------------------------------
  // Icons
  // -----------------------------------------------------------------------

  static double get iconSmall => AppScale.w(18.0);
  static double get iconMedium => AppScale.w(24.0);
  static double get iconLarge => AppScale.w(48.0);
  static double get iconXLarge => AppScale.w(64.0);
  static double get iconXXLarge => AppScale.w(80.0);

  // -----------------------------------------------------------------------
  // Borders & elevation
  // -----------------------------------------------------------------------

  static double get borderRadiusCard => AppScale.w(12.0);
  static double get borderRadiusChip => AppScale.w(12.0);
  static const double elevationCard = 1.0;

  // -----------------------------------------------------------------------
  // Splash / loading screen
  // -----------------------------------------------------------------------

  /// Rendered width of the splash logo (the source image is square).
  static double get splashLogoWidth => AppScale.w(180.0);

  /// Width of the tiny loading line under the "CPReady" wordmark.
  static double get splashLoaderWidth => AppScale.w(200.0);

  /// Thickness of the tiny loading line.
  static double get splashLoaderHeight => AppScale.w(4.0);

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// Rendered size of the small logo in the home header.
  static double get homeLogoSize => AppScale.w(52.0);

  /// Thickness of the thin black divider (home header + bottom nav).
  static double get dividerThickness => AppScale.w(1.5);

  /// Corner radius of the home cards.
  static double get homeCardRadius => AppScale.w(20.0);

  /// Minimum height of the gradient welcome card; it grows with its text.
  static double get homeWelcomeCardMinHeight => AppScale.w(132.0);

  /// Border width of the home cards.
  static double get homeCardBorderWidth => AppScale.w(1.5);

  /// Rendered size of the bluetooth illustration on the device card.
  static double get homeBluetoothImageSize => AppScale.w(70.0);

  /// Minimum height of the gradient call-to-action button; it grows when its
  /// label wraps.
  static double get homeButtonHeight => AppScale.w(54.0);

  /// Corner radius of the gradient call-to-action button.
  static double get homeButtonRadius => AppScale.w(14.0);

  /// Dash length of the dotted info-card border.
  static double get homeDottedDash => AppScale.w(1.5);

  /// Gap between dashes of the dotted info-card border.
  static double get homeDottedGap => AppScale.w(2.0);

  /// Stroke width of the heartbeat (ECG) nav icon.
  static double get heartbeatStrokeWidth => AppScale.w(1.0);

  /// Rendered size of the bottom-nav icons.
  static double get navIconSize => AppScale.w(28.0);

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  /// Corner radius of the gradient option cards.
  static double get practiceCardRadius => AppScale.w(20.0);

  /// Corner radius of the slim dotted option box.
  static double get practiceDottedRadius => AppScale.w(12.0);

  /// Thickness of the dotted border around the option box.
  static double get practiceDottedThickness => AppScale.w(1.5);

  /// Dash length of the dotted option box border.
  static double get practiceDottedDash => AppScale.w(1.5);

  /// Gap between dashes of the dotted option box border.
  static double get practiceDottedGap => AppScale.w(2.0);

  /// Width reserved on the right of an option card for its logo. The logo is
  /// scaled to the height of the text block beside it.
  static double get practiceOptionIconWidth => AppScale.w(72.0);

  // -----------------------------------------------------------------------
  // Step-by-step guide screen
  // -----------------------------------------------------------------------

  /// Size of the transparent back button glyph.
  static double get guideBackIconSize => AppScale.w(18.0);

  /// Thickness of the black edge around each step card.
  static double get guideStepCardBorderWidth => AppScale.w(1.0);

  /// Diameter of the red numbered circle.
  static double get guideNumberCircleSize => AppScale.w(28.0);

  /// Space between the step number and the badge's edge; the badge grows with
  /// the number.
  static double get guideNumberCirclePadding => AppScale.w(6.0);

  /// Corner radius of the step cards.
  static double get guideStepCardRadius => AppScale.w(16.0);

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// Corner radius of a session row.
  static double get historyRowRadius => AppScale.w(12.0);

  /// Thickness of the edge drawn around a session row.
  static double get historyRowBorderWidth => AppScale.w(1.0);

  /// Corner radius of the "Interrupted" label.
  static double get historyInterruptedLabelRadius => AppScale.w(6.0);

  /// Minimum height of the "Clear History" button (matches the home gradient
  /// button); it grows when its label wraps.
  static double get historyClearButtonHeight => AppScale.w(54.0);
  static double get historyClearButtonRadius => AppScale.w(14.0);

  /// Three-dot session-actions glyph, and the tap box around it.
  static double get historyMoreIconSize => AppScale.w(20.0);
  static double get historyMoreTapSize => AppScale.w(32.0);

  /// Minimum height of the outlined "See more" capsule on a session row (kept
  /// low enough to sit on the same line as the timestamp).
  static double get historySeeMoreMinHeight => AppScale.w(22.0);
  static double get historySeeMoreRadius => AppScale.w(11.0);
  static double get historySeeMoreBorderWidth => AppScale.w(1.0);

  // -----------------------------------------------------------------------
  // Practice flow (setup / hand placement / calibration / countdown)
  // -----------------------------------------------------------------------

  /// Size of the transparent back-arrow glyph on the flow screens.
  static double get flowBackIconSize => AppScale.w(18.0);

  /// Corner radius of the big instructional panel.
  static double get flowPanelRadius => AppScale.w(24.0);

  /// Thickness of the grey edge around the panel and the name field.
  static double get flowPanelBorderWidth => AppScale.w(1.0);

  /// Height of the trainee-name field.
  static double get flowFieldHeight => AppScale.w(56.0);

  /// Corner radius of the name field.
  static double get flowFieldRadius => AppScale.w(12.0);

  /// Height of the flat action button.
  static double get flowActionHeight => AppScale.w(54.0);

  /// Corner radius of the flat action button.
  static double get flowActionRadius => AppScale.w(14.0);

  /// Rendered size of the hand-placement illustration (the source is square).
  /// Also used by Calibration, which shows the same picture.
  static double get flowHandImageSize => AppScale.w(150.0);

  /// Smallest the illustration shrinks to while the card is short; below this
  /// the card keeps the picture and lets the screen scroll.
  static double get flowHandImageMinSize => AppScale.w(40.0);

  /// Size of the Hand Placement and Calibration cards. The width never exceeds
  /// the space available, and the height is a floor so the card grows when its
  /// text wraps on a narrow screen.
  static double get flowCardWidth => AppScale.w(284.0);
  static double get flowCardMinHeight => AppScale.w(290.0);

  /// Rendered size of the countdown illustration (the source is square).
  static double get countdownImageSize => AppScale.w(190.0);

  // -----------------------------------------------------------------------
  // Practice setup — training mode
  // -----------------------------------------------------------------------

  /// Corner radius and edge width of a training-mode option.
  static double get profileOptionRadius => AppScale.w(12.0);
  static double get profileOptionBorderWidth => AppScale.w(1.0);

  /// Radio indicator: outer ring and inner dot.
  static double get profileOptionIndicatorSize => AppScale.w(20.0);
  static double get profileOptionIndicatorDotSize => AppScale.w(10.0);
  static double get profileOptionIndicatorBorderWidth => AppScale.w(2.0);

  /// Minimum height of an option; it grows when its description wraps.
  static double get profileOptionMinHeight => AppScale.w(52.0);

  // -----------------------------------------------------------------------
  // Manikin depth calibration
  // -----------------------------------------------------------------------

  /// Corner radius and edge width of the mean-depth box.
  static double get manikinValueRadius => AppScale.w(12.0);
  static double get manikinValueBorderWidth => AppScale.w(1.0);

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  /// Corner radius and edge width of a metric section.
  static double get liveSectionRadius => AppScale.w(12.0);
  static double get liveSectionBorderWidth => AppScale.w(1.0);

  /// Padding between a metric section's edge and its value capsule, so the
  /// capsule stops short of the section instead of spanning it.
  static double get liveSectionPaddingH => AppScale.w(16.0);

  /// Minimum height of the Rate / Recoil / Depth sections.
  static double get liveSectionMinHeight => AppScale.w(96.0);

  /// Value capsule (pill).
  static double get liveCapsuleHeight => AppScale.w(44.0);
  static double get liveCapsuleRadius => AppScale.w(22.0);
  static double get liveCapsulePaddingH => AppScale.w(10.0);

  /// One width for the Rate / Recoil / Depth capsules, so all three read as the
  /// same pill. A narrower section clamps it, so it never overflows.
  static double get liveCapsuleWidth => AppScale.w(132.0);

  /// Compression-count section: narrower than the Depth section. Width and
  /// height are minimums; the section grows with its circle.
  static double get liveCounterWidth => AppScale.w(200.0);
  static double get liveCounterHeight => AppScale.w(152.0);

  /// Smallest diameter of the counter circle; it grows to hold its two lines.
  static double get liveCounterCircleSize => AppScale.w(112.0);

  /// Space between the counter circle and the section's edge, and between the
  /// circle's edge and its two lines.
  static double get liveCounterCardPadding => AppScale.w(12.0);
  static double get liveCounterCirclePadding => AppScale.w(12.0);

  /// Diameter of the status bullet / cross glyph.
  static double get liveStatusGlyphSize => AppScale.w(14.0);

  /// Gradient "Hold to End Session" button.
  static double get liveHoldButtonHeight => AppScale.w(54.0);
  static double get liveHoldButtonRadius => AppScale.w(14.0);

  /// Voice-cue toggle in the live header: glyph and its tap box.
  static double get liveMuteIconSize => AppScale.w(24.0);
  static double get liveMuteTapSize => AppScale.w(40.0);

  /// Cadence-warning banner.
  static double get liveNoticeRadius => AppScale.w(10.0);
  static double get liveNoticeBorderWidth => AppScale.w(1.0);

  /// "BENCH MODE" capsule.
  static double get liveBenchBadgeRadius => AppScale.w(8.0);

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  static double get summaryBannerRadius => AppScale.w(24.0);
  static double get summaryPanelRadius => AppScale.w(16.0);
  static double get summaryPanelBorderWidth => AppScale.w(1.0);
  static double get summaryRowRadius => AppScale.w(16.0);
  static double get summaryRowBorderWidth => AppScale.w(1.0);

  /// Minimum height of a metric row; it grows with its label.
  static double get summaryRowMinHeight => AppScale.w(52.0);
  static double get summaryCapsuleHeight => AppScale.w(30.0);
  static double get summaryCapsuleRadius => AppScale.w(15.0);

  /// One fixed width for all five metric capsules, so the rows line up.
  static double get summaryCapsuleWidth => AppScale.w(84.0);

  /// Minimum height of the "Session Saved" banner. Deliberately taller than its
  /// text so the green fill reads as a solid bar.
  static double get summarySavedBannerHeight => AppScale.w(92.0);
}
