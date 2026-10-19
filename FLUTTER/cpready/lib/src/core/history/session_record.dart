/// One finished practice session as stored in the History database.
///
/// A record is either *completed* — it carries the firmware's FINAL_SUMMARY
/// values — or *interrupted*, in which case every metric is null and only the
/// trainee, timestamps, duration and packet count are known.
///
/// Column names and status values come from [AppHistory]; no SQL lives here.

import '../../config/config.dart';
import '../metrics/cpr_metrics.dart';

/// How a practice session ended.
enum SessionStatus {
  /// Ended with a FINAL_SUMMARY packet from the firmware.
  completed,

  /// Ended early (e.g. the BLE link dropped) with no summary.
  interrupted,
}

/// A single persisted practice session.
class SessionRecord {
  /// Row id. Null until the record has been inserted.
  final int? id;

  /// Free-text trainee name captured on the Setup screen.
  final String traineeName;

  /// How the session ended.
  final SessionStatus status;

  /// Wall-clock start, stored as device local time.
  final DateTime startedAt;

  /// Wall-clock end, stored as device local time.
  final DateTime endedAt;

  /// Firmware-reported duration when a summary exists, otherwise the
  /// app-measured wall-clock duration.
  final int durationSeconds;

  /// Number of telemetry packets recorded during the session.
  final int packetCount;

  // FINAL_SUMMARY values. All null for an interrupted session.
  final int? rateCpm;
  final int? depthTenthsMm;
  final int? recoilPercent;
  final int? ccfPercent;
  final int? totalCompressions;

  // Provenance. Best-effort: any of these may be null.
  final String? deviceName;
  final String? firmwareVersion;
  final String? appVersion;

  const SessionRecord({
    this.id,
    required this.traineeName,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.packetCount,
    this.rateCpm,
    this.depthTenthsMm,
    this.recoilPercent,
    this.ccfPercent,
    this.totalCompressions,
    this.deviceName,
    this.firmwareVersion,
    this.appVersion,
  });

  /// True when the session ended with a FINAL_SUMMARY packet.
  bool get isCompleted => status == SessionStatus.completed;

  /// Compression depth in centimetres, derived from the stored tenths of a
  /// millimetre. Null for an interrupted session.
  double? get depthCm =>
      depthTenthsMm == null ? null : depthTenthsMm!.toDouble() / 100.0;

  /// Compression depth in millimetres, derived from the stored tenths of a
  /// millimetre. Null for an interrupted session.
  double? get depthMm =>
      depthTenthsMm == null ? null : depthTenthsMm!.toDouble() / 10.0;

  /// The stored summary rebuilt as the packet shape the UI consumes.
  ///
  /// Returns null for an interrupted session, which has no summary — the
  /// Session Summary screen then renders no metrics card.
  CprMetrics? get summary {
    if (!isCompleted || rateCpm == null) return null;
    final depth = depthCm ?? 0.0;
    return CprMetrics(
      packetType: 4,
      recoilComplete: false,
      recoilPercentage: recoilPercent ?? 0,
      rateCpm: rateCpm!,
      depthCm: depth,
      depthMm: depth * 10.0,
      ccfPercent: ccfPercent ?? 0,
      audioPromptCode: 0,
      totalCompressions: totalCompressions ?? 0,
      elapsedSeconds: durationSeconds,
    );
  }

  /// The status value stored in the database.
  String get statusValue => status == SessionStatus.completed
      ? AppHistory.statusCompleted
      : AppHistory.statusInterrupted;

  /// This record as a database row (without [id], which SQLite assigns).
  Map<String, Object?> toMap() => <String, Object?>{
        AppHistory.columnTraineeName: traineeName,
        AppHistory.columnStatus: statusValue,
        AppHistory.columnStartedAt: startedAt.toIso8601String(),
        AppHistory.columnEndedAt: endedAt.toIso8601String(),
        AppHistory.columnDurationSeconds: durationSeconds,
        AppHistory.columnPacketCount: packetCount,
        AppHistory.columnRateCpm: rateCpm,
        AppHistory.columnDepthTenthsMm: depthTenthsMm,
        AppHistory.columnRecoilPercent: recoilPercent,
        AppHistory.columnCcfPercent: ccfPercent,
        AppHistory.columnTotalCompressions: totalCompressions,
        AppHistory.columnDeviceName: deviceName,
        AppHistory.columnFirmwareVersion: firmwareVersion,
        AppHistory.columnAppVersion: appVersion,
      };

  /// Rebuilds a record from a database row.
  factory SessionRecord.fromMap(Map<String, Object?> map) {
    return SessionRecord(
      id: map[AppHistory.columnId] as int?,
      traineeName: map[AppHistory.columnTraineeName] as String? ?? '',
      status: map[AppHistory.columnStatus] == AppHistory.statusInterrupted
          ? SessionStatus.interrupted
          : SessionStatus.completed,
      startedAt:
          DateTime.parse(map[AppHistory.columnStartedAt] as String).toLocal(),
      endedAt: DateTime.parse(map[AppHistory.columnEndedAt] as String).toLocal(),
      durationSeconds: map[AppHistory.columnDurationSeconds] as int? ?? 0,
      packetCount: map[AppHistory.columnPacketCount] as int? ?? 0,
      rateCpm: map[AppHistory.columnRateCpm] as int?,
      depthTenthsMm: map[AppHistory.columnDepthTenthsMm] as int?,
      recoilPercent: map[AppHistory.columnRecoilPercent] as int?,
      ccfPercent: map[AppHistory.columnCcfPercent] as int?,
      totalCompressions: map[AppHistory.columnTotalCompressions] as int?,
      deviceName: map[AppHistory.columnDeviceName] as String?,
      firmwareVersion: map[AppHistory.columnFirmwareVersion] as String?,
      appVersion: map[AppHistory.columnAppVersion] as String?,
    );
  }
}
