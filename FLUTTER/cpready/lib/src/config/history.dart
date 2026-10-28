/// Practice History persistence configuration.
///
/// Everything the History store and its screens read without executing logic:
/// database identity, schema version, table/column names, session status
/// values, and the date/time/duration display formats.
///
/// The DDL lives here so a column rename is a single edit in `lib/src/config/`.
/// The repository in `lib/src/core/history/` executes it; no screen contains
/// SQL or column names.

class AppHistory {
  // -----------------------------------------------------------------------
  // Database
  // -----------------------------------------------------------------------

  /// File name of the SQLite database inside the app documents directory.
  static const String fileName = 'cpready_history.db';

  /// Schema version written to the database.
  ///
  /// Bump this and add a matching `case` to the repository's migration switch
  /// whenever the table shape changes, so existing installs upgrade instead of
  /// losing their history.
  ///
  /// v3 is additive: it only creates the Device Settings table.
  /// v4 is additive: it adds [columnPacketsLost] to the sessions table.
  static const int schemaVersion = 4;

  // -----------------------------------------------------------------------
  // Table and columns
  // -----------------------------------------------------------------------

  static const String tableSessions = 'sessions';

  static const String columnId = 'id';
  static const String columnTraineeName = 'trainee_name';
  static const String columnStatus = 'status';
  static const String columnStartedAt = 'started_at_local';
  static const String columnEndedAt = 'ended_at_local';
  static const String columnDurationSeconds = 'duration_seconds';
  static const String columnPacketCount = 'packet_count';

  // FINAL_SUMMARY packet fields (all NULL for an interrupted session).
  static const String columnRateCpm = 'rate_cpm';
  static const String columnDepthTenthsMm = 'depth_tenths_mm';
  static const String columnRecoilPercent = 'recoil_percent';
  static const String columnCcfPercent = 'ccf_percent';
  static const String columnTotalCompressions = 'total_compressions';

  /// Firmware quality_flags byte (steady/first-stroke/bench mode).
  static const String columnQualityFlags = 'quality_flags';

  /// Telemetry notifications lost during the session (sequence-number gaps);
  /// the received count is [columnPacketCount]. NULL for rows before v4.
  static const String columnPacketsLost = 'packets_lost';

  // Provenance.
  static const String columnDeviceName = 'device_name';
  static const String columnFirmwareVersion = 'firmware_version';
  static const String columnAppVersion = 'app_version';

  /// Schema v1 DDL. Kept for migration tests and for documentation of the
  /// shape that existed before [columnQualityFlags] was added.
  static const String createSessionsV1 =
      '''
CREATE TABLE $tableSessions (
  $columnId                 INTEGER PRIMARY KEY AUTOINCREMENT,
  $columnTraineeName        TEXT    NOT NULL,
  $columnStatus             TEXT    NOT NULL,
  $columnStartedAt          TEXT    NOT NULL,
  $columnEndedAt            TEXT    NOT NULL,
  $columnDurationSeconds    INTEGER NOT NULL,
  $columnPacketCount        INTEGER NOT NULL,
  $columnRateCpm            INTEGER,
  $columnDepthTenthsMm      INTEGER,
  $columnRecoilPercent      INTEGER,
  $columnCcfPercent         INTEGER,
  $columnTotalCompressions  INTEGER,
  $columnDeviceName         TEXT,
  $columnFirmwareVersion    TEXT,
  $columnAppVersion         TEXT
)
''';

  /// Schema v2 DDL: v1 plus the firmware's quality flags.
  static const String createSessionsV2 =
      '''
CREATE TABLE $tableSessions (
  $columnId                 INTEGER PRIMARY KEY AUTOINCREMENT,
  $columnTraineeName        TEXT    NOT NULL,
  $columnStatus             TEXT    NOT NULL,
  $columnStartedAt          TEXT    NOT NULL,
  $columnEndedAt            TEXT    NOT NULL,
  $columnDurationSeconds    INTEGER NOT NULL,
  $columnPacketCount        INTEGER NOT NULL,
  $columnRateCpm            INTEGER,
  $columnDepthTenthsMm      INTEGER,
  $columnRecoilPercent      INTEGER,
  $columnCcfPercent         INTEGER,
  $columnTotalCompressions  INTEGER,
  $columnQualityFlags       INTEGER,
  $columnDeviceName         TEXT,
  $columnFirmwareVersion    TEXT,
  $columnAppVersion         TEXT
)
''';

  /// Schema v4 DDL: v2 plus the lost-packet count.
  static const String createSessionsV4 =
      '''
CREATE TABLE $tableSessions (
  $columnId                 INTEGER PRIMARY KEY AUTOINCREMENT,
  $columnTraineeName        TEXT    NOT NULL,
  $columnStatus             TEXT    NOT NULL,
  $columnStartedAt          TEXT    NOT NULL,
  $columnEndedAt            TEXT    NOT NULL,
  $columnDurationSeconds    INTEGER NOT NULL,
  $columnPacketCount        INTEGER NOT NULL,
  $columnRateCpm            INTEGER,
  $columnDepthTenthsMm      INTEGER,
  $columnRecoilPercent      INTEGER,
  $columnCcfPercent         INTEGER,
  $columnTotalCompressions  INTEGER,
  $columnQualityFlags       INTEGER,
  $columnDeviceName         TEXT,
  $columnFirmwareVersion    TEXT,
  $columnAppVersion         TEXT,
  $columnPacketsLost        INTEGER
)
''';

  /// Additive v1 → v2 migration. Existing rows keep all their data and get a
  /// null quality_flags value.
  static const String migrateSessionsV1ToV2 =
      'ALTER TABLE $tableSessions ADD COLUMN $columnQualityFlags INTEGER';

  /// Additive v3 → v4 migration. Existing rows get a null packets_lost value.
  static const String migrateSessionsV3ToV4 =
      'ALTER TABLE $tableSessions ADD COLUMN $columnPacketsLost INTEGER';

  // -----------------------------------------------------------------------
  // Session status values (stored verbatim in [columnStatus])
  // -----------------------------------------------------------------------

  /// A session that ended with a FINAL_SUMMARY packet.
  static const String statusCompleted = 'completed';

  /// A session that ended early (e.g. the BLE link dropped).
  static const String statusInterrupted = 'interrupted';

  // -----------------------------------------------------------------------
  // Display formats
  // -----------------------------------------------------------------------
  //
  // A tiny formatter in `core/history/` renders these patterns; the month
  // names and patterns are data so the row layout is editable here.

  /// Month abbreviations, index 0 = January.
  static const List<String> monthAbbreviations = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Date layout for a History row. Tokens: `MMM`, `d`, `yyyy`.
  static const String datePattern = 'MMM d, yyyy';

  /// Time layout for a History row. Tokens: `h`/`hh` (12-hour), `mm`, `A`
  /// (substituted with [amSuffix] or [pmSuffix]).
  static const String timePattern = 'h:mm A';

  /// Substituted for the `A` token in [timePattern].
  static const String amSuffix = 'AM';
  static const String pmSuffix = 'PM';

  /// Separator between the date and the time on a History row.
  static const String dateTimeSeparator = ' ';

  /// Separator between the timestamp and the duration on a History row.
  static const String rowSeparator = '  •  ';

  /// Separator between the minutes and the seconds of a duration.
  static const String durationSeparator = ':';
}
