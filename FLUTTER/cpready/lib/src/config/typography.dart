/// Typography scale: font family, sizes, weights, and line heights.
///
/// Every [TextStyle] in the app derives from these values.
///
/// ---------------------------------------------------------------------------
/// CHANGING THE APP FONT
/// ---------------------------------------------------------------------------
/// [fontFamily] must match the `family` name declared under `fonts:` in
/// `pubspec.yaml` (currently "Montserrat"). To switch fonts:
///   1. Add the new .ttf files to `assets/fonts/`.
///   2. Update the `fonts:` section in `pubspec.yaml` (family + asset paths).
///   3. Set [fontFamily] below to the new family name.
/// Nothing in `lib/src/widgets/` or `lib/src/screens/` needs to change.

import 'package:flutter/material.dart';

/// Font family used app-wide. Set to null to use the Material default.
class AppTypography {
  /// Brand font family. Must match the `family:` key in `pubspec.yaml`.
  static const String? fontFamily = 'Montserrat';

  // -----------------------------------------------------------------------
  // Display / headline
  // -----------------------------------------------------------------------

  static const double displaySmallSize = 20.0;
  static const FontWeight displaySmallWeight = FontWeight.bold;

  static const double headlineSmallSize = 24.0;
  static const FontWeight headlineSmallWeight = FontWeight.bold;

  // -----------------------------------------------------------------------
  // Titles
  // -----------------------------------------------------------------------

  static const double titleLargeSize = 18.0;
  static const FontWeight titleLargeWeight = FontWeight.bold;

  static const double titleMediumSize = 16.0;
  static const FontWeight titleMediumWeight = FontWeight.normal;

  static const double titleSmallSize = 14.0;
  static const FontWeight titleSmallWeight = FontWeight.bold;

  // -----------------------------------------------------------------------
  // Body
  // -----------------------------------------------------------------------

  static const double bodyLargeSize = 16.0;
  static const FontWeight bodyLargeWeight = FontWeight.normal;

  static const double bodyMediumSize = 14.0;
  static const FontWeight bodyMediumWeight = FontWeight.normal;

  static const double bodySmallSize = 12.0;
  static const FontWeight bodySmallWeight = FontWeight.normal;

  // -----------------------------------------------------------------------
  // Labels & buttons
  // -----------------------------------------------------------------------

  static const double labelLargeSize = 14.0;
  static const FontWeight labelLargeWeight = FontWeight.normal;

  static const double buttonSize = 14.0;
  static const FontWeight buttonWeight = FontWeight.bold;

  // -----------------------------------------------------------------------
  // Splash / loading screen
  // -----------------------------------------------------------------------

  /// "CPReady" wordmark size on the splash screen.
  static const double splashTitleSize = 40.0;
  /// Weight of the splash wordmark (matches the other headings).
  static const FontWeight splashTitleWeight = headingWeight;

  /// Letter spacing for the splash wordmark.
  static const double splashTitleLetterSpacing = 1.0;

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// "CPREADY" wordmark size in the home header.
  static const double homeBrandSize = 16.0;

  /// "Home" page label size in the home header.
  static const double homePageSize = 13.0;

  /// "Welcome!" size on the gradient welcome card.
  static const double homeWelcomeSize = 30.0;

  /// "Start your training now" size on the welcome card (matches the title).
  static const double homeWelcomeSubtitleSize = homeWelcomeSize;

  /// Device-card headline ("No device connected yet" / "Connect Device").
  static const double homeCardTitleSize = 16.0;

  /// "Connect Device" headline shown in the card while connecting starts.
  static const double homeConnectingTitleSize = 22.0;

  /// Device-card supporting text.
  static const double homeCardSubtitleSize = 13.0;

  /// Dotted info-card paragraph size.
  static const double homeInfoSize = 10.0;

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  /// Big "Practice" heading under the header.
  static const double practiceTitleSize = 34.0;

  /// Bold "Choose an option below." inside the dotted box.
  static const double practiceOptionSubtitleSize = 16.0;

  /// Bold title inside an option card.
  static const double practiceOptionTitleSize = 21.0;

  /// Supporting text inside an option card.
  static const double practiceOptionBodySize = 13.0;

  // -----------------------------------------------------------------------
  // Step-by-step guide screen
  // -----------------------------------------------------------------------

  /// "Step-by-step Guide" heading.
  static const double guideTitleSize = 26.0;

  /// Step paragraph size.
  static const double guideStepSize = 12.0;

  /// Number inside the red circle.
  static const double guideNumberSize = 13.0;

  /// Heaviest weight we ship (Montserrat Black — see the `fonts:` list in
  /// `pubspec.yaml`). Used by the page headings and the header wordmark.
  static const FontWeight headingWeight = FontWeight.w900;

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// Trainee name on a session row.
  /// Screen heading (slightly smaller than the Practice screen's title).
  static const double historyTitleSize = 30.0;

  /// Label on the bottom "Clear History" button.
  static const double historyClearButtonSize = 16.0;

  static const double historyRowTitleSize = 18.0;

  /// Timestamp, duration and "See more" on a session row.
  static const double historyRowMetaSize = 14.0;

  /// The outlined "See more" capsule's own label (smaller than the row text).
  static const double historySeeMoreSize = 12.0;

  /// "Interrupted" label on a session row.
  static const double historyInterruptedSize = 11.0;

  // -----------------------------------------------------------------------
  // Helper: build a TextStyle from size + weight
  // -----------------------------------------------------------------------

  static TextStyle style({
    required double size,
    required FontWeight weight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // -----------------------------------------------------------------------
  // Practice flow (setup / hand placement / calibration / countdown)
  // -----------------------------------------------------------------------

  /// Title beside the back arrow ("Practice Setup", "Hand Placement",
  /// "Calibration").
  static const double flowTitleSize = 26.0;

  /// Big blue heading above the name field.
  static const double flowHeadingSize = 30.0;

  /// Text typed into the name field, and its placeholder.
  static const double flowFieldTextSize = 15.0;

  /// Small helper line under the name field.
  static const double flowHelperSize = 12.0;

  /// Label on the flat action button.
  static const double flowActionSize = 16.0;

  /// Instruction inside the hand-placement panel — and the Calibration status,
  /// which renders identically.
  static const double flowPanelHeadingSize = 26.0;

  /// Countdown number.
  static const double countdownNumberSize = 64.0;

  /// "Begin Compression Now".
  /// Big "Begin Compression Now" on the countdown. 10.4 em wide, so anything
  /// above ~33 stays on one line inside the page padding.
  static const double countdownTitleSize = 26.0;

  /// Helper line under the countdown heading.
  static const double countdownHelperSize = 12.0;

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  static const double liveTitleSize = 34.0;
  static const double liveStatusSize = 14.0;
  static const double liveTimerSize = 32.0;
  static const double liveTimerLabelSize = 15.0;
  static const double liveSectionLabelSize = 16.0;
  static const double liveCapsuleSize = 20.0;
  static const double liveCounterSize = 34.0;
  static const double liveCounterLabelSize = 12.0;

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  static const double summaryTitleSize = 30.0;
  static const double summaryBannerSize = 28.0;
  static const double summaryTraineeSize = 18.0;
  static const double summaryRowLabelSize = 15.0;
  static const double summaryCapsuleSize = 13.0;
  static const double summaryDurationLabelSize = 18.0;
}
