import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../config/config.dart';
import '../metrics/cpr_metrics.dart';
import 'raw_frame.dart';
import 'session_metadata.dart';

/// Finished (or interrupted) local recording summary.
class TelemetryRecording {
  final String sessionId;
  final String directoryPath;
  final String status;
  final DateTime startedAt;
  final DateTime endedAt;
  final String participantCode;
  final String experiment;
  final String notes;
  final String deviceName;
  final String deviceId;
  final String appVersion;
  final int sampleCount;
  final int frameCount;
  final int missingSamples;
  final int missingFrames;
  final int firmwareDroppedFrames;
  final int sizeBytes;

  const TelemetryRecording({
    required this.sessionId,
    required this.directoryPath,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.participantCode,
    required this.experiment,
    required this.notes,
    required this.deviceName,
    required this.deviceId,
    required this.appVersion,
    required this.sampleCount,
    required this.frameCount,
    required this.missingSamples,
    required this.missingFrames,
    required this.firmwareDroppedFrames,
    required this.sizeBytes,
  });

  bool get interrupted => status == 'interrupted';

  String get rawPath => '$directoryPath/${AppTelemetry.rawFileName}';
  String get metricsPath => '$directoryPath/${AppTelemetry.metricsFileName}';
  String get eventsPath => '$directoryPath/${AppTelemetry.eventsFileName}';
  String get metadataPath => '$directoryPath/${AppTelemetry.metadataFileName}';

  List<String> get filePaths => <String>[
        rawPath,
        metricsPath,
        eventsPath,
        metadataPath,
      ];
}

/// Append-only writer for one raw telemetry session.
///
/// Sinks are buffered during active 100 Hz streaming and flushed once at
/// [start] and once at [stop] so `IOSink.writeln()` never races an in-flight
/// `IOSink.flush()` StreamSink binding. `session.json` is written at start
/// (status `recording`) and rewritten atomically at stop.
class TelemetryRecorder {
  TelemetryRecorder({Directory? rootDirectory}) : _rootOverride = rootDirectory;

  final Directory? _rootOverride;

  Directory? _directory;
  SessionMetadata? _metadata;
  DateTime? _startedAt;

  IOSink? _raw;
  IOSink? _metrics;
  IOSink? _events;

  bool _started = false;
  bool _closed = false;
  bool _flushing = false;

  int _framesReceived = 0;
  int _samplesReceived = 0;
  int? _firstSampleIndex;
  int? _lastSampleIndex;
  int? _lastFrameSequence;
  int _missingSamples = 0;
  int _missingFrames = 0;
  int _firmwareDroppedFrames = 0;
  int _lastLoggedStrokeCount = 0;
  Map<String, Object?>? _deviceConfigSnapshot;
  Map<String, Object?>? _finalSummarySnapshot;

  bool get isRecording => _started && !_closed;
  String? get sessionId => _metadata?.sessionId;
  String? get directoryPath => _directory?.path;

  Future<TelemetryRecording> start(SessionMetadata metadata) async {
    if (_started) throw StateError('Telemetry recording already started');
    _metadata = metadata;
    _startedAt = metadata.startedAt;
    _framesReceived = 0;
    _samplesReceived = 0;
    _firstSampleIndex = null;
    _lastSampleIndex = null;
    _lastFrameSequence = null;
    _missingSamples = 0;
    _missingFrames = 0;
    _firmwareDroppedFrames = 0;
    _lastLoggedStrokeCount = 0;
    _deviceConfigSnapshot = null;
    _finalSummarySnapshot = null;

    final Directory root = _rootOverride ?? await _defaultRoot();
    final Directory directory = Directory('${root.path}/${metadata.sessionId}');
    await directory.create(recursive: true);
    _directory = directory;

    _raw = File('${directory.path}/${AppTelemetry.rawFileName}').openWrite();
    _metrics =
        File('${directory.path}/${AppTelemetry.metricsFileName}').openWrite();
    _events =
        File('${directory.path}/${AppTelemetry.eventsFileName}').openWrite();

    _raw!.writeln(AppTelemetry.rawHeader);
    _metrics!.writeln(AppTelemetry.metricsHeader);
    _events!.writeln(AppTelemetry.eventsHeader);
    _started = true;
    _closed = false;
    addEvent('recording_started', metadata.sessionId);
    await _writeJson(status: 'recording', endedAt: null);
    await _flushSinks();
    return _summary(status: 'recording', endedAt: DateTime.now());
  }

