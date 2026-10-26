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
    AppHistory.columnQualityFlags,
    AppHistory.columnDeviceName,
    AppHistory.columnFirmwareVersion,
    AppHistory.columnAppVersion,
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
          await db.execute(AppHistory.createSessionsV2);
          await db.execute(AppDeviceSettings.createTable);
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

  /// Closes the database handle.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
