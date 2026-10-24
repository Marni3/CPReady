/// CPReady telemetry metrics decoded from the firmware's packed little-endian
/// BLE packet.
///
/// Packet layout is defined in CPReady firmware:
/// `CPReady_Program/include/BLEReadings.h`. The current firmware sends 12
/// bytes; 11-byte packets from older firmware are still accepted and are
/// treated as steady cadence.
///
/// The class carries only decoded protocol values. Bit masks and cue codes
/// live in [AppBleConfig].

import 'dart:typed_data';

import '../../config/ble.dart';

class CprMetrics {
  final int packetType;

  /// The chest was released fully. Live frames carry this as a per-stroke
  /// flag; in a final summary it means the session reached 100% compliance.
  final bool recoilComplete;

  /// Full-release score on a 0..100 scale: the live flag scaled to 0 or 100,
  /// or the compliance percentage the final summary reports.
  final int recoilPercentage;
  final int rateCpm;
  final double depthCm;
  final double depthMm;
  final int ccfPercent;
  final int audioPromptCode;
  final int totalCompressions;
  final int elapsedSeconds;

  /// Quality bitfield from byte 11 (see [AppBleConfig.qualitySteadyCadence]
  /// and the other `quality*` masks).
  final int qualityFlags;

  const CprMetrics({
    required this.packetType,
    required this.recoilComplete,
    required this.recoilPercentage,
    required this.rateCpm,
    required this.depthCm,
    required this.depthMm,
    required this.ccfPercent,
    required this.audioPromptCode,
    required this.totalCompressions,
    required this.elapsedSeconds,
    this.qualityFlags = AppBleConfig.qualitySteadyCadence,
  });

  /// Cadence is steady enough for a stable reading.
  bool get isSteadyCadence =>
      qualityFlags & AppBleConfig.qualitySteadyCadence != 0;

  /// First stroke of a session, or the first after a pause.
  bool get isFirstStroke => qualityFlags & AppBleConfig.qualityFirstStroke != 0;

  /// The device is running the relaxed bench-test profile.
  bool get isBenchMode => qualityFlags & AppBleConfig.qualityBenchMode != 0;

  static CprMetrics fromBytes(List<int> bytes) {
    if (bytes.length < 11) {
      throw ArgumentError('Expected at least 11 bytes, got ${bytes.length}');
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));

    final type = byteData.getUint8(0);
    final recoilRaw = byteData.getUint8(1);

    // Byte 1 changes meaning with the packet type: a live frame carries the
    // per-stroke full-recoil flag (1/0), the final summary carries the session
    // recoil compliance percentage (0..100). Scaling the flag to 0/100 here
    // keeps every display path on one scale — reading the raw flag as a
    // percentage made every live packet look like "Partial".
    final bool isSummary = type == AppBleConfig.packetFinalSummary;
    final int recoilPercent = isSummary
        ? recoilRaw
        : (recoilRaw == 1 ? 100 : 0);
    final rate = byteData.getUint16(2, Endian.little);
    final depthTenths = byteData.getUint16(4, Endian.little);
    final ccf = byteData.getUint8(6);
    final audioCue = byteData.getUint8(7);
    final totalCount = byteData.getUint8(8);
    final elapsed = byteData.getUint16(9, Endian.little);
    final flags = bytes.length >= 12
        ? byteData.getUint8(11)
        : AppBleConfig.qualitySteadyCadence;

    return CprMetrics(
      packetType: type,
      recoilComplete: recoilPercent >= 100,
      recoilPercentage: recoilPercent,
      rateCpm: rate,
      depthCm: depthTenths / 100.0,
      depthMm: depthTenths / 10.0,
      ccfPercent: ccf,
      audioPromptCode: audioCue,
      totalCompressions: totalCount,
      elapsedSeconds: elapsed,
      qualityFlags: flags,
    );
  }
}

/// Human-readable audio coaching cue text for a CPReady `audio_prompt_code`.
String audioPromptText(int cueCode) {
  switch (cueCode) {
    case 0:
      return 'None';
    case 1:
      return 'Push harder';
    case 2:
      return 'Push shallower';
    case 3:
      return 'Release chest completely';
    case 4:
      return 'Speed up';
    case 5:
      return 'Slow down';
    case 6:
      return 'Good compressions';
    default:
      return 'Unknown cue $cueCode';
  }
}

/// Human-readable packet type label for a CPReady `packet_type`.
String packetTypeLabel(int packetType) {
  switch (packetType) {
    case 1:
      return 'Realtime';
    case 2:
      return 'Calibrating';
    case 3:
      return 'Calib Done';
    case 4:
      return 'Final Summary';
    case 5:
      return 'Error';
    default:
      return 'Unknown type $packetType';
  }
}
