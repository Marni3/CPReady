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

import 'scale.dart';

/// Font family used app-wide. Set to null to use the Material default.
class AppTypography {
  /// Brand font family. Must match the `family:` key in `pubspec.yaml`.
  static const String? fontFamily = 'Montserrat';

  // -----------------------------------------------------------------------
  // Display / headline
  // -----------------------------------------------------------------------

  static double get displaySmallSize => AppScale.sp(20.0);
  static const FontWeight displaySmallWeight = FontWeight.bold;

  static double get headlineSmallSize => AppScale.sp(24.0);
  static const FontWeight headlineSmallWeight = FontWeight.bold;

  // -----------------------------------------------------------------------
  // Titles
  // -----------------------------------------------------------------------

  static double get titleLargeSize => AppScale.sp(18.0);
  static const FontWeight titleLargeWeight = FontWeight.bold;

  static double get titleMediumSize => AppScale.sp(16.0);
  static const FontWeight titleMediumWeight = FontWeight.normal;

  static double get titleSmallSize => AppScale.sp(14.0);
  static const FontWeight titleSmallWeight = FontWeight.bold;

  // -----------------------------------------------------------------------
  // Body
  // -----------------------------------------------------------------------

  static double get bodyLargeSize => AppScale.sp(16.0);
  static const FontWeight bodyLargeWeight = FontWeight.normal;

  static double get bodyMediumSize => AppScale.sp(14.0);
  static const FontWeight bodyMediumWeight = FontWeight.normal;

  static double get bodySmallSize => AppScale.sp(12.0);
  static const FontWeight bodySmallWeight = FontWeight.normal;

  // -----------------------------------------------------------------------
  // Labels & buttons
  // -----------------------------------------------------------------------

  static double get labelLargeSize => AppScale.sp(14.0);
  static const FontWeight labelLargeWeight = FontWeight.normal;

  static double get buttonSize => AppScale.sp(14.0);
  static const FontWeight buttonWeight = FontWeight.bold;

  // -----------------------------------------------------------------------
  // Splash / loading screen
  // -----------------------------------------------------------------------

  /// "CPReady" wordmark size on the splash screen.
  static double get splashTitleSize => AppScale.sp(40.0);

  /// Weight of the splash wordmark (matches the other headings).
  static const FontWeight splashTitleWeight = headingWeight;

  /// Letter spacing for the splash wordmark.
  static double get splashTitleLetterSpacing => AppScale.sp(1.0);

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// "CPREADY" wordmark size in the home header.
  static double get homeBrandSize => AppScale.sp(16.0);

  /// "Home" page label size in the home header.
  static double get homePageSize => AppScale.sp(13.0);

  /// "Welcome!" size on the gradient welcome card.
  static double get homeWelcomeSize => AppScale.sp(30.0);

  /// "Start your training now" size on the welcome card (matches the title).
  static double get homeWelcomeSubtitleSize => homeWelcomeSize;

  /// Device-card headline ("No device connected yet" / "Connect Device").
  static double get homeCardTitleSize => AppScale.sp(16.0);

  /// "Connect Device" headline shown in the card while connecting starts.
  static double get homeConnectingTitleSize => AppScale.sp(22.0);

  /// Device-card supporting text.
  static double get homeCardSubtitleSize => AppScale.sp(13.0);

  /// Dotted info-card paragraph size.
  static double get homeInfoSize => AppScale.sp(10.0);

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  /// Big "Practice" heading under the header.
  static double get practiceTitleSize => AppScale.sp(34.0);

  /// Bold "Choose an option below." inside the dotted box.
  static double get practiceOptionSubtitleSize => AppScale.sp(16.0);

  /// Bold title inside an option card.
  static double get practiceOptionTitleSize => AppScale.sp(18.0);

  /// Supporting text inside an option card.
  static double get practiceOptionBodySize => AppScale.sp(13.0);

  // -----------------------------------------------------------------------
  // Step-by-step guide screen
  // -----------------------------------------------------------------------

  /// "Step-by-step Guide" heading.
  static double get guideTitleSize => AppScale.sp(26.0);

  /// Step paragraph size.
  static double get guideStepSize => AppScale.sp(12.0);

