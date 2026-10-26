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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/feedback/metric_feedback.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../widgets/widgets.dart';

enum _Stage { intro, zeroing, ready, running, enterTarget, saving, sent, error }

/// Manikin depth calibration screen.
class ManikinCalibrationScreen extends StatefulWidget {
  const ManikinCalibrationScreen({super.key});

  @override
  State<ManikinCalibrationScreen> createState() =>
      _ManikinCalibrationScreenState();
}

class _ManikinCalibrationScreenState extends State<ManikinCalibrationScreen> {
  final TextEditingController _target = TextEditingController();

  BleController? _controller;
  StreamSubscription<CprMetrics>? _sub;
  Timer? _ticker;
  Timer? _summaryTimeout;
  Timer? _calibrationTimeout;

  _Stage _stage = _Stage.intro;
  int _trialRemaining = AppDurations.manikinTrialSeconds;
  CprMetrics? _latest;
  double? _meanDepth;
  bool _targetValid = false;
  bool _sending = false;

  /// True once SET_TIME has been changed, so the restore is only sent when
  /// there is something to restore.
  bool _durationChanged = false;

  /// True between START and the summary; leaving then aborts the trial.
  bool _trialActive = false;

  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = AppScope.of(context);
    _controller!.addListener(_onConnectionChanged);
    _sub = _controller!.packets.listen(_onPacket);
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
  /// Sends SET_TIME:15 and CALIBRATE to firmware. The software queue in
  /// BleController paces both commands safely.
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

    if (_stage == _Stage.zeroing || _stage == _Stage.running) {
      return;
    }

    setState(() {
      _stage = _Stage.zeroing;
      _error = null;
      _meanDepth = null;
      _latest = null;
      _sending = false;
      _trialRemaining = AppDurations.manikinTrialSeconds;
      _target.clear();
      _targetValid = false;
    });

    try {
      await controller.sendCommand(
        AppBleConfig.commandSetTime(AppDurations.manikinTrialSeconds),
      );
      _durationChanged = true;

      await controller.sendCommand(AppBleConfig.commandCalibrate);
    } catch (error) {
      debugPrint('Manikin zeroing start failed: ');
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

  /// Step 2: Start 15s Active Compression Trial
  ///
  /// Trainee taps Start after baseline is verified and hands are in position.
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

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;

    switch (_stage) {
      case _Stage.zeroing:
        if (metrics.packetType == AppBleConfig.packetCalibrationDone) {
          _calibrationTimeout?.cancel();
          _calibrationTimeout = null;
          setState(() {
            _stage = _Stage.ready;
          });
        } else if (metrics.packetType == AppBleConfig.packetError) {
          final String msg = switch (metrics.errorCode) {
            AppBleConfig.errMotionUnstable => AppStrings.calibrationErrorUnstable,
            AppBleConfig.errLowSampleCount => AppStrings.calibrationErrorLowSamples,
            AppBleConfig.errGravityImplausible => AppStrings.calibrationErrorGravity,
            AppBleConfig.errSensorAlignment => AppStrings.calibrationErrorAlignment,
            AppBleConfig.errWrongState => AppStrings.calibrationErrorBusy,
            AppBleConfig.errI2cFault => AppStrings.calibrationErrorI2cFault,
            _ => AppStrings.manikinError,
          };
          _fail(msg);
        }
      case _Stage.running:
        if (metrics.packetType == AppBleConfig.packetRealtime) {
          setState(() => _latest = metrics);
        } else if (metrics.packetType == AppBleConfig.packetFinalSummary) {
          _complete(metrics);
        } else if (metrics.packetType == AppBleConfig.packetError) {
          _fail();
        }
      default:
        break;
    }
  }

  /// Turns the trial summary into the target-entry state.
  void _complete(CprMetrics summary) {
    _stopTimers();
    _trialActive = false;
    unawaited(_restorePracticeDuration());

    if (summary.depthCm <= 0) {
      setState(() {
        _stage = _Stage.error;
        _error = AppStrings.manikinNoCompressions;
      });
      return;
    }

    setState(() {
      _stage = _Stage.enterTarget;
      _meanDepth = summary.depthCm;
      _latest = null;
      _error = null;
    });
  }

  /// Ends a failed or timed-out trial and records the reason.
  void _fail([String? specificError]) {
    _stopTimers();
    if (_trialActive) {
      _trialActive = false;
      unawaited(_abortTrial());
    }
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
    _stopTimers();
    if (_trialActive && _controller != null && _controller!.isConnected) {
      _trialActive = false;
      unawaited(_abortTrial());
    }
    if (_durationChanged && _controller != null && _controller!.isConnected) {
      unawaited(_restorePracticeDuration());
    }
    _target.dispose();
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
      _Stage.ready => AppStrings.manikinStart,
      _Stage.running => AppStrings.manikinTrialRunning,
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
          AppStrings.manikinIntroBody,
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
            height: 1.5,
          ),
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
          AppStrings.manikinBaselineReady,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinBodySize,
            weight: FontWeight.normal,
            color: AppColors.flowHelperText,
            height: 1.5,
          ),
        ),
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
