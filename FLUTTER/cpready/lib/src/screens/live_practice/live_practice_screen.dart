/// Active CPR session: live metrics and the press-and-hold End Session control.
///
/// Full-screen (no top header, no bottom nav) and with no back button. A
/// session ends in three ways: the hold completes and STOP is sent, the
/// firmware sends its own FINAL_SUMMARY (it auto-stops once its configured
/// session time elapses), or the BLE link drops. A drop abandons the session —
/// nothing is saved and the app returns to Home with a notice.
///
/// Every visual value comes from `lib/src/config/`; this file only composes
/// widgets.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/feedback/metric_feedback.dart';
import '../../core/history/history_revision.dart';
import '../../core/history/session_record.dart';
import '../../core/history/session_repository.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../widgets/widgets.dart';
import '../session_complete/session_complete_screen.dart';

/// Live practice screen.
class LivePracticeScreen extends StatefulWidget {
  /// Trainee name captured on the setup screen; filed with the session.
  final String traineeName;

  const LivePracticeScreen({super.key, required this.traineeName});

  @override
  State<LivePracticeScreen> createState() => _LivePracticeScreenState();
}

class _LivePracticeScreenState extends State<LivePracticeScreen> {
  BleController? _controller;
  SessionRepository? _repository;
  bool _initialized = false;

  StreamSubscription<CprMetrics>? _packetSub;
  Timer? _tick;

  CprMetrics? _latest;
  int? _lastCount;
  DateTime? _lastCompressionAt;
  bool _ending = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final controller = AppScope.of(context);
    _controller = controller;
    _repository = AppScope.history(context);

    controller.startRecording();
    controller.addListener(_onControllerChanged);
    _packetSub = controller.packets.listen(_onPacket);

