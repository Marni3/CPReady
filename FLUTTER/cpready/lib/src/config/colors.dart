/// Semantic color map.
///
/// Colors are named by *intent* (e.g. [statusConnected]) not by appearance
/// (e.g. brandPurple), so rebranding only requires changing the hex here.
///
/// The [brandPrimary], [brandSecondary] and [brandSurface] values seed the
/// Material [ColorScheme] below; every screen color is a separate, named entry.

import 'package:flutter/material.dart';

class AppColors {
  // -----------------------------------------------------------------------
  // Brand — feeds the Material ColorScheme
  // -----------------------------------------------------------------------

  /// Primary brand color; seeds the Material color scheme.
  static const Color brandPrimary = Color(0xFF6200EE);

  /// Secondary brand color; seeds the Material color scheme.
  static const Color brandSecondary = Color(0xFF6200EE);

  /// Surface brand color; seeds the Material color scheme's container role.
  static const Color brandSurface = Color(0xFFEADDFF);

  // -----------------------------------------------------------------------
  // Core brand palette
  // -----------------------------------------------------------------------

  /// Brand blue (#0A3D79) — header wordmark, card borders, connecting text,
  /// and the top stop of every brand gradient.
  static const Color brandBlue = Color(0xFF0A3D79);

  /// Brand navy (#021B4B) — bottom stop of every brand gradient.
  static const Color brandNavy = Color(0xFF021B4B);

  /// Brand gradient stops (splash, home welcome card, gradient buttons).
  static const Color brandGradientTop = brandBlue;
  static const Color brandGradientBottom = brandNavy;

  // -----------------------------------------------------------------------
  // Splash / loading screen
  // -----------------------------------------------------------------------

  /// Foreground used on the dark splash gradient (logo tint, title, loader).
  static const Color splashForeground = Color(0xFFFFFFFF);

  /// Track behind the splash loading line (unfilled portion).
  static const Color splashLoaderTrack = Color(0xFFA6A6A6);

  /// Filling portion of the splash loading line (fills the track left→right).
  static const Color splashLoaderFill = Color(0xFFFFFFFF);

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// "CPREADY" wordmark in the home header.
  static const Color homeBrandText = brandBlue;

  /// "Home" page label (and its underline) in the home header.
  static const Color homePageText = Color(0xFF3B3A3A);

  /// Thin grey divider (top header + bottom nav).
  static const Color divider = Color(0xFFD9D9D9);

  /// Body text inside the white device card.
  static const Color homeCardText = Color(0xFF000000);

  /// Border of the device card and the dotted info card.
  static const Color homeCardBorder = brandBlue;

  /// Text/foreground on the brand gradient (welcome card + gradient button).
  static const Color homeWelcomeText = Color(0xFFFFFFFF);

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  /// Big "Practice" heading under the header, and the bold text inside the
  /// dotted "Choose an option below." box.
  static const Color practiceTitleText = brandBlue;

  /// Border of the slim dotted option box.
  static const Color practiceDottedBorder = brandBlue;

  /// Text + icon on the gradient option cards.
  static const Color practiceOptionText = Color(0xFFFFFFFF);

  // -----------------------------------------------------------------------
  // Step-by-step guide screen
  // -----------------------------------------------------------------------

  /// Back button glyph.
  static const Color guideBackIcon = Color(0xFF153350);

  /// Big "Step-by-step Guide" heading.
  static const Color guideTitleText = brandBlue;

  /// Card background behind each numbered step.
  static const Color guideStepCardBackground = Color(0xFFF6F9FF);

  /// Thin edge drawn around each step card.
  static const Color guideStepCardBorder = Color(0xFF9E9E9E);

  /// Step paragraph text (bold lead + regular remainder).
  static const Color guideStepText = Color(0xFF1A1A1A);

  /// Numbered circle on the left of each step.
  static const Color guideStepNumberBackground = Color(0xFF8B0000);

