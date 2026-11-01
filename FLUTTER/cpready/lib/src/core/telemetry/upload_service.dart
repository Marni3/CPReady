import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../config/config.dart';
import '../history/session_repository.dart';
import 'telemetry_session_record.dart';

enum TelemetryUploadOutcome { uploaded, notConfigured, failed }

class TelemetryUploadResult {
  final TelemetryUploadOutcome outcome;
  final String message;
  final String? remotePrefix;

  const TelemetryUploadResult(
    this.outcome, {
    this.message = '',
    this.remotePrefix,
  });

  bool get isUploaded => outcome == TelemetryUploadOutcome.uploaded;
  bool get isNotConfigured => outcome == TelemetryUploadOutcome.notConfigured;
}

/// Uploads a finished raw recording to Supabase Storage and inserts one row in
/// `telemetry_sessions`.
///
/// Uses the publishable/anon key from `--dart-define`; never a service-role
/// key. Requests are idempotent by session UUID: an existing object (409) and
/// an existing metadata row (409) both count as success.
class TelemetryUploadService {
  const TelemetryUploadService();

  static bool _retrying = false;

  /// Uploads one record and updates its queue row.
  Future<TelemetryUploadResult> uploadAndRecord(
    TelemetrySessionRecord record,
    SessionRepository repository,
  ) async {
    final TelemetryUploadResult result = await upload(record);
    switch (result.outcome) {
      case TelemetryUploadOutcome.uploaded:
        await repository.updateTelemetryUpload(
          id: record.id,
          status: AppHistory.telemetryUploaded,
          attempts: record.uploadAttempts + 1,
          error: null,
          remotePrefix: result.remotePrefix,
        );
        break;
      case TelemetryUploadOutcome.notConfigured:
        // Leave the row complete so a later build with credentials retries it.
        break;
      case TelemetryUploadOutcome.failed:
        await repository.updateTelemetryUpload(
          id: record.id,
          status: AppHistory.telemetryFailed,
          attempts: record.uploadAttempts + 1,
          error: result.message,
        );
        break;
    }
    return result;
  }

  /// Retries every pending row once. Called on app start and after a session.
  Future<void> retryPending(SessionRepository repository) async {
    if (_retrying) return;
    _retrying = true;
    try {
      await repository.markStaleTelemetryRecordings();
      if (!AppTelemetry.isUploadConfigured) return;
      final List<TelemetrySessionRecord> pending =
          await repository.listPendingTelemetry();
      for (final TelemetrySessionRecord record in pending) {
        try {
          final TelemetryUploadResult result =
              await uploadAndRecord(record, repository);
          if (result.isNotConfigured) break;
        } catch (error) {
          debugPrint('Telemetry upload for ${record.id} failed: $error');
        }
      }
    } catch (error) {
      debugPrint('Telemetry upload retry failed: $error');
    } finally {
      _retrying = false;
    }
  }

  /// Uploads the four files plus the metadata row. Never throws.
  Future<TelemetryUploadResult> upload(
    TelemetrySessionRecord record,
  ) async {
    if (!AppTelemetry.isUploadConfigured) {
      return const TelemetryUploadResult(
        TelemetryUploadOutcome.notConfigured,
        message: 'Supabase URL/key not supplied at build time',
      );
    }

    final Directory directory = Directory(record.localPath);
    final Map<String, String> files = <String, String>{
      AppTelemetry.rawFileName: 'text/csv',
      AppTelemetry.metricsFileName: 'text/csv',
      AppTelemetry.eventsFileName: 'text/csv',
      AppTelemetry.metadataFileName: 'application/json',
    };
    for (final String name in files.keys) {
      if (!await File('${directory.path}/$name').exists()) {
        return TelemetryUploadResult(
          TelemetryUploadOutcome.failed,
          message: 'Missing local file: $name',
        );
      }
    }

    final String base = AppTelemetry.supabaseUrl.trim().replaceFirst(
          RegExp(r'/+$'),
          '',
        );
    final String key = AppTelemetry.supabasePublishableKey.trim();
    final String prefix = record.id;
    final HttpClient client = HttpClient()
      ..connectionTimeout = AppTelemetry.requestTimeout;

    try {
      for (final MapEntry<String, String> file in files.entries) {
        final List<int> bytes =
            await File('${directory.path}/${file.key}').readAsBytes();
        final Uri uri = Uri.parse(
          '$base/storage/v1/object/${AppTelemetry.bucket}/$prefix/${file.key}',
        );
        final _HttpResult result = await _post(
          client,
          uri,
          bytes,
          key: key,
          contentType: file.value,
          extraHeaders: <String, String>{'x-upsert': 'false'},
        );
        if (!result.ok && result.status != 409) {
          return TelemetryUploadResult(
            TelemetryUploadOutcome.failed,
            message:
                'Storage ${file.key}: HTTP ${result.status} ${result.body}',
          );
        }
      }

      final Map<String, Object?> row = <String, Object?>{
        'id': record.id,
        'participant_code': record.participantCode,
        'experiment': record.experiment,
        'notes': record.notes,
        'status': AppHistory.telemetryUploaded,
        'started_at': record.startedAt.toUtc().toIso8601String(),
        'ended_at': record.endedAt?.toUtc().toIso8601String(),
        'sample_count': record.sampleCount,
        'frame_count': record.frameCount,
        'missing_samples': record.missingSamples,
        'missing_frames': record.missingFrames,
        'size_bytes': record.sizeBytes,
        'device_name': record.deviceName,
        'device_id': record.deviceId,
        'app_version': record.appVersion,
        'storage_prefix': prefix,
        'schema_version': AppTelemetry.schemaVersion,
      };
      final _HttpResult rowResult = await _post(
        client,
        Uri.parse('$base/rest/v1/${AppTelemetry.table}'),
        utf8.encode(jsonEncode(row)),
        key: key,
        contentType: 'application/json',
        extraHeaders: <String, String>{'Prefer': 'return=minimal'},
      );
      if (!rowResult.ok && rowResult.status != 409) {
        return TelemetryUploadResult(
          TelemetryUploadOutcome.failed,
          message: 'Metadata row: HTTP ${rowResult.status} ${rowResult.body}',
        );
      }

      return TelemetryUploadResult(
        TelemetryUploadOutcome.uploaded,
        remotePrefix: prefix,
      );
    } catch (error) {
      return TelemetryUploadResult(
        TelemetryUploadOutcome.failed,
        message: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_HttpResult> _post(
    HttpClient client,
    Uri uri,
    List<int> body, {
    required String key,
    required String contentType,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final HttpClientRequest request =
        await client.postUrl(uri).timeout(AppTelemetry.requestTimeout);
    request.headers.set('apikey', key);
    request.headers.set('Authorization', 'Bearer $key');
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    extraHeaders.forEach(request.headers.set);
    request.contentLength = body.length;
    request.add(body);
    final HttpClientResponse response =
        await request.close().timeout(AppTelemetry.requestTimeout);
    final String responseBody = await response
        .transform(utf8.decoder)
        .join()
        .timeout(AppTelemetry.requestTimeout);
    final bool ok = response.statusCode >= 200 && response.statusCode < 300;
    return _HttpResult(
      response.statusCode,
      ok,
      responseBody.length > 300 ? responseBody.substring(0, 300) : responseBody,
    );
  }
}

class _HttpResult {
  final int status;
  final bool ok;
  final String body;

  const _HttpResult(this.status, this.ok, this.body);
}
