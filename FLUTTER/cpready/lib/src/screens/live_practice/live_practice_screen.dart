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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/audio/voice_coach.dart';
import '../../core/audio/voice_cue_gate.dart';
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
  VoiceCoach? _coach;
  bool _initialized = false;

  StreamSubscription<CprMetrics>? _packetSub;
  Timer? _tick;
  Timer? _startWatchdog;

  CprMetrics? _latest;
  int? _lastCount;
  DateTime? _lastCompressionAt;
  bool _ending = false;
  bool _finished = false;

  /// Consecutive real-time packets that reported an unsteady rhythm.
  int _unsteadyPackets = 0;

  /// True once the run above lasted long enough to show the warning.
  bool _cadenceWarning = false;

  /// Voice cues are on by default; the header toggle mutes them per session.
  bool _muted = false;

  /// Duplicate and overlap guard for the firmware's cue codes.
  final VoiceCueGate _cueGate = VoiceCueGate();

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

    controller.startRecording();
    controller.addListener(_onControllerChanged);
    _packetSub = controller.packets.listen(_onPacket);

    // START is accepted only after calibration. If the device rejects it or the
    // first notification never arrives, surface the failure instead of showing
    // an apparently live session full of zeros forever.
    _startWatchdog = Timer(AppDurations.startWatchdog, _onStartTimeout);

    // Keeps the elapsed timer and the compression-activity window current.
    _tick = Timer.periodic(AppDurations.liveTick, (_) {
      if (mounted && !_finished) {
        setState(() {});
      }
    });
  }

  void _onStartTimeout() {
    if (!mounted || _finished || _latest != null) return;
    _stopSessionInternals();
    _controller?.stopRecording();
    _controller?.resetSessionData();
    _finished = true;
    unawaited(_showStartFailure());
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
      context.go(AppRoutes.calibration, extra: widget.traineeName);
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _stopSessionInternals() {
    _packetSub?.cancel();
    _packetSub = null;
    _tick?.cancel();
    _tick = null;
    _startWatchdog?.cancel();
    _startWatchdog = null;
    _controller?.removeListener(_onControllerChanged);
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

  void _onPacket(CprMetrics metrics) {
    if (!mounted) return;
    final int count = metrics.totalCompressions;

    // The first stroke and the packet after a pause also report unsteady
    // cadence; only a sustained run should raise the banner.
    final bool realtime = metrics.packetType == AppBleConfig.packetRealtime;
    if (realtime) {
      _startWatchdog?.cancel();
      _startWatchdog = null;
      final bool unsteady = !metrics.isSteadyCadence && !metrics.isFirstStroke;
      _unsteadyPackets = unsteady ? _unsteadyPackets + 1 : 0;
    }

    setState(() {
      _latest = metrics;
      if (_lastCount == null || count > _lastCount!) {
        _lastCompressionAt = DateTime.now();
      }
      _lastCount = count;
      if (realtime) {
        _cadenceWarning =
            _unsteadyPackets >= AppDurations.liveCadenceWarningPackets;
      }
    });

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

    // The firmware already throttles and prioritizes its prompts; play the cue
    // it asked for unless the session is ending or the user muted the voice.
    if (metrics.packetType == AppBleConfig.packetRealtime &&
        !_muted &&
        !_ending &&
        !_finished &&
        _cueGate.allows(metrics.audioPromptCode)) {
      unawaited(_coach?.play(metrics.audioPromptCode));
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) unawaited(_coach?.stop());
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

    final DateTime startedAt = controller.sessionStartedAt ?? DateTime.now();
    final int recorded = controller.stopRecording().length;
    final DateTime endedAt = controller.sessionEndedAt ?? DateTime.now();

    // A completed result must carry a usable summary. A zero-compression STOP
    // is an accidental early end, not a session worth saving.
    SessionEndReason finalReason = reason;
    if (finalReason == SessionEndReason.completed &&
        (summary == null || summary.totalCompressions <= 0)) {
      finalReason = SessionEndReason.resultsUnavailable;
    }
    final CprMetrics? finalSummary = finalReason == SessionEndReason.completed
        ? summary
        : null;

    // Firmware duration when a summary exists, else the app-measured span.
    final int durationSeconds = finalSummary != null
        ? finalSummary.elapsedSeconds
        : endedAt.difference(startedAt).inSeconds;

    bool historySaved = true;
    if (finalReason == SessionEndReason.completed) {
      historySaved = await _persistSession(
        controller,
        finalSummary!,
        recorded,
        startedAt,
        endedAt,
        durationSeconds,
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
          historySaved: historySaved,
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

    final summary = await _requestResults(controller);
    if (summary == null || summary.totalCompressions <= 0) return null;

    final DateTime startedAt = controller.sessionStartedAt ?? DateTime.now();
    final DateTime endedAt = controller.sessionEndedAt ?? DateTime.now();
    final bool historySaved = await _persistSession(
      controller,
      summary,
      controller.sessionPackets.length,
      startedAt,
      endedAt,
      summary.elapsedSeconds,
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
  ) async {
    final repository = _repository;
    if (repository == null) return false;

    final record = SessionRecord(
      traineeName: widget.traineeName,
      status: SessionStatus.completed,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      packetCount: packets,
      rateCpm: summary.rateCpm,
      depthTenthsMm: (summary.depthCm * 100).round(),
      recoilPercent: summary.recoilPercentage,
      ccfPercent: summary.ccfPercent,
      totalCompressions: summary.totalCompressions,
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
                            ),
                          SizedBox(height: AppSpacing.liveTimerTopGap),
                          _TimerBlock(startedAt: controller?.sessionStartedAt),
                          if (latest?.isBenchMode ?? false) ...<Widget>[
                            SizedBox(height: AppSpacing.liveBenchBadgeTopGap),
                            const Center(child: BenchBadge()),
                          ],
                          if (_cadenceWarning) ...<Widget>[
                            SizedBox(height: AppSpacing.liveNoticeTopGap),
                            const _CadenceWarning(),
                          ],
                          SizedBox(height: AppSpacing.liveSectionTopGap),
                          LayoutBuilder(
                            builder:
                                (BuildContext context, BoxConstraints bounds) {
                                  final Widget rate = _MetricSection(
                                    label: AppStrings.liveRateLabel,
                                    capsule: _capsule(
                                      rateText(latest?.rateCpm),
                                      rateRating(latest?.rateCpm),
                                    ),
                                  );
                                  final Widget recoil = _MetricSection(
                                    label: AppStrings.liveRecoilLabel,
                                    capsule: _capsule(
                                      recoilText(latest?.recoilPercentage),
                                      recoilRating(latest?.recoilPercentage),
                                    ),
                                  );
                                  final double each =
                                      (bounds.maxWidth -
                                          AppSpacing.liveSectionGap) /
                                      2;

                                  if (each < AppLayout.minSectionWidth) {
                                    return Column(
                                      children: <Widget>[
                                        rate,
                                        SizedBox(
                                          height:
                                              AppSpacing.liveSectionStackGap,
                                        ),
                                        recoil,
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: <Widget>[
                                      Expanded(child: rate),
                                      SizedBox(
                                        width: AppSpacing.liveSectionGap,
                                      ),
                                      Expanded(child: recoil),
                                    ],
                                  );
                                },
                          ),
                          SizedBox(height: AppSpacing.liveSectionStackGap),
                          _MetricSection(
                            label: AppStrings.liveDepthLabel,
                            capsule: _capsule(
                              depthText(latest?.depthCm),
                              depthRating(latest?.depthCm),
                            ),
                          ),
                          SizedBox(height: AppSpacing.liveSectionStackGap),
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
                  SizedBox(height: AppSpacing.liveSectionStackGap),
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

  const _StatusHeader({
    required this.controller,
    required this.muted,
    required this.onToggleMute,
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
                child: Text(
                  AppStrings.livePracticeTitle,
                  style: AppTypography.style(
                    size: AppTypography.liveTitleSize,
                    weight: AppTypography.headingWeight,
                    color: AppColors.liveLabelText,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: muted
                    ? AppStrings.liveUnmuteCues
                    : AppStrings.liveMuteCues,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleMute,
                  child: SizedBox(
                    width: AppSizes.liveMuteTapSize,
                    height: AppSizes.liveMuteTapSize,
                    child: Icon(
                      muted ? Icons.volume_off : Icons.volume_up,
                      size: AppSizes.liveMuteIconSize,
                      color: AppColors.liveLabelText,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