  /// Number inside the circle.
  static const Color guideStepNumberText = Color(0xFFFFFFFF);

  // -----------------------------------------------------------------------
  // Bottom navigation
  // -----------------------------------------------------------------------

  /// Selected nav item (icon + label).
  static const Color navSelected = Color(0xFF153350);

  /// Unselected nav item (muted grey).
  static const Color navUnselected = Color(0xFF9E9E9E);

  // -----------------------------------------------------------------------
  // Connection feedback
  // -----------------------------------------------------------------------

  /// "Connected!" confirmation text.
  static const Color connected = Color(0xFF00620B);

  // -----------------------------------------------------------------------
  // Status — migrated from previous inline Colors values
  // -----------------------------------------------------------------------

  static const Color statusConnected = Color(0xFF2E7D32);
  static const Color statusScanning = Color(0xFF1565C0);
  static const Color statusConnecting = Color(0xFFE65100);
  static const Color statusDisconnected = Color(0xFF757575);
  static const Color statusError = Color(0xFFB00020);

  // -----------------------------------------------------------------------
  // Surfaces
  // -----------------------------------------------------------------------

  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceScaffold = Color(0xFFFFFFFF);
  static const Color surfaceBackground = Color(0xFFFFFFFF);

  // -----------------------------------------------------------------------
  // On-surface text / icon colors
  // -----------------------------------------------------------------------

  static const Color onSurface = Color(0xFF000000);
  static const Color onSurfaceVariant = Color(0xFF4A4A4A);
  static const Color onErrorContainer = Color(0xFF000000);

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// Background of a session row in the History list.
  static const Color historyRowBackground = Color(0xFFF6F9FF);

  /// Thin edge around a session row.
  static const Color historyRowBorder = divider;

  /// Trainee name on a session row.
  static const Color historyRowTitleText = brandBlue;

  /// Session heading at the top of the tab (styled like Practice's title).
  static const Color historyTitleText = brandBlue;

  /// Timestamp and duration text on a session row (both share one line).
  static const Color historyRowDateText = brandBlue;

  /// Duration line on a session row (it sits above the row's actions).
  static const Color historyRowMetaText = Color(0xFF6B6B6B);

  /// "See more" label and the three-dot button on a row.
  static const Color historyRowActionsText = brandBlue;

  /// Edge of the outlined "See more" capsule, which has no fill.
  static const Color historySeeMoreBorder = Color(0xFF000000);

  /// Label on the bottom gradient "Clear History" button.
  static const Color historyClearButtonText = Color(0xFFFFFFFF);

  /// "Interrupted" label on a session that ended before its summary arrived.
  static const Color historyInterruptedBackground = Color(0xFFFDE7EA);
  static const Color historyInterruptedText = statusError;

  // -----------------------------------------------------------------------
  // Practice flow (setup / hand placement / calibration / countdown)
  // -----------------------------------------------------------------------

  /// Back-arrow glyph on the flow screens.
  static const Color flowBackIcon = guideBackIcon;

  /// Big blue headings on the flow screens.
  static const Color flowHeadingText = brandBlue;

  /// Small black helper line under a field.
  static const Color flowHelperText = Color(0xFF000000);

  /// Fill of the big instructional panel.
  static const Color flowPanelBackground = Color(0xFFF6F9FF);

  /// Grey edge around the name field.
  static const Color flowPanelBorder = Color(0xFF9E9E9E);

  /// Light grey edge around the instructional cards (hand placement,
  /// calibration).
  static const Color flowCardBorder = Color(0xFFD9D9D9);

  /// Text typed into the name field.
  static const Color flowFieldText = Color(0xFF000000);

  /// Placeholder inside the name field.
  static const Color flowFieldHint = Color(0xFF6B6B6B);

  /// Flat action button ("Continue", "Begin Session", "Return to Home").
  static const Color flowActionBackground = Color(0xFFE0E8F4);
  static const Color flowActionText = brandBlue;

