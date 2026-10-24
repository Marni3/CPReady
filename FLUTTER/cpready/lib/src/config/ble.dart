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

  /// Selects the adult-manikin kinematic profile. The firmware also resets its
  /// depth scalar to that profile's default value.
  static const String commandProfileManikin = 'SET_PROFILE:MANIKIN';

  /// Selects the relaxed bench-test kinematic profile.
  static const String commandProfileBench = 'SET_PROFILE:BENCH';

  /// Sets the firmware's auto-stop duration. The value is volatile: it lasts
  /// until the device restarts and applies to the next session.
  static String commandSetTime(int seconds) => 'SET_TIME:$seconds';

  /// Scales the depth reading so a trial mean of the measured depth matches the
  /// manikin's reported depth.
  static String commandCalibrateTarget(double depthCm) =>
      'CALIBRATE_TARGET:${depthCm.toStringAsFixed(1)}';

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

  // -----------------------------------------------------------------------
  // Audio coaching cue codes (byte 7)
  // -----------------------------------------------------------------------

  static const int cuePushHarder = 1;
  static const int cuePushShallower = 2;
  static const int cueReleaseFully = 3;
  static const int cueSpeedUp = 4;
  static const int cueSlowDown = 5;
  static const int cueGoodJob = 6;
}
