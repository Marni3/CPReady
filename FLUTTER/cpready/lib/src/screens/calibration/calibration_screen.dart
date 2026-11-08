
/// Baseline calibration screen.
///
/// Sends CALIBRATE when opened and waits for the ESP32 to confirm
/// calibration success. An animated ellipsis indicates progress.
/// On success, briefly displays Baseline Ready and automatically
/// navigates to Live Practice.
///
/// Retry remains available when calibration fails.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../core/practice_session_args.dart';
import '../../widgets/widgets.dart';

class CalibrationScreen extends StatefulWidget {
  final String traineeName;
  final int practiceDurationSec;

  const CalibrationScreen({
    super.key,
    required this.traineeName,
    required this.practiceDurationSec,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

enum _CalibrationState { waiting, calibrating, ready, error }

class _CalibrationScreenState extends State<CalibrationScreen> {
  BleController? _controller;
  StreamSubscription<CprMetrics>? _sub;

  Timer? _timeout;
  Timer? _successTransition;
  Timer? _dotsTimer;

  _CalibrationState _state = _CalibrationState.waiting;

  String? _errorText;

  bool _entered = false;
  bool _navigated = false;

  int _dotCount = 1;

  bool get _isCalibrating =>
      _state == _CalibrationState.waiting ||
      _state == _CalibrationState.calibrating;

  void _startDotsAnimation() {
    _dotsTimer?.cancel();
    _dotCount = 1;

    _dotsTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (timer) {
        if (!mounted || !_isCalibrating) {
          timer.cancel();
          return;
        }

        setState(() {
          _dotCount = (_dotCount % 3) + 1;
        });
      },
    );
  }

  void _stopDotsAnimation() {
    _dotsTimer?.cancel();
    _dotsTimer = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final controller = AppScope.of(context);

    if (_controller != controller) {
      _controller?.removeListener(_onConnectionChanged);
      _controller = controller;
      _controller?.addListener(_onConnectionChanged);
    }

    if (_entered) return;

    _entered = true;
    unawaited(_startCalibration());
  }

  void _onConnectionChanged() {
    if (!mounted) return;

    final controller = _controller;

    if (controller == null || !controller.isConnected) {
      if (_state == _CalibrationState.error) return;

      _timeout?.cancel();
      _successTransition?.cancel();
      _stopDotsAnimation();

      setState(() {
        _state = _CalibrationState.error;
        _errorText = AppStrings.calibrationErrorDisconnected;
      });
    }
  }

  Future<void> _startCalibration() async {
    final controller = _controller ?? AppScope.of(context);

    await _sub?.cancel();

    _timeout?.cancel();
    _successTransition?.cancel();
    _stopDotsAnimation();

    if (!mounted) return;

    if (!controller.isConnected) {
      setState(() {
        _state = _CalibrationState.error;
        _errorText = AppStrings.calibrationErrorDisconnected;
      });
      return;
    }

    setState(() {
      _state = _CalibrationState.waiting;
      _errorText = null;
      _dotCount = 1;
    });

    _startDotsAnimation();

    _sub = controller.packets.listen(_onPacket);

    _timeout = Timer(
      AppDurations.calibrationTimeout,
      () {
        if (!mounted ||
            _state == _CalibrationState.ready ||
            _state == _CalibrationState.error) {
          return;
        }

        _stopDotsAnimation();

        setState(() {
          _state = _CalibrationState.error;
          _errorText = AppStrings.calibrationTimeout;
        });
      },
    );

    try {
      await controller.sendCommand(
        AppBleConfig.commandCalibrate,
      );
    } catch (error) {
      debugPrint('Calibration start failed: $error');

      _timeout?.cancel();
      _stopDotsAnimation();

      if (mounted && _state != _CalibrationState.ready) {
        setState(() {
          _state = _CalibrationState.error;
          _errorText = error is TimeoutException
              ? AppStrings.commandWriteTimeout
              : AppStrings.calibrationStartFailed;
        });
      }
    }
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;

    switch (metrics.packetType) {
      case AppBleConfig.packetCalibrating:
        if (_state == _CalibrationState.waiting ||
            _state == _CalibrationState.calibrating) {
          setState(() {
            _state = _CalibrationState.calibrating;
          });
        }
        break;

      case AppBleConfig.packetCalibrationDone:
        if (_state == _CalibrationState.ready ||
            _state == _CalibrationState.error ||
            _navigated) {
          break;
        }

        _timeout?.cancel();
        _successTransition?.cancel();
        _stopDotsAnimation();

        setState(() {
          _state = _CalibrationState.ready;
        });

        _successTransition = Timer(
          const Duration(milliseconds: 800),
          () {
            if (!mounted || _navigated) return;
            if (_state != _CalibrationState.ready) return;
            if (_controller?.isConnected != true) return;

            _navigated = true;

            context.pushNamed(
              AppRoutes.livePractice,
              extra: PracticeSessionArgs(
                traineeName: widget.traineeName,
                practiceDurationSec: widget.practiceDurationSec,
              ),
            );
          },
        );
        break;

      case AppBleConfig.packetError:
        _timeout?.cancel();
        _successTransition?.cancel();
        _stopDotsAnimation();

        String msg;

        switch (metrics.errorCode) {
          case AppBleConfig.errMotionUnstable:
            msg = AppStrings.calibrationErrorUnstable;
            break;

          case AppBleConfig.errLowSampleCount:
            msg = AppStrings.calibrationErrorLowSamples;
            break;

          case AppBleConfig.errGravityImplausible:
            msg = AppStrings.calibrationErrorGravity;
            break;

          case AppBleConfig.errSensorAlignment:
            msg = AppStrings.calibrationErrorAlignment;
            break;

          case AppBleConfig.errWrongState:
            msg = AppStrings.calibrationErrorBusy;
            break;

          case AppBleConfig.errI2cFault:
            msg = AppStrings.calibrationErrorI2cFault;
            break;

          default:
            msg = AppStrings.calibrationRejected;
            break;
        }

        setState(() {
          _state = _CalibrationState.error;
          _errorText = msg;
        });
        break;

      default:
        break;
    }
  }

  Future<void> _retryCalibration() async {
    if (!mounted) return;

    await _startCalibration();
  }

  @override
  void dispose() {
    _stopDotsAnimation();
    _successTransition?.cancel();
    _timeout?.cancel();

    _controller?.removeListener(_onConnectionChanged);
    _sub?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = _state == _CalibrationState.ready;

    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    final String calibrationLabel =
        AppStrings.calibrationCalibrating
            .replaceFirst(RegExp(r'\.*\s*$'), '');

    final String statusText = switch (_state) {
      _CalibrationState.waiting =>
        '$calibrationLabel${'.' * _dotCount}',
      _CalibrationState.calibrating =>
        '$calibrationLabel${'.' * _dotCount}',
      _CalibrationState.ready => AppStrings.calibrationReady,
      _CalibrationState.error => AppStrings.calibrationError,
    };

    final TextStyle titleStyle = AppTypography.style(
      size: AppTypography.flowTitleSize,
      weight: AppTypography.headingWeight,
      color: AppColors.flowHeadingText,
    );

    final TextStyle helperStyle = AppTypography.style(
      size: AppTypography.flowHelperSize,
      weight: FontWeight.normal,
      color: AppColors.summaryFailedText,
    );

    final String? helper = ready
        ? null
        : _state == _CalibrationState.error
            ? (_errorText ?? AppStrings.calibrationError)
            : AppStrings.calibrationNotReady;

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
                Expanded(
                  child: LayoutBuilder(
                    builder: (
                      BuildContext context,
                      BoxConstraints constraints,
                    ) {
                      final double titleHeight =
                          measureTextHeight(
                        context,
                        AppStrings.calibrationTitle,
                        titleStyle,
                        maxWidth:
                            constraints.maxWidth -
                            AppSizes.flowBackIconSize -
                            AppSpacing.flowBackTapRight -
                            AppSpacing.flowBackTitleGap,
                      );

                      final double helperHeight = helper == null
                          ? 0
                          : AppSpacing.small +
                              measureTextHeight(
                                context,
                                helper,
                                helperStyle,
                                maxWidth: constraints.maxWidth,
                              );

                      final double cardSpace = math.max(
                        0.0,
                        constraints.maxHeight -
                            math.max(
                              titleHeight,
                              AppSizes.flowBackIconSize +
                                  2 * AppSpacing.flowBackTapV,
                            ) -
                            AppSpacing.flowTitleGap -
                            helperHeight,
                      );

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.center,
                              children: <Widget>[
                                const FlowBackButton(),
                                SizedBox(
                                  width:
                                      AppSpacing.flowBackTitleGap,
                                ),
                                Expanded(
                                  child: Text(
                                    AppStrings.calibrationTitle,
                                    style: titleStyle,
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(
                              height: AppSpacing.flowTitleGap,
                            ),

                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: cardSpace,
                              ),
                              child: FlowIllustrationCard(
                                caption: statusText,
                                availableHeight: cardSpace,
                              ),
                            ),

                            if (helper != null) ...<Widget>[
                              SizedBox(
                                height: AppSpacing.small,
                              ),
                              Text(
                                helper,
                                textAlign: TextAlign.center,
                                style: helperStyle,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),

                SizedBox(height: AppSpacing.section),

                if (_state == _CalibrationState.error) ...<Widget>[
                  FlatActionButton(
                    label: AppStrings.calibrationRetry,
                    onPressed: () =>
                        unawaited(_retryCalibration()),
                  ),
                  SizedBox(
                    height: AppSpacing.flowActionStackGap,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
