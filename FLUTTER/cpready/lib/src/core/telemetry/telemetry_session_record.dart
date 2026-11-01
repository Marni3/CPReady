import '../../config/config.dart';
import 'telemetry_recorder.dart';

/// One row in the raw-telemetry upload queue.
class TelemetrySessionRecord {
  final String id;
  final String participantCode;
  final String experiment;
  final String notes;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String localPath;
  final int sampleCount;
  final int frameCount;
  final int missingSamples;
  final int missingFrames;
  final int sizeBytes;
  final int uploadAttempts;
  final String? lastError;
  final String? remotePrefix;
  final String? deviceName;
  final String? deviceId;
  final String? appVersion;
  final DateTime createdAt;

  const TelemetrySessionRecord({
    required this.id,
    required this.participantCode,
    required this.experiment,
    required this.notes,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.localPath,
    required this.sampleCount,
    required this.frameCount,
    required this.missingSamples,
    required this.missingFrames,
    required this.sizeBytes,
    required this.uploadAttempts,
    required this.lastError,
    required this.remotePrefix,
    required this.deviceName,
    required this.deviceId,
    required this.appVersion,
    required this.createdAt,
  });

  bool get isUploaded => status == AppHistory.telemetryUploaded;

  bool get isPendingUpload =>
      (status == AppHistory.telemetryComplete ||
          status == AppHistory.telemetryInterrupted ||
          status == AppHistory.telemetryFailed) &&
      uploadAttempts < AppHistory.telemetryMaxUploadAttempts;

  Map<String, Object?> toMap() => <String, Object?>{
        AppHistory.columnTelemetryId: id,
        AppHistory.columnTelemetryParticipantCode: participantCode,
        AppHistory.columnTelemetryExperiment: experiment,
        AppHistory.columnTelemetryNotes: notes,
        AppHistory.columnTelemetryStatus: status,
        AppHistory.columnTelemetryStartedAt: startedAt.toIso8601String(),
        AppHistory.columnTelemetryEndedAt: endedAt?.toIso8601String(),
        AppHistory.columnTelemetryLocalPath: localPath,
        AppHistory.columnTelemetrySampleCount: sampleCount,
        AppHistory.columnTelemetryFrameCount: frameCount,
        AppHistory.columnTelemetryMissingSamples: missingSamples,
        AppHistory.columnTelemetryMissingFrames: missingFrames,
        AppHistory.columnTelemetrySizeBytes: sizeBytes,
        AppHistory.columnTelemetryUploadAttempts: uploadAttempts,
        AppHistory.columnTelemetryLastError: lastError,
        AppHistory.columnTelemetryRemotePrefix: remotePrefix,
        AppHistory.columnTelemetryDeviceName: deviceName,
        AppHistory.columnTelemetryDeviceId: deviceId,
        AppHistory.columnTelemetryAppVersion: appVersion,
        AppHistory.columnTelemetryCreatedAt: createdAt.toIso8601String(),
      };

  factory TelemetrySessionRecord.fromMap(Map<String, Object?> map) {
    return TelemetrySessionRecord(
      id: map[AppHistory.columnTelemetryId] as String? ?? '',
      participantCode:
          map[AppHistory.columnTelemetryParticipantCode] as String? ?? '',
      experiment: map[AppHistory.columnTelemetryExperiment] as String? ?? '',
      notes: map[AppHistory.columnTelemetryNotes] as String? ?? '',
      status: map[AppHistory.columnTelemetryStatus] as String? ?? '',
      startedAt: DateTime.parse(
        map[AppHistory.columnTelemetryStartedAt] as String,
      ).toLocal(),
      endedAt: _date(map[AppHistory.columnTelemetryEndedAt]),
      localPath: map[AppHistory.columnTelemetryLocalPath] as String? ?? '',
      sampleCount: map[AppHistory.columnTelemetrySampleCount] as int? ?? 0,
      frameCount: map[AppHistory.columnTelemetryFrameCount] as int? ?? 0,
      missingSamples:
          map[AppHistory.columnTelemetryMissingSamples] as int? ?? 0,
      missingFrames: map[AppHistory.columnTelemetryMissingFrames] as int? ?? 0,
      sizeBytes: map[AppHistory.columnTelemetrySizeBytes] as int? ?? 0,
      uploadAttempts:
          map[AppHistory.columnTelemetryUploadAttempts] as int? ?? 0,
      lastError: map[AppHistory.columnTelemetryLastError] as String?,
      remotePrefix: map[AppHistory.columnTelemetryRemotePrefix] as String?,
      deviceName: map[AppHistory.columnTelemetryDeviceName] as String?,
      deviceId: map[AppHistory.columnTelemetryDeviceId] as String?,
      appVersion: map[AppHistory.columnTelemetryAppVersion] as String?,
      createdAt: DateTime.parse(
        map[AppHistory.columnTelemetryCreatedAt] as String,
      ).toLocal(),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  static TelemetrySessionRecord fromRecording(
    TelemetryRecording recording, {
    required String status,
  }) {
    return TelemetrySessionRecord(
      id: recording.sessionId,
      participantCode: recording.participantCode,
      experiment: recording.experiment,
      notes: recording.notes,
      status: status,
      startedAt: recording.startedAt,
      endedAt: recording.endedAt,
      localPath: recording.directoryPath,
      sampleCount: recording.sampleCount,
      frameCount: recording.frameCount,
      missingSamples: recording.missingSamples,
      missingFrames: recording.missingFrames,
      sizeBytes: recording.sizeBytes,
      uploadAttempts: 0,
      lastError: null,
      remotePrefix: null,
      deviceName: recording.deviceName,
      deviceId: recording.deviceId,
      appVersion: recording.appVersion,
      createdAt: DateTime.now(),
    );
  }
}
