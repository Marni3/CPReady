/// Spacing scale used for padding and margins throughout the app.
///
/// All spacing values live here so density can be adjusted in one place.

import 'package:flutter/material.dart';

import 'scale.dart';

class AppSpacing {
  /// Page-level padding (outer edge of content).
  static double get page => AppScale.w(24.0);

  /// Inner padding inside cards.
  static double get card => AppScale.w(24.0);

  /// Gap between major sections.
  static double get section => AppScale.w(24.0);

  /// Gap between items within a section.
  static double get item => AppScale.w(12.0);

  /// Small gap between related elements.
  static double get small => AppScale.w(8.0);

  /// Tiny gap (e.g. icon to text).
  static double get tiny => AppScale.w(4.0);

  // -----------------------------------------------------------------------
  // Splash / loading screen
  // -----------------------------------------------------------------------

  /// Gap between the splash logo and the "CPReady" wordmark.
  static double get splashLogoGap => AppScale.h(30.0);

  /// Gap between the wordmark and the tiny loading line.
  static double get splashLoaderGap => AppScale.h(80.0);

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// Gap between the home cards.
  static double get homeSectionGap => AppScale.h(16.0);

  /// Inner padding of the home cards.
  static double get homeCardPadding => AppScale.w(20.0);

  /// Gap between "Welcome!" and its subtitle.
  static double get homeWelcomeGap => AppScale.h(0.0);

  /// Horizontal breathing room inside the home gradient button, so a wrapped
  /// label does not touch the edges.
  static double get homeButtonLabelInsetH => AppScale.w(16.0);

  /// Left inset of the welcome text: pushes the (still left-aligned) block
  /// closer to the middle of the gradient card.
  static double get homeWelcomeInset => AppScale.w(50.0);

  /// Padding around the bluetooth illustration on the device card.
  static double get homeBluetoothImagePadding => AppScale.w(8.0);

  /// Space between the bottom-nav items.
  static double get navItemGap => AppScale.w(28.0);

  /// Space between the bottom-nav items on compact screens.
  static double get navItemGapCompact => AppScale.w(14.0);

  /// Horizontal padding inside each bottom-nav item (tap-target width).
  static double get navItemPadding => AppScale.w(14.0);

  /// Horizontal padding inside each bottom-nav item on compact screens.
  static double get navItemPaddingCompact => AppScale.w(8.0);

  /// Vertical breathing room around the top + bottom dividers.
  static double get dividerGap => AppScale.h(18.0);

  /// Gap between the header wordmark and its settings button.
  static double get headerSettingsGap => AppScale.w(8.0);

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  /// Gap between the header divider and the "Practice" heading.
  static double get practiceTopPadding => AppScale.h(24.0);

  /// Gap between the "Practice" heading and the dotted option box.
  static double get practiceTitleGap => AppScale.h(20.0);

  /// Gap between the dotted option box and the first option card.
  static double get practiceOptionTopGap => AppScale.h(28.0);

  /// Gap between the two option cards.
  static double get practiceOptionGap => AppScale.h(32.0);

  /// Horizontal padding of the option cards.
  static double get practiceOptionPaddingH => AppScale.w(28.0);

  /// Vertical padding of the option cards — extra height around the text.
  static double get practiceOptionPaddingV => AppScale.h(44.0);

  /// Gap between an option card's text block and its logo.
  static double get practiceOptionIconGap => AppScale.w(14.0);

  /// Vertical padding inside the slim dotted option box.
  static double get practiceDottedPaddingV => AppScale.h(10.0);

  /// Horizontal padding inside the slim dotted option box.
  static double get practiceDottedPaddingH => AppScale.w(20.0);

  // -----------------------------------------------------------------------
  // Step-by-step guide screen
  // -----------------------------------------------------------------------

  /// Extra space above the back-arrow/title row, dropping the heading away
  /// from the top of the screen.
  static double get guideTopPadding => AppScale.h(56.0);

  /// Horizontal gap between the back arrow and the title on the same line.
  static double get guideBackTitleGap => AppScale.w(6.0);

  /// Tap slop above and below the back arrow.
  static double get guideBackTapV => AppScale.h(10.0);

  /// Tap slop to the right of the back arrow.
  static double get guideBackTapRight => AppScale.w(6.0);

  /// Gap between the title and the first step card.
  static double get guideTitleGap => AppScale.h(26.0);

  /// Extra inset of the step cards from each screen edge, on top of [page].
  static double get guideCardSideInset => AppScale.w(14.0);

  /// Gap between two step cards.
  static double get guideStepGap => AppScale.h(8.0);

  /// Vertical padding inside a step card.
  static double get guideStepPaddingV => AppScale.h(12.0);

