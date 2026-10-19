/// All user-facing UI copy (English only).
///
/// Strings are keyed by intent so they can be edited here without touching
/// widgets. This also prepares the app for future i18n if needed.

class AppStrings {
  // -----------------------------------------------------------------------
  // App identity
  // -----------------------------------------------------------------------

  static const String appName = 'CPReady';

  // -----------------------------------------------------------------------
  // Splash
  // -----------------------------------------------------------------------

  static const String splashTitle = 'CPREADY';
  static const String splashLoading = 'Loading…';

  // -----------------------------------------------------------------------
  // Navigation
  // -----------------------------------------------------------------------

  static const String navHome = 'Home';
  static const String navPractice = 'Practice';
  static const String navHistory = 'History';

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  static const String homeTitle = 'CPReady Overview';
  static const String homeBody =
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
      'Sed do eiusmod tempor incididunt ut labore et dolore magna '
      'aliqua. Ut enim ad minim veniam, quis nostrud exercitation '
      'ullamco laboris nisi ut aliquip ex ea commodo consequat. '
      'Duis aute irure dolor in reprehenderit in voluptate velit '
      'esse cillum dolore eu fugiat nulla pariatur. '
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
      'Sed do eiusmod tempor incididunt ut labore et dolore magna '
      'aliqua. Ut enim ad minim veniam, quis nostrud exercitation '
      'ullamco laboris nisi ut aliquip ex ea commodo consequat. '
      'Duis aute irure dolor in reprehenderit in voluptate velit '
      'esse cillum dolore eu fugiat nulla pariatur. ';
  static const String homeDeviceConnection = 'Device Connection';

  // Home — redesigned homepage -------------------------------------------------

  /// Home header wordmark (all caps).
  static const String homeHeaderBrand = 'CPREADY';

  /// Home header page label.
  static const String homeHeaderPage = 'Home';

  /// Gradient welcome card.
  static const String homeWelcomeTitle = 'Welcome!';
  static const String homeWelcomeSubtitle = 'Start your training now';

  /// Device card — nothing connected yet.
  static const String homeDeviceNoneTitle = 'No device connected yet';
  static const String homeDeviceNoneSubtitle =
      'Pair your device now and start training!';
  static const String homeDeviceConnect = 'Connect your device now!';

  /// Device card — connecting / scanning.
  static const String homeConnectingTitle = 'CONNECT DEVICE';
  static const String homeConnectingInstruction =
      'Turn on your CPReady\n device and keep it nearby.';
  static const String homeScanning = 'Scanning';
  static const String homeConnected = 'Connected!';

  /// Dotted info card paragraph.
  static const String homeInfoBody =
      'CPReady was developed to address challenges by serving as a '
      'supplementary tool for CPR training in schools, providing real-time '
      'feedback, automatic performance logging, and objective measurement of '
      'key compression metrics—helping students and instructors.';

  // -----------------------------------------------------------------------
  // Practice screen
  // -----------------------------------------------------------------------

  static const String practiceHeaderPage = 'Practice';
  static const String practiceTitle = 'Practice';
  static const String practiceSubtitle = 'Choose an option below.';
  static const String practiceGuide = 'Step-by-step Guide';
  static const String practiceGuideBody =
      'Tap to view the basic step-by-step guide for hands-only CPR.';
  static const String practiceStart = 'Start practice';
  static const String practiceStartBody =
      'Tap to start the practice session for hands-only CPR.';
  static const String buttonConnect = 'Connect to CPReady';

  // -----------------------------------------------------------------------
  // History screen
  // -----------------------------------------------------------------------

  /// History tab — header page label.
  static const String historyHeaderPage = 'History';

  /// History tab — screen heading, styled like the Practice screen's title.
  static const String historyTitle = 'Session History';

  /// History tab — empty state (shown when no session has been saved yet).
  static const String historyEmptyTitle = 'No sessions yet';
  static const String historyEmptyBody =
      'Finish a practice session and it will appear here.';

  /// History tab — the bottom button and its confirmation dialog.
  static const String historyClearButton = 'Clear History';
  static const String historyClearAllTitle = 'Clear all history?';
  static const String historyClearAllBody =
      'Every saved session will be deleted. This cannot be undone.';
  static const String historyClearAllConfirm = 'Delete all';
  static const String historyClearAllCancel = 'Cancel';

  /// History tab — per-session actions: open the summary, or delete the row.
  static const String historySeeMore = 'See more';
  static const String historyDeleteOneTitle = 'Delete this session?';
  static const String historyDeleteOneBody =
      'This session will be removed from History. This cannot be undone.';
  static const String historyDeleteOneConfirm = 'Delete';

  /// History tab — marker on a session that ended before its summary arrived.
  static const String historyInterruptedLabel = 'Interrupted';

  /// History tab — a session id that no longer exists.
  static const String historyMissing = 'That session is no longer available.';

  // -----------------------------------------------------------------------
  // Guide screen
  // -----------------------------------------------------------------------

