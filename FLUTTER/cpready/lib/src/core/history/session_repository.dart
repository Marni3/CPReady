/// The single reader/writer for the app's local SQLite database.
///
/// Creates and migrates the store in the app documents directory and exposes
/// the operations History and Device Settings need. All SQL and all table or
/// column names come from config, so no screen or widget contains either.

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../config/config.dart';
import '../settings/device_settings.dart';
import '../telemetry/telemetry_session_record.dart';
import 'session_record.dart';

/// Persists finished practice sessions and the last known device settings.
class SessionRepository {
  /// [factory] and [databasePath] exist for tests; production callers use the
  /// defaults (the real sqflite factory and the app documents directory).
  SessionRepository({DatabaseFactory? factory, String? databasePath})
      : this._(factory ?? databaseFactory, databasePath);

  SessionRepository._(this._factory, this._databasePath);

  final DatabaseFactory _factory;
  final String? _databasePath;

  Database? _db;

  static const List<String> _columns = <String>[
    AppHistory.columnId,
    AppHistory.columnTraineeName,
    AppHistory.columnStatus,
    AppHistory.columnStartedAt,
    AppHistory.columnEndedAt,
    AppHistory.columnDurationSeconds,
    AppHistory.columnPacketCount,
    AppHistory.columnRateCpm,
    AppHistory.columnDepthTenthsMm,
    AppHistory.columnRecoilPercent,
    AppHistory.columnCcfPercent,
    AppHistory.columnTotalCompressions,
    AppHistory.columnCompressionSeconds,
    AppHistory.columnPauseSeconds,
    AppHistory.columnQualityFlags,
    AppHistory.columnDeviceName,
    AppHistory.columnFirmwareVersion,
    AppHistory.columnAppVersion,
    AppHistory.columnPacketsLost,
  ];

  static const List<String> _telemetryColumns = <String>[
    AppHistory.columnTelemetryId,
    AppHistory.columnTelemetryParticipantCode,
    AppHistory.columnTelemetryExperiment,
    AppHistory.columnTelemetryNotes,
    AppHistory.columnTelemetryStatus,
    AppHistory.columnTelemetryStartedAt,
    AppHistory.columnTelemetryEndedAt,
    AppHistory.columnTelemetryLocalPath,
    AppHistory.columnTelemetrySampleCount,
    AppHistory.columnTelemetryFrameCount,
    AppHistory.columnTelemetryMissingSamples,
    AppHistory.columnTelemetryMissingFrames,
    AppHistory.columnTelemetrySizeBytes,
    AppHistory.columnTelemetryUploadAttempts,
    AppHistory.columnTelemetryLastError,
    AppHistory.columnTelemetryRemotePrefix,
    AppHistory.columnTelemetryDeviceName,
    AppHistory.columnTelemetryDeviceId,
    AppHistory.columnTelemetryAppVersion,
    AppHistory.columnTelemetryCreatedAt,
  ];

