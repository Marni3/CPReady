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
  /// v5 is additive: it creates the raw-telemetry upload queue table.
  /// v6 is additive: it adds [columnCompressionSeconds] and
  /// [columnPauseSeconds] to the sessions table.
  static const int schemaVersion = 6;

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

  /// Active compression time and pause time, in whole seconds, derived from
  /// [columnCcfPercent] and [columnDurationSeconds] when the session is saved.
  static const String columnCompressionSeconds = 'compression_seconds';
  static const String columnPauseSeconds = 'pause_seconds';

  /// Firmware quality_flags byte (steady/first-stroke/bench mode).
  static const String columnQualityFlags = 'quality_flags';

  /// Telemetry notifications lost during the session (sequence-number gaps);
  /// the received count is [columnPacketCount]. NULL for rows before v4.
  static const String columnPacketsLost = 'packets_lost';

  // -----------------------------------------------------------------------
  // Raw telemetry upload queue (schema v5)
  // -----------------------------------------------------------------------

  static const String tableTelemetry = 'telemetry_sessions';

  static const String columnTelemetryId = 'id';
  static const String columnTelemetryParticipantCode = 'participant_code';
  static const String columnTelemetryExperiment = 'experiment';
  static const String columnTelemetryNotes = 'notes';
  static const String columnTelemetryStatus = 'status';
  static const String columnTelemetryStartedAt = 'started_at_local';
  static const String columnTelemetryEndedAt = 'ended_at_local';
  static const String columnTelemetryLocalPath = 'local_path';
  static const String columnTelemetrySampleCount = 'sample_count';
  static const String columnTelemetryFrameCount = 'frame_count';
  static const String columnTelemetryMissingSamples = 'missing_samples';
  static const String columnTelemetryMissingFrames = 'missing_frames';
  static const String columnTelemetrySizeBytes = 'size_bytes';
  static const String columnTelemetryUploadAttempts = 'upload_attempts';
  static const String columnTelemetryLastError = 'last_error';
  static const String columnTelemetryRemotePrefix = 'remote_prefix';
  static const String columnTelemetryDeviceName = 'device_name';
  static const String columnTelemetryDeviceId = 'device_id';
  static const String columnTelemetryAppVersion = 'app_version';
  static const String columnTelemetryCreatedAt = 'created_at_local';

  /// Additive v5 table. Every raw recording has one row, created when the
  /// session starts and updated when it stops and when an upload is attempted.
  static const String createTelemetryV5 = '''
CREATE TABLE $tableTelemetry (
  $columnTelemetryId               TEXT PRIMARY KEY,
  $columnTelemetryParticipantCode  TEXT NOT NULL,
  $columnTelemetryExperiment       TEXT,
  $columnTelemetryNotes            TEXT,
  $columnTelemetryStatus           TEXT NOT NULL,
  $columnTelemetryStartedAt        TEXT NOT NULL,
  $columnTelemetryEndedAt          TEXT,
  $columnTelemetryLocalPath        TEXT NOT NULL,
  $columnTelemetrySampleCount      INTEGER NOT NULL DEFAULT 0,
  $columnTelemetryFrameCount       INTEGER NOT NULL DEFAULT 0,
  $columnTelemetryMissingSamples   INTEGER NOT NULL DEFAULT 0,
  $columnTelemetryMissingFrames    INTEGER NOT NULL DEFAULT 0,
  $columnTelemetrySizeBytes        INTEGER NOT NULL DEFAULT 0,
  $columnTelemetryUploadAttempts   INTEGER NOT NULL DEFAULT 0,
  $columnTelemetryLastError        TEXT,
  $columnTelemetryRemotePrefix     TEXT,
  $columnTelemetryDeviceName       TEXT,
  $columnTelemetryDeviceId         TEXT,
  $columnTelemetryAppVersion       TEXT,
  $columnTelemetryCreatedAt        TEXT NOT NULL
)
''';

  // Provenance.
  static const String columnDeviceName = 'device_name';
  static const String columnFirmwareVersion = 'firmware_version';
  static const String columnAppVersion = 'app_version';

  /// Schema v1 DDL. Kept for migration tests and for documentation of the
  /// shape that existed before [columnQualityFlags] was added.
  static const String createSessionsV1 = '''
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
  static const String createSessionsV2 = '''
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
  static const String createSessionsV4 = '''
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

  /// Schema v6 DDL: v4 plus the compression/pause split.
  static const String createSessionsV6 = '''
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
  $columnPacketsLost        INTEGER,
  $columnCompressionSeconds INTEGER,
  $columnPauseSeconds       INTEGER
)
''';

  /// Additive v1 → v2 migration. Existing rows keep all their data and get a
  /// null quality_flags value.
  static const String migrateSessionsV1ToV2 =
      'ALTER TABLE $tableSessions ADD COLUMN $columnQualityFlags INTEGER';

  /// Additive v3 → v4 migration. Existing rows get a null packets_lost value.
  static const String migrateSessionsV3ToV4 =
      'ALTER TABLE $tableSessions ADD COLUMN $columnPacketsLost INTEGER';

  /// Additive v5 → v6 migration. Existing rows get null compression/pause
  /// values and the summary screen derives them from CCF when they are absent.
  static const List<String> migrateSessionsV5ToV6 = <String>[
    'ALTER TABLE $tableSessions ADD COLUMN $columnCompressionSeconds INTEGER',
    'ALTER TABLE $tableSessions ADD COLUMN $columnPauseSeconds INTEGER',
  ];

  // -----------------------------------------------------------------------
  // Session status values (stored verbatim in [columnStatus])
  // -----------------------------------------------------------------------

  /// A session that ended with a FINAL_SUMMARY packet.
  static const String statusCompleted = 'completed';

  /// A session that ended early (e.g. the BLE link dropped).
  static const String statusInterrupted = 'interrupted';

  // -----------------------------------------------------------------------
  // Raw telemetry status values
  // -----------------------------------------------------------------------

  /// Recording is open; an app kill leaves this value behind.
  static const String telemetryRecording = 'recording';

  /// Files are finalised and waiting for an upload attempt.
  static const String telemetryComplete = 'complete';

  /// Files are finalised but the link dropped/sensor failed mid-session.
  static const String telemetryInterrupted = 'interrupted';

  /// The app was killed before the recording could be finalised. Files stay
  /// local for manual recovery; the queue does not auto-upload them.
  static const String telemetryIncomplete = 'incomplete';

  /// Every file and the metadata row reached Supabase.
  static const String telemetryUploaded = 'uploaded';

  /// The last upload attempt failed; the queue retries on the next launch.
  static const String telemetryFailed = 'failed';

  /// Stop retrying after this many failed attempts; the local files remain.
  static const int telemetryMaxUploadAttempts = 5;

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