  Future<Directory> _defaultRoot() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    return Directory(
      '${documents.path}/${AppTelemetry.recordingsDirectory}',
    );
  }

  void addFrame(RawTelemetryFrame frame, {DateTime? receivedAt}) {
    if (!isRecording || _raw == null) return;
    _framesReceived++;

    final int? previousFrame = _lastFrameSequence;
    if (previousFrame != null) {
      final int gap = (frame.frameSequence - previousFrame - 1) & 0xFFFF;
      if (gap > 0 && gap <= AppBleConfig.maxPlausibleSequenceGap) {
        _missingFrames += gap;
      }
    }
    _lastFrameSequence = frame.frameSequence;
    if (frame.droppedFrames > _firmwareDroppedFrames) {
      _firmwareDroppedFrames = frame.droppedFrames;
    }

    for (final RawTelemetrySample sample in frame.samples) {
      final int? previousSample = _lastSampleIndex;
      if (previousSample != null) {
        final int gap = sample.sampleIndex - previousSample - 1;
        if (gap > 0 && gap <= 10000) _missingSamples += gap;
      }
      _firstSampleIndex ??= sample.sampleIndex;
      _lastSampleIndex = sample.sampleIndex;
      _samplesReceived++;
      _raw!.writeln(
        '${sample.timeUs},${sample.sampleIndex},${frame.frameSequence},'
        '${frame.strokeCount},${frame.deviceState},${frame.flags},'
        '${sample.chestXMg},${sample.chestYMg},${sample.chestZMg},'
        '${sample.baseXMg},${sample.baseYMg},${sample.baseZMg},'
        '${frame.unclampedDepthMm}',
      );
    }
  }

  void setDeviceConfig(Map<String, Object?> config) {
    _deviceConfigSnapshot = config;
    addEvent('device_config', jsonEncode(config));
  }

  void addMetrics(CprMetrics metrics, {DateTime? receivedAt}) {
    if (!isRecording || _metrics == null) return;
    final DateTime at = receivedAt ?? DateTime.now();
    final int recoilStatus = metrics.packetType == AppBleConfig.packetFinalSummary
        ? metrics.recoilPercentage
        : (metrics.recoilComplete ? 1 : 0);
    _metrics!.writeln(
      '${at.toUtc().toIso8601String()},${metrics.packetType},'
      '$recoilStatus,${metrics.rateCpm},${(metrics.depthCm * 100).round()},'
      '${metrics.ccfPercent},${metrics.audioPromptCode},'
      '${metrics.totalCompressions},${metrics.elapsedSeconds},'
      '${metrics.qualityFlags},${metrics.sequence ?? ''}',
    );

    if (metrics.packetType == AppBleConfig.packetRealtime &&
        metrics.totalCompressions > _lastLoggedStrokeCount) {
      _lastLoggedStrokeCount = metrics.totalCompressions;
      addEvent('stroke', '${metrics.totalCompressions}');
    } else if (metrics.packetType == AppBleConfig.packetFinalSummary) {
      _finalSummarySnapshot = <String, Object?>{
        'rate_cpm': metrics.rateCpm,
        'depth_tenths_mm': (metrics.depthCm * 100).round(),
        'recoil_percent': metrics.recoilPercentage,
        'ccf_percent': metrics.ccfPercent,
        'total_compressions': metrics.totalCompressions,
        'elapsed_sec': metrics.elapsedSeconds,
        'quality_flags': metrics.qualityFlags,
      };
      addEvent('final_summary', jsonEncode(_finalSummarySnapshot));
    } else if (metrics.packetType == AppBleConfig.packetError) {
      addEvent('device_error', '${metrics.errorCode}');
    }
  }

  void addEvent(String event, [String detail = '']) {
    if (_events == null || _closed) return;
    _events!.writeln(
      '${DateTime.now().toUtc().toIso8601String()},'
      '${_csv(event)},${_csv(detail)}',
    );
  }

  Future<void> _flushSinks() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _raw?.flush();
      await _metrics?.flush();
      await _events?.flush();
    } catch (_) {
      // A full disk must not take down the live session; stop() will report
      // the final summary and the caller can surface the failure.
    } finally {
      _flushing = false;
    }
  }

  /// Finalises the recording. [interrupted] marks a link drop, sensor fault or
  /// app-side abort while still preserving every byte already written.
  Future<TelemetryRecording> stop({bool interrupted = false}) async {
    if (!_started || _closed) {
      throw StateError('Telemetry recording is not active');
    }
    addEvent(
      interrupted ? 'interrupted' : 'recording_stopped',
      'samples=$_samplesReceived,frames=$_framesReceived',
    );
    _closed = true;
    _started = false;
    await _flushSinks();
    await _raw?.close();
    await _metrics?.close();
    await _events?.close();
    _raw = null;
    _metrics = null;
    _events = null;

    final DateTime endedAt = DateTime.now();
    final String status = interrupted ? 'interrupted' : 'complete';
    await _writeJson(status: status, endedAt: endedAt);
    return _summary(status: status, endedAt: endedAt);
  }

  /// Closes without finalising; optionally removes the partial folder.
  Future<void> abort({bool delete = false}) async {
    if (_closed) return;
    _closed = true;
    _started = false;
    await _raw?.close();
    await _metrics?.close();
    await _events?.close();
    _raw = null;
    _metrics = null;
    _events = null;
    if (delete) {
      final Directory? directory = _directory;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<void> _writeJson({
    required String status,
    required DateTime? endedAt,
  }) async {
    final Directory? directory = _directory;
    final SessionMetadata? metadata = _metadata;
    if (directory == null || metadata == null) return;

    final Map<String, Object?> json = <String, Object?>{
      ...metadata.toJson(),
      'schema_version': AppTelemetry.schemaVersion,
      'status': status,
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'sample_count': _samplesReceived,
      'frame_count': _framesReceived,
      'missing_samples': _missingSamples,
      'missing_frames': _missingFrames,
      'firmware_dropped_frames': _firmwareDroppedFrames,
      'first_sample_index': _firstSampleIndex,
      'last_sample_index': _lastSampleIndex,
      if (_deviceConfigSnapshot != null) 'device_config': _deviceConfigSnapshot,
      if (_finalSummarySnapshot != null) 'final_summary': _finalSummarySnapshot,
      'files': <String>[
        AppTelemetry.rawFileName,
        AppTelemetry.metricsFileName,
        AppTelemetry.eventsFileName,
      ],
    };
    final File target =
        File('${directory.path}/${AppTelemetry.metadataFileName}');
    final File temp = File('${target.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }

  TelemetryRecording _summary({
    required String status,
    required DateTime endedAt,
  }) {
    final SessionMetadata metadata = _metadata!;
    int size = 0;
    final Directory? directory = _directory;
    if (directory != null) {
      for (final String name in <String>[
        AppTelemetry.rawFileName,
        AppTelemetry.metricsFileName,
        AppTelemetry.eventsFileName,
        AppTelemetry.metadataFileName,
      ]) {
        final File file = File('${directory.path}/$name');
        if (file.existsSync()) size += file.lengthSync();
      }
    }
    return TelemetryRecording(
      sessionId: metadata.sessionId,
      directoryPath: directory?.path ?? '',
      status: status,
      startedAt: _startedAt ?? metadata.startedAt,
      endedAt: endedAt,
      participantCode: metadata.participantCode,
      experiment: metadata.experiment,
      notes: metadata.notes,
      deviceName: metadata.deviceName,
      deviceId: metadata.deviceId,
      appVersion: metadata.appVersion,
      sampleCount: _samplesReceived,
      frameCount: _framesReceived,
      missingSamples: _missingSamples,
      missingFrames: _missingFrames,
      firmwareDroppedFrames: _firmwareDroppedFrames,
      sizeBytes: size,
    );
  }

  static String _csv(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}
