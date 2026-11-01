import 'dart:math';

/// Metadata written to `session.json` and used to label an uploaded dataset.
///
/// Deliberately carries a participant code, never the trainee name. The
/// practice-history table keeps the name locally; the uploaded dataset does
/// not.
class SessionMetadata {
  final String sessionId;
  final String participantCode;
  final String experiment;
  final String notes;
  final String deviceName;
  final String deviceId;
  final String appVersion;
  final DateTime startedAt;

  const SessionMetadata({
    required this.sessionId,
    required this.participantCode,
    required this.experiment,
    required this.notes,
    required this.deviceName,
    required this.deviceId,
    required this.appVersion,
    required this.startedAt,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'schema_version': 1,
        'session_id': sessionId,
        'participant_code': participantCode,
        'experiment': experiment,
        'notes': notes,
        'device_name': deviceName,
        'device_id': deviceId,
        'app_version': appVersion,
        'started_at': startedAt.toUtc().toIso8601String(),
      };
}

/// RFC 4122 version-4 UUID without adding a package.
String newSessionId() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String hex =
      bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
