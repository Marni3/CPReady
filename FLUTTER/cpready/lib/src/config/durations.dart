/// Duration constants: animations, timeouts, and hold windows.
///
/// All time-based behavior is configured here so tuning never touches
/// widget code.

class AppDurations {
  // -----------------------------------------------------------------------
  // App lifecycle
  // -----------------------------------------------------------------------

  /// Splash screen display time before navigating home.
  static const int splashMs = 1500;

  /// Time for the splash loading line to fill from empty to full.
  static const int splashLoaderMs = 1500;

  // -----------------------------------------------------------------------
  // Practice flow
  // -----------------------------------------------------------------------

  /// Press-and-hold duration to end a live session.
  static const int holdSessionMs = 1500;

  /// Length of the "get into position" countdown shown after Calibration.
  static const int countdownMs = 3000;

  /// One step of that countdown.
  static const int countdownTickMs = 1000;

  /// Refresh interval for the live screen's elapsed timer and its
  /// compression-activity window.
  static const int liveTickMs = 1000;

  /// How long the app waits for the firmware's FINAL_SUMMARY after sending
  /// STOP. Mirrors BLE_FINAL_RESULT_TIMEOUT_MS in the firmware.
  static const int finalSummaryTimeoutMs = 2000;

  /// Second wait window after sending GET_RESULTS when the first summary wait
  /// expired. Mirrors the same 2.0 s firmware contract.
  static const int getResultsTimeoutMs = 2000;

  /// How long the baseline calibration screen waits for Type 2/Type 3 before
  /// reporting a timeout. The firmware window is 2.0 s; the rest is margin for
  /// the queued write and the first notification.
  static const int calibrationTimeoutMs = 6000;

  /// How long the manikin screen waits for the Type 3 ACK after sending
  /// CALIBRATE_TARGET.
  static const int targetAckTimeoutMs = 2000;

  /// How long the live screen waits for the first real-time packet after START
  /// before treating the start as rejected.
  static const int startWatchdogMs = 3000;

  /// How long Device Settings waits for a Type 6 config report after GET_CONFIG.
  /// The plan budgets 2 s; older firmware never answers and falls back to the
  /// last locally saved values.
  static const int configReportTimeoutMs = 2000;

  /// Press-and-hold duration for the destructive factory-reset action.
  static const int resetConfigHoldMs = 2000;

  /// Practice session length the device runs after the manikin trial restores
  /// it. Mirrors DEFAULT_PRACTICE_DURATION_SEC in the firmware.
  static const int practiceSessionSeconds = 120;

  /// Length of the manikin depth trial.
  static const int manikinTrialSeconds = 15;

  /// How long the trial may run before the app gives up waiting for its
  /// FINAL_SUMMARY.
  static const int manikinSummaryTimeoutMs = 20000;
  static const int manikinCalibrationTimeoutMs = 10000;

  /// Baseline zeroing window used for the on-screen countdown.
  static const int calibrationWindowSeconds = 2;

  // -----------------------------------------------------------------------
  // BLE / telemetry supervision
  // -----------------------------------------------------------------------

  /// How long a compression counts as "currently active" for the live counter
  /// circle. The firmware pushes telemetry at 5 Hz, so this window keeps the
  /// circle steady between packets instead of flickering.
  static const int compressionActiveWindowMs = 1200;

  // -----------------------------------------------------------------------
  // Voice coaching
  // -----------------------------------------------------------------------

  /// Shortest gap before the same cue may play again. Much shorter than the
  /// firmware's own 5 s prompt cooldown, so a legitimate repeat still plays.
  static const int voiceCueDuplicateMs = 1000;

  /// Shortest gap between two different cues, so they never overlap.
  static const int voiceCueMinGapMs = 250;

  // -----------------------------------------------------------------------
  // Live cadence warning
  // -----------------------------------------------------------------------

  /// Real-time packets that must report unsteady cadence in a row before the
  /// warning is shown. The first stroke and the packet after a pause also
  /// report unsteady cadence, so a literal per-packet rule would flash the
  /// warning at the start of every run.
  static const int liveCadenceWarningPackets = 3;

  // -----------------------------------------------------------------------
  // Animations
  // -----------------------------------------------------------------------

  static const int defaultAnimationMs = 300;

  // -----------------------------------------------------------------------
  // Home screen
  // -----------------------------------------------------------------------

  /// Interval between the "Scanning." / "Scanning.." / "Scanning..." steps.
  static const int homeScanIntervalMs = 400;

  // -----------------------------------------------------------------------
  // Convenience Duration getters
  // -----------------------------------------------------------------------

  static const Duration splash = Duration(milliseconds: splashMs);
  static const Duration splashLoader = Duration(milliseconds: splashLoaderMs);
  static const Duration homeScanInterval = Duration(
    milliseconds: homeScanIntervalMs,
  );
  static const Duration holdSession = Duration(milliseconds: holdSessionMs);
  static const Duration countdown = Duration(milliseconds: countdownMs);
  static const Duration countdownTick = Duration(milliseconds: countdownTickMs);
  static const Duration liveTick = Duration(milliseconds: liveTickMs);
  static const Duration finalSummaryTimeout = Duration(
    milliseconds: finalSummaryTimeoutMs,
  );
  static const Duration getResultsTimeout = Duration(
    milliseconds: getResultsTimeoutMs,
  );
  static const Duration calibrationTimeout = Duration(
    milliseconds: calibrationTimeoutMs,
  );
  static const Duration targetAckTimeout = Duration(
    milliseconds: targetAckTimeoutMs,
  );
  static const Duration startWatchdog = Duration(milliseconds: startWatchdogMs);
  static const Duration configReportTimeout = Duration(
    milliseconds: configReportTimeoutMs,
  );
  static const Duration resetConfigHold = Duration(
    milliseconds: resetConfigHoldMs,
  );
  static const Duration manikinSummaryTimeout = Duration(
    milliseconds: manikinSummaryTimeoutMs,
  );
  static const Duration compressionActiveWindow = Duration(
    milliseconds: compressionActiveWindowMs,
  );
  static const Duration voiceCueDuplicate = Duration(
    milliseconds: voiceCueDuplicateMs,
  );
  static const Duration voiceCueMinGap = Duration(
    milliseconds: voiceCueMinGapMs,
  );
  static const Duration defaultAnimation = Duration(
    milliseconds: defaultAnimationMs,
  );
}
