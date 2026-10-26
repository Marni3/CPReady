import 'package:sqflite/sqflite.dart';

import 'package:cpready/src/core/history/session_record.dart';
import 'package:cpready/src/core/history/session_repository.dart';
import 'package:cpready/src/core/settings/device_settings.dart';

class _FailingDatabaseFactory implements DatabaseFactory {
  const _FailingDatabaseFactory();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('The fake repository does not open a database');
  }
}

/// Repository that records inserts in memory.
class FakeSessionRepository extends SessionRepository {
  FakeSessionRepository()
    : super(
        factory: const _FailingDatabaseFactory(),
        databasePath: 'fake-history.db',
      );

  final List<SessionRecord> inserted = <SessionRecord>[];

  /// In-memory stand-in for the single Device Settings row.
  DeviceSettings? deviceSettings;

  @override
  Future<int> insertSession(SessionRecord record) async {
    inserted.add(record);
    return inserted.length;
  }

  @override
  Future<List<SessionRecord>> listSessions() async =>
      inserted.reversed.toList(growable: false);

  @override
  Future<DeviceSettings?> loadDeviceSettings() async => deviceSettings;

  @override
  Future<void> saveDeviceSettings(DeviceSettings settings) async {
    deviceSettings = settings;
  }

  @override
  Future<void> clearDeviceSettings() async {
    deviceSettings = null;
  }
}