  /// Flat action button label while the button is disabled.
  static const Color flowActionDisabledText = Color(0xFF9E9E9E);

  /// Training-mode option: fill and edge unselected, then selected.
  static const Color profileOptionBackground = Color(0xFFF6F9FF);
  static const Color profileOptionBorder = Color(0xFF9E9E9E);
  static const Color profileOptionSelectedBackground = Color(0xFFE0E8F4);
  static const Color profileOptionSelectedBorder = brandBlue;

  /// Radio dot and selected outline.
  static const Color profileOptionIndicator = brandBlue;

  /// Option title and its description.
  static const Color profileOptionText = Color(0xFF000000);
  static const Color profileOptionBodyText = Color(0xFF4A4A4A);

  // -----------------------------------------------------------------------
  // Manikin depth calibration
  // -----------------------------------------------------------------------

  /// Box holding the trial's mean depth.
  static const Color manikinValueBackground = flowActionBackground;
  static const Color manikinValueBorder = flowPanelBorder;
  static const Color manikinValueText = brandBlue;
  static const Color manikinErrorText = statusError;

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  /// Edge and fill of a live metric section.
  static const Color liveSectionBorder = brandBlue;
  static const Color liveSectionBackground = Color(0xFFFCFDFF);

  /// Section headings, the timer, and its caption.
  static const Color liveLabelText = brandBlue;

  /// Status line while the link is up (green bullet).
  static const Color liveStatusConnected = statusConnected;

  /// Status line while the link is down (red cross).
  static const Color liveStatusLost = statusError;

  /// Capsule fills: value in range / out of range / nothing yet.
  static const Color liveCapsulePositive = Color(0xFF0BA61C);
  static const Color liveCapsuleNegative = statusError;
  static const Color liveCapsuleNeutral = Color(0xFF9E9E9E);
  static const Color liveCapsuleText = Color(0xFFFFFFFF);

  /// Compression-count circle: idle (translucent red) and active (green).
  static const Color liveCounterIdle = Color(0x99B00020);
  static const Color liveCounterActive = Color(0xFF0BA61C);
  static const Color liveCounterText = Color(0xFFFFFFFF);

  /// Overlay that fills the "Hold to End Session" button while it is held.
  static const Color liveHoldFillOverlay = Color(0x59FFFFFF);

  /// Cadence-warning banner.
  static const Color liveWarningBackground = Color(0xFFFFF3CD);
  static const Color liveWarningBorder = Color(0xFFE0B400);
  static const Color liveWarningText = Color(0xFF7A5B00);

  /// "BENCH MODE" capsule.
  static const Color liveBenchBadgeBackground = flowActionBackground;
  static const Color liveBenchBadgeText = brandBlue;

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  /// "Session Saved" banner: the brand green at 20% so it reads as a tint over
  /// the white screen rather than a solid fill.
  static const Color summarySavedBackground = Color(0x33A5D6A7);

  /// "Session Saved" label: a mid green that sits softly on the tinted fill
  /// instead of reading as a heavy block.
  static const Color summarySavedText = Color(0xFF2E7D32);

  /// "not saved" banner (BLE drop / write failure).
  static const Color summaryFailedBackground = Color(0xFFFDE7EA);
  static const Color summaryFailedText = statusError;

  /// Big heading and the trainee line.
  static const Color summaryHeadingText = brandBlue;

  /// Panel holding the metric rows.
  static const Color summaryPanelBackground = flowPanelBackground;
  static const Color summaryPanelBorder = Color(0xFFD9D9D9);

  /// Metric row: white fill, black edge, blue label.
  static const Color summaryRowBackground = Color(0xFFFFFFFF);
  static const Color summaryRowBorder = Color(0xFF000000);
  static const Color summaryRowLabelText = brandBlue;

  /// CCF / Compressions capsule.
  static const Color summaryCapsuleBackground = flowActionBackground;
  static const Color summaryCapsuleText = brandBlue;
}
