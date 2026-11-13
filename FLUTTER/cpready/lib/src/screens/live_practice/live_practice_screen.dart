/// Active CPR session: live metrics and the press-and-hold End Session control.
///
/// Full-screen (no top header, no bottom nav) and with no back button. On
/// entry the screen sends SET_TIME and START, then waits: the session (and its
/// clock) begins on the trainee's first compression, and a chosen duration is
/// enforced from that moment. A session ends when the hold completes and STOP
/// is sent, when the chosen duration expires, when the firmware sends its own
/// FINAL_SUMMARY (its safety stop), or when the BLE link drops. A drop
/// abandons the session — nothing is saved and the app returns to Home with a
/// notice.
///
/// Every visual value comes from `lib/src/config/`; this file only composes
/// widgets.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/audio/live_coaching_controller.dart';
import '../../core/audio/metronome.dart';
import '../../core/audio/voice_coach.dart';
import '../../core/audio/voice_cue_gate.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/feedback/metric_feedback.dart';
import '../../core/history/history_revision.dart';
import '../../core/history/session_record.dart';
import '../../core/history/session_repository.dart';
import '../../core/metrics/compression_time.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../core/metrics/session_refinement_engine.dart';
import '../../core/practice_session_args.dart';
import '../../core/settings/metronome_preferences.dart';
import '../../core/telemetry/raw_frame.dart';
import '../../core/telemetry/session_metadata.dart';
import '../../core/telemetry/telemetry_recorder.dart';
import '../../core/telemetry/telemetry_session_record.dart';
import '../../core/telemetry/upload_service.dart';
import '../../widgets/widgets.dart';
import '../session_complete/session_complete_screen.dart';

/// Live practice screen.
class LivePracticeScreen extends StatefulWidget {
  /// Trainee name captured on the setup screen; filed with the session.
  final String traineeName;

  /// Session duration in seconds (0 = unlimited/manual stop).
  final int practiceDurationSec;

  /// Metronome pace chosen on Practice Setup, in beats per minute.
  final int metronomeTempoBpm;

  /// Clock for the voice-cue gate. Widget tests pass one that follows the
  /// pumped time; the app leaves it null and uses the wall clock.
  @visibleForTesting
  final DateTime Function()? cueClock;

  /// Test hook: replaces the asset metronome so widget tests never touch a
  /// platform audio channel.
  @visibleForTesting
  final Metronome? metronome;

  const LivePracticeScreen({
    super.key,
    required this.traineeName,
    required this.practiceDurationSec,
    this.metronomeTempoBpm = AppMetronome.defaultTempoBpm,
    this.cueClock,
    this.metronome,
  });

  @override
  State<LivePracticeScreen> createState() => _LivePracticeScreenState();
}

class _LivePracticeScreenState extends State<LivePracticeScreen> {
  BleController? _controller;
  SessionRepository? _repository;
  VoiceCoach? _coach;
  bool _initialized = false;

  StreamSubscription<CprMetrics>? _packetSub;
  StreamSubscription<RawTelemetryFrame>? _rawSub;
  TelemetryRecorder? _telemetryRecorder;
  Timer? _tick;
  Timer? _startWatchdog;

  CprMetrics? _latest;
  int? _lastCount;
  DateTime? _lastCompressionAt;
  bool _ending = false;
  bool _finished = false;

  /// Wall-clock moment of the first compression. The session clock and the
  /// saved start time use this, not the moment the screen opened.
  DateTime? _sessionStartAt;

  /// True once a real-time packet has reported at least one compression.
  bool _firstCompressionSeen = false;

  /// True once the first real-time packet has arrived, even if it carries
  /// zero compressions. Used to fade in the metrics display as soon as the
  /// session stream starts, instead of waiting for the first compression.
  bool _firstRealtimePacketSeen = false;

  /// Firmware elapsed time when the first compression was reported. Used to
  /// turn the firmware's own clock (which starts at START) into a duration
  /// measured from the first compression.
  int _firstCompressionElapsedSec = 0;

  /// Consecutive real-time packets that reported an unsteady rhythm.
  int _unsteadyPackets = 0;

  /// Consecutive real-time packets that reported a steady rhythm (for hysteresis).
  int _steadyPackets = 0;

  /// True once the run above lasted long enough to show the warning.
  bool _cadenceWarning = false;

  /// Stabilized live depth (in cm) displayed on the Depth capsule during unsteady rhythm.
  double? _displayDepthCm;

  /// In-memory 100 Hz raw accelerometer samples buffered for post-session refinement.
  final List<RawTelemetrySample> _inMemoryRawSamples = <RawTelemetrySample>[];
  bool _inMemoryRawStreamActive = false;
  double _activeDepthK = 10.85;
  String _activeSensitivity = 'BALANCED';

  /// Voice cues are on by default; the header toggle mutes them per session.
  bool _muted = false;



  /// Metronome on by default; the header toggle silences it and the choice is
  /// remembered for the next session.
  bool _metronomeEnabled = AppMetronome.defaultEnabled;

  final MetronomePreferences _metronomePreferences =
      const MetronomePreferences();

  late final Metronome _metronome = widget.metronome ?? AssetMetronome();

  Timer? _beatTimer;
  Stopwatch? _beatClock;
  int _nextBeatNumber = 0;
  bool _metronomeRunning = false;

  /// App-side dynamic voice coaching engine (suppresses depth cues when unsteady).
  late final LiveCoachingController _coachingController =
      LiveCoachingController(clock: widget.cueClock);

  /// Rolling-median depth stabilizer for unsteady live display.
  final LiveDepthStabilizer _depthStabilizer = LiveDepthStabilizer();

  /// Duplicate and overlap guard for the firmware's cue codes.
  late final VoiceCueGate _cueGate = VoiceCueGate(clock: widget.cueClock);

