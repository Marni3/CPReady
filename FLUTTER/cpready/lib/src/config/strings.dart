/// All user-facing UI copy (English only).
///
/// Strings are keyed by intent, so copy changes stay in this file and never
/// reach the widgets.

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

  /// Shared confirmation action.
  static const String actionCancel = 'Cancel';

  /// Tooltip for the header gear that opens Device Settings.
  static const String settingsTooltip = 'Settings';

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
      'Turn on your CPReady device and keep it nearby.';
  static const String homeScanning = 'Scanning';
  static const String homeConnected = 'Connected!';

  /// Device card — connected: opens the manikin depth calibration flow.
  static const String homeManikinCalibration = 'Manikin Calibration';

  /// Device card — connected: opens the firmware configuration screen.
  static const String homeDeviceSettings = 'Device Settings';

  /// Manikin calibration needs the manikin profile; the last saved settings
  /// say the device is still in bench mode.
  static const String homeCalibrationRequiresManikinTitle =
      'Switch to Manikin mode';
  static const String homeCalibrationRequiresManikinBody =
      'Manikin calibration needs the Adult Manikin profile, but the last known '
      'device mode is Bench Test. Open Device Settings to switch modes first.';
  static const String homeCalibrationRequiresManikinAction =
      'Open Device Settings';

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
  // Practice setup — training mode
  // -----------------------------------------------------------------------

  /// Section label above the two profile options.
  static const String setupTrainingMode = 'Training mode';

  static const String setupProfileManikin = 'Adult Manikin Mode';
  static const String setupProfileManikinBody =
      'Standard AHA thresholds for training manikins.';

  static const String setupProfileBench = 'Bench Test Mode';
  static const String setupProfileBenchBody =
      'Relaxed sensitivity for desk and palm pressing.';

  /// Shown under the options when the mode change could not be sent.
  static const String setupProfileSendFailed =
      'Could not send the mode change to the device.';

  /// Confirmation shown before SET_PROFILE, because current firmware resets K.
  static const String profileSwitchWarningTitle = 'Change training mode?';
  static const String profileSwitchWarningBody =
      'Switching modes resets the device’s calibrated depth scalar (K). '
      'Recalibrate the manikin before relying on depth readings.';
  static const String profileSwitchConfirm = 'Switch mode';

  /// Persistent reminder after a successful mode change.
  static const String profileSwitchResetNotice =
      'Mode changed. Recalibrate the manikin before using depth readings.';

  // -----------------------------------------------------------------------
  // Device Settings
  // -----------------------------------------------------------------------

  static const String deviceSettingsTitle = 'Device Settings';
  static const String deviceSettingsSubtitle =
      'Read and change the device configuration. The last known values are '
      'saved on this phone.';
  static const String deviceSettingsLoading = 'Loading saved settings…';

  static const String deviceSettingsCurrent = 'Current configuration';
  static const String deviceSettingsProfile = 'Profile';
  static const String deviceSettingsDepthK = 'Depth calibration (K)';
  static const String deviceSettingsDuration = 'Practice duration';
  static const String deviceSettingsSource = 'Source';
  static const String deviceSettingsSourceDevice = 'Read from device';
  static const String deviceSettingsSourceLocal = 'Last known (this phone)';
  static const String deviceSettingsSourceDefault = 'No saved values yet';
  static const String deviceSettingsUnknown = 'Unknown';

  static const String deviceSettingsRefresh = 'Refresh from Device';
  static const String deviceSettingsRefreshing =
      'Reading device configuration…';
  static const String deviceSettingsReadBack =
      'Configuration read from the device.';
  static const String deviceSettingsUnsupported =
      'This device does not support configuration read-back. Showing the last '
      'known values saved on this phone.';
  static const String deviceSettingsReadFailed =
      'Could not read the device configuration. Showing the last known values '
      'saved on this phone.';
  static const String deviceSettingsOffline =
      'Not connected. Reconnect to read or change device settings.';

  static const String deviceSettingsProfileSection = 'Kinematic profile';
  static const String deviceSettingsProfileHelper =
      'Changing modes resets the device’s calibrated K. Recalibrate the manikin '
      'afterwards.';
  static const String deviceSettingsProfileChanged =
      'Mode changed. Recalibrate the manikin before using depth readings.';
  static const String deviceSettingsProfileFailed =
      'Could not change the device mode.';

  static const String deviceSettingsKSection = 'Set depth K';
  static const String deviceSettingsKHelper =
      'Enter a value from 1.00 to 30.00. SET_K writes and persists it on the '
      'device.';
  static const String deviceSettingsKHint = 'e.g. 11.20';
  static const String deviceSettingsKSet = 'Set K on Device';
  static const String deviceSettingsKSending = 'Sending K…';
  static const String deviceSettingsKInvalid =
      'Enter a K value from 1.00 to 30.00.';
  static const String deviceSettingsKSent =
      'K sent to the device. Refresh to verify it when read-back is supported.';
  static const String deviceSettingsKFailed = 'Could not send K to the device.';
  static const String deviceSettingsLocalSaveFailed =
      'The device command succeeded, but the value could not be saved on this '
      'phone.';

  static const String deviceSettingsResetSection = 'Factory reset';
  static const String deviceSettingsResetWarning =
      'Restores the device profile, K, and duration to factory defaults. This '
      'cannot be undone.';
  static const String deviceSettingsResetHold =
      'Hold to reset device configuration';
  static const String deviceSettingsResetDone =
      'Device configuration reset. Recalibrate the manikin before a session.';
  static const String deviceSettingsResetFailed =
      'Could not reset the device configuration.';

  static String deviceSettingsSeconds(int seconds) => '$seconds seconds';

  // -----------------------------------------------------------------------
  // Hand placement
  // -----------------------------------------------------------------------

  static const String handPlacementTitle = 'Hand Placement';

  /// Instruction inside the panel; it wraps to the card's width.
  static const String handPlacementInstruction = 'Place both hands on chest';

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
  static const String calibrationTimeout =
      'Calibration timed out. Keep hands still and try again.';
  static const String calibrationRejected =
      'The device could not calibrate. Keep hands still and release downward pressure.';
  static const String calibrationStartFailed =
      'Could not start calibration. Check the device and try again.';
  static const String calibrationRetry = 'Retry Calibration';
  static const String calibrationBeginSession = 'Begin Session';

  /// Countdown shown while the firmware's 2 s zeroing window runs.
  static String calibrationCountdown(int seconds) => 'Calibrating… ${seconds}s';

  // Specific diagnostic error strings matching firmware reason codes
  static const String calibrationErrorUnstable =
      'Excessive movement detected during baseline zeroing. Keep the vest completely still on the manikin and retry.';
  static const String calibrationErrorLowSamples =
      'Insufficient sensor samples received during calibration. Ensure the device is powered and retry.';
  static const String calibrationErrorGravity =
      'Sensor readings out of expected range. Verify the vest is flat on the chest.';
  static const String calibrationErrorAlignment =
      'Sensors misaligned. Ensure the vest is positioned correctly on the manikin.';
  static const String calibrationErrorBusy =
      'Device is busy with another session or calibration. Please wait or restart the session.';
  static const String calibrationErrorNoTrialData =
      'At least 5 compressions are required during the 15 s trial before target depth calibration can be saved.';
  static const String calibrationErrorI2cFault =
      'Hardware sensor communication error. Please power cycle the CPReady vest.';
  static const String calibrationErrorDisconnected =
      'Device disconnected. Please reconnect your CPReady device and retry.';
  static const String commandWriteTimeout =
      'Device communication timed out. Please check device proximity and retry.';

  // -----------------------------------------------------------------------
  // Manikin depth calibration (separate from the baseline Calibration step)
  // -----------------------------------------------------------------------

  static const String manikinTitle = 'Manikin Calibration';

  /// Intro paragraph on the start screen.
  static const String manikinIntroBody =
      'Run a 15-second trial on the manikin, then enter the depth it reports. '
      'The device uses that value to scale its depth readings.';

  static const String manikinStartZeroing = 'Zero Baseline';
  static const String manikinBaselineReady =
      'Baseline calibrated! Position hands and press Start when ready.';
  static const String manikinStart = 'Start 15 s Trial';
  static const String manikinPreparing = 'Preparing sensor…';
  static const String manikinTrialRunning = 'Trial running…';
  static const String manikinTimeRemaining = 'Time remaining';
  static const String manikinLiveDepth = 'Depth';
  static const String manikinMeanDepth = 'Trial mean depth';
  static const String manikinTargetLabel = 'Manikin reported depth';
  static const String manikinTargetHint = 'e.g. 5.5';
  static const String manikinTargetUnit = 'cm';
  static const String manikinInvalidTarget =
      'Enter a depth between 1.0 and 10.0 cm.';
  static const String manikinSave = 'Save Calibration';
  static const String manikinSaving = 'Saving…';
  static const String manikinSavingBody =
      'Waiting for the device to confirm the new depth scale…';
  static const String manikinRetry = 'Retry Trial';
  static const String manikinError =
      'The trial did not finish. Check the device and try again.';
  static const String manikinNoDeviceConnected =
      'No device connected. Please pair your CPReady device first.';
  static const String manikinSendFailed =
      'Could not send the calibration to the device.';
  static const String manikinTargetRejected =
      'The device could not save the calibration. Check the target depth and try again.';
  static const String manikinTargetTimeout =
      'No confirmation from the device. The calibration was not saved.';
  static const String manikinNoCompressions =
      'No compressions were detected. Press firmly and try again.';

  /// Result after the target command was acknowledged by the device.
  static const String manikinSentTitle = 'Calibration Saved';
  static const String manikinSentBody =
      'The device stored the new depth scale in flash memory. '
      'It will be used from the next session.';
  static const String manikinDone = 'Done';

  // -----------------------------------------------------------------------
  // Begin compression
  // -----------------------------------------------------------------------

  static const String beginCompressionTitle = 'Begin Compression Now';

  /// Helper line under the heading.
  static const String beginCompressionBody =
      'Get into position as live session start automatically.';

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

  /// Accessibility labels for the voice-cue toggle in the live header.
  static const String liveMuteCues = 'Mute voice cues';
  static const String liveUnmuteCues = 'Unmute voice cues';

  /// Shown after three consecutive packets report unsteady cadence.
  static const String liveCadenceWarning =
      'Rhythm unsteady — depth readings may fluctuate.';

  /// Capsule marking a session running the relaxed bench profile.
  static const String liveBenchBadge = 'BENCH MODE';

  /// Shown when START is rejected or the first telemetry packet never arrives.
  static const String liveStartFailedTitle = 'Session did not start';
  static const String liveStartFailedBody =
      'The device did not start sending live readings. Reconnect, recalibrate, '
      'and try again.';
  static const String liveStartFailedAction = 'Recalibrate';

  // -----------------------------------------------------------------------
  // Session summary
  // -----------------------------------------------------------------------

  static const String sessionSummaryTitle = 'Session Summary';
  static const String sessionSaved = 'Session Saved';

  /// Status shown when the session ended before a FINAL_SUMMARY arrived.
  static const String sessionInterrupted = 'Session Interrupted (disconnected)';
  static const String sessionInterruptedDetail =
      'BLE link was lost before a final summary arrived — this session was not saved.';

  /// Status shown when STOP completed but the device never returned a summary,
  /// or when the summary is not usable (for example, zero compressions).
  static const String sessionResultsUnavailable = 'Results Unavailable';
  static const String sessionResultsUnavailableDetail =
      'The device did not return a final summary, so this session was not saved.';

  /// Button that re-sends GET_RESULTS from the unavailable-results screen.
  static const String sessionRetryRetrieval = 'Retry Retrieval';
  static const String sessionRetrievalFailed =
      'The device still did not return a summary.';

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
