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
}