  /// Horizontal padding inside a step card.
  static double get guideStepPaddingH => AppScale.w(14.0);

  /// Gap between the numbered circle and the step text.
  static double get guideNumberGap => AppScale.w(12.0);

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// Gap between the header divider and the "Session History" heading — the
  /// same position the Practice screen's title sits at.
  static double get historyTopPadding => AppScale.h(24.0);

  /// Gap between the heading and the list.
  static double get historyTitleGap => AppScale.h(20.0);

  /// Gap between the list and the bottom "Clear History" button.
  static double get historyClearButtonTopGap => AppScale.h(16.0);

  /// Gap under that button, above the bottom nav.
  static double get historyClearButtonBottomGap => AppScale.h(12.0);

  /// Gap between two session rows.
  static double get historyRowGap => AppScale.h(10.0);

  /// Inner padding of a session row.
  static double get historyRowPadding => AppScale.w(16.0);

  /// Gap between the trainee name and the timestamp line inside a row.
  static double get historyRowTextGap => AppScale.h(0.0);

  /// Gap between a row's timestamp and its "See more" capsule.
  static double get historyRowActionsGap => AppScale.w(8.0);

  /// Gap between a row's "See more" capsule and the three-dot button (the
  /// glyph already carries its own inset inside its tap box).
  static double get historyRowDotsGap => AppScale.w(0.0);

  /// Right inset of the duration so its right edge lands on the three-dot
  /// glyph, which sits inset inside its own tap box.
  static double get historyDurationRightPad => AppScale.w(6.0);

  /// Horizontal padding inside the outlined "See more" capsule.
  static double get historySeeMorePaddingH => AppScale.w(12.0);

  /// Horizontal padding inside the "Interrupted" label.
  static double get historyInterruptedPaddingH => AppScale.w(8.0);

  /// Vertical padding inside the "Interrupted" label.
  static double get historyInterruptedPaddingV => AppScale.h(2.0);

  // -----------------------------------------------------------------------
  // Practice flow (setup / hand placement / calibration / countdown)
  // -----------------------------------------------------------------------

  /// Space above the back-arrow/title row.
  static double get flowTopPadding => AppScale.h(56.0);

  /// Horizontal gap between the back arrow and the title.
  static double get flowBackTitleGap => AppScale.w(6.0);

  /// Tap slop above and below the back arrow.
  static double get flowBackTapV => AppScale.h(10.0);

  /// Tap slop to the right of the back arrow.
  static double get flowBackTapRight => AppScale.w(6.0);

  /// Gap between the title row and the first content block.
  static double get flowTitleGap => AppScale.h(34.0);

  /// Gap between the big heading and the name field.
  static double get flowHeadingGap => AppScale.h(18.0);

  /// Gap between the name field and its helper line.
  static double get flowHelperGap => AppScale.h(8.0);

  /// Horizontal padding inside the name field.
  static double get flowFieldPaddingH => AppScale.w(18.0);

  /// Padding under the flat action button.
  static double get flowActionBottomPadding => AppScale.h(28.0);

  /// Space between two stacked action buttons.
  static double get flowActionStackGap => AppScale.h(12.0);

  /// Horizontal breathing room kept inside an action button, so a wrapped
  /// label does not touch the edges.
  static double get flowActionLabelInsetH => AppScale.w(16.0);

  /// Vertical breathing room above and below an action button's label. The
  /// button's height is a minimum, so a wrapped label adds height here.
  static double get flowActionLabelInsetV => AppScale.h(10.0);

  /// Inner padding of the big instructional panel.
  static double get flowPanelPadding => AppScale.w(24.0);

  /// Gap between the panel's illustration and its text.
  static double get flowPanelContentGap => AppScale.h(20.0);

  /// Where the Hand Placement / Calibration card sits in the free space
  /// between the title and the action button. Negative Y lifts it above the
  /// middle.
  static const Alignment flowCardAlignment = Alignment(0.0, -0.45);

  /// Gap between the countdown number and its illustration.
  static double get countdownNumberGap => AppScale.h(26.0);

  /// Gap between the countdown illustration and the heading.
  static double get countdownImageGap => AppScale.h(22.0);

  /// Gap between the countdown heading and the helper line.
  static double get countdownHelperGap => AppScale.h(10.0);

  // -----------------------------------------------------------------------
  // Practice setup — training mode
  // -----------------------------------------------------------------------

  /// Gap between the name helper line and the training-mode section.
  static double get setupProfileTopGap => AppScale.h(24.0);

  /// Gap between the section label and the first option.
  static double get setupProfileTitleGap => AppScale.h(10.0);

  /// Gap between the two options.
  static double get setupProfileOptionGap => AppScale.h(8.0);

  /// Inner padding of an option.
  static double get profileOptionPaddingV => AppScale.h(10.0);
  static double get profileOptionPaddingH => AppScale.w(14.0);

