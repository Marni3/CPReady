/// Baseline calibration step of the practice flow.
///
/// Full-screen (no top header, no bottom nav): a small back arrow beside the
/// title, one large panel holding the CPReady logo and the live calibration
/// status, and two stacked buttons near the bottom — Retry Calibration and
/// Begin Session.
///
/// CALIBRATE is sent when this screen opens — the firmware only starts its
/// baseline window on that command, and reports progress/success as packet
/// types 2 and 3. Retry runs that same command again; Begin Session continues
/// to the countdown, which is what sends START.

import 'dart:async';

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
                    const SizedBox(width: AppSpacing.flowBackTitleGap),
                    Expanded(
                      child: Text(
                        AppStrings.calibrationTitle,
                        style: AppTypography.style(
                          size: AppTypography.flowTitleSize,
                          weight: AppTypography.headingWeight,
                          color: AppColors.flowHeadingText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.flowTitleGap),
                Expanded(
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Align(
                                alignment: AppSpacing.flowCardAlignment,
                                child: FlowPanel(
                                  width: AppSizes.flowCardWidth,
                                  minHeight: AppSizes.flowCardMinHeight,
                                  border: AppColors.flowCardBorder,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Image.asset(
                                        AppAssets.handPlacementGuide,
                                        width: AppSizes.flowHandImageSize,
                                        height: AppSizes.flowHandImageSize,
                                        fit: BoxFit.contain,
                                      ),
                                      const SizedBox(
                                        height: AppSpacing.flowPanelContentGap,
                                      ),
                                      Text(
                                        statusText,
                                        textAlign: TextAlign.center,
                                        style: AppTypography.style(
                                          size: AppTypography
                                              .flowPanelHeadingSize,
                                          weight: AppTypography.headingWeight,
                                          color: AppColors.flowHeadingText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                  ),
                ),
                if (!ready) ...<Widget>[
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    AppStrings.calibrationNotReady,
                    textAlign: TextAlign.center,
                    style: AppTypography.style(
                      size: AppTypography.flowHelperSize,
                      weight: FontWeight.normal,
                      color: AppColors.summaryFailedText,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.section),
                FlatActionButton(
                  label: AppStrings.calibrationRetry,
                  onPressed: () => unawaited(_retryCalibration()),
                ),
                const SizedBox(height: AppSpacing.flowActionStackGap),
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
