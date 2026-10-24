/// Packet decoding: the current 12-byte frame and the 11-byte fallback.

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';

void main() {
  List<int> frame({int flags = AppBleConfig.qualitySteadyCadence}) {
    return <int>[
      AppBleConfig.packetRealtime, // packet type
      1, // recoil flag: 1 = full release, 0 = leaning
      110, 0, // rate, little-endian
      0x1C, 0x02, // depth in hundredths of a cm (540 -> 5.40 cm)
      96, // CCF
      AppBleConfig.cuePushHarder, // audio cue
      152, // total compressions
      83, 0, // elapsed seconds, little-endian
      flags,
    ];
  }

  test('decodes the 12-byte packet, including its quality flags', () {
    final CprMetrics metrics = CprMetrics.fromBytes(frame(flags: 0x05));

    expect(metrics.packetType, AppBleConfig.packetRealtime);
    expect(metrics.recoilPercentage, 100);
    expect(metrics.recoilComplete, isTrue);
    expect(metrics.rateCpm, 110);
    expect(metrics.depthCm, closeTo(5.40, 0.001));
    expect(metrics.depthMm, closeTo(54.0, 0.001));
    expect(metrics.ccfPercent, 96);
    expect(metrics.audioPromptCode, AppBleConfig.cuePushHarder);
    expect(metrics.totalCompressions, 152);
    expect(metrics.elapsedSeconds, 83);
    expect(metrics.qualityFlags, 0x05);
    expect(metrics.isSteadyCadence, isTrue);
    expect(metrics.isFirstStroke, isFalse);
    expect(metrics.isBenchMode, isTrue);
  });

  test('scales the live recoil flag instead of reading it as a percentage', () {
    final List<int> leaning = frame()..[1] = 0;

    expect(CprMetrics.fromBytes(frame()).recoilPercentage, 100);
    expect(CprMetrics.fromBytes(leaning).recoilPercentage, 0);
    expect(CprMetrics.fromBytes(leaning).recoilComplete, isFalse);
  });

  test('keeps the summary recoil compliance percentage', () {
    final List<int> summary = frame()..[0] = AppBleConfig.packetFinalSummary;
    summary[1] = 88;

    final CprMetrics metrics = CprMetrics.fromBytes(summary);

    expect(metrics.recoilPercentage, 88);
    expect(metrics.recoilComplete, isFalse);
  });

  test('decodes each quality bit independently', () {
    expect(CprMetrics.fromBytes(frame(flags: 0x01)).isSteadyCadence, isTrue);
    expect(CprMetrics.fromBytes(frame(flags: 0x02)).isFirstStroke, isTrue);
    expect(CprMetrics.fromBytes(frame(flags: 0x00)).isSteadyCadence, isFalse);
  });

  test('treats an 11-byte packet as steady cadence', () {
    final CprMetrics metrics = CprMetrics.fromBytes(frame().sublist(0, 11));

    expect(metrics.rateCpm, 110);
    expect(metrics.qualityFlags, AppBleConfig.qualitySteadyCadence);
    expect(metrics.isSteadyCadence, isTrue);
    expect(metrics.isBenchMode, isFalse);
  });

  test('rejects a frame shorter than 11 bytes', () {
    expect(
      () => CprMetrics.fromBytes(frame().sublist(0, 10)),
      throwsArgumentError,
    );
  });
}