  static const String guideTitle = 'Step-by-step Guide';

  // -----------------------------------------------------------------------
  // Practice setup
  // -----------------------------------------------------------------------

  static const String setupTitle = 'Practice Setup';

  /// Big blue heading above the name field.
  static const String setupHeading = 'Trainee name';

  /// Placeholder shown inside the field.
  static const String setupNameHint = 'Trainee name*';

  /// Small black helper line under the field.
  static const String setupHelper = 'Input a name to use';

  static const String setupContinue = 'Continue';

  // -----------------------------------------------------------------------
  // Hand placement
  // -----------------------------------------------------------------------

  static const String handPlacementTitle = 'Hand Placement';

  /// Instruction inside the panel. The break is intentional.
  static const String handPlacementInstruction = 'Place both hands\non chest';

  static const String handPlacementBegin = 'Begin Session';

  // -----------------------------------------------------------------------
  // Calibration
  // -----------------------------------------------------------------------

  static const String calibrationTitle = 'Calibration';
  static const String calibrationWaiting = 'Starting calibration…';
  static const String calibrationCalibrating = 'Calibrating…';
  static const String calibrationReady = 'Baseline ready.';
  static const String calibrationError = 'Calibration problem.';
  static const String calibrationNotReady =
      'Not ready. Keep hands still and release downward pressure.';
  static const String calibrationBeginSession = 'Begin Session';

  // -----------------------------------------------------------------------
  // Begin compression
  // -----------------------------------------------------------------------

  static const String beginCompressionTitle = 'Begin Compression Now';

  /// Helper line under the heading. The break is intentional.
  static const String beginCompressionBody =
      'Get into position as live\nsession start automatically.';

  // -----------------------------------------------------------------------
  // Live practice
  // -----------------------------------------------------------------------

  static const String livePracticeTitle = 'Live Practice';
  static const String liveElapsedLabel = 'Elapsed Time';
  static const String liveRateLabel = 'Rate';
  static const String liveRecoilLabel = 'Recoil';
  static const String liveDepthLabel = 'Depth';

  /// Caption inside the compression-count circle (lowercase by design).
  static const String liveCompressionsLabel = 'compressions';

  /// Recoil capsule, full release.
  static const String liveRecoilFull = 'Full';

  /// Recoil capsule, incomplete release.
  static const String liveRecoilPartial = 'Partial';

  /// Shown in a capsule before the first telemetry packet arrives.
  static const String liveNoValue = '--';

  /// Unit suffixes for the live capsule values.
  static const String liveRateUnit = 'cpm';
  static const String liveDepthUnit = 'cm';
  static const String livePercentUnit = '%';

  static const String liveHoldEndSession = 'Hold to End Session';

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  static const String sessionSummaryTitle = 'Session Summary';
  static const String sessionSaved = 'Session Saved';

  /// Status shown when the session ended before a FINAL_SUMMARY arrived.
  /// The session is still persisted to History (§2-33).
  static const String sessionInterrupted = 'Session Interrupted (disconnected)';
  static const String sessionInterruptedDetail =
      'BLE link was lost before a final summary arrived — this session was saved to History.';

  /// Shown when the session could not be written to the History database.
  static const String sessionHistoryFailed =
      'This session could not be saved to History.';

  /// Label prefixed to the trainee name on the summary.
  static const String sessionTrainee = 'Trainee Name';

  /// Labels for the summary metric rows.
  static const String sessionRecoil = 'Recoil';
  static const String sessionRate = 'Rate';
  static const String sessionDepth = 'Depth';
  static const String sessionCcf = 'CCF';
  static const String sessionCompressions = 'Compressions';
  static const String sessionDuration = 'Session Duration';

  static const String sessionReturnToHome = 'Return to Home';

  // -----------------------------------------------------------------------
  // Connection status chip labels (suffixed by controller at runtime)
  // -----------------------------------------------------------------------

  static const String statusDisconnected = 'Disconnected';
  static const String statusScanning = 'Scanning…';
  static const String statusConnecting = 'Connecting…';
  static const String statusConnected = 'Connected';
  static const String statusErrorPrefix = 'Error: ';

  // -----------------------------------------------------------------------
  // BLE errors raised by the controller (shown after [statusErrorPrefix])
  // -----------------------------------------------------------------------

  /// Connect was tapped while the phone's Bluetooth is switched off.
  static const String bleErrorOff = 'Bluetooth is off';

  /// Bluetooth is off and Android would not show its turn-on prompt.
  static const String bleErrorTurnOnFailed = 'Turn on Bluetooth to connect';

  // -----------------------------------------------------------------------
  // Practice flow — the link going away mid-flow
  // -----------------------------------------------------------------------

  /// Notice shown when a flow screen finds the board gone.
  static const String flowLinkLostTitle = 'Connection lost';
  static const String flowLinkLostBody =
      'The CPReady device is not connected, so the practice session cannot '
      'continue. Reconnect from the Home screen and start again.';
  static const String flowLinkLostAction = 'Back to Home';
}
