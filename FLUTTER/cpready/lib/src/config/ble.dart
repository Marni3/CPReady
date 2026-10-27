/// BLE configuration: device name, GATT UUIDs, and scan timing.
///
/// These values mirror the firmware GATT service defined in
/// `CPReady_Program/include/BLEReadings.h`.

class AppBleConfig {
  /// Advertised device name scanned for by the app.
  static const String deviceName = 'CPReady';

  /// GATT service UUID.
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  /// Notify (telemetry) characteristic UUID.
  static const String notifyUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Write (command) characteristic UUID.
  static const String commandUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  /// BLE scan timeout.
  static const int scanTimeoutSeconds = 5;

  // -----------------------------------------------------------------------
  // Firmware text commands (written to the command characteristic)
  // -----------------------------------------------------------------------

  /// Starts the stationary baseline calibration window.
  static const String commandCalibrate = 'CALIBRATE';

  /// Begins the active session; the firmware accepts it only once the
  /// baseline is ready.
  static const String commandStart = 'START';

  /// Finalises the session; the firmware answers with its FINAL_SUMMARY.
  static const String commandStop = 'STOP';

  /// Re-sends the last FINAL_SUMMARY held in firmware RAM.
  static const String commandGetResults = 'GET_RESULTS';

  /// Pauses the session clock (paused time counts toward neither elapsed time
  /// nor CCF). Not exposed in the UI yet.
  static const String commandPause = 'PAUSE';

  /// Resumes a paused session.
  static const String commandResume = 'RESUME';

  /// Selects the adult-manikin kinematic profile. Each profile keeps its own
  /// depth scalar (K) on the device.
  static const String commandProfileManikin = 'SET_PROFILE:MANIKIN';

  /// Selects the relaxed bench-test kinematic profile.
  static const String commandProfileBench = 'SET_PROFILE:BENCH';

  /// Sets the firmware's auto-stop duration. The value is volatile: it lasts
  /// until the session ends, aborts, the link drops or the device restarts.
  static String commandSetTime(int seconds) => 'SET_TIME:$seconds';

  /// Scales the depth reading so a trial mean of the measured depth matches the
  /// manikin's reported depth.
  static String commandCalibrateTarget(double depthCm) =>
      'CALIBRATE_TARGET:${depthCm.toStringAsFixed(1)}';

  /// Sets the harmonic depth scalar directly and persists it to flash.
  static String commandSetK(double depthK) =>
      'SET_K:${depthK.toStringAsFixed(2)}';

  /// Clears the firmware's flash configuration and restores factory defaults.
  static const String commandResetConfig = 'RESET_CONFIG';

  /// Requests the current device configuration; the firmware answers with a
  /// Type 6 config report.
  static const String commandGetConfig = 'GET_CONFIG';

  // -----------------------------------------------------------------------
  // Telemetry packet types (see BLEReadings.h)
  // -----------------------------------------------------------------------

  /// Live per-stroke telemetry.
  static const int packetRealtime = 1;

  /// Baseline calibration underway.
  static const int packetCalibrating = 2;

  /// Baseline calibration completed.
  static const int packetCalibrationDone = 3;

  /// Whole-session summary sent when the session ends.
  static const int packetFinalSummary = 4;

  /// Firmware error condition.
  static const int packetError = 5;

  /// Device-configuration report, sent in response to GET_CONFIG. Firmware
  /// older than F-01 never sends it; screens must tolerate its absence.
  static const int packetConfigReport = 6;

  // -----------------------------------------------------------------------
  // Type 6 configuration report (F-01)
  // -----------------------------------------------------------------------
  //
  // Parsed defensively so older firmware that never sends Type 6 simply lands
  // in the unsupported state.

  /// Length of the Type 6 config report.
  static const int configReportLength = 12;

  /// Type 6 profile values (byte 1).
  static const int configProfileManikin = 0;
  static const int configProfileBench = 1;

  /// Type 6 config_flags bits (byte 4).
  static const int configFlagBenchActive = 0x01;
  static const int configFlagCustomK = 0x02;

  /// Protocol version the app expects in byte 9.
  static const int configProtocolVersion = 1;

  /// `depth_k_x100` scale used by the config report and SET_K contract.
  static const double depthKScale = 100.0;

  /// Accepted SET_K / config-report range.
  static const double depthKMin = 1.0;
  static const double depthKMax = 30.0;

  // -----------------------------------------------------------------------
  // Packet validation (see SOFTWARE_DEVELOPER_GUIDE.md §2.4)
  // -----------------------------------------------------------------------

  /// Protocol v2 packet size: the 12-byte layout plus a 16-bit stroke count
  /// (bytes 12..13) and a 16-bit notification sequence number (bytes 14..15).
  static const int packetLengthV2 = 16;

  /// 12-byte (v1) and 11-byte frames from older firmware are still accepted;
  /// any other length is rejected by the decoder.
  static const int packetLength = 12;
  static const int legacyPacketLength = 11;

  /// Sequence gaps larger than this are treated as a firmware restart rather
  /// than lost packets.
  static const int maxPlausibleSequenceGap = 1000;

  /// Plausibility limits applied to live and summary frames.
  static const int maxPlausibleRateCpm = 250;
  static const int maxPlausibleDepthTenthsMm = 1000;
  static const int maxPlausibleCcfPercent = 100;
  static const int fullRecoilPercent = 100;

  // -----------------------------------------------------------------------
  // Quality flags (byte 11; see BLEReadings.h)
  // -----------------------------------------------------------------------

  /// Cadence is steady enough for a stable reading.
  static const int qualitySteadyCadence = 0x01;

  /// First stroke of a session, or the first after a pause. Cadence is not yet
  /// synchronized, so the steady flag is cleared for this packet.
  static const int qualityFirstStroke = 0x02;

  /// The device is running the relaxed bench-test profile.
  static const int qualityBenchMode = 0x04;

  /// Recoil is an acceleration estimate (no force sensor): it cannot detect
  /// leaning, so the app shows it without grading it.
  static const int qualityRecoilEstimated = 0x08;

  // -----------------------------------------------------------------------
  // Audio coaching cue codes (byte 7)
  // -----------------------------------------------------------------------

  static const int cuePushHarder = 1;
  static const int cuePushShallower = 2;
  static const int cueReleaseFully = 3;
  static const int cueSpeedUp = 4;
  static const int cueSlowDown = 5;
  static const int cueGoodJob = 6;

  // -----------------------------------------------------------------------
  // Calibration & telemetry error codes (byte 7 when packetType == packetError)
  // -----------------------------------------------------------------------

  static const int errNone = 0;
  static const int errMotionUnstable = 1;
  static const int errLowSampleCount = 2;
  static const int errGravityImplausible = 3;
  static const int errSensorAlignment = 4;
  static const int errWrongState = 5;
  static const int errNoTrialData = 6;
  static const int errI2cFault = 7;
}
