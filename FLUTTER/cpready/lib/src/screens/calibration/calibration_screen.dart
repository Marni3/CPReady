/// Baseline calibration step of the practice flow.
///
/// Full-screen (no top header, no bottom nav): a small back arrow beside the
/// title, one large panel holding the CPReady logo and the live calibration
/// status, and the action buttons near the bottom. "Begin Session" is always
/// present; "Retry Calibration" appears only after a failed attempt.
///
/// CALIBRATE is sent when this screen opens — the firmware only starts its
/// baseline window on that command, and reports progress/success as packet
/// types 2 and 3. Retry runs that same command again; Begin Session continues
/// to the countdown, which is what sends START.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../widgets/widgets.dart';

/// Baseline calibration screen.
class CalibrationScreen extends StatefulWidget {
  /// Trainee name captured on the setup screen; carried through the flow.
  final String traineeName;

  const CalibrationScreen({super.key, required this.traineeName});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

enum _CalibrationState { waiting, calibrating, ready, error }

class _CalibrationScreenState extends State<CalibrationScreen> {
  StreamSubscription<CprMetrics>? _sub;
  _CalibrationState _state = _CalibrationState.waiting;
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    unawaited(_startCalibration());
  }

  Future<void> _startCalibration() async {
    final controller = AppScope.of(context);

    await _sub?.cancel();
    _sub = controller.packets.listen(_onPacket);

    try {
      await controller.sendCommand(AppBleConfig.commandCalibrate);
    } catch (error) {
      debugPrint('Calibration start failed: $error');
      if (mounted) {
        setState(() => _state = _CalibrationState.error);
      }
    }
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;
    switch (metrics.packetType) {
      case AppBleConfig.packetCalibrating:
        setState(() => _state = _CalibrationState.calibrating);
      case AppBleConfig.packetCalibrationDone:
        setState(() => _state = _CalibrationState.ready);
      case AppBleConfig.packetError:
        setState(() => _state = _CalibrationState.error);
      default:
        break; // realtime packets are not calibration events
    }
  }

  /// Runs the calibration handshake again, from the top.
  Future<void> _retryCalibration() async {
    if (!mounted) return;
    setState(() => _state = _CalibrationState.waiting);
    await _startCalibration();
  }

  void _beginSession() {
    if (_state != _CalibrationState.ready) return;
    context.pushNamed(AppRoutes.beginCompression, extra: widget.traineeName);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = _state == _CalibrationState.ready;
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    final String statusText = switch (_state) {
      _CalibrationState.waiting => AppStrings.calibrationWaiting,
      _CalibrationState.calibrating => AppStrings.calibrationCalibrating,
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
    final String? helper = ready ? null : AppStrings.calibrationNotReady;

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
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          // The card takes the space the title and the helper
                          // line leave over. Both are measured with the styles
                          // they are painted with; the whole block scrolls if it
                          // still does not fit.
                          final double titleHeight = measureTextHeight(
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    const FlowBackButton(),
                                    SizedBox(
                                      width: AppSpacing.flowBackTitleGap,
                                    ),
                                    Expanded(
                                      child: Text(
                                        AppStrings.calibrationTitle,
                                        style: titleStyle,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: AppSpacing.flowTitleGap),
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
                                  SizedBox(height: AppSpacing.small),
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
                    onPressed: () => unawaited(_retryCalibration()),
                  ),
                  SizedBox(height: AppSpacing.flowActionStackGap),
                ],
                FlatActionButton(
                  label: AppStrings.calibrationBeginSession,
                  onPressed: ready ? _beginSession : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
