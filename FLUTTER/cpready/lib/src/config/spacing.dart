/// Spacing scale used for padding and margins throughout the app.
///
/// All spacing values live here so density can be adjusted in one place.

import 'package:flutter/material.dart';

class AppSpacing {
  /// Page-level padding (outer edge of content).
  static const double page = 24.0;

  /// Inner padding inside cards.
  static const double card = 24.0;

  /// Gap between major sections.
  static const double section = 24.0;

  /// Gap between items within a section.
  static const double item = 12.0;

  /// Small gap between related elements.
  static const double small = 8.0;

  /// Tiny gap (e.g. icon to text).
  static const double tiny = 4.0;

  // -----------------------------------------------------------------------
  // Splash / loading screen
  // -----------------------------------------------------------------------

  /// Gap between the splash logo and the "CPReady" wordmark.
  static const double splashLogoGap = 30.0;

  /// Gap between the wordmark and the tiny loading line.
  static const double splashLoaderGap = 80.0;

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// Gap between the home cards.
  static const double homeSectionGap = 16.0;

  /// Inner padding of the home cards.
  static const double homeCardPadding = 20.0;

  /// Gap between "Welcome!" and its subtitle.
  static const double homeWelcomeGap = 0.0;

  /// Left inset of the welcome text: pushes the (still left-aligned) block
  /// closer to the middle of the gradient card.
  static const double homeWelcomeInset = 50.0;

  /// Padding around the bluetooth illustration on the device card.
  static const double homeBluetoothImagePadding = 8.0;

  /// Space between the bottom-nav items.
  static const double navItemGap = 28.0;

  /// Horizontal padding inside each bottom-nav item (tap-target width).
  static const double navItemPadding = 14.0;

  /// Horizontal inset of the top + bottom dividers from each screen edge.
  static const double dividerInset = 24.0;

  /// Vertical breathing room around the top + bottom dividers.
  static const double dividerGap = 18.0;

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  /// Huge gap between the header divider and the "Practice" heading.
  static const double practiceTopPadding = 72.0;

  /// Gap between the "Practice" heading and the dotted option box.
  static const double practiceTitleGap = 20.0;

  /// Gap between the dotted option box and the first option card.
  static const double practiceOptionTopGap = 28.0;

  /// Gap between the two option cards.
  static const double practiceOptionGap = 32.0;

  /// Horizontal padding of the option cards.
  static const double practiceOptionPaddingH = 28.0;

  /// Vertical padding of the option cards — extra height around the text.
  static const double practiceOptionPaddingV = 44.0;

  /// Gap between an option card's text block and its logo.
  static const double practiceOptionIconGap = 14.0;

  /// Vertical padding inside the slim dotted option box.
  static const double practiceDottedPaddingV = 10.0;

  /// Horizontal padding inside the slim dotted option box.
  static const double practiceDottedPaddingH = 20.0;

  // -----------------------------------------------------------------------
  // Step-by-step guide screen
  // -----------------------------------------------------------------------

  /// Extra space above the back-arrow/title row, dropping the heading away
  /// from the top of the screen.
  static const double guideTopPadding = 56.0;

  /// Horizontal gap between the back arrow and the title on the same line.
  static const double guideBackTitleGap = 6.0;

  /// Tap slop above and below the back arrow.
  static const double guideBackTapV = 10.0;

  /// Tap slop to the right of the back arrow.
  static const double guideBackTapRight = 6.0;

  /// Gap between the title and the first step card.
  static const double guideTitleGap = 26.0;

  /// Extra inset of the step cards from each screen edge, on top of [page].
  static const double guideCardSideInset = 14.0;

  /// Gap between two step cards.
  static const double guideStepGap = 8.0;

  /// Vertical padding inside a step card.
  static const double guideStepPaddingV = 12.0;

  /// Horizontal padding inside a step card.
  static const double guideStepPaddingH = 14.0;

  /// Gap between the numbered circle and the step text.
  static const double guideNumberGap = 12.0;

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// Huge gap between the header divider and the "Session History" heading —
  /// the same position the Practice screen's title sits at.
  static const double historyTopPadding = 72.0;

  /// Gap between the heading and the list.
  static const double historyTitleGap = 20.0;

  /// Gap between the list and the bottom "Clear History" button.
  static const double historyClearButtonTopGap = 16.0;

  /// Gap under that button, above the bottom nav.
  static const double historyClearButtonBottomGap = 12.0;

  /// Gap between two session rows.
  static const double historyRowGap = 10.0;

  /// Inner padding of a session row.
  static const double historyRowPadding = 16.0;

  /// Gap between the trainee name and the timestamp line inside a row.
  static const double historyRowTextGap = 0.0;

  /// Gap between a row's timestamp and its "See more" capsule.
  static const double historyRowActionsGap = 8.0;