  /// Number inside the red circle.
  static double get guideNumberSize => AppScale.sp(13.0);

  /// Heaviest weight the app uses (Montserrat Black — see the `fonts:` list in
  /// `pubspec.yaml`). Used by the page headings and the header wordmark.
  static const FontWeight headingWeight = FontWeight.w900;

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// Trainee name on a session row.
  /// Screen heading (slightly smaller than the Practice screen's title).
  static double get historyTitleSize => AppScale.sp(30.0);

  /// Label on the bottom "Clear History" button.
  static double get historyClearButtonSize => AppScale.sp(16.0);

  static double get historyRowTitleSize => AppScale.sp(18.0);

  /// Timestamp, duration and "See more" on a session row.
  static double get historyRowMetaSize => AppScale.sp(14.0);

  /// The outlined "See more" capsule's own label (smaller than the row text).
  static double get historySeeMoreSize => AppScale.sp(12.0);

  /// "Interrupted" label on a session row.
  static double get historyInterruptedSize => AppScale.sp(11.0);

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
  static double get flowTitleSize => AppScale.sp(26.0);

  /// Big blue heading above the name field.
  static double get flowHeadingSize => AppScale.sp(30.0);

  /// Text typed into the name field, and its placeholder.
  static double get flowFieldTextSize => AppScale.sp(15.0);

  /// Small helper line under the name field.
  static double get flowHelperSize => AppScale.sp(12.0);

  /// Label on the flat action button.
  static double get flowActionSize => AppScale.sp(16.0);

  /// Instruction inside the hand-placement panel — and the Calibration status,
  /// which renders identically.
  static double get flowPanelHeadingSize => AppScale.sp(26.0);

  /// Countdown number.
  static double get countdownNumberSize => AppScale.sp(64.0);

  /// "Training mode" section label.
  static double get setupProfileLabelSize => AppScale.sp(13.0);

  /// Training-mode option title and description.
  static double get profileOptionTitleSize => AppScale.sp(15.0);
  static double get profileOptionBodySize => AppScale.sp(11.0);

  // -----------------------------------------------------------------------
  // Manikin depth calibration
  // -----------------------------------------------------------------------

  /// Intro paragraph and the error line.
  static double get manikinBodySize => AppScale.sp(13.0);

  /// Small labels ("Time remaining", "Trial mean depth").
  static double get manikinLabelSize => AppScale.sp(13.0);

  /// The trial's mean depth.
  static double get manikinValueSize => AppScale.sp(22.0);

  /// "Begin Compression Now".
  /// Big "Begin Compression Now" on the countdown. 10.4 em wide, so anything
  /// above ~33 stays on one line inside the page padding.
  static double get countdownTitleSize => AppScale.sp(26.0);

  /// Helper line under the countdown heading.
  static double get countdownHelperSize => AppScale.sp(12.0);

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  static double get liveTitleSize => AppScale.sp(34.0);
  static double get liveStatusSize => AppScale.sp(14.0);
  static double get liveTimerSize => AppScale.sp(32.0);
  static double get liveTimerLabelSize => AppScale.sp(15.0);
  static double get liveSectionLabelSize => AppScale.sp(16.0);
  static double get liveCapsuleSize => AppScale.sp(20.0);
  static double get liveCounterSize => AppScale.sp(34.0);
  static double get liveCounterLabelSize => AppScale.sp(12.0);

  /// Cadence-warning banner and the "BENCH MODE" capsule.
  static double get liveNoticeSize => AppScale.sp(12.0);
  static double get liveBenchBadgeSize => AppScale.sp(10.0);

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  static double get summaryTitleSize => AppScale.sp(30.0);
  static double get summaryBannerSize => AppScale.sp(28.0);

  /// Banner size on compact screens, where the interrupted label would
  /// otherwise wrap far past the banner's width.
  static double get summaryBannerCompactSize => AppScale.sp(21.0);
  static double get summaryTraineeSize => AppScale.sp(18.0);
  static double get summaryRowLabelSize => AppScale.sp(15.0);
  static double get summaryCapsuleSize => AppScale.sp(13.0);
  static double get summaryDurationLabelSize => AppScale.sp(18.0);
}