  /// Cue code carried by the previous real-time packet. Older firmware repeats
  /// a cue in every packet until the next stroke, so only a change of code is a
  /// new cue; otherwise a pause after a cue replays it about once a second.
  int _previousCueCode = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final controller = AppScope.of(context);
    _controller = controller;
    _repository = AppScope.history(context);
    _coach = AppScope.voice(context);
    unawaited(
      _coach!.preload().catchError((Object error) {
        debugPrint('Voice cue preload failed: $error');
      }),
    );
    unawaited(_loadMetronomePreferences());
    unawaited(
      _metronome.preload().catchError((Object error) {
        debugPrint('Metronome preload failed: $error');
      }),
    );

    controller.startRecording();
    controller.addListener(_onControllerChanged);
    _packetSub = controller.packets.listen(_onPacket);
    unawaited(_loadStoredDeviceConfig());
    if (controller.telemetryEnabled) {
      unawaited(_startTelemetry(controller));
    } else if (controller.supportsRawTelemetry) {
      unawaited(_startInMemoryRawStream(controller));
    }

    // SET_TIME has to be accepted before START: the firmware rejects config
    // changes during a running session. START then makes the firmware emit
    // real-time packets; the app's session clock starts on the first one.
    unawaited(_sendStartCommands(controller));

