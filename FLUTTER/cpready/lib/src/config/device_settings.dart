/// Device Settings persistence configuration.
///
/// The last known profile, depth scalar and duration are stored in the same
/// SQLite database as History. This keeps the screen sensible when firmware
/// does not answer GET_CONFIG (F-01 is still pending).
///
/// The DDL lives here so the table shape is editable in one place; the
/// repository in `lib/src/core/history/` executes it.

class AppDeviceSettings {
  /// Table holding the single local device-settings row.
  static const String table = 'device_settings';

  static const String columnId = 'id';
  static const String columnProfile = 'profile';
  static const String columnDepthK = 'depth_k';
  static const String columnPracticeDurationSec = 'practice_duration_sec';
  static const String columnUpdatedAt = 'updated_at_local';

  /// There is only ever one row; [save] replaces it.
  static const int singleRowId = 1;

  /// Factory / fallback practice duration, mirroring the firmware default.
  static const int defaultPracticeDurationSec = 120;

  /// Schema v3 DDL. Additive: History rows are untouched.
  static const String createTable =
      '''
CREATE TABLE $table (
  $columnId                   INTEGER PRIMARY KEY CHECK ($columnId = $singleRowId),
  $columnProfile              TEXT    NOT NULL,
  $columnDepthK               REAL,
  $columnPracticeDurationSec  INTEGER NOT NULL,
  $columnUpdatedAt            TEXT    NOT NULL
)
''';
}
