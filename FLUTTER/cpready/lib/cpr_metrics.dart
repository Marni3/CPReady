import 'dart:typed_data';

/// CPReady telemetry metrics decoded from an 11-byte packed little-endian BLE packet.
///
/// Packet layout is defined in CPReady firmware:
/// `CPReady_Program/include/BLEReadings.h`
class CprMetrics {
  final int packetType;
  final bool recoilComplete;
  final int recoilPercentage;
  final int rateCpm;
  final double depthCm;
  final double depthMm;
  final int ccfPercent;
  final int audioPromptCode;
  final int totalCompressions;
  final int elapsedSeconds;

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
  });

  static CprMetrics fromBytes(List<int> bytes) {
    if (bytes.length < 11) {
      throw ArgumentError('Expected at least 11 bytes, got ${bytes.length}');
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));

    final type = byteData.getUint8(0);
    final recoilVal = byteData.getUint8(1);
    final rate = byteData.getUint16(2, Endian.little);
    final depthTenths = byteData.getUint16(4, Endian.little);
    final ccf = byteData.getUint8(6);
    final audioCue = byteData.getUint8(7);
    final totalCount = byteData.getUint8(8);
    final elapsed = byteData.getUint16(9, Endian.little);

    return CprMetrics(
      packetType: type,
      recoilComplete: recoilVal == 1,
      recoilPercentage: recoilVal,
      rateCpm: rate,
      depthCm: depthTenths / 100.0,
      depthMm: depthTenths / 10.0,
      ccfPercent: ccf,
      audioPromptCode: audioCue,
      totalCompressions: totalCount,
      elapsedSeconds: elapsed,
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
