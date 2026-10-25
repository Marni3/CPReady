/// Manikin depth calibration.
/// This is separate from the baseline Calibration step: CALIBRATE only zeroes
/// the sensor, while CALIBRATE_TARGET rescales the depth reading so it matches
/// the depth the manikin reports.
/// The trial reuses the firmware's normal session path: SET_TIME is shortened
/// to 15 seconds, CALIBRATE runs the baseline, START begins the trial, and the
/// firmware's own FINAL_SUMMARY supplies the mean depth. The practice duration
/// is restored before the screen is left.
/// The firmware does not acknowledge CALIBRATE_TARGET over BLE, so the last
/// state says the command was sent and asks for a check on the next run rather
/// than claiming the value was stored.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/feedback/metric_feedback.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../widgets/widgets.dart';

enum _Stage { intro, preparing, running, enterTarget, sent, error }

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
    _sub = _controller!.packets.listen(_onPacket);
  }

  // -------------------------------------------------------------------------
  // Trial
  // -------------------------------------------------------------------------

  /// Starts the 15-second manikin depth calibration trial.
  ///
  /// Sends SET_TIME:15 to firmware, then waits for firmware's CALIBRATE completion
  /// (packetCalibrationDone) before beginning the trial. If calibration doesn't
  /// complete within the timeout, shows a specific error rather than the generic
  /// "trial did not finish" message.
  Future<void> _startTrial() async {
    final BleController? controller = _controller;
    if (controller == null) return;

    // If a calibration trial is already in progress, don't start another.
    if (_stage == _Stage.running || _stage == _Stage.enterTarget || _stage == _Stage.sent) {
      return;
    }

    setState(() {
      _stage = _Stage.preparing;
      _error = null;
      _meanDepth = null;
      _latest = null;
      _sending = false;
      _trialRemaining = AppDurations.manikinTrialSeconds;
      _target.clear();
      _targetValid = false;
    });

    // Send SET_TIME to firmware for the 15-second trial duration.
    try {
      await controller.sendCommand(
        AppBleConfig.commandSetTime(AppDurations.manikinTrialSeconds),
      );
      _durationChanged = true;
    } catch (error) {
      debugPrint('Manikin trial SET_TIME failed: $error');
      _fail();
      return;
    }

    // Send CALIBRATE to firmware to begin baseline calibration window.
    // The firmware will respond with packetCalibrationDone when calibration is ready.
    try {
      await controller.sendCommand(AppBleConfig.commandCalibrate);
    } catch (error) {
      debugPrint('Manikin trial CALIBRATE failed: $error');
      _fail();
      return;
    }

    // Wait for firmware's CALIBRATE completion packet. If it doesn't arrive
    // within the calibration timeout, the trial cannot start.
    _calibrationTimeout?.cancel();
    _calibrationTimeout = Timer(Duration(milliseconds: AppDurations.manikinCalibrationTimeoutMs), () {
      if (!mounted) return;
      _fail();
    });

    debugPrint('Manikin trial started: waiting for calibration done (timeout ${AppDurations.manikinCalibrationTimeoutMs}ms)');
  }

  Future<void> _beginTrial() async {
    final BleController? controller = _controller;
    if (controller == null || !mounted || _stage != _Stage.preparing) return;

    // Cancel the calibration timeout since we're beginning the trial.
    _calibrationTimeout?.cancel();
    _calibrationTimeout = null;

    // Guard: refuse to begin the trial if no BLE device is connected.
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
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!mounted || _trialRemaining <= 0) return;
      setState(() => _trialRemaining -= 1);
    });
    _summaryTimeout = Timer(AppDurations.manikinSummaryTimeout, () {
      if (!mounted || _stage != _Stage.running) return;
      _fail();
    });

    try {
      await controller.sendCommand(AppBleConfig.commandStart);
    } catch (error) {
      debugPrint('Manikin trial START failed: $error');
      if (mounted) _fail();
    }
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;

    switch (_stage) {
      case _Stage.preparing:
        if (metrics.packetType == AppBleConfig.packetCalibrationDone) {
          _calibrationTimeout?.cancel();
          _calibrationTimeout = null;
          unawaited(_beginTrial());
        } else if (metrics.packetType == AppBleConfig.packetError) {
          _fail();
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
  void _fail() {
    _stopTimers();
    if (_trialActive) {
      _trialActive = false;
      unawaited(_abortTrial());
    }
    unawaited(_restorePracticeDuration());

    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      // Show specific error based on what failed.
      if (_controller == null || !_controller!.isConnected) {
        _error = AppStrings.manikinNoDeviceConnected;
      } else {
        _error = AppStrings.manikinError;
      }
    });
  }

  Future<void> _abortTrial() async {
    try {
      await _controller?.sendCommand(AppBleConfig.commandStop);
    } catch (error) {
      debugPrint('Manikin trial stop failed: $error');
    }
  }

  /// Sends the target depth; the firmware computes and persists the new scale.
  Future<void> _save() async {
    final BleController? controller = _controller;
    final double? depth = double.tryParse(_target.text.trim());
    if (controller == null || depth == null || !_targetValid || _sending) {
      return;
    }

    setState(() => _sending = true);
    try {
      await controller.sendCommand(AppBleConfig.commandCalibrateTarget(depth));
      if (!mounted) return;
      setState(() {
        _stage = _Stage.sent;
        _sending = false;
      });
    } catch (error) {
      debugPrint('Manikin target send failed: $error');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = AppStrings.manikinSendFailed;
      });
    }
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

  /// Puts the firmware's auto-stop back to the normal practice length.
  Future<void> _restorePracticeDuration() async {
    if (!_durationChanged) return;
    _durationChanged = false;
    try {
      await _controller?.sendCommand(
        AppBleConfig.commandSetTime(AppDurations.practiceSessionSeconds),
      );
    } catch (error) {
      debugPrint('Practice duration restore failed: $error');
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
    _sub?.cancel();
    _stopTimers();
    if (_trialActive) {
      _trialActive = false;
      unawaited(_abortTrial());
    }
    unawaited(_restorePracticeDuration());
    _target.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // UI
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
      _Stage.intro => AppStrings.manikinStart,
      _Stage.preparing => AppStrings.manikinPreparing,
      _Stage.running => AppStrings.manikinTrialRunning,
      _Stage.enterTarget => AppStrings.manikinSave,
      _Stage.sent => AppStrings.manikinDone,
      _Stage.error => AppStrings.manikinRetry,
    };
  }

  VoidCallback? get _action {
    return switch (_stage) {
      _Stage.intro || _Stage.error => () => unawaited(_startTrial()),
      _Stage.enterTarget => _targetValid && !_sending ? _save : null,
      _Stage.sent => () => Navigator.of(context).maybePop(),
      _Stage.preparing || _Stage.running => null,
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
      _Stage.preparing || _Stage.running => _buildTrial(),
      _Stage.enterTarget => _buildTargetEntry(),
      _Stage.sent => _buildSent(),
      _Stage.error => _buildError(),
    };
  }

  Widget _buildIntro() {
    return Text(
      AppStrings.manikinIntroBody,
      style: AppTypography.style(
        size: AppTypography.manikinBodySize,
        weight: FontWeight.normal,
        color: AppColors.flowHelperText,
        height: 1.5,
      ),
    );
  }

  Widget _buildTrial() {
    final bool preparing = _stage == _Stage.preparing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          preparing
              ? AppStrings.manikinPreparing
              : AppStrings.manikinTrialRunning,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.manikinLabelSize,
            weight: FontWeight.bold,
            color: AppColors.flowHeadingText,
          ),
        ),
        if (!preparing) ...<Widget>[
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