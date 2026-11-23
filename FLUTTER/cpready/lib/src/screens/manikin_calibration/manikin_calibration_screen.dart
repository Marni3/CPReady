/// Manikin depth calibration.
///
/// This is separate from the baseline Calibration step: CALIBRATE only zeroes
/// the sensor, while CALIBRATE_TARGET rescales the depth reading so it matches
/// the depth the manikin reports.
///
/// The trial runs as a multi-step workflow:
/// 1. Baseline Zeroing: Trainee rests hands motionless on chest (CALIBRATE).
/// 2. Ready Confirmation: Trainee positions hands and taps 'Start 15 s Trial'.
/// 3. Compression Trial: 15 seconds of active CPR compressions (START).
/// 4. Summary & Target Entry: Firmware's FINAL_SUMMARY provides the mean depth,
///    and trainee inputs reference depth from manikin.
/// 5. Calibration Saved: CALIBRATE_TARGET is committed to NVS.
///
/// Disconnections and link timeouts are trapped gracefully without crashing
/// or leaking practice duration settings into regular practice sessions.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/audio/live_coaching_controller.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/ble/device_config.dart';
import '../../core/ble/kinematic_profile.dart';
import '../../core/feedback/metric_feedback.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../core/metrics/session_refinement_engine.dart';
import '../../core/settings/device_settings.dart';
import '../../core/telemetry/raw_frame.dart';
import '../../widgets/widgets.dart';

/// How depth calibration is performed on the manikin.
enum CalibrationMode {
  /// 15-second timed trial compared against a digital reference manikin.
  referenceTrial,

  /// Continuous ~10-stroke bursts with live manual K adjustment by feel.
  subjectiveFeel,
}

enum _Stage {
  intro,
  zeroing,
  ready,
  running,
  feelTuning,
  enterTarget,
  saving,
  sent,
  error,
}

/// Manikin depth calibration screen.
class ManikinCalibrationScreen extends StatefulWidget {
  const ManikinCalibrationScreen({super.key});

  @override
  State<ManikinCalibrationScreen> createState() =>
      _ManikinCalibrationScreenState();
}

class _ManikinCalibrationScreenState extends State<ManikinCalibrationScreen> {
  static const int _feelBurstWindow = 10;
  static const int _feelBurstResetGapMs = 2500;
  static const double _nominalK = 11.20;
  static const double _defaultManikinK = 10.85;

  final TextEditingController _target = TextEditingController();
  final TextEditingController _feelKController =
      TextEditingController(text: '10.85');

  BleController? _controller;
  StreamSubscription<CprMetrics>? _sub;
  StreamSubscription<RawTelemetryFrame>? _rawSub;
  Timer? _ticker;
  Timer? _summaryTimeout;
  Timer? _calibrationTimeout;

  final List<CprMetrics> _trialPackets = <CprMetrics>[];
  final List<RawTelemetrySample> _trialRawSamples = <RawTelemetrySample>[];
  bool _trialRawStreamActive = false;

  CalibrationMode _mode = CalibrationMode.referenceTrial;
  _Stage _stage = _Stage.intro;
  int _trialRemaining = AppDurations.manikinTrialSeconds;
  CprMetrics? _latest;
  double? _meanDepth;
  bool _targetValid = false;
  bool _sending = false;

  // Subjective ("Feel") calibration state
  double _activeFirmwareK = _defaultManikinK;
  double _sliderK = _defaultManikinK;
  double? _feelInitialK;
  bool _feelKModified = false;
  final List<double> _feelBurstRawCm = <double>[];
  int _lastFeelStrokeCount = 0;
  DateTime? _lastFeelStrokeAt;
  late final LiveCoachingController _feelCoach = LiveCoachingController();

  /// True once SET_TIME has been changed, so the restore is only sent when
  /// there is something to restore.
  bool _durationChanged = false;

  /// True between START and the summary; leaving then aborts the trial.
  bool _trialActive = false;

  /// True only once CALIBRATE has been dispatched, preventing a stale Type 3
  /// packet from advancing zeroing prematurely.
  bool _calibrateCommandSent = false;

  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = AppScope.of(context);
    _controller!.addListener(_onConnectionChanged);
    _sub = _controller!.packets.listen(_onPacket);
    unawaited(_loadSavedFeelK());
  }

  Future<void> _loadSavedFeelK() async {
    try {
      final DeviceSettings? stored =
          await AppScope.history(context).loadDeviceSettings();
      if (!mounted || stored?.depthK == null) return;
      final double k = stored!.depthK!;
      setState(() {
        _activeFirmwareK = k;
        _sliderK = k;
        _feelKController.text = k.toStringAsFixed(2);
      });
    } catch (_) {
      // Repository is optional or unsupported in layout matrix tests.
    }
  }

  Future<void> _syncFeelKFromDevice() async {
    final BleController? controller = _controller;
    if (controller == null || !controller.isConnected) return;
    try {
      final DeviceConfig? config = await controller.requestConfig(
        timeout: AppDurations.configReportTimeout,
      );
      if (!mounted || config == null) return;
      setState(() {
        _activeFirmwareK = config.depthK;
        _sliderK = config.depthK;
        _feelKController.text = config.depthK.toStringAsFixed(2);
      });
    } catch (_) {}
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    final BleController? controller = _controller;
    if (controller == null || !controller.isConnected) {
      if (_stage == _Stage.intro || _stage == _Stage.error) return;
      _stopTimers();
      _trialActive = false;
      setState(() {
        _stage = _Stage.error;
        _error = AppStrings.manikinNoDeviceConnected;
        _sending = false;
      });
    }
  }

  // -------------------------------------------------------------------------
  // Workflow Steps
  // -------------------------------------------------------------------------

  /// Step 1: Zero Baseline
  ///
  /// Sends SET_TIME:15 (or SET_TIME:0 in Subjective Feel mode) and CALIBRATE
  /// to firmware. The software queue in BleController paces both commands safely.
  Future<void> _startZeroing() async {
    final BleController? controller = _controller;
    if (controller == null) return;

    if (!controller.isConnected) {
      setState(() {
        _stage = _Stage.error;
        _error = AppStrings.manikinNoDeviceConnected;
      });
      return;
    }

    if (_stage == _Stage.zeroing ||
        _stage == _Stage.running ||
        _stage == _Stage.feelTuning) {
      return;
    }

    setState(() {
      _stage = _Stage.zeroing;
      _calibrateCommandSent = false;
      _error = null;
      _meanDepth = null;
      _latest = null;
      _sending = false;
      _trialRemaining = AppDurations.manikinTrialSeconds;
      _target.clear();
      _targetValid = false;
      _feelBurstRawCm.clear();
      _lastFeelStrokeCount = 0;
      _lastFeelStrokeAt = null;
      _feelInitialK = _activeFirmwareK;
      _feelKModified = false;
      _feelCoach.reset();
    });

    try {
      final int sessionSeconds = _mode == CalibrationMode.subjectiveFeel
          ? 0
          : AppDurations.manikinTrialSeconds;
      await controller.sendCommand(AppBleConfig.commandSetTime(sessionSeconds));
      _durationChanged = true;

      _calibrateCommandSent = true;
      await controller.sendCommand(AppBleConfig.commandCalibrate);
    } catch (error) {
      debugPrint('Manikin zeroing start failed: $error');
      if (mounted) _fail();
      return;
    }

    _calibrationTimeout?.cancel();
    _calibrationTimeout = Timer(
      Duration(milliseconds: AppDurations.manikinCalibrationTimeoutMs),
      () {
        if (!mounted || _stage != _Stage.zeroing) return;
        _fail();
      },
    );
  }

  /// Step 2: Start 15s Active Compression Trial or Subjective Live Feel Tuning
  Future<void> _startTrialRun() async {
    final BleController? controller = _controller;
    if (controller == null || !mounted || _stage != _Stage.ready) return;

    if (!controller.isConnected) {
      setState(() {
        _stage = _Stage.error;
        _error = AppStrings.manikinNoDeviceConnected;
      });
      return;
    }

    if (_mode == CalibrationMode.subjectiveFeel) {
      _feelBurstRawCm.clear();
      _lastFeelStrokeCount = 0;
      _lastFeelStrokeAt = null;
      _feelInitialK = _activeFirmwareK;
      _feelKModified = false;
      _feelCoach.reset();
      setState(() {
        _stage = _Stage.feelTuning;
        _trialActive = true;
        _latest = null;
        _error = null;
      });

      try {
        await controller.sendCommand(AppBleConfig.commandStart);
      } catch (error) {
        debugPrint('Subjective feel calibration START failed: $error');
        if (mounted) _fail();
      }
      return;
    }

    _trialPackets.clear();
    _trialRawSamples.clear();
    if (controller.supportsRawTelemetry) {
      await _rawSub?.cancel();
      _rawSub = controller.rawFrames.listen((RawTelemetryFrame frame) {
        if (_trialRawSamples.length < 18000) {
          _trialRawSamples.addAll(frame.samples);
        }
      });
      try {
        await controller.sendCommand(AppTelemetry.commandOn);
        _trialRawStreamActive = true;
      } catch (_) {}
    }

    setState(() {
      _stage = _Stage.running;
      _trialActive = true;
      _trialRemaining = AppDurations.manikinTrialSeconds;
      _error = null;
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!mounted || _trialRemaining <= 0) return;
      setState(() => _trialRemaining -= 1);
    });

    _summaryTimeout?.cancel();
    _summaryTimeout = Timer(AppDurations.manikinSummaryTimeout, () {
      if (!mounted || _stage != _Stage.running) return;
      _fail();
    });

    try {
      await controller.sendCommand(AppBleConfig.commandStart);
    } catch (error) {
      debugPrint('Manikin trial START failed: ');
      if (mounted) _fail();
    }
  }

  String _messageForErrorCode(int errorCode) {
    return switch (errorCode) {
      AppBleConfig.errMotionUnstable => AppStrings.calibrationErrorUnstable,
      AppBleConfig.errLowSampleCount => AppStrings.calibrationErrorLowSamples,
      AppBleConfig.errGravityImplausible => AppStrings.calibrationErrorGravity,
      AppBleConfig.errSensorAlignment => AppStrings.calibrationErrorAlignment,
      AppBleConfig.errWrongState => AppStrings.calibrationErrorBusy,
      AppBleConfig.errNoTrialData => AppStrings.calibrationErrorNoTrialData,
      AppBleConfig.errI2cFault => AppStrings.calibrationErrorI2cFault,
      AppBleConfig.errCalibOutOfRange => AppStrings.manikinTargetRejected,
      _ => AppStrings.manikinError,
    };
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;

    switch (_stage) {
      case _Stage.zeroing:
        if (metrics.packetType == AppBleConfig.packetCalibrationDone) {
          if (!_calibrateCommandSent) return;
          _calibrationTimeout?.cancel();
          _calibrationTimeout = null;
          setState(() {
            _stage = _Stage.ready;
          });
        } else if (metrics.packetType == AppBleConfig.packetError) {
          _fail(_messageForErrorCode(metrics.errorCode));
        }
      case _Stage.running:
        if (metrics.packetType == AppBleConfig.packetRealtime) {
          _trialPackets.add(metrics);
          setState(() => _latest = metrics);
        } else if (metrics.packetType == AppBleConfig.packetFinalSummary) {
          _complete(metrics);
        } else if (metrics.packetType == AppBleConfig.packetError) {
          _fail(_messageForErrorCode(metrics.errorCode));
        }
      case _Stage.feelTuning:
        if (metrics.packetType == AppBleConfig.packetRealtime) {
          _handleFeelRealtimePacket(metrics);
        } else if (metrics.packetType == AppBleConfig.packetError) {
          _fail(_messageForErrorCode(metrics.errorCode));
        }
      default:
        break;
    }
  }

  void _handleFeelRealtimePacket(CprMetrics metrics) {
    final bool isNewStroke =
        metrics.totalCompressions > _lastFeelStrokeCount &&
        metrics.depthCm > 0.0;

    if (isNewStroke) {
      final DateTime now = DateTime.now();
      if (_lastFeelStrokeAt != null &&
          now.difference(_lastFeelStrokeAt!).inMilliseconds >
              _feelBurstResetGapMs) {
        _feelBurstRawCm.clear();
        _feelCoach.reset();
      }
      _lastFeelStrokeAt = now;
      _lastFeelStrokeCount = metrics.totalCompressions;

      final double kDivisor =
          _activeFirmwareK > 0.0 ? _activeFirmwareK : _nominalK;
      final double rawCm = metrics.depthCm * (_nominalK / kDivisor);
      _feelBurstRawCm.add(rawCm);
      if (_feelBurstRawCm.length > _feelBurstWindow) {
        _feelBurstRawCm.removeAt(0);
      }

      final double scaledDepth = _scaledDepthCm(rawCm);
      final CprMetrics rescaledForCoach = CprMetrics(
        packetType: metrics.packetType,
        recoilComplete: metrics.recoilComplete,
        recoilPercentage: metrics.recoilPercentage,
        rateCpm: metrics.rateCpm,
        depthCm: scaledDepth,
        depthMm: scaledDepth * 10.0,
        ccfPercent: metrics.ccfPercent,
        audioPromptCode: metrics.audioPromptCode,
        totalCompressions: metrics.totalCompressions,
        elapsedSeconds: metrics.elapsedSeconds,
        qualityFlags: metrics.qualityFlags,
        sequence: metrics.sequence,
      );
      final int cue = _feelCoach.evaluate(
        rescaledForCoach,
        cadenceWarningActive: !metrics.isSteadyCadence,
      );
      if (cue != 0) {
        unawaited(AppScope.voice(context).play(cue));
      }
    }

    setState(() {
      _latest = metrics;
    });
  }

  double _scaledDepthCm(double rawCm) {
    return (rawCm * (_sliderK / _nominalK)).clamp(0.0, 10.0);
  }

  double? get _feelLastStrokeCm =>
      _feelBurstRawCm.isEmpty ? null : _scaledDepthCm(_feelBurstRawCm.last);

  double? get _feelAverageCm {
    if (_feelBurstRawCm.isEmpty) return null;
    // Skip stroke #1 in a burst of >= 3 strokes so an initial warm-up push
    // does not skew the 10-stroke steady feel average.
    final int startIdx = _feelBurstRawCm.length >= 3 ? 1 : 0;
    double sum = 0.0;
    int count = 0;
    for (int i = startIdx; i < _feelBurstRawCm.length; i++) {
      sum += _scaledDepthCm(_feelBurstRawCm[i]);
      count++;
    }
    return count > 0 ? sum / count : null;
  }

  void _setFeelKLocal(double nextK, {bool updateTextField = true}) {
    final double clamped = nextK
        .clamp(AppBleConfig.depthKMin, AppBleConfig.depthKMax)
        .toDouble();
    setState(() {
      _sliderK = clamped;
      _error = null;
      if (updateTextField) {
        _feelKController.text = clamped.toStringAsFixed(2);
      }
    });
  }

  Future<void> _commitFeelKToDevice(double k) async {
    final double clamped = k
        .clamp(AppBleConfig.depthKMin, AppBleConfig.depthKMax)
        .toDouble();
    _feelCoach.reset();
    final BleController? controller = _controller;
    if (controller == null || !controller.isConnected) return;
    _feelInitialK ??= _activeFirmwareK;
    try {
      await controller.sendCommand(AppBleConfig.commandSetK(clamped));
      _feelKModified = true;
      if (mounted) {
        setState(() {
          _activeFirmwareK = clamped;
        });
      }
    } catch (error) {
      debugPrint('Live SET_K failed: $error');
    }
  }

  /// Restores the original K in firmware if the user abandons Live Feel
  /// Calibration after sending live SET_K adjustments without tapping Save.
  Future<void> _restoreUnsavedFeelK() async {
    if (!_feelKModified || _feelInitialK == null) return;
    final double restoreK = _feelInitialK!;
    _feelKModified = false;
    final BleController? controller = _controller;
    if (controller == null || !controller.isConnected) return;
    try {
      await controller.sendCommand(AppBleConfig.commandSetK(restoreK));
    } catch (error) {
      debugPrint('Unsaved feel K restore failed: $error');
    }
  }

  Future<void> _saveFeelCalibration() async {
    final BleController? controller = _controller;
    if (controller == null || _sending) return;

    if (!controller.isConnected) {
      setState(() {
        _error = AppStrings.manikinNoDeviceConnected;
      });
      return;
    }

    final historyRepo = AppScope.history(context);
    final double finalK = _sliderK
        .clamp(AppBleConfig.depthKMin, AppBleConfig.depthKMax)
        .toDouble();

    setState(() {
      _sending = true;
      _stage = _Stage.saving;
      _error = null;
    });

    try {
      if (_trialActive) {
        _trialActive = false;
        await controller.sendCommand(AppBleConfig.commandStop);
      }
      await controller.sendCommand(AppBleConfig.commandSetK(finalK));
      _activeFirmwareK = finalK;
      _feelInitialK = finalK;
      _feelKModified = false;
      await _restorePracticeDuration();

      try {
        final DeviceSettings? existing = await historyRepo.loadDeviceSettings();
        await historyRepo.saveDeviceSettings(
          DeviceSettings(
            profile: existing?.profile ?? KinematicProfile.manikin,
            depthK: finalK,
            practiceDurationSec: existing?.practiceDurationSec ??
                AppDeviceSettings.defaultPracticeDurationSec,
            updatedAt: DateTime.now(),
          ),
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _stage = _Stage.sent;
        _sending = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('Save subjective calibration failed: $error');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.feelTuning;
        _sending = false;
        _error = AppStrings.manikinSendFailed;
      });
    }
  }

  /// Turns the trial summary into the target-entry state.
  void _complete(CprMetrics summary) {
    _stopTimers();
    _trialActive = false;
    unawaited(_stopTrialRawStream());
    unawaited(_restorePracticeDuration());

    final CprMetrics refined = SessionRefinementEngine.refineSession(
      firmwareSummary: summary,
      sessionPackets: _trialPackets,
      rawSamples: _trialRawSamples,
    ).refinedSummary;

    if (refined.depthCm <= 0) {
      setState(() {
        _stage = _Stage.error;
        _error = AppStrings.manikinNoCompressions;
      });
      return;
    }

    setState(() {
      _stage = _Stage.enterTarget;
      _meanDepth = refined.depthCm;
      _latest = null;
      _error = null;
    });
  }

  Future<void> _stopTrialRawStream() async {
    await _rawSub?.cancel();
    _rawSub = null;
    if (!_trialRawStreamActive) return;
    _trialRawStreamActive = false;
    final BleController? controller = _controller;
    if (controller == null || !controller.isConnected) return;
    try {
      await controller.sendCommand(AppTelemetry.commandOff);
    } catch (_) {}
  }

  /// Ends a failed or timed-out trial and records the reason.
  void _fail([String? specificError]) {
    _stopTimers();
    unawaited(_stopTrialRawStream());
    if (_trialActive) {
      _trialActive = false;
      unawaited(_abortTrial());
    }
    unawaited(_restoreUnsavedFeelK());
    unawaited(_restorePracticeDuration());

    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      if (_controller == null || !_controller!.isConnected) {
        _error = AppStrings.manikinNoDeviceConnected;
      } else if (specificError != null) {
        _error = specificError;
      } else {
        _error = AppStrings.manikinError;
      }
    });
  }

  Future<void> _abortTrial() async {
    final BleController? controller = _controller;
    if (controller == null || !controller.isConnected) return;
    try {
      await controller.sendCommand(AppBleConfig.commandStop);
    } catch (error) {
      debugPrint('Manikin trial stop failed: ');
    }
  }

  /// Sends the target depth and waits for the firmware's Type 3 ACK.
  ///
  /// The GATT write completing is not proof that K was persisted; the ACK is.
  Future<void> _save() async {
    final BleController? controller = _controller;
    final double? depth = double.tryParse(_target.text.trim());
    if (controller == null || depth == null || !_targetValid || _sending) {
      return;
    }

    if (!controller.isConnected) {
      setState(() {
        _error = AppStrings.manikinNoDeviceConnected;
      });
      return;
    }

    setState(() {
      _sending = true;
      _stage = _Stage.saving;
      _error = null;
    });

    final ackFuture = controller.awaitPacketWhere(
      (m) =>
          m.packetType == AppBleConfig.packetCalibrationDone ||
          m.packetType == AppBleConfig.packetError,
      timeout: AppDurations.targetAckTimeout,
    );

    try {
      await controller.sendCommand(AppBleConfig.commandCalibrateTarget(depth));
    } catch (error) {
      debugPrint('Manikin target send failed: $error');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.enterTarget;
        _sending = false;
        _error = AppStrings.manikinSendFailed;
      });
      return;
    }

    final CprMetrics? ack = await ackFuture;
    if (!mounted) return;

    // A disconnect may have moved the screen to the error stage while the ACK
    // wait was outstanding; do not overwrite that more specific message.
    if (_stage != _Stage.saving || !controller.isConnected) return;

    if (ack?.packetType == AppBleConfig.packetCalibrationDone) {
      setState(() {
        _stage = _Stage.sent;
        _sending = false;
        _error = null;
      });
      return;
    }

    final String targetError;
    if (ack?.packetType == AppBleConfig.packetError) {
      targetError = (ack?.errorCode == AppBleConfig.errNoTrialData)
          ? AppStrings.calibrationErrorNoTrialData
          : AppStrings.manikinTargetRejected;
    } else {
      targetError = AppStrings.manikinTargetTimeout;
    }

    setState(() {
      _stage = _Stage.enterTarget;
      _sending = false;
      _error = targetError;
    });
  }

  void _targetChanged(String text) {
    final double? value = double.tryParse(text.trim());
    final bool valid = value != null && value >= 1.0 && value <= 10.0;
    if (valid == _targetValid && _error == null) {
      setState(() => _targetValid = valid);
      return;
    }
    setState(() {
      _targetValid = valid;
      _error = null;
    });
  }

  /// Puts the firmware session length back to normal practice (120s).
  Future<void> _restorePracticeDuration() async {
    if (!_durationChanged) return;
    _durationChanged = false;
    final BleController? controller = _controller;
    if (controller == null || !controller.isConnected) return;
    try {
      await controller.sendCommand(
        AppBleConfig.commandSetTime(AppDurations.practiceSessionSeconds),
      );
    } catch (error) {
      debugPrint('Practice duration restore failed: ');
    }
  }

  void _stopTimers() {
    _ticker?.cancel();
    _ticker = null;
    _summaryTimeout?.cancel();
    _summaryTimeout = null;
    _calibrationTimeout?.cancel();
    _calibrationTimeout = null;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onConnectionChanged);
    _sub?.cancel();
    unawaited(_stopTrialRawStream());
    _stopTimers();
    if (_trialActive && _controller != null && _controller!.isConnected) {
      _trialActive = false;
      unawaited(_abortTrial());
    }
    if (_feelKModified && _controller != null && _controller!.isConnected) {
      unawaited(_restoreUnsavedFeelK());
    }
    if (_durationChanged && _controller != null && _controller!.isConnected) {
      unawaited(_restorePracticeDuration());
    }
    _target.dispose();
    _feelKController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // UI Building
  // -------------------------------------------------------------------------

  OutlineInputBorder _fieldBorder() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.flowFieldRadius),
      borderSide: BorderSide(
        color: AppColors.flowPanelBorder,
        width: AppSizes.flowPanelBorderWidth,
      ),
    );
  }

  String get _actionLabel {
    return switch (_stage) {
      _Stage.intro => AppStrings.manikinStartZeroing,
      _Stage.zeroing => AppStrings.manikinPreparing,
      _Stage.ready => _mode == CalibrationMode.subjectiveFeel
          ? AppStrings.manikinFeelStart
          : AppStrings.manikinStart,
      _Stage.running => AppStrings.manikinTrialRunning,
      _Stage.feelTuning => AppStrings.manikinFeelFinishSave,
      _Stage.enterTarget => AppStrings.manikinSave,
      _Stage.saving => AppStrings.manikinSaving,
      _Stage.sent => AppStrings.manikinDone,
      _Stage.error => AppStrings.manikinRetry,
    };
  }

  VoidCallback? get _action {
    return switch (_stage) {
      _Stage.intro || _Stage.error => () => unawaited(_startZeroing()),
      _Stage.ready => () => unawaited(_startTrialRun()),
      _Stage.feelTuning =>
        !_sending ? () => unawaited(_saveFeelCalibration()) : null,
      _Stage.enterTarget => _targetValid && !_sending ? _save : null,
      _Stage.sent => () => Navigator.of(context).maybePop(),
      _Stage.zeroing || _Stage.running || _Stage.saving => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return Scaffold(
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const FlowBackButton(),
                    SizedBox(width: AppSpacing.flowBackTitleGap),
                    Expanded(
                      child: Text(
                        AppStrings.manikinTitle,
                        style: AppTypography.style(
                          size: AppTypography.flowTitleSize,
                          weight: AppTypography.headingWeight,
                          color: AppColors.flowHeadingText,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.flowTitleGap),
                Expanded(child: SingleChildScrollView(child: _buildContent())),
                SizedBox(height: AppSpacing.section),
                FlatActionButton(label: _actionLabel, onPressed: _action),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return switch (_stage) {
      _Stage.intro => _buildIntro(),
      _Stage.zeroing => _buildZeroing(),
      _Stage.ready => _buildReady(),
      _Stage.running => _buildRunning(),
      _Stage.feelTuning => _buildFeelTuning(),
      _Stage.enterTarget => _buildTargetEntry(),
      _Stage.saving => _buildSaving(),
      _Stage.sent => _buildSent(),
      _Stage.error => _buildError(),
    };
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.manikinModeSelectorTitle,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.small),
        _ModeOptionCard(
          title: AppStrings.manikinModeReferenceTitle,
          body: AppStrings.manikinModeReferenceBody,
          selected: _mode == CalibrationMode.referenceTrial,
          onTap: () {
            if (_mode == CalibrationMode.referenceTrial) return;
            setState(() => _mode = CalibrationMode.referenceTrial);
          },
        ),
        SizedBox(height: AppSpacing.small),
        _ModeOptionCard(
          title: AppStrings.manikinModeFeelTitle,
          body: AppStrings.manikinModeFeelBody,
          selected: _mode == CalibrationMode.subjectiveFeel,
          onTap: () {
            if (_mode == CalibrationMode.subjectiveFeel) return;
            setState(() => _mode = CalibrationMode.subjectiveFeel);
            unawaited(_syncFeelKFromDevice());
          },
        ),
        SizedBox(height: AppSpacing.section),
        Text(
          'Step 1: Zero Baseline',
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.small),
        Text(
          'Place the vest flat on the manikin chest. Keep your hands resting motionless on the chest while zeroing.',
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildZeroing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.manikinPreparing,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.section),
        const Center(child: CircularProgressIndicator()),
        SizedBox(height: AppSpacing.section),
        Text(
          'Calibrating motionless baseline… Keep your hands steady.',
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
          ),
        ),
      ],
    );
  }

  Widget _buildReady() {
    final bool isFeel = _mode == CalibrationMode.subjectiveFeel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Baseline Calibrated',
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.flowHeadingSize,
            weight: AppTypography.headingWeight,
            color: AppColors.connected,
          ),
        ),
        SizedBox(height: AppSpacing.manikinSectionGap),
        Text(
          isFeel ? AppStrings.manikinFeelReadyBody : AppStrings.manikinBaselineReady,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
            height: 1.5,
          ),
        ),
        if (!isFeel) ...<Widget>[
          SizedBox(height: AppSpacing.section),
          Text(
            'Compress continuously for 15 seconds at a steady rate of 100-120 CPM.',
            textAlign: TextAlign.center,
            style: AppTypography.style(
              size: AppTypography.manikinBodySize,
              weight: FontWeight.bold,
              color: AppColors.flowHeadingText,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeelTuning() {
    final double? avgCm = _feelAverageCm;
    final double? lastCm = _feelLastStrokeCm;
    final MetricRating? avgRating = depthRating(avgCm);

    final Color bannerBg;
    final Color bannerBorder;
    final Color bannerText;
    final String statusLabel;

    if (avgCm == null) {
      bannerBg = AppColors.flowPanelBackground;
      bannerBorder = AppColors.flowPanelBorder;
      bannerText = AppColors.flowHelperText;
      statusLabel = AppStrings.manikinFeelStatusWaiting;
    } else if (avgRating == MetricRating.good) {
      bannerBg = AppColors.summarySavedBackground;
      bannerBorder = AppColors.liveCapsulePositive;
      bannerText = AppColors.summarySavedText;
      statusLabel = AppStrings.manikinFeelStatusGood;
    } else if (avgCm < AppTargets.depthMinCm) {
      bannerBg = AppColors.historyInterruptedBackground;
      bannerBorder = AppColors.statusError;
      bannerText = AppColors.statusError;
      statusLabel = AppStrings.manikinFeelStatusShallow;
    } else {
      bannerBg = AppColors.historyInterruptedBackground;
      bannerBorder = AppColors.statusError;
      bannerText = AppColors.statusError;
      statusLabel = AppStrings.manikinFeelStatusDeep;
    }

    final double sliderMin = math.min(5.0, _sliderK);
    final double sliderMax = math.max(35.0, _sliderK);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.manikinFeelInstruction,
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
            height: 1.4,
          ),
        ),
        SizedBox(height: AppSpacing.item),
        Container(
          padding: EdgeInsets.all(AppSpacing.item),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(AppSizes.manikinValueRadius),
            border: Border.all(
              color: bannerBorder,
              width: AppSizes.manikinValueBorderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                AppStrings.manikinFeelLastSetAvg,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.manikinLabelSize,
                  weight: FontWeight.bold,
                  color: AppColors.flowHeadingText,
                ),
              ),
              SizedBox(height: AppSpacing.tiny),
              Text(
                depthText(avgCm),
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.flowHeadingSize,
                  weight: AppTypography.headingWeight,
                  color: bannerText,
                ),
              ),
              SizedBox(height: AppSpacing.tiny),
              Text(
                statusLabel,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.manikinBodySize,
                  weight: FontWeight.bold,
                  color: bannerText,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.item),
        Row(
          children: <Widget>[
            Expanded(
              child: _FeelMetricTile(
                label: AppStrings.manikinFeelStrokesInSet,
                value: '${_feelBurstRawCm.length} / $_feelBurstWindow',
              ),
            ),
            SizedBox(width: AppSpacing.small),
            Expanded(
              child: _FeelMetricTile(
                label: AppStrings.manikinFeelLastStroke,
                value: depthText(lastCm),
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.item),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(
              child: Text(
                AppStrings.manikinFeelSliderLabel,
                style: AppTypography.style(
                  size: AppTypography.manikinLabelSize,
                  weight: FontWeight.bold,
                  color: AppColors.flowHeadingText,
                ),
              ),
            ),
            Text(
              'K = ${_sliderK.toStringAsFixed(2)}',
              style: AppTypography.style(
                size: AppTypography.manikinLabelSize,
                weight: FontWeight.bold,
                color: AppColors.manikinValueText,
              ),
            ),
          ],
        ),
        Slider(
          value: _sliderK.clamp(sliderMin, sliderMax).toDouble(),
          min: sliderMin,
          max: sliderMax,
          activeColor: AppColors.brandBlue,
          onChanged: (double v) {
            final double rounded = (v * 20).round() / 20.0;
            _setFeelKLocal(rounded);
          },
          onChangeEnd: (double v) {
            final double rounded = (v * 20).round() / 20.0;
            _setFeelKLocal(rounded);
            unawaited(_commitFeelKToDevice(rounded));
          },
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.tiny,
          runSpacing: AppSpacing.tiny,
          children: <Widget>[
            for (final double delta in <double>[-0.50, -0.10, 0.10, 0.50])
              OutlinedButton(
                onPressed: () {
                  final double next = (_sliderK + delta)
                      .clamp(AppBleConfig.depthKMin, AppBleConfig.depthKMax)
                      .toDouble();
                  _setFeelKLocal(next);
                  unawaited(_commitFeelKToDevice(next));
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.small,
                    vertical: AppSpacing.tiny,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(
                  delta > 0
                      ? '+${delta.toStringAsFixed(2)}'
                      : delta.toStringAsFixed(2),
                ),
              ),
          ],
        ),
        SizedBox(height: AppSpacing.small),
        Row(
          children: <Widget>[
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppSizes.flowFieldHeight,
                ),
                child: TextField(
                  controller: _feelKController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onSubmitted: (String text) {
                    final double? parsed = double.tryParse(text.trim());
                    if (parsed != null &&
                        parsed >= AppBleConfig.depthKMin &&
                        parsed <= AppBleConfig.depthKMax) {
                      _setFeelKLocal(parsed);
                      unawaited(_commitFeelKToDevice(parsed));
                    }
                  },
                  onChanged: (String text) {
                    final double? parsed = double.tryParse(text.trim());
                    if (parsed != null &&
                        parsed >= AppBleConfig.depthKMin &&
                        parsed <= AppBleConfig.depthKMax) {
                      _setFeelKLocal(parsed, updateTextField: false);
                    }
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.flowPanelBackground,
                    labelText: 'Manual K (${AppBleConfig.depthKMin.toInt()}–${AppBleConfig.depthKMax.toInt()})',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.flowFieldPaddingH,
                    ),
                    border: _fieldBorder(),
                    enabledBorder: _fieldBorder(),
                    focusedBorder: _fieldBorder(),
                  ),
                ),
              ),
            ),
            SizedBox(width: AppSpacing.small),
            TextButton(
              onPressed: () {
                setState(() {
                  _feelBurstRawCm.clear();
                  _feelCoach.reset();
                });
              },
              child: const Text(AppStrings.manikinFeelClearSet),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          SizedBox(height: AppSpacing.small),
          Text(
            _error!,
            style: AppTypography.style(
              size: AppTypography.manikinBodySize,
              weight: FontWeight.normal,
              color: AppColors.manikinErrorText,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRunning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.manikinTrialRunning,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.manikinSectionGap),
        Text(
          '$_trialRemaining',
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.countdownNumberSize,
            weight: AppTypography.headingWeight,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.manikinSectionGap),
        Text(
          AppStrings.manikinLiveDepth,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.manikinFieldGap),
        Text(
          depthText(_latest?.depthCm),
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinValueSize,
            weight: AppTypography.headingWeight,
            color: AppColors.flowHeadingText,
          ),
        ),
      ],
    );
  }

  Widget _buildTargetEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.manikinMeanDepth,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.manikinFieldGap),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.manikinValuePaddingH,
            vertical: AppSpacing.manikinValuePaddingV,
          ),
          decoration: BoxDecoration(
            color: AppColors.manikinValueBackground,
            borderRadius: BorderRadius.circular(AppSizes.manikinValueRadius),
            border: Border.all(
              color: AppColors.manikinValueBorder,
              width: AppSizes.manikinValueBorderWidth,
            ),
          ),
          child: Text(
            depthText(_meanDepth),
            textAlign: TextAlign.center,
            style: AppTypography.style(
              size: AppTypography.manikinValueSize,
              weight: AppTypography.headingWeight,
              color: AppColors.manikinValueText,
            ),
          ),
        ),
        SizedBox(height: AppSpacing.manikinSectionGap),
        Text(
          AppStrings.manikinTargetLabel,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.manikinFieldGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppSizes.flowFieldHeight,
                ),
                child: TextField(
                  controller: _target,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: _targetChanged,
                  style: AppTypography.style(
                    size: AppTypography.flowFieldTextSize,
                    weight: FontWeight.normal,
                    color: AppColors.flowFieldText,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.flowPanelBackground,
                    hintText: AppStrings.manikinTargetHint,
                    hintStyle: AppTypography.style(
                      size: AppTypography.flowFieldTextSize,
                      weight: FontWeight.normal,
                      color: AppColors.flowFieldHint,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.flowFieldPaddingH,
                    ),
                    border: _fieldBorder(),
                    enabledBorder: _fieldBorder(),
                    focusedBorder: _fieldBorder(),
                  ),
                ),
              ),
            ),
            SizedBox(width: AppSpacing.manikinUnitGap),
            Text(
              AppStrings.manikinTargetUnit,
              style: AppTypography.style(
                size: AppTypography.flowFieldTextSize,
                weight: FontWeight.bold,
                color: AppColors.flowHeadingText,
              ),
            ),
          ],
        ),
        if (_target.text.trim().isNotEmpty && !_targetValid) ...<Widget>[
          SizedBox(height: AppSpacing.manikinFieldGap),
          Text(
            AppStrings.manikinInvalidTarget,
            style: AppTypography.style(
              size: AppTypography.manikinBodySize,
              weight: FontWeight.normal,
              color: AppColors.manikinErrorText,
            ),
          ),
        ],
        if (_error != null) ...<Widget>[
          SizedBox(height: AppSpacing.manikinFieldGap),
          Text(
            _error!,
            style: AppTypography.style(
              size: AppTypography.manikinBodySize,
              weight: FontWeight.normal,
              color: AppColors.manikinErrorText,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSaving() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.manikinSaving,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.section),
        const Center(child: CircularProgressIndicator()),
        SizedBox(height: AppSpacing.section),
        Text(
          AppStrings.manikinSavingBody,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
          ),
        ),
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.manikinSentTitle,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.flowHeadingSize,
            weight: AppTypography.headingWeight,
            color: AppColors.flowHeadingText,
          ),
        ),
        SizedBox(height: AppSpacing.manikinSectionGap),
        Text(
          AppStrings.manikinSentBody,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Text(
      _error ?? AppStrings.manikinError,
      textAlign: TextAlign.center,
      style: AppTypography.style(
        size: AppTypography.manikinBodySize,
        weight: FontWeight.normal,
        color: AppColors.manikinErrorText,
        height: 1.5,
      ),
    );
  }
}