  /// Opens the database on first use and keeps the handle for later calls.
  Future<Database> _database() async {
    final Database? existing = _db;
    if (existing != null && existing.isOpen) return existing;

    final String path = _databasePath ?? await _defaultPath();

    final Database db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppHistory.schemaVersion,
        onCreate: (Database db, int version) async {
          await db.execute(AppHistory.createSessionsV6);
          await db.execute(AppDeviceSettings.createTable);
          await db.execute(AppHistory.createTelemetryV5);
        },
        onUpgrade: _migrate,
      ),
    );

    _db = db;
    return db;
  }

  /// Upgrades a database created by an older build.
  ///
  /// Every step is additive so saved history survives. When
  /// [AppHistory.schemaVersion] is bumped, add one step per version here (plus
  /// the matching DDL in `config/history.dart`).
  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(AppHistory.migrateSessionsV1ToV2);
    }
    if (oldVersion < 3) {
      await db.execute(AppDeviceSettings.createTable);
    }
    if (oldVersion < 4) {
      await db.execute(AppHistory.migrateSessionsV3ToV4);
    }
    if (oldVersion < 5) {
      await db.execute(AppHistory.createTelemetryV5);
    }
    if (oldVersion < 6) {
      for (final String statement in AppHistory.migrateSessionsV5ToV6) {
        await db.execute(statement);
      }
    }
  }

  Future<String> _defaultPath() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/${AppHistory.fileName}';
  }

  /// Inserts a finished session and returns its new row id.
  Future<int> insertSession(SessionRecord record) async {
    final Database db = await _database();
    return db.insert(AppHistory.tableSessions, record.toMap());
  }

  /// All saved sessions, newest first (by session start, then insertion).
  Future<List<SessionRecord>> listSessions() async {
    final Database db = await _database();
    final List<Map<String, Object?>> rows = await db.query(
      AppHistory.tableSessions,
      columns: _columns,
      orderBy:
          '${AppHistory.columnStartedAt} DESC, ${AppHistory.columnId} DESC',
    );
    return rows.map(SessionRecord.fromMap).toList(growable: false);
  }

  /// One session by row id, or null when it no longer exists.
  Future<SessionRecord?> getSession(int id) async {
    final Database db = await _database();
    final List<Map<String, Object?>> rows = await db.query(
      AppHistory.tableSessions,
      columns: _columns,
      where: '${AppHistory.columnId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SessionRecord.fromMap(rows.first);
  }

  /// Deletes one session.
  Future<void> deleteSession(int id) async {
    final Database db = await _database();
    await db.delete(
      AppHistory.tableSessions,
      where: '${AppHistory.columnId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Deletes every saved session.
  Future<void> deleteAllSessions() async {
    final Database db = await _database();
    await db.delete(AppHistory.tableSessions);
  }

  /// Last known device settings, or null before anything has been saved.
  Future<DeviceSettings?> loadDeviceSettings() async {
    final Database db = await _database();
    final List<Map<String, Object?>> rows = await db.query(
      AppDeviceSettings.table,
      where: '${AppDeviceSettings.columnId} = ?',
      whereArgs: <Object?>[AppDeviceSettings.singleRowId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DeviceSettings.fromMap(rows.first);
  }

  /// Replaces the single local settings row.
  Future<void> saveDeviceSettings(DeviceSettings settings) async {
    final Database db = await _database();
    await db.insert(
      AppDeviceSettings.table,
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clears the local fallback, e.g. when the stored row is unreadable.
  Future<void> clearDeviceSettings() async {
    final Database db = await _database();
    await db.delete(AppDeviceSettings.table);
  }

  // -----------------------------------------------------------------------
  // Raw telemetry upload queue
  // -----------------------------------------------------------------------

  /// Inserts or replaces one raw-recording row.
  Future<void> saveTelemetrySession(TelemetrySessionRecord record) async {
    final Database db = await _database();
    await db.insert(
      AppHistory.tableTelemetry,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marks rows left in `recording` by a killed app as incomplete. The files
  /// stay on disk; they are not auto-uploaded because their session.json may
  /// be incomplete.
  Future<int> markStaleTelemetryRecordings() async {
    final Database db = await _database();
    return db.update(
      AppHistory.tableTelemetry,
      <String, Object?>{
        AppHistory.columnTelemetryStatus: AppHistory.telemetryIncomplete,
        AppHistory.columnTelemetryLastError:
            'App terminated before the recording was finalised',
      },
      where: '${AppHistory.columnTelemetryStatus} = ?',
      whereArgs: <Object?>[AppHistory.telemetryRecording],
    );
  }

  /// One raw session by UUID, or null.
  Future<TelemetrySessionRecord?> getTelemetrySession(String id) async {
    final Database db = await _database();
    final List<Map<String, Object?>> rows = await db.query(
      AppHistory.tableTelemetry,
      columns: _telemetryColumns,
      where: '${AppHistory.columnTelemetryId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TelemetrySessionRecord.fromMap(rows.first);
  }

  /// Sessions whose upload should be attempted, oldest first.
  Future<List<TelemetrySessionRecord>> listPendingTelemetry() async {
    final Database db = await _database();
    final List<Map<String, Object?>> rows = await db.query(
      AppHistory.tableTelemetry,
      columns: _telemetryColumns,
      where: '${AppHistory.columnTelemetryStatus} IN (?, ?, ?) '
          'AND ${AppHistory.columnTelemetryUploadAttempts} < ?',
      whereArgs: <Object?>[
        AppHistory.telemetryComplete,
        AppHistory.telemetryInterrupted,
        AppHistory.telemetryFailed,
        AppHistory.telemetryMaxUploadAttempts,
      ],
      orderBy: '${AppHistory.columnTelemetryStartedAt} ASC',
    );
    return rows.map(TelemetrySessionRecord.fromMap).toList(growable: false);
  }

  /// Records the outcome of one upload attempt.
  Future<void> updateTelemetryUpload({
    required String id,
    required String status,
    required int attempts,
    String? error,
    String? remotePrefix,
  }) async {
    final Database db = await _database();
    await db.update(
      AppHistory.tableTelemetry,
      <String, Object?>{
        AppHistory.columnTelemetryStatus: status,
        AppHistory.columnTelemetryUploadAttempts: attempts,
        AppHistory.columnTelemetryLastError: error,
        if (remotePrefix != null)
          AppHistory.columnTelemetryRemotePrefix: remotePrefix,
      },
      where: '${AppHistory.columnTelemetryId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Removes the queue row only; local files are owned by the recorder and are
  /// intentionally not deleted here.
  Future<void> deleteTelemetrySession(String id) async {
    final Database db = await _database();
    await db.delete(
      AppHistory.tableTelemetry,
      where: '${AppHistory.columnTelemetryId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Closes the database handle.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
