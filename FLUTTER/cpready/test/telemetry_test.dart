/// Raw frame decoding and local recording layout.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/core/telemetry/raw_frame.dart';
import 'package:cpready/src/core/telemetry/session_metadata.dart';
import 'package:cpready/src/core/telemetry/telemetry_recorder.dart';

Uint8List _frame({
  required int sequence,
  required int firstIndex,
  required List<List<int>> samples,
  int flags = AppTelemetry.flagStreaming,
  int unclampedDepthMm = 58,
}) {
  final int count = samples.length;
  final Uint8List bytes = Uint8List(
    AppTelemetry.headerBytes + count * AppTelemetry.sampleBytes,
  );
  final ByteData data = ByteData.sublistView(bytes);
  data.setUint8(0, AppTelemetry.frameType);
  data.setUint8(1, AppTelemetry.frameVersion);
  data.setUint16(2, sequence, Endian.little);
  data.setUint8(4, count);
  data.setUint8(5, flags);
  data.setUint16(6, 7, Endian.little);
  data.setUint32(8, firstIndex, Endian.little);
  data.setUint16(12, 0, Endian.little);
  data.setUint8(14, 2);
  data.setUint8(15, unclampedDepthMm);
  for (int i = 0; i < count; i++) {
    final int base = AppTelemetry.headerBytes + i * AppTelemetry.sampleBytes;
    data.setUint32(base, 1000000 + i * 10000, Endian.little);
    data.setInt16(base + 4, samples[i][0], Endian.little);
    data.setInt16(base + 6, samples[i][1], Endian.little);
    data.setInt16(base + 8, samples[i][2], Endian.little);
    data.setInt16(base + 10, samples[i][3], Endian.little);
    data.setInt16(base + 12, samples[i][4], Endian.little);
    data.setInt16(base + 14, samples[i][5], Endian.little);
  }
  return bytes;
}

void main() {
  test('decodes a 2-sample frame with the frozen offsets', () {
    final RawTelemetryFrame frame = RawTelemetryFrame.fromBytes(
      _frame(
        sequence: 3,
        firstIndex: 40,
        samples: <List<int>>[
          <int>[1, -2, 3, -4, 5, -6],
          <int>[7, -8, 9, -10, 11, -12],
        ],
      ),
    );

    expect(frame.frameSequence, 3);
    expect(frame.strokeCount, 7);
    expect(frame.firstSampleIndex, 40);
    expect(frame.samples, hasLength(2));
    expect(frame.samples[0].sampleIndex, 40);
    expect(frame.samples[1].sampleIndex, 41);
    expect(frame.samples[0].timeUs, 1000000);
    expect(frame.samples[0].chestXMg, 1);
    expect(frame.samples[0].chestYMg, -2);
    expect(frame.samples[0].chestZMg, 3);
    expect(frame.samples[0].baseXMg, -4);
    expect(frame.samples[0].baseYMg, 5);
    expect(frame.samples[0].baseZMg, -6);
    expect(frame.samples[1].chestZMg, 9);
    expect(frame.unclampedDepthMm, 58);
  });

  test('rejects type, version, count and length mismatches', () {
    final Uint8List good = _frame(
      sequence: 1,
      firstIndex: 0,
      samples: <List<int>>[
        <int>[0, 0, 0, 0, 0, 0],
      ],
    );

    final Uint8List wrongType = Uint8List.fromList(good);
    wrongType[0] = 0x03;
    expect(
      () => RawTelemetryFrame.fromBytes(wrongType),
      throwsFormatException,
    );

    final Uint8List wrongVersion = Uint8List.fromList(good);
    wrongVersion[1] = 2;
    expect(
      () => RawTelemetryFrame.fromBytes(wrongVersion),
      throwsFormatException,
    );

    final Uint8List wrongCount = Uint8List.fromList(good);
    wrongCount[4] = 2;
    expect(
      () => RawTelemetryFrame.fromBytes(wrongCount),
      throwsFormatException,
    );

    expect(
      () => RawTelemetryFrame.fromBytes(good.sublist(0, 20)),
      throwsFormatException,
    );
  });

  test('records raw CSV rows and counts sample/frame gaps', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'cpready_telemetry_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final TelemetryRecorder recorder = TelemetryRecorder(rootDirectory: root);
    final TelemetryRecording started = await recorder.start(
      SessionMetadata(
        sessionId: '11111111-1111-4111-8111-111111111111',
        participantCode: 'P001',
        experiment: 'test',
        notes: 'unit',
        deviceName: 'CPReady',
        deviceId: 'device',
        appVersion: '1.0.0',
        startedAt: DateTime.utc(2026, 11, 1, 12),
      ),
    );

    recorder.addFrame(
      RawTelemetryFrame.fromBytes(
        _frame(
          sequence: 1,
          firstIndex: 0,
          samples: <List<int>>[
            <int>[1, 2, 3, 4, 5, 6],
            <int>[7, 8, 9, 10, 11, 12],
          ],
        ),
      ),
    );
    recorder.addFrame(
      RawTelemetryFrame.fromBytes(
        _frame(
          sequence: 4,
          firstIndex: 4,
          samples: <List<int>>[
            <int>[13, 14, 15, 16, 17, 18],
            <int>[19, 20, 21, 22, 23, 24],
          ],
        ),
      ),
    );
    recorder.addMetrics(
      const CprMetrics(
        packetType: AppBleConfig.packetRealtime,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 110,
        depthCm: 5.5,
        depthMm: 55,
        ccfPercent: 90,
        audioPromptCode: 0,
        totalCompressions: 8,
        elapsedSeconds: 12,
        qualityFlags: AppBleConfig.qualitySteadyCadence,
        sequence: 9,
      ),
    );

    final TelemetryRecording stopped = await recorder.stop();
    expect(started.sampleCount, 0);
    expect(stopped.sampleCount, 4);
    expect(stopped.frameCount, 2);
    expect(stopped.missingSamples, 2);
    expect(stopped.missingFrames, 2);
    expect(stopped.status, 'complete');

    final List<String> raw = await File(stopped.rawPath).readAsLines();
    expect(raw, hasLength(5));
    expect(raw.first, AppTelemetry.rawHeader);
    expect(raw[1], contains('1000000,0,1,7,2,1,1,2,3,4,5,6,58'));

    final List<String> metrics = await File(stopped.metricsPath).readAsLines();
    expect(metrics, hasLength(2));
    expect(metrics.first, AppTelemetry.metricsHeader);
    expect(metrics[1], contains('1,110,550,90'));

    final List<String> events = await File(stopped.eventsPath).readAsLines();
    expect(events.any((String line) => line.contains(',stroke,8')), isTrue);
    expect(
      events.any((String line) => line.contains(',recording_stopped,')),
      isTrue,
    );

    final Map<String, Object?> json =
        jsonDecode(await File(stopped.metadataPath).readAsString())
            as Map<String, Object?>;
    expect(json['schema_version'], 2);
    expect(json['session_id'], '11111111-1111-4111-8111-111111111111');
    expect(json['participant_code'], 'P001');
    expect(json['status'], 'complete');
    expect(json['sample_count'], 4);
    expect(json['missing_samples'], 2);
    expect(json['trainee_name'], isNull);
  });
}