  /// Gap between the radio indicator and the text block, and between the
  /// option title and its description.
  static double get profileOptionIndicatorGap => AppScale.w(12.0);
  static double get profileOptionTextGap => AppScale.h(2.0);

  // -----------------------------------------------------------------------
  // Manikin depth calibration
  // -----------------------------------------------------------------------

  /// Gap between the intro/labels and the next block.
  static double get manikinSectionGap => AppScale.h(18.0);

  /// Gap between a field label and its field.
  static double get manikinFieldGap => AppScale.h(8.0);

  /// Gap between the target field and its unit.
  static double get manikinUnitGap => AppScale.w(8.0);

  /// Inner padding of the mean-depth box.
  static double get manikinValuePaddingV => AppScale.h(10.0);
  static double get manikinValuePaddingH => AppScale.w(14.0);

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  /// Extra left inset of the title and the status line.
  static double get liveHeaderInset => AppScale.w(16.0);

  /// Gap between the title and the status line.
  static double get liveStatusGap => AppScale.h(6.0);

  /// Gap between the status line and the timer.
  static double get liveTimerTopGap => AppScale.h(26.0);

  /// Gap between the timer and its caption.
  static double get liveTimerLabelGap => AppScale.h(0.0);

  /// Gap between the timer block and the metric sections.
  static double get liveSectionTopGap => AppScale.h(28.0);

  /// Gap between the two side-by-side metric sections.
  static double get liveSectionGap => AppScale.w(16.0);

  /// Gap between stacked metric sections.
  static double get liveSectionStackGap => AppScale.h(14.0);

  /// Gap between a section heading and its capsule.
  static double get liveSectionLabelGap => AppScale.h(10.0);

  /// Gap above the cadence-warning banner, and between the banner and the
  /// sections below it.
  static double get liveNoticeTopGap => AppScale.h(16.0);
  static double get liveNoticeBottomGap => AppScale.h(12.0);

  /// Inner padding of the cadence-warning banner.
  static double get liveNoticePaddingH => AppScale.w(14.0);
  static double get liveNoticePaddingV => AppScale.h(10.0);

  /// "BENCH MODE" capsule: gap above it and its inner padding.
  static double get liveBenchBadgeTopGap => AppScale.h(8.0);
  static double get liveBenchBadgePaddingH => AppScale.w(10.0);
  static double get liveBenchBadgePaddingV => AppScale.h(4.0);

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  /// Space between the top of the screen and the heading.
  static double get summaryTopPadding => AppScale.h(26.0);

  /// Left and right inset shared by the heading, the banner under it and the
  /// trainee line, so the three share one left edge.
  static double get summaryTitleInsetH => AppScale.w(40.0);

  /// Side inset of the metric panel and the action button — the widest
  /// elements on the screen.
  static double get summaryPanelInsetH => AppScale.w(16.0);

  /// Inner padding of the saved/not-saved banner.
  static double get summaryBannerPaddingV => AppScale.h(18.0);
  static double get summaryBannerPaddingH => AppScale.w(28.0);

  /// Gap between the heading and the banner.
  static double get summaryBannerGap => AppScale.h(18.0);

  /// Gap between the banner and the trainee line.
  static double get summaryTraineeGap => AppScale.h(14.0);

  /// Gap between the trainee line and the metric panel.
  static double get summaryPanelGap => AppScale.h(16.0);

  /// Space between a metric cell and the panel's left and right edges. This is
  /// what keeps a cell from spanning the whole section.
  static double get summaryPanelPaddingH => AppScale.w(32.0);

  /// The same inset on compact screens, where the regular one would squeeze the
  /// row labels.
  static double get summaryPanelPaddingHCompact => AppScale.w(20.0);

  /// Space above the first cell and below the duration line.
  static double get summaryPanelPaddingV => AppScale.h(24.0);

  /// Gap between two metric rows.
  static double get summaryRowGap => AppScale.h(14.0);

  /// Horizontal padding inside a metric row, between the row's edge and its
  /// label / value capsule.
  static double get summaryRowPaddingH => AppScale.w(12.0);

  /// Gap above the "Session Duration" line — its own separation from the cells
  /// above it.
  static double get summaryDurationGap => AppScale.h(32.0);

  /// Padding under the "Session Duration" line.
  static double get summaryDurationBottomPadding => AppScale.h(6.0);

  /// Side inset of the "Return to Home" button. Wider than the panel's inset,
  /// so the button is narrower than the panel and lines up with the heading
  /// block.
  static double get summaryActionInsetH => AppScale.w(40.0);

  /// Gap above the "Return to Home" button.
  static double get summaryActionTopGap => AppScale.h(20.0);
}
