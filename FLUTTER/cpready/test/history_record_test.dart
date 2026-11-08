/// History schema and quality-flag / packet-loss / timing provenance.

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/history/session_record.dart';

void main() {
  test('schema v6 keeps the older fields and adds the session tables', () {
    expect(AppHistory.schemaVersion, 6);
    expect(AppHistory.columnQualityFlags, 'quality_flags');
    expect(AppHistory.createSessionsV2, contains('quality_flags'));
    expect(
      AppHistory.migrateSessionsV1ToV2,
      'ALTER TABLE sessions ADD COLUMN quality_flags INTEGER',
    );
    expect(AppHistory.createSessionsV4, contains('quality_flags'));
    expect(AppHistory.createSessionsV4, contains('packets_lost'));
    expect(
      AppHistory.migrateSessionsV3ToV4,
      'ALTER TABLE sessions ADD COLUMN packets_lost INTEGER',
    );
    expect(AppHistory.createTelemetryV5, contains(AppHistory.tableTelemetry));
    expect(
      AppHistory.createTelemetryV5,
      contains(AppHistory.columnTelemetryLocalPath),
    );
    expect(
      AppHistory.createSessionsV6,
      contains(AppHistory.columnCompressionSeconds),
    );
    expect(
      AppHistory.createSessionsV6,
      contains(AppHistory.columnPauseSeconds),
    );
    expect(AppHistory.migrateSessionsV5ToV6, hasLength(2));
    expect(AppDeviceSettings.createTable, contains(AppDeviceSettings.table));
    expect(
      AppDeviceSettings.createTable,
      contains(AppDeviceSettings.columnDepthK),
    );
  });

  test('record round-trips the lost-packet count', () {
    final record = SessionRecord(
      traineeName: 'Alexandra',
      status: SessionStatus.completed,
      startedAt: DateTime(2026, 10, 26, 10),
      endedAt: DateTime(2026, 10, 26, 10, 2),
      durationSeconds: 120,
      packetCount: 598,
      packetsLost: 2,
      rateCpm: 110,
      depthTenthsMm: 550,
      recoilPercent: 100,
      ccfPercent: 90,
      totalCompressions: 230,
    );

    final loaded = SessionRecord.fromMap(record.toMap());

    expect(loaded.packetCount, 598);
    expect(loaded.packetsLost, 2);
    expect(loaded.totalCompressions, 230);
  });

  test('record round-trips compression and pause time', () {
    final record = SessionRecord(
      traineeName: 'Alexandra',
      status: SessionStatus.completed,
      startedAt: DateTime(2026, 10, 26, 10),
      endedAt: DateTime(2026, 10, 26, 10, 2),
      durationSeconds: 110,
      packetCount: 240,
      rateCpm: 110,
      depthTenthsMm: 550,
      recoilPercent: 100,
      ccfPercent: 88,
      totalCompressions: 200,
      compressionSeconds: 97,
      pauseSeconds: 13,
    );

    final loaded = SessionRecord.fromMap(record.toMap());

    expect(loaded.compressionSeconds, 97);
    expect(loaded.pauseSeconds, 13);
  });

  test('record round-trips quality flags and bench provenance', () {
    final record = SessionRecord(
      traineeName: 'Alexandra',
      status: SessionStatus.completed,
      startedAt: DateTime(2026, 10, 26, 10),
      endedAt: DateTime(2026, 10, 26, 10, 2),
      durationSeconds: 120,
      packetCount: 240,
      rateCpm: 110,
      depthTenthsMm: 550,
      recoilPercent: 100,
      ccfPercent: 90,
      totalCompressions: 30,
      qualityFlags:
          AppBleConfig.qualitySteadyCadence | AppBleConfig.qualityBenchMode,
      deviceName: 'CPReady',
      appVersion: '1.0.0',
    );

    final loaded = SessionRecord.fromMap(record.toMap());

    expect(loaded.qualityFlags, 0x05);
    expect(loaded.isBenchMode, isTrue);
    expect(loaded.summary?.qualityFlags, 0x05);
    expect(loaded.summary?.isBenchMode, isTrue);
    expect(loaded.summary?.recoilComplete, isTrue);
  });

  test('old rows without quality flags load as standard manikin sessions', () {
    final record = SessionRecord(
      id: 1,
      traineeName: 'Alexandra',
      status: SessionStatus.completed,
      startedAt: DateTime(2026, 10, 26, 10),
      endedAt: DateTime(2026, 10, 26, 10, 2),
      durationSeconds: 120,
      packetCount: 240,
      rateCpm: 110,
      depthTenthsMm: 550,
      recoilPercent: 80,
      ccfPercent: 90,
      totalCompressions: 30,
      qualityFlags: null,
      deviceName: 'CPReady',
      appVersion: '1.0.0',
    );

    expect(record.isBenchMode, isFalse);
    expect(record.summary?.qualityFlags, AppBleConfig.qualitySteadyCadence);
    expect(record.summary?.isBenchMode, isFalse);
    expect(record.summary?.recoilComplete, isFalse);
  });
}