    // Keeps the elapsed timer and the compression-activity window current.
    // The metronome is self-scheduling via _scheduleNextBeat(), so the tick
    // timer only refreshes the UI clock and does not reschedule beats.
    _tick = Timer.periodic(AppDurations.liveTick, (_) {
      if (mounted && !_finished) {
        setState(() {});
      }
    });
  }

  /// Configures the firmware's safety stop and starts the stream.
  ///
  /// The firmware counts its session length from START, before the trainee's
  /// first compression, so the chosen duration gets a grace period on the
  /// device. The app ends the session itself once the chosen time has elapsed
  /// since the first compression; the firmware value is only a backstop for a
  /// lost link or a killed app.
  Future<void> _sendStartCommands(BleController controller) async {
    final int duration = widget.practiceDurationSec;
    final int firmwareDuration = duration == 0
        ? 0
        : math.min(3600, duration + AppDurations.sessionStartGraceSeconds);

    try {
      await controller
          .sendCommand(AppBleConfig.commandSetTime(firmwareDuration));
    } catch (error) {
      // START may still work; the live screen surfaces a dropped link.
      debugPrint('Practice duration set failed: $error');
    }

    try {
      await controller.sendCommand(AppBleConfig.commandStart);
    } catch (error) {
      debugPrint('Session start failed: $error');
      if (!mounted) return;
      // Without a link there is nothing to retry; the connection listener (or
      // the flow guard) takes over. Only a rejected START on a live link needs
      // the failure dialog.
      if (!controller.isConnected) return;
      _onStartTimeout();
      return;
    }

    if (!mounted || _finished) return;

    // START is accepted only after calibration. If the device rejected it or
    // the first notification never arrives, surface the failure instead of
    // showing an apparently live session full of zeros forever.
    _startWatchdog ??= Timer(AppDurations.startWatchdog, _onStartTimeout);
  }

  Future<void> _startTelemetry(BleController controller) async {
    if (!controller.supportsRawTelemetry) {
      debugPrint('Raw telemetry requested but the characteristic is absent');
      return;
    }

    final SessionMetadata metadata = SessionMetadata(
      sessionId: newSessionId(),
      participantCode: controller.telemetryParticipantCode.isEmpty
          ? 'P001'
          : controller.telemetryParticipantCode,
      experiment: controller.telemetryExperiment.isEmpty
          ? 'practice'
          : controller.telemetryExperiment,
      notes: controller.telemetryNotes,
      deviceName: controller.deviceName ?? '',
      deviceId: controller.ble.device?.remoteId.toString() ?? '',
      appVersion: AppIdentity.version,
      startedAt: controller.sessionStartedAt ?? DateTime.now(),
    );

    final TelemetryRecorder recorder = TelemetryRecorder();
    TelemetryRecording recording;
    try {
      recording = await recorder.start(metadata);
    } catch (error) {
      debugPrint('Raw telemetry start failed: $error');
      await recorder.abort(delete: true);
      return;
    }

    if (!mounted || _finished) {
      await recorder.abort(delete: true);
      return;
    }

    _telemetryRecorder = recorder;
    _rawSub = controller.rawFrames.listen(_onRawFrame);

    try {
      final stored = await _repository?.loadDeviceSettings();
      if (stored != null) {
        recorder.setDeviceConfig(<String, Object?>{
          'profile': stored.profile.name,
          'depth_k': stored.depthK,
          'practice_duration_sec': stored.practiceDurationSec,
        });
      }
    } catch (error) {
      debugPrint('Telemetry device config snapshot skipped: $error');
    }
    try {
      await _repository?.saveTelemetrySession(
        TelemetrySessionRecord.fromRecording(
          recording,
          status: AppHistory.telemetryRecording,
        ),
      );
    } catch (error) {
      debugPrint('Telemetry queue insert failed: $error');
    }

    if (_finished) {
      await _abortTelemetry(delete: true);
      return;
    }

    try {
      await controller.sendCommand(AppTelemetry.commandOn);
    } catch (error) {
      debugPrint('TELEM:1 failed; raw recording aborted: $error');
      await _abortTelemetry(delete: true);
      return;
    }

    // The start watchdog can fire while the command is in flight. If so, turn
    // the firmware stream off again and discard anything that was recorded.
    if (_finished) {
      await _sendTelemetryOff(controller);
      await _abortTelemetry(delete: true);
    }
  }

  Future<void> _loadStoredDeviceConfig() async {
    try {
      final stored = await _repository?.loadDeviceSettings();
      if (stored != null && mounted) {
        _activeDepthK = stored.depthK ?? 10.85;
        _activeSensitivity = stored.profile.name.toUpperCase();
      }
    } catch (error) {
      debugPrint('Device settings load skipped: $error');
    }
  }

  Future<void> _startInMemoryRawStream(BleController controller) async {
    if (!controller.supportsRawTelemetry || _finished) return;
    _rawSub = controller.rawFrames.listen(_onRawFrame);
    try {
      await controller.sendCommand(AppTelemetry.commandOn);
      _inMemoryRawStreamActive = true;
    } catch (error) {
      debugPrint('In-memory TELEM:1 failed: $error');
      await _rawSub?.cancel();
      _rawSub = null;
      return;
    }
    if (_finished) {
      _inMemoryRawStreamActive = false;
      await _sendTelemetryOff(controller);
      await _rawSub?.cancel();
      _rawSub = null;
    }
  }

  void _onRawFrame(RawTelemetryFrame frame) {
    if (!mounted) return;
    if (_inMemoryRawSamples.length < 360000) {
      _inMemoryRawSamples.addAll(frame.samples);
    }
    _telemetryRecorder?.addFrame(frame);
  }

  Future<void> _abortTelemetry({bool delete = false}) async {
    await _rawSub?.cancel();
    _rawSub = null;
    final TelemetryRecorder? recorder = _telemetryRecorder;
    _telemetryRecorder = null;
    if (recorder == null) return;
    final String? id = recorder.sessionId;
    await recorder.abort(delete: delete);
    if (delete && id != null) {
      try {
        await _repository?.deleteTelemetrySession(id);
      } catch (error) {
        debugPrint('Telemetry queue cleanup failed: $error');
      }
    }
  }

  Future<(TelemetryRecording?, Future<TelemetryUploadResult>?)> _stopTelemetry(
      bool interrupted) async {
    final TelemetryRecorder? recorder = _telemetryRecorder;
    if (recorder == null) return (null, null);
    _telemetryRecorder = null;

    TelemetryRecording recording;
    try {
      recording = await recorder.stop(interrupted: interrupted);
    } catch (error) {
      debugPrint('Raw telemetry finalize failed: $error');
      await recorder.abort();
      return (null, null);
    }

    final String status = interrupted
        ? AppHistory.telemetryInterrupted
        : AppHistory.telemetryComplete;
    final TelemetrySessionRecord row = TelemetrySessionRecord.fromRecording(
      recording,
      status: status,
    );

    final SessionRepository? repository = _repository;
    if (repository != null) {
      try {
        await repository.saveTelemetrySession(row);
      } catch (error) {
        debugPrint('Telemetry queue finalize failed: $error');
      }
    }

    if (!mounted) return (recording, null);
    final Future<TelemetryUploadResult>? upload = repository == null
        ? null
        : AppScope.uploads(context).uploadAndRecord(row, repository);
    return (recording, upload);
  }

  void _onStartTimeout() {
    if (!mounted || _finished || _latest != null) return;
    // Set this before the asynchronous cleanup so an in-flight telemetry start
    // cannot turn the stream on after it has been aborted.
    _finished = true;
    _stopSessionInternals();
    _controller?.stopRecording();
    _controller?.resetSessionData();
    if (_telemetryRecorder != null || _inMemoryRawStreamActive) {
      _inMemoryRawStreamActive = false;
      unawaited(_sendTelemetryOff(_controller));
    }
    unawaited(_abortTelemetry(delete: true));
    unawaited(_showStartFailure());
  }

  Future<void> _sendTelemetryOff(BleController? controller) async {
    try {
      await controller?.sendCommand(AppTelemetry.commandOff);
    } catch (error) {
      debugPrint('TELEM:0 failed: $error');
    }
  }

  Future<void> _showStartFailure() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.liveStartFailedTitle),
        content: const Text(AppStrings.liveStartFailedBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.liveStartFailedAction),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final BleController? controller = _controller;
    if (controller != null && controller.isConnected) {
      // START was rejected or lost while the link is still up. A fresh
      // CALIBRATE is required before the firmware will accept START again.
      context.go(
        AppRoutes.calibration,
        extra: PracticeSessionArgs(
          traineeName: widget.traineeName,
          practiceDurationSec: widget.practiceDurationSec,
          metronomeTempoBpm: widget.metronomeTempoBpm,
        ),
      );
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _stopSessionInternals() {
    _packetSub?.cancel();
    _packetSub = null;
    unawaited(_rawSub?.cancel());
    _rawSub = null;
    _tick?.cancel();
    _tick = null;
    _startWatchdog?.cancel();
    _startWatchdog = null;
    _controller?.removeListener(_onControllerChanged);
    _stopMetronome();
    unawaited(_coach?.stop());
  }

  /// True while compressions are still being counted, so the counter circle
  /// reads as active rather than idle.
  bool get _compressing {
    final DateTime? at = _lastCompressionAt;
    final int count = _latest?.totalCompressions ?? 0;
    if (at == null || count <= 0) return false;
    return DateTime.now().difference(at) <=
        AppDurations.compressionActiveWindow;
  }

  /// Error packets: a sensor fault ends the session; before the first live
  /// packet any error means START was rejected; later ones answer some other
  /// command and leave the running session alone.
  void _onDeviceError(int errorCode) {
    if (_finished || _ending) return;
    if (errorCode == AppBleConfig.errI2cFault) {
      _startWatchdog?.cancel();
      _startWatchdog = null;
      unawaited(_finish(reason: SessionEndReason.sensorFault, summary: null));
      return;
    }
    if (_latest == null) {
      _startWatchdog?.cancel();
      _startWatchdog = null;
      _onStartTimeout();
    }
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;
    _telemetryRecorder?.addMetrics(metrics);
    final int count = metrics.totalCompressions;

    if (metrics.packetType == AppBleConfig.packetError) {
      _onDeviceError(metrics.errorCode);
      return;
    }

    final bool realtime = metrics.packetType == AppBleConfig.packetRealtime;
    // Calibration progress/ready packets are not session data. They must not
    // count as the session going live: a device re-running its baseline has
    // not started, and the start watchdog has to fire.
    if (!realtime && metrics.packetType != AppBleConfig.packetFinalSummary) {
      return;
    }

    // The first stroke and the packet after a pause also report unsteady
    // cadence; only a sustained run should raise the banner.
    if (realtime) {
      _startWatchdog?.cancel();
      _startWatchdog = null;
      final bool unsteady = !metrics.isSteadyCadence && !metrics.isFirstStroke;
      // Count cadence per new compression stroke, not per 5 Hz heartbeat
      // repeat. A repeated packet carries the same totalCompressions, so it
      // must not flip-flop the warning counters or extend an unsteady run.
      final bool newStroke = count > (_lastCount ?? 0);
      if (unsteady && newStroke) {
        _unsteadyPackets += 1;
        _steadyPackets = 0;
      } else if (!unsteady) {
        _unsteadyPackets = 0;
        if (newStroke && !metrics.isFirstStroke) {
          _steadyPackets += 1;
        }
      }

      // "Begin Session" opens this screen, but the session itself starts on
      // the trainee's first compression.
      if (!_firstRealtimePacketSeen) {
        _firstRealtimePacketSeen = true;
      }
      if (!_firstCompressionSeen && count > 0) {
        _firstCompressionSeen = true;
        _firstCompressionElapsedSec = metrics.elapsedSeconds;
        _sessionStartAt = DateTime.now();
        _controller?.sessionStartedAt = _sessionStartAt;
      }
    }

    setState(() {
      _latest = metrics;
      if (_lastCount == null || count > _lastCount!) {
        _lastCompressionAt = DateTime.now();
      }
      _lastCount = count;
      if (realtime) {
        if (_unsteadyPackets >= AppDurations.liveCadenceWarningPackets) {
          _cadenceWarning = true;
        } else if (!_cadenceWarning ||
            _steadyPackets >= AppDurations.liveCadenceClearPackets) {
          _cadenceWarning = false;
        }
        _displayDepthCm = _depthStabilizer.stabilize(
          metrics,
          unsteadyActive: _cadenceWarning,
        );
      }
    });

    _syncMetronome();

    // The firmware's limit counts from START, before the first compression, so
    // the app stops the session itself once the chosen length has elapsed
    // since that first compression. Unlimited (0) relies on the manual stop.
    if (realtime &&
        _firstCompressionSeen &&
        widget.practiceDurationSec > 0 &&
        !_ending &&
        !_finished &&
        metrics.elapsedSeconds - _firstCompressionElapsedSec >=
            widget.practiceDurationSec) {
      unawaited(_endSession());
      return;
    }

    // Firmware auto-stop: a FINAL_SUMMARY arrives without a STOP command.
    if (metrics.packetType == AppBleConfig.packetFinalSummary &&
        !_ending &&
        !_finished) {
      final bool usable = metrics.totalCompressions > 0;
      unawaited(
        _finish(
          reason: usable
              ? SessionEndReason.completed
              : SessionEndReason.resultsUnavailable,
          summary: usable ? metrics : null,
        ),
      );
      return;
    }

   
    // Dynamic app-side voice coaching.
    // Only one instruction may play at a time.
    // Continue tracking errors while audio is busy.
    if (realtime) {
      final bool canSpeak =
          !_muted &&
          !_ending &&
          !_finished &&
          _coach != null &&
          !_coach!.isBusy;

      final int cue;
      final bool newCue;

      if (metrics.audioPromptCode != 0) {
        final bool suppressLegacyDepth = _cadenceWarning &&
            (metrics.audioPromptCode ==
                    AppBleConfig.cuePushHarder ||
                metrics.audioPromptCode ==
                    AppBleConfig.cuePushShallower);

        cue = suppressLegacyDepth
            ? 0
            : metrics.audioPromptCode;

        newCue = cue != 0 &&
            cue != _previousCueCode;

        _previousCueCode = metrics.audioPromptCode;
      } else {
        _previousCueCode = 0;

        cue = _coachingController.evaluate(
          metrics,
          cadenceWarningActive: _cadenceWarning,
          allowPrompt: canSpeak,
        );

        newCue = cue != 0;
      }

      if (newCue && cue != 0 && kDebugMode) {
        debugPrint(
          'Voice cue $cue received at '
          '${DateTime.now().toIso8601String()}',
        );
      }

      if (newCue &&
          canSpeak &&
          _cueGate.allows(cue)) {
        if (kDebugMode) {
          debugPrint(
            'Voice cue $cue accepted at '
            '${DateTime.now().toIso8601String()}',
          );
        }

       unawaited(_coach!.play(cue));
      }
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) unawaited(_coach?.stop());
  }

  /// Applies the remembered on/off choice. The first frame already shows the
  /// default (on), so this only ever corrects it.
  Future<void> _loadMetronomePreferences() async {
    final bool enabled = await _metronomePreferences.loadEnabled();
    if (!mounted || _finished || enabled == _metronomeEnabled) return;
    setState(() => _metronomeEnabled = enabled);
    _syncMetronome();
  }

  void _toggleMetronome() {
    final bool enabled = !_metronomeEnabled;
    setState(() => _metronomeEnabled = enabled);
    unawaited(_metronomePreferences.saveEnabled(enabled));
    _syncMetronome();
  }

  /// Runs the metronome continuously after the first compression.
  /// It stops when disabled or when the session ends.
  /// Voice coaching does not interrupt the beat.
  void _syncMetronome() {
    if (!mounted || _finished || _ending) {
      _stopMetronome();
      return;
    }

    final bool shouldRun =
        _metronomeEnabled && _firstCompressionSeen;

    if (shouldRun == _metronomeRunning) return;

    if (shouldRun) {
      _startMetronome();
    } else {
      _stopMetronome();
    }
  }

 
void _startMetronome() {
  _beatTimer?.cancel();

  _metronomeRunning = true;
  _beatClock = Stopwatch()..start();
  _nextBeatNumber = 1;

  unawaited(_metronome.tick());
  _scheduleNextBeat();
}

void _scheduleNextBeat() {
  _beatTimer?.cancel();

  final Stopwatch? clock = _beatClock;
  if (!mounted || !_metronomeRunning || clock == null) return;

  final int intervalMs =
      AppMetronome.beatInterval(widget.metronomeTempoBpm).inMilliseconds;
  if (intervalMs <= 0) return;

  final int elapsedMs = clock.elapsedMilliseconds;

  while (_nextBeatNumber * intervalMs <= elapsedMs) {
    _nextBeatNumber++;
  }

  final int targetMs = _nextBeatNumber * intervalMs;
  final int waitMs = targetMs - elapsedMs;

  _beatTimer = Timer(Duration(milliseconds: waitMs), () {
    if (!mounted || !_metronomeRunning) return;

    _syncMetronome();
    if (!mounted || !_metronomeRunning) return;

    unawaited(_metronome.tick());

    _nextBeatNumber++;
    _scheduleNextBeat();
  });
}

void _stopMetronome() {
  _beatTimer?.cancel();
  _beatTimer = null;

  _beatClock?.stop();
  _beatClock = null;
  _nextBeatNumber = 0;

  if (!_metronomeRunning) return;

  _metronomeRunning = false;
  unawaited(_metronome.stop());
}

  void _onControllerChanged() {
    if (!mounted || _finished) return;
    final BleStatus? status = _controller?.status;
    if (status != BleStatus.error && status != BleStatus.disconnected) return;

    // A dropped link abandons the session. Show the interrupted result rather
    // than returning silently to Home, and never write an interrupted row.
    unawaited(_finish(reason: SessionEndReason.interrupted, summary: null));
  }

  Future<void> _endSession() async {
    if (_ending || _finished) return;
    final controller = _controller;
    if (controller == null) return;

    setState(() => _ending = true);

    // Listen for FINAL_SUMMARY before/while sending STOP.
    final summaryFuture = controller.awaitPacketWhere(
      (m) => m.packetType == AppBleConfig.packetFinalSummary,
      timeout: AppDurations.finalSummaryTimeout,
    );

    try {
      await controller.sendCommand(AppBleConfig.commandStop);
    } catch (_) {
      // Connection may already be gone; the timeout below decides.
    }

    CprMetrics? summary = await summaryFuture;

    // The guide requires one GET_RESULTS recovery before declaring the results
    // unavailable. The firmware caches the last summary in RAM precisely for
    // this case.
    if (summary == null && controller.isConnected) {
      summary = await _requestResults(controller);
    }

    if (!mounted || _finished) return;
    final bool usable = summary != null && summary.totalCompressions > 0;
    await _finish(
      reason: usable
          ? SessionEndReason.completed
          : SessionEndReason.resultsUnavailable,
      summary: usable ? summary : null,
    );
  }

  /// Sends GET_RESULTS and waits for a Type 4 summary.
  Future<CprMetrics?> _requestResults(BleController controller) async {
    controller.beginResultsRecovery();
    final summaryFuture = controller.awaitPacketWhere(
      (m) => m.packetType == AppBleConfig.packetFinalSummary,
      timeout: AppDurations.getResultsTimeout,
    );
    try {
      await controller.sendCommand(AppBleConfig.commandGetResults);
    } catch (error) {
      debugPrint('GET_RESULTS failed: $error');
      return null;
    }
    return summaryFuture;
  }

  Future<void> _finish({
    required SessionEndReason reason,
    required CprMetrics? summary,
  }) async {
    if (_finished) return;
    _finished = true;

    final controller = _controller;
    _stopSessionInternals();

    if (!mounted || controller == null) return;

    final DateTime startedAt =
        _sessionStartAt ?? controller.sessionStartedAt ?? DateTime.now();
    final List<CprMetrics> recordedPackets = controller.stopRecording();
    final int recorded = recordedPackets.length;
    final DateTime endedAt = controller.sessionEndedAt ?? DateTime.now();

    if (_inMemoryRawStreamActive) {
      _inMemoryRawStreamActive = false;
      unawaited(_sendTelemetryOff(controller));
    } else if (_telemetryRecorder != null) {
      unawaited(_sendTelemetryOff(controller));
    }

    // A completed result must carry a usable summary. A zero-compression STOP
    // is an accidental early end, not a session worth saving.
    SessionEndReason finalReason = reason;
    if (finalReason == SessionEndReason.completed &&
        (summary == null || summary.totalCompressions <= 0)) {
      finalReason = SessionEndReason.resultsUnavailable;
    }
    CprMetrics? finalSummary =
        finalReason == SessionEndReason.completed ? summary : null;

    if (finalSummary != null) {
      final SessionRefinementResult refinement =
          SessionRefinementEngine.refineSession(
        firmwareSummary: finalSummary,
        sessionPackets: recordedPackets,
        rawSamples: _inMemoryRawSamples,
        depthK: _activeDepthK,
        sensitivityPreset: _activeSensitivity,
      );
      _telemetryRecorder?.setRefinementSnapshot(refinement.toJson());
      finalSummary = refinement.refinedSummary;
    }

    final (
      TelemetryRecording? telemetryRecording,
      Future<TelemetryUploadResult>? telemetryUpload,
    ) = await _stopTelemetry(finalReason != SessionEndReason.completed);

    // Firmware duration when a summary exists, minus the time that passed
    // before the first compression, so the result reflects the practice
    // session rather than the wait to get into position.
    final int durationSeconds = finalSummary != null
        ? math.max(
            0,
            finalSummary.elapsedSeconds - _firstCompressionElapsedSec,
          )
        : math.max(0, endedAt.difference(startedAt).inSeconds);

    // Compression and pause time are the CCF split over that same duration.
    final CompressionTimeBreakdown? times = finalSummary == null
        ? null
        : CompressionTimeBreakdown.fromCcf(
            ccfPercent: finalSummary.ccfPercent,
            durationSeconds: durationSeconds,
          );

    bool historySaved = true;
    if (finalReason == SessionEndReason.completed) {
      historySaved = await _persistSession(
        controller,
        finalSummary!,
        recorded,
        startedAt,
        endedAt,
        durationSeconds,
        times,
      );
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionCompleteScreen(
          traineeName: widget.traineeName,
          reason: finalReason,
          summary: finalSummary,
          durationSeconds: durationSeconds,
          compressionSeconds: times?.compressionSeconds,
          pauseSeconds: times?.pauseSeconds,
          historySaved: historySaved,
          telemetryRecording: telemetryRecording,
          telemetryUpload: telemetryUpload,
          onRetryRetrieval: finalReason == SessionEndReason.resultsUnavailable
              ? _retryRetrieval
              : null,
        ),
      ),
    );
  }

  /// Handles the manual Retry Retrieval action on the result screen.
  Future<SessionResultData?> _retryRetrieval() async {
    final controller = _controller;
    if (controller == null || !controller.isConnected) return null;

    final rawSummary = await _requestResults(controller);
    if (rawSummary == null || rawSummary.totalCompressions <= 0) return null;
    final summary = SessionRefinementEngine.refineSession(
      firmwareSummary: rawSummary,
      sessionPackets: controller.sessionPackets,
      rawSamples: _inMemoryRawSamples,
      depthK: _activeDepthK,
      sensitivityPreset: _activeSensitivity,
    ).refinedSummary;

    final DateTime startedAt =
        _sessionStartAt ?? controller.sessionStartedAt ?? DateTime.now();
    final DateTime endedAt = controller.sessionEndedAt ?? DateTime.now();
    final int durationSeconds =
        math.max(0, summary.elapsedSeconds - _firstCompressionElapsedSec);
    final CompressionTimeBreakdown? times =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: summary.ccfPercent,
      durationSeconds: durationSeconds,
    );
    final bool historySaved = await _persistSession(
      controller,
      summary,
      controller.sessionPackets.length,
      startedAt,
      endedAt,
      durationSeconds,
      times,
    );

    return SessionResultData(
      reason: SessionEndReason.completed,
      summary: summary,
      historySaved: historySaved,
    );
  }

  /// Writes a completed session to History.
  ///
  /// Returns false when the write failed, so the result screen can say the
  /// session was not stored. Never throws.
  Future<bool> _persistSession(
    BleController controller,
    CprMetrics summary,
    int packets,
    DateTime startedAt,
    DateTime endedAt,
    int durationSeconds,
    CompressionTimeBreakdown? times,
  ) async {
    final repository = _repository;
    if (repository == null) return false;

    // Loss can only be counted when the firmware numbers its packets.
    final bool sequenced = controller.sessionPackets.any(
      (CprMetrics packet) => packet.sequence != null,
    );

    final record = SessionRecord(
      traineeName: widget.traineeName,
      status: SessionStatus.completed,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      packetCount: packets,
      packetsLost: sequenced ? controller.sessionPacketsLost : null,
      rateCpm: summary.rateCpm,
      depthTenthsMm: (summary.depthCm * 100).round(),
      recoilPercent: summary.recoilPercentage,
      ccfPercent: summary.ccfPercent,
      totalCompressions: summary.totalCompressions,
      compressionSeconds: times?.compressionSeconds,
      pauseSeconds: times?.pauseSeconds,
      qualityFlags: summary.qualityFlags,
      deviceName: controller.deviceName,
      appVersion: AppIdentity.version,
    );

    try {
      await repository.insertSession(record);
      markHistoryChanged();
      return true;
    } catch (error) {
      debugPrint('History write failed: $error');
      return false;
    }
  }

  @override
  void dispose() {
    _stopSessionInternals();
    unawaited(_metronome.dispose());
    if (_telemetryRecorder != null || _inMemoryRawStreamActive) {
      _inMemoryRawStreamActive = false;
      unawaited(_sendTelemetryOff(_controller));
    }
    unawaited(_abortTelemetry());
    super.dispose();
  }

  Widget _capsule(String text, MetricRating? rating) {
    return ValueCapsule(
      text: text,
      background: ValueCapsule.gradedBackground(rating),
      foreground: AppColors.liveCapsuleText,
      minHeight: AppSizes.liveCapsuleHeight,
      radius: AppSizes.liveCapsuleRadius,
      textSize: AppTypography.liveCapsuleSize,
      textWeight: AppTypography.headingWeight,
      minWidth: AppSizes.liveCapsuleWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final latest = _latest;
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return PopScope(
      canPop: false, // sessions end only through the hold or the firmware
      child: Scaffold(
        backgroundColor: AppColors.surfaceScaffold,
        body: SafeArea(
          child: ContentBounds(
            child: Padding(
              padding: EdgeInsets.only(
                top: AppSpacing.flowTopPadding,
                bottom: AppSpacing.flowActionBottomPadding,
                left: page,
                right: page,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (controller != null)
                            _StatusHeader(
                              controller: controller,
                              muted: _muted,
                              onToggleMute: _toggleMute,
                              metronomeEnabled: _metronomeEnabled,
                              onToggleMetronome: _toggleMetronome,
                            ),
                          SizedBox(height: AppSpacing.liveTimerTopGap),
                          _TimerBlock(startedAt: _sessionStartAt),
                          if (latest?.isBenchMode ?? false) ...<Widget>[
                            SizedBox(height: AppSpacing.liveBenchBadgeTopGap),
                            const Center(child: BenchBadge()),
                          ],
                          if (_cadenceWarning) ...<Widget>[
                            SizedBox(height: AppSpacing.liveNoticeTopGap),
                            const _CadenceWarning(),
                          ],
                          SizedBox(height: AppSpacing.liveSectionTopGap),
                          Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              AnimatedOpacity(
                                opacity: _firstRealtimePacketSeen ? 1.0 : 0.30,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                child: IgnorePointer(
                                  ignoring: !_firstCompressionSeen,
                                  child: Column(
                                    children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: _MetricSection(
                                        label: AppStrings.liveRateLabel,
                                        capsule: _capsule(
                                          rateText(latest?.rateCpm),
                                          rateRating(latest?.rateCpm),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: AppSpacing.liveSectionGap),
                                    Expanded(
                                      child: _MetricSection(
                                        label: AppStrings.liveRecoilLabel,
                                        capsule: _capsule(
                                          recoilText(latest?.recoilPercentage),
                                          liveRecoilRating(latest?.recoilPercentage),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                      SizedBox(
                                        height: AppSpacing.liveSectionStackGap,
                                      ),

                                      _MetricSection(
                                        label: AppStrings.liveDepthLabel,
                                        capsule: _capsule(
                                          depthText(latest?.depthCm),
                                          depthRating(latest?.depthCm),
                                        ),
                                      ),

                                      SizedBox(
                                        height: AppSpacing.liveSectionStackGap,
                                      ),

                                      Center(
                                        child: _CompressionCounter(
                                          count:
                                              latest?.totalCompressions ?? 0,
                                          active: _compressing,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              if (!_firstCompressionSeen)
                                Positioned.fill(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      child: Container(
                                        width: double.infinity,
                                        constraints: const BoxConstraints(
                                          maxWidth: 340,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                          vertical: 26,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF174477),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.16),
                                              blurRadius: 18,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            const Icon(
                                              Icons.pan_tool_alt_rounded,
                                              size: 36,
                                              color: Colors.white,
                                            ),

                                            const SizedBox(height: 14),

                                            const Text(
                                              'Start When Ready',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 21,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),

                                            const SizedBox(height: 10),

                                            const Text(
                                              'Begin chest compressions whenever '
                                              "you're ready. The session timer "
                                              'will start automatically.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Color(0xFFE4F0FF),
                                                fontSize: 13,
                                                height: 1.5,
                                              ),
                                            ),

                                            const SizedBox(height: 18),

                                            const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                Icon(
                                                  Icons.circle,
                                                  size: 8,
                                                  color: Color(0xFF9DD4FF),
                                                ),
                                                SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Waiting for first compression',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: Color(0xFFBEDFFF),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.liveSectionStackGap),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _ending ? null : _endSession,
                    child: IgnorePointer(
                      child: HoldFillButton(
                        label: 'Tap to End Session',
                        duration: AppDurations.holdSession,
                        enabled: !_ending,
                        onComplete: _endSession,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title, voice-cue toggle, and live connection status, all indented past the
/// rest of the content.
class _StatusHeader extends StatelessWidget {
  final BleController controller;
  final bool muted;
  final VoidCallback onToggleMute;
  final bool metronomeEnabled;
  final VoidCallback onToggleMetronome;

  const _StatusHeader({
    required this.controller,
    required this.muted,
    required this.onToggleMute,
    required this.metronomeEnabled,
    required this.onToggleMetronome,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: AppSpacing.liveHeaderInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  AppStrings.livePracticeTitle,
                  maxLines: 1,
                  softWrap: false,
                  style: AppTypography.style(
                    size: AppTypography.liveTitleSize,
                    weight: AppTypography.headingWeight,
                    color: AppColors.liveLabelText,
                  ),
                ),
              ),
            ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
                      Semantics(
                        button: true,
                        label:
                            muted ? AppStrings.liveUnmuteCues : AppStrings.liveMuteCues,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onToggleMute,
                          child: SizedBox(
                            width: 20,
                            height: AppSizes.liveMuteTapSize,
                            child: Center(
                              child: Icon(
                                muted ? Icons.volume_off : Icons.volume_up,
                                size: AppSizes.liveMuteIconSize,
                                color: AppColors.liveLabelText,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Semantics(
                        button: true,
                        label: metronomeEnabled
                            ? AppStrings.liveMetronomeDisable
                            : AppStrings.liveMetronomeEnable,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onToggleMetronome,
                          child: SizedBox(
                            width: 36,
                            height: AppSizes.liveMuteTapSize,
                            // The tap box sets the touch target only. Centering keeps its
                            // tight constraints off the glyph, which otherwise filled
                            // the box and ignored its own size.
                            child: Center(
                              child: MetronomeIcon(
                                enabled: metronomeEnabled,
                                size: AppSizes.liveMetronomeIconSize,
                                color: AppColors.liveLabelText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ), // Closes the new icon group
            ],
          ), // Closes the main header Row
          SizedBox(height: AppSpacing.liveStatusGap),
          _StatusLine(controller: controller),
        ],
      ),
    );
  }
}

/// Bullet + label status line: a green dot while the link is up, a red cross
/// once it is gone.
class _StatusLine extends StatelessWidget {
  final BleController controller;

  const _StatusLine({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final (
          String label,
          Color color,
          bool up,
        ) = switch (controller.status) {
          BleStatus.connected => (
              AppStrings.statusConnected,
              AppColors.liveStatusConnected,
              true,
            ),
          BleStatus.scanning => (
              AppStrings.statusScanning,
              AppColors.statusScanning,
              true,
            ),
          BleStatus.connecting => (
              AppStrings.statusConnecting,
              AppColors.statusConnecting,
              true,
            ),
          BleStatus.disconnected => (
              AppStrings.statusDisconnected,
              AppColors.liveStatusLost,
              false,
            ),
          BleStatus.error => (
              '${AppStrings.statusErrorPrefix}${controller.lastError}',
              AppColors.liveStatusLost,
              false,
            ),
        };

        return Row(
          children: <Widget>[
            Icon(
              up ? Icons.circle : Icons.close,
              size: AppSizes.liveStatusGlyphSize,
              color: color,
            ),
            SizedBox(width: AppSpacing.small),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.style(
                  size: AppTypography.liveStatusSize,
                  weight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Amber notice shown once the firmware reports a sustained unsteady rhythm.
class _CadenceWarning extends StatelessWidget {
  const _CadenceWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.liveNoticePaddingH,
        vertical: AppSpacing.liveNoticePaddingV,
      ),
      decoration: BoxDecoration(
        color: AppColors.liveWarningBackground,
        borderRadius: BorderRadius.circular(AppSizes.liveNoticeRadius),
        border: Border.all(
          color: AppColors.liveWarningBorder,
          width: AppSizes.liveNoticeBorderWidth,
        ),
      ),
      child: Text(
        AppStrings.liveCadenceWarning,
        textAlign: TextAlign.center,
        style: AppTypography.style(
          size: AppTypography.liveNoticeSize,
          weight: FontWeight.bold,
          color: AppColors.liveWarningText,
        ),
      ),
    );
  }
}

/// Centred elapsed timer and its caption.
class _TimerBlock extends StatelessWidget {
  final DateTime? startedAt;

  const _TimerBlock({required this.startedAt});

  @override
  Widget build(BuildContext context) {
    final int raw =
        startedAt == null ? 0 : DateTime.now().difference(startedAt!).inSeconds;
    final int seconds = raw < 0 ? 0 : raw;

    return Column(
      children: <Widget>[
        Text(
          durationText(seconds),
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.liveTimerSize,
            weight: AppTypography.headingWeight,
            color: AppColors.liveLabelText,
          ),
        ),
        SizedBox(height: AppSpacing.liveTimerLabelGap),
        Text(
          AppStrings.liveElapsedLabel,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.liveTimerLabelSize,
            weight: AppTypography.headingWeight,
            color: AppColors.liveLabelText,
          ),
        ),
      ],
    );
  }
}

/// Bordered section holding a heading and its value capsule.
class _MetricSection extends StatelessWidget {
  final String label;
  final Widget capsule;

  const _MetricSection({required this.label, required this.capsule});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: AppSizes.liveSectionMinHeight),
      decoration: BoxDecoration(
        color: AppColors.liveSectionBackground,
        borderRadius: BorderRadius.circular(AppSizes.liveSectionRadius),
        border: Border.all(
          color: AppColors.liveSectionBorder,
          width: AppSizes.liveSectionBorderWidth,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.style(
              size: AppTypography.liveSectionLabelSize,
              weight: AppTypography.headingWeight,
              color: AppColors.liveLabelText,
            ),
          ),
          SizedBox(height: AppSpacing.liveSectionLabelGap),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.liveSectionPaddingH,
            ),
            child: capsule,
          ),
        ],
      ),
    );
  }
}

/// Compression tally in a circle: translucent red while idle, green while
/// compressions are being counted.
class _CompressionCounter extends StatelessWidget {
  final int count;
  final bool active;

  const _CompressionCounter({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final TextStyle countStyle = AppTypography.style(
      size: AppTypography.liveCounterSize,
      weight: AppTypography.headingWeight,
      color: AppColors.liveCounterText,
    );
    final TextStyle labelStyle = AppTypography.style(
      size: AppTypography.liveCounterLabelSize,
      weight: FontWeight.normal,
      color: AppColors.liveCounterText,
    );
    final String countText = '$count';
    const String labelText = AppStrings.liveCompressionsLabel;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The circle is a floor plus whatever the two lines need, so a larger
        // rendered text size widens both the circle and the card around it.
        final double textWidth = math.max(
          measureTextWidth(context, countText, countStyle),
          measureTextWidth(context, labelText, labelStyle),
        );
        final double textHeight =
            measureTextHeight(context, countText, countStyle) +
                measureTextHeight(context, labelText, labelStyle);
        final double diameter = math.min(
          math.max(
            AppSizes.liveCounterCircleSize,
            math.max(textWidth, textHeight) +
                2 * AppSizes.liveCounterCirclePadding,
          ),
          math.max(
            0.0,
            constraints.maxWidth - 2 * AppSizes.liveCounterCardPadding,
          ),
        );

        return Container(
          constraints: BoxConstraints(
            minWidth: AppSizes.liveCounterWidth,
            minHeight: AppSizes.liveCounterHeight,
          ),
          padding: EdgeInsets.all(AppSizes.liveCounterCardPadding),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.liveSectionBackground,
            borderRadius: BorderRadius.circular(AppSizes.liveSectionRadius),
            border: Border.all(
              color: AppColors.liveSectionBorder,
              width: AppSizes.liveSectionBorderWidth,
            ),
          ),
          child: Container(
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            padding: EdgeInsets.all(AppSizes.liveCounterCirclePadding),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? AppColors.liveCounterActive
                  : AppColors.liveCounterIdle,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(countText, textAlign: TextAlign.center, style: countStyle),
                Text(labelText, textAlign: TextAlign.center, style: labelStyle),
              ],
            ),
          ),
        );
      },
    );
  }
}