    // Keeps the elapsed timer and the compression-activity window current.
    _tick = Timer.periodic(AppDurations.liveTick, (_) {
      if (mounted && !_finished) {
        setState(() {});
      }
    });
  }

  /// True while compressions are still being counted, so the counter circle
  /// reads as active rather than idle.
  bool get _compressing {
    final DateTime? at = _lastCompressionAt;
    final int count = _latest?.totalCompressions ?? 0;
    if (at == null || count <= 0) return false;
    return DateTime.now().difference(at) <= AppDurations.compressionActiveWindow;
  }

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;
    final int count = metrics.totalCompressions;
    setState(() {
      _latest = metrics;
      if (_lastCount == null || count > _lastCount!) {
        _lastCompressionAt = DateTime.now();
      }
      _lastCount = count;
    });

    // Firmware auto-stop: a FINAL_SUMMARY arrives without us asking.
    if (metrics.packetType == AppBleConfig.packetFinalSummary &&
        !_ending &&
        !_finished) {
      unawaited(_finish(saved: true, summary: metrics));
    }
  }

  void _onControllerChanged() {
    if (!mounted || _finished) return;
    if (_controller?.status != BleStatus.error) return;

    // Unexpected BLE disconnect mid-session: the session is abandoned rather
    // than continued — nothing is saved, no summary is shown — and the
    // link-lost notice returns to Home.
    _finished = true;
    _tick?.cancel();
    _controller?.stopRecording();
    unawaited(abortFlowToHome(context));
  }

  Future<void> _endSession() async {
    if (_ending || _finished) return;
    final controller = _controller;
    if (controller == null) return;

    setState(() => _ending = true);

    // Listen for FINAL_SUMMARY before/while sending STOP.
    final summaryFuture = controller.packets
        .where((m) => m.packetType == AppBleConfig.packetFinalSummary)
        .first
        .then<CprMetrics?>((m) => m)
        .timeout(AppDurations.finalSummaryTimeout, onTimeout: () => null);

    try {
      await controller.sendCommand(AppBleConfig.commandStop);
    } catch (_) {
      // Connection may already be gone; the timeout below decides.
    }

    final summary = await summaryFuture;

    if (!mounted || _finished) return;
    await _finish(saved: summary != null, summary: summary);
  }

  Future<void> _finish({
    required bool saved,
    required CprMetrics? summary,
  }) async {
    if (_finished) return;
    _finished = true;

    final controller = _controller;
    _packetSub?.cancel();
    _tick?.cancel();
    controller?.removeListener(_onControllerChanged);

    if (!mounted || controller == null) return;

    final int recorded = controller.stopRecording().length;
    final DateTime startedAt = controller.sessionStartedAt ?? DateTime.now();
    final DateTime endedAt = controller.sessionEndedAt ?? DateTime.now();

    // Firmware duration when a summary exists, else the app-measured span.
    final int durationSeconds = summary != null
        ? summary.elapsedSeconds
        : endedAt.difference(startedAt).inSeconds;

    // Persist before the result screen, so a saved row always exists when the
    // result is shown.
    final bool historySaved = await _persistSession(
      controller,
      summary,
      recorded,
      startedAt,
      endedAt,
      durationSeconds,
    );

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionCompleteScreen(
          traineeName: widget.traineeName,
          saved: saved,
          summary: summary,
          durationSeconds: durationSeconds,
          historySaved: historySaved,
        ),
      ),
    );
  }

  /// Writes the finished session to History.
  ///
  /// Returns false when the write failed, so the result screen can say the
  /// session was not stored. Never throws.
  Future<bool> _persistSession(
    BleController controller,
    CprMetrics? summary,
    int packets,
    DateTime startedAt,
    DateTime endedAt,
    int durationSeconds,
  ) async {
    final repository = _repository;
    if (repository == null) return false;

    final bool completed = summary != null;

    final record = SessionRecord(
      traineeName: widget.traineeName,
      status: completed ? SessionStatus.completed : SessionStatus.interrupted,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      packetCount: packets,
      rateCpm: summary?.rateCpm,
      depthTenthsMm:
          summary == null ? null : (summary.depthCm * 100).round(),
      recoilPercent: summary?.recoilPercentage,
      ccfPercent: summary?.ccfPercent,
      totalCompressions: summary?.totalCompressions,
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
    _packetSub?.cancel();
    _tick?.cancel();
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  Widget _capsule(String text, MetricRating? rating) {
    return ValueCapsule(
      text: text,
      background: ValueCapsule.gradedBackground(rating),
      foreground: AppColors.liveCapsuleText,
      height: AppSizes.liveCapsuleHeight,
      radius: AppSizes.liveCapsuleRadius,
      textSize: AppTypography.liveCapsuleSize,
      textWeight: AppTypography.headingWeight,
      width: AppSizes.liveCapsuleWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final latest = _latest;

    return PopScope(
      canPop: false, // sessions end only through the hold or the firmware
      child: Scaffold(
        backgroundColor: AppColors.surfaceScaffold,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.flowTopPadding,
              bottom: AppSpacing.flowActionBottomPadding,
              left: AppSpacing.page,
              right: AppSpacing.page,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (controller != null) _StatusHeader(controller: controller),
                const SizedBox(height: AppSpacing.liveTimerTopGap),
                _TimerBlock(startedAt: controller?.sessionStartedAt),
                const SizedBox(height: AppSpacing.liveSectionTopGap),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            const SizedBox(width: AppSpacing.liveSectionGap),
                            Expanded(
                              child: _MetricSection(
                                label: AppStrings.liveRecoilLabel,
                                capsule: _capsule(
                                  recoilText(latest?.recoilPercentage),
                                  recoilRating(latest?.recoilPercentage),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.liveSectionStackGap),
                        _MetricSection(
                          label: AppStrings.liveDepthLabel,
                          capsule: _capsule(
                            depthText(latest?.depthCm),
                            depthRating(latest?.depthCm),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.liveSectionStackGap),
                        Center(
                          child: _CompressionCounter(
                            count: latest?.totalCompressions ?? 0,
                            active: _compressing,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.liveSectionStackGap),
                HoldFillButton(
                  label: AppStrings.liveHoldEndSession,
                  duration: AppDurations.holdSession,
                  enabled: !_ending,
                  onComplete: _endSession,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Title plus live connection status, both indented past the rest of the
/// content.
class _StatusHeader extends StatelessWidget {
  final BleController controller;

  const _StatusHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.liveHeaderInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AppStrings.livePracticeTitle,
            style: AppTypography.style(
              size: AppTypography.liveTitleSize,
              weight: AppTypography.headingWeight,
              color: AppColors.liveLabelText,
            ),
          ),
          const SizedBox(height: AppSpacing.liveStatusGap),
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
        final (String label, Color color, bool up) = switch (controller.status) {
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
            const SizedBox(width: AppSpacing.small),
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

/// Centred elapsed timer and its caption.
class _TimerBlock extends StatelessWidget {
  final DateTime? startedAt;

  const _TimerBlock({required this.startedAt});

  @override
  Widget build(BuildContext context) {
    final int raw = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt!).inSeconds;
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
        const SizedBox(height: AppSpacing.liveTimerLabelGap),
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
      height: AppSizes.liveSectionHeight,
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
          const SizedBox(height: AppSpacing.liveSectionLabelGap),
          Padding(
            padding: const EdgeInsets.symmetric(
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
    return Container(
      width: AppSizes.liveCounterWidth,
      height: AppSizes.liveCounterHeight,
      decoration: BoxDecoration(
        color: AppColors.liveSectionBackground,
        borderRadius: BorderRadius.circular(AppSizes.liveSectionRadius),
        border: Border.all(
          color: AppColors.liveSectionBorder,
          width: AppSizes.liveSectionBorderWidth,
        ),
      ),
      child: Center(
        child: Container(
          width: AppSizes.liveCounterCircleSize,
          height: AppSizes.liveCounterCircleSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                active ? AppColors.liveCounterActive : AppColors.liveCounterIdle,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$count',
                style: AppTypography.style(
                  size: AppTypography.liveCounterSize,
                  weight: AppTypography.headingWeight,
                  color: AppColors.liveCounterText,
                ),
              ),
              Text(
                AppStrings.liveCompressionsLabel,
                style: AppTypography.style(
                  size: AppTypography.liveCounterLabelSize,
                  weight: FontWeight.normal,
                  color: AppColors.liveCounterText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
