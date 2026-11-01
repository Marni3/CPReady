import 'dart:typed_data';

import '../../config/config.dart';

/// One unfiltered accelerometer sample from the raw BLE stream.
class RawTelemetrySample {
  /// Device `micros()` at the read.
  final int timeUs;

  /// Frame-relative monotonic index.
  final int sampleIndex;

  final int chestXMg;
  final int chestYMg;
  final int chestZMg;
  final int baseXMg;
  final int baseYMg;
  final int baseZMg;

  const RawTelemetrySample({
    required this.timeUs,
    required this.sampleIndex,
    required this.chestXMg,
    required this.chestYMg,
    required this.chestZMg,
    required this.baseXMg,
    required this.baseYMg,
    required this.baseZMg,
  });
}

/// A decoded raw accelerometer frame.
///
/// Throws [FormatException] for any length, type, version or count that does
/// not match the frozen contract in [AppTelemetry].
class RawTelemetryFrame {
  final int frameSequence;
  final int flags;
  final int strokeCount;
  final int firstSampleIndex;
  final int droppedFrames;
  final int deviceState;
  final List<RawTelemetrySample> samples;

  const RawTelemetryFrame({
    required this.frameSequence,
    required this.flags,
    required this.strokeCount,
    required this.firstSampleIndex,
    required this.droppedFrames,
    required this.deviceState,
    required this.samples,
  });

  bool get isStreaming => flags & AppTelemetry.flagStreaming != 0;
  bool get hasSensorFault => flags & AppTelemetry.flagSensorFault != 0;
  bool get hasOverrun => flags & AppTelemetry.flagOverrun != 0;
  bool get isCalibrating => flags & AppTelemetry.flagCalibrating != 0;

  static RawTelemetryFrame fromBytes(List<int> bytes) {
    if (bytes.length < AppTelemetry.headerBytes) {
      throw FormatException(
        'Raw frame too short: ${bytes.length} bytes',
      );
    }

    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    if (data.getUint8(0) != AppTelemetry.frameType) {
      throw FormatException(
          'Not a raw telemetry frame: type ${data.getUint8(0)}');
    }
    if (data.getUint8(1) != AppTelemetry.frameVersion) {
      throw FormatException(
        'Unsupported raw telemetry version: ${data.getUint8(1)}',
      );
    }

    final int sampleCount = data.getUint8(4);
    if (sampleCount < 1 || sampleCount > AppTelemetry.maxSamplesPerFrame) {
      throw FormatException('Invalid raw sample count: $sampleCount');
    }

    final int expected =
        AppTelemetry.headerBytes + sampleCount * AppTelemetry.sampleBytes;
    if (bytes.length != expected) {
      throw FormatException(
        'Raw frame length ${bytes.length}, expected $expected',
      );
    }

    final int firstSampleIndex = data.getUint32(8, Endian.little);
    final List<RawTelemetrySample> samples =
        List<RawTelemetrySample>.generate(sampleCount, (int i) {
      final int base = AppTelemetry.headerBytes + i * AppTelemetry.sampleBytes;
      return RawTelemetrySample(
        timeUs: data.getUint32(base, Endian.little),
        sampleIndex: firstSampleIndex + i,
        chestXMg: data.getInt16(base + 4, Endian.little),
        chestYMg: data.getInt16(base + 6, Endian.little),
        chestZMg: data.getInt16(base + 8, Endian.little),
        baseXMg: data.getInt16(base + 10, Endian.little),
        baseYMg: data.getInt16(base + 12, Endian.little),
        baseZMg: data.getInt16(base + 14, Endian.little),
      );
    }, growable: false);

    return RawTelemetryFrame(
      frameSequence: data.getUint16(2, Endian.little),
      flags: data.getUint8(5),
      strokeCount: data.getUint16(6, Endian.little),
      firstSampleIndex: firstSampleIndex,
      droppedFrames: data.getUint16(12, Endian.little),
      deviceState: data.getUint8(14),
      samples: samples,
    );
  }
}