  /// Gap between a row's "See more" capsule and the three-dot button (the
  /// glyph already carries its own inset inside its tap box).
  static const double historyRowDotsGap = 0.0;

  /// Right inset of the duration so its right edge lands on the three-dot
  /// glyph, which sits inset inside its own tap box.
  static const double historyDurationRightPad = 6.0;

  /// Horizontal padding inside the outlined "See more" capsule.
  static const double historySeeMorePaddingH = 12.0;

  /// Horizontal padding inside the "Interrupted" label.
  static const double historyInterruptedPaddingH = 8.0;

  /// Vertical padding inside the "Interrupted" label.
  static const double historyInterruptedPaddingV = 2.0;

  // -----------------------------------------------------------------------
  // Practice flow (setup / hand placement / calibration / countdown)
  // -----------------------------------------------------------------------

  /// Space above the back-arrow/title row.
  static const double flowTopPadding = 56.0;

  /// Horizontal gap between the back arrow and the title.
  static const double flowBackTitleGap = 6.0;

  /// Tap slop above and below the back arrow.
  static const double flowBackTapV = 10.0;

  /// Tap slop to the right of the back arrow.
  static const double flowBackTapRight = 6.0;

  /// Gap between the title row and the first content block.
  static const double flowTitleGap = 34.0;

  /// Gap between the big heading and the name field.
  static const double flowHeadingGap = 18.0;

  /// Gap between the name field and its helper line.
  static const double flowHelperGap = 8.0;

  /// Horizontal padding inside the name field.
  static const double flowFieldPaddingH = 18.0;

  /// Padding under the flat action button.
  static const double flowActionBottomPadding = 28.0;

  /// Inner padding of the big instructional panel.
  static const double flowPanelPadding = 24.0;

  /// Gap between the panel's illustration and its text.
  static const double flowPanelContentGap = 20.0;

  /// Where the Hand Placement / Calibration card sits in the free space
  /// between the title and the action button. Negative Y lifts it above the
  /// middle.
  static const Alignment flowCardAlignment = Alignment(0.0, -0.45);

  /// Gap between the countdown number and its illustration.
  static const double countdownNumberGap = 26.0;

  /// Gap between the countdown illustration and the heading.
  static const double countdownImageGap = 22.0;

  /// Gap between the countdown heading and the helper line.
  static const double countdownHelperGap = 10.0;

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  /// Extra left inset of the title and the status line.
  static const double liveHeaderInset = 16.0;

  /// Gap between the title and the status line.
  static const double liveStatusGap = 6.0;

  /// Gap between the status line and the timer.
  static const double liveTimerTopGap = 26.0;

  /// Gap between the timer and its caption.
  static const double liveTimerLabelGap = 0.0;

  /// Gap between the timer block and the metric sections.
  static const double liveSectionTopGap = 28.0;

  /// Gap between the two side-by-side metric sections.
  static const double liveSectionGap = 16.0;

  /// Gap between stacked metric sections.
  static const double liveSectionStackGap = 14.0;

  /// Gap between a section heading and its capsule.
  static const double liveSectionLabelGap = 10.0;

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  /// Space between the top of the screen and the heading.
  static const double summaryTopPadding = 26.0;

  /// Left and right inset shared by the heading, the banner under it and the
  /// trainee line, so the three share one left edge.
  static const double summaryTitleInsetH = 40.0;

  /// Side inset of the metric panel and the action button — the widest
  /// elements on the screen.
  static const double summaryPanelInsetH = 16.0;

  /// Inner padding of the saved/not-saved banner.
  static const double summaryBannerPaddingV = 18.0;
  static const double summaryBannerPaddingH = 28.0;

  /// Gap between the heading and the banner.
  static const double summaryBannerGap = 18.0;

  /// Gap between the banner and the trainee line.
  static const double summaryTraineeGap = 14.0;

  /// Gap between the trainee line and the metric panel.
  static const double summaryPanelGap = 16.0;

  /// Space between a metric cell and the panel's left and right edges. This is
  /// what keeps a cell from spanning the whole section.
  static const double summaryPanelPaddingH = 32.0;

  /// Space above the first cell and below the duration line.
  static const double summaryPanelPaddingV = 24.0;

  /// Gap between two metric rows.
  static const double summaryRowGap = 14.0;

  /// Horizontal padding inside a metric row, between the row's edge and its
  /// label / value capsule.
  static const double summaryRowPaddingH = 12.0;

  /// Gap above the "Session Duration" line — its own separation from the cells
  /// above it.
  static const double summaryDurationGap = 32.0;

  /// Padding under the "Session Duration" line.
  static const double summaryDurationBottomPadding = 6.0;

  /// Side inset of the "Return to Home" button. Wider than the panel's inset,
  /// so the button is narrower than the panel and lines up with the heading
  /// block.
  static const double summaryActionInsetH = 40.0;

  /// Gap above the "Return to Home" button.
  static const double summaryActionTopGap = 20.0;
}