class _ModeOptionCard extends StatelessWidget {
  const _ModeOptionCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.profileOptionPaddingH,
            vertical: AppSpacing.profileOptionPaddingV,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.profileOptionSelectedBackground
                : AppColors.profileOptionBackground,
            borderRadius: BorderRadius.circular(AppSizes.profileOptionRadius),
            border: Border.all(
              color: selected
                  ? AppColors.profileOptionSelectedBorder
                  : AppColors.profileOptionBorder,
              width: AppSizes.profileOptionBorderWidth,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: selected
                      ? AppColors.profileOptionIndicator
                      : AppColors.profileOptionBorder,
                ),
              ),
              SizedBox(width: AppSpacing.small),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTypography.style(
                        size: AppTypography.profileOptionTitleSize,
                        weight: FontWeight.bold,
                        color: AppColors.profileOptionText,
                      ),
                    ),
                    SizedBox(height: AppSpacing.tiny),
                    Text(
                      body,
                      style: AppTypography.style(
                        size: AppTypography.profileOptionBodySize,
                        weight: FontWeight.normal,
                        color: AppColors.profileOptionBodyText,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeelMetricTile extends StatelessWidget {
  const _FeelMetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.small,
        vertical: AppSpacing.small,
      ),
      decoration: BoxDecoration(
        color: AppColors.manikinValueBackground,
        borderRadius: BorderRadius.circular(AppSizes.manikinValueRadius),
        border: Border.all(
          color: AppColors.manikinValueBorder,
          width: AppSizes.manikinValueBorderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.style(
              size: AppTypography.profileOptionBodySize,
              weight: FontWeight.bold,
              color: AppColors.flowHelperText,
            ),
          ),
          SizedBox(height: AppSpacing.tiny),
          Text(
            value,
            textAlign: TextAlign.center,
            style: AppTypography.style(
              size: AppTypography.manikinValueSize,
              weight: AppTypography.headingWeight,
              color: AppColors.manikinValueText,
            ),
          ),
        ],
      ),
    );
  }
}
