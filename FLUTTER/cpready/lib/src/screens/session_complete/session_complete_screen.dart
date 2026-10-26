/// Session Summary: shown when a practice session ends, and reused by the
/// History detail screen for a stored session.
///
/// Full-screen (no top header, no bottom nav) and with no back button — the
/// only exit is Return to Home, which resets the route stack to the tab shell
/// on the Home tab.
///
/// Every visual value comes from `lib/src/config/`; this file only composes
/// widgets.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/feedback/metric_feedback.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../core/tab_state.dart';
import '../../widgets/widgets.dart';

/// Why the result screen is being shown.
enum SessionEndReason {
  /// A usable FINAL_SUMMARY arrived and the session was saved.
  completed,

  /// The BLE link dropped before a summary arrived.
  interrupted,

  /// STOP completed but no usable summary arrived.
  resultsUnavailable,
}

/// Data returned when a results-retrieval retry succeeds.
class SessionResultData {
  /// The reason the results screen should now show.
  final SessionEndReason reason;

  /// The retrieved firmware summary.
  final CprMetrics summary;

  /// False when the retrieved summary could not be written to History.
  final bool historySaved;

  const SessionResultData({
    required this.reason,
    required this.summary,
    required this.historySaved,
  });
}

/// Result screen shown after a session ends.
class SessionCompleteScreen extends StatefulWidget {
  /// Trainee the session is filed under.
  final String traineeName;

  /// Why the session ended.
  final SessionEndReason reason;

  /// Firmware summary; null when no usable summary exists.
  final CprMetrics? summary;

  /// Firmware-reported duration when a summary exists, otherwise the
  /// app-measured span.
  final int durationSeconds;

  /// False when the session could not be written to the History database.
  final bool historySaved;

  /// Optional GET_RESULTS retry used by the results-unavailable state.
  final Future<SessionResultData?> Function()? onRetryRetrieval;

  const SessionCompleteScreen({
    super.key,
    required this.traineeName,
    required this.reason,
    required this.summary,
    required this.durationSeconds,
    this.historySaved = true,
    this.onRetryRetrieval,
  });

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  late SessionEndReason _reason = widget.reason;
  late CprMetrics? _summary = widget.summary;
  late int _durationSeconds = widget.durationSeconds;
  late bool _historySaved = widget.historySaved;
  bool _retrying = false;
  bool _retryFailed = false;

  void _returnToHome(BuildContext context) {
    // Home is tab 0 of the shell; reset to the root and let MainShell open it.
    selectedTabNotifier.value = 0;
    context.go(AppRoutes.home);
  }

  Future<void> _retryRetrieval() async {
    final callback = widget.onRetryRetrieval;
    if (callback == null || _retrying) return;

    setState(() {
      _retrying = true;
      _retryFailed = false;
    });

    SessionResultData? result;
    try {
      result = await callback();
    } catch (error) {
      debugPrint('Results retrieval retry failed: $error');
    }

    if (!mounted) return;
    setState(() {
      _retrying = false;
      if (result == null) {
        _retryFailed = true;
        return;
      }
      _reason = result.reason;
      _summary = result.summary;
      _durationSeconds = result.summary.elapsedSeconds;
      _historySaved = result.historySaved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showRetry =
        _reason == SessionEndReason.resultsUnavailable &&
        widget.onRetryRetrieval != null;

    return PopScope(
      canPop: false, // explicit exit only, never back into the session
      child: AdaptiveScreen(
        padding: EdgeInsets.only(
          top: AppSpacing.summaryTopPadding,
          bottom: AppSpacing.flowActionBottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.summaryTitleInsetH,
                  ),
                  child: Text(
                    AppStrings.sessionSummaryTitle,
                    textAlign: TextAlign.left,
                    style: AppTypography.style(
                      size: AppTypography.summaryTitleSize,
                      weight: AppTypography.headingWeight,
                      color: AppColors.summaryHeadingText,
                    ),
                  ),
                ),
                SizedBox(height: AppSpacing.summaryBannerGap),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.summaryTitleInsetH,
                  ),
                  child: _SavedBanner(
                    reason: _reason,
                    historySaved: _historySaved,
                  ),
                ),
                if (_retryFailed) ...<Widget>[
                  SizedBox(height: AppSpacing.small),
                  Text(
                    AppStrings.sessionRetrievalFailed,
                    textAlign: TextAlign.center,
                    style: AppTypography.style(
                      size: AppTypography.bodySmallSize,
                      weight: FontWeight.normal,
                      color: AppColors.summaryFailedText,
                    ),
                  ),
                ],
                SizedBox(height: AppSpacing.summaryTraineeGap),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.summaryTitleInsetH,
                  ),
                  child: Text(
                    '${AppStrings.sessionTrainee}: ${widget.traineeName}',
                    style: AppTypography.style(
                      size: AppTypography.summaryTraineeSize,
                      weight: AppTypography.headingWeight,
                      color: AppColors.summaryHeadingText,
                    ),
                  ),
                ),
                if (_summary != null) ...<Widget>[
                  if (_summary!.isBenchMode) ...<Widget>[
                    SizedBox(height: AppSpacing.small),
                    const Center(child: BenchBadge()),
                  ],
                  SizedBox(height: AppSpacing.summaryPanelGap),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.summaryPanelInsetH,
                    ),
                    child: _MetricsPanel(
                      metrics: _summary!,
                      durationSeconds: _durationSeconds,
                    ),
                  ),
                ],
              ],
            ),
            Padding(
              padding: EdgeInsets.only(
                top: AppSpacing.summaryActionTopGap,
                left: AppSpacing.summaryActionInsetH,
                right: AppSpacing.summaryActionInsetH,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (showRetry) ...<Widget>[
                    FlatActionButton(
                      label: AppStrings.sessionRetryRetrieval,
                      onPressed: _retrying
                          ? null
                          : () => unawaited(_retryRetrieval()),
                    ),
                    SizedBox(height: AppSpacing.flowActionStackGap),
                  ],
                  FlatActionButton(
                    label: AppStrings.sessionReturnToHome,
                    onPressed: () => _returnToHome(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green "Session Saved" bar, or the red interrupted/unavailable bar.
class _SavedBanner extends StatelessWidget {
  final SessionEndReason reason;
  final bool historySaved;

  const _SavedBanner({required this.reason, required this.historySaved});

  @override
  Widget build(BuildContext context) {
    final bool saved = reason == SessionEndReason.completed;
    final Color background = saved
        ? AppColors.summarySavedBackground
        : AppColors.summaryFailedBackground;
    final Color foreground = saved
        ? AppColors.summarySavedText
        : AppColors.summaryFailedText;
    final bool compact = AppLayout.isCompact(MediaQuery.sizeOf(context).width);

    final String title = switch (reason) {
      SessionEndReason.completed => AppStrings.sessionSaved,
      SessionEndReason.interrupted => AppStrings.sessionInterrupted,
      SessionEndReason.resultsUnavailable =>
        AppStrings.sessionResultsUnavailable,
    };
    final String detail = switch (reason) {
      SessionEndReason.completed => '',
      SessionEndReason.interrupted => AppStrings.sessionInterruptedDetail,
      SessionEndReason.resultsUnavailable =>
        AppStrings.sessionResultsUnavailableDetail,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          constraints: BoxConstraints(
            minHeight: saved ? AppSizes.summarySavedBannerHeight : 0,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.summaryBannerPaddingH,
            vertical: AppSpacing.summaryBannerPaddingV,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSizes.summaryBannerRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: compact
                      ? AppTypography.summaryBannerCompactSize
                      : AppTypography.summaryBannerSize,
                  weight: AppTypography.headingWeight,
                  color: foreground,
                ),
              ),
              if (!saved) ...<Widget>[
                SizedBox(height: AppSpacing.small),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: AppTypography.style(
                    size: AppTypography.bodySmallSize,
                    weight: FontWeight.normal,
                    color: foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (saved && !historySaved) ...<Widget>[
          SizedBox(height: AppSpacing.small),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: AppSizes.iconSmall,
                color: AppColors.summaryFailedText,
              ),
              SizedBox(width: AppSpacing.small),
              Expanded(
                child: Text(
                  AppStrings.sessionHistoryFailed,
                  style: AppTypography.style(
                    size: AppTypography.bodySmallSize,
                    weight: FontWeight.normal,
                    color: AppColors.summaryFailedText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Panel holding the five metric rows and the session duration.
class _MetricsPanel extends StatelessWidget {
  final CprMetrics metrics;
  final int durationSeconds;

  const _MetricsPanel({required this.metrics, required this.durationSeconds});

  Widget _gradedCapsule(String text, MetricRating? rating) {
    return ValueCapsule(
      text: text,
      background: ValueCapsule.gradedBackground(rating),
      foreground: AppColors.liveCapsuleText,
      minHeight: AppSizes.summaryCapsuleHeight,
      radius: AppSizes.summaryCapsuleRadius,
      textSize: AppTypography.summaryCapsuleSize,
      minWidth: AppSizes.summaryCapsuleWidth,
    );
  }

  Widget _valueCapsule(String text) {
    return ValueCapsule(
      text: text,
      background: AppColors.summaryCapsuleBackground,
      foreground: AppColors.summaryCapsuleText,
      minHeight: AppSizes.summaryCapsuleHeight,
      radius: AppSizes.summaryCapsuleRadius,
      textSize: AppTypography.summaryCapsuleSize,
      textWeight: AppTypography.headingWeight,
      minWidth: AppSizes.summaryCapsuleWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlowPanel(
      background: AppColors.summaryPanelBackground,
      border: AppColors.summaryPanelBorder,
      radius: AppSizes.summaryPanelRadius,
      borderWidth: AppSizes.summaryPanelBorderWidth,
      padding: EdgeInsets.symmetric(
        horizontal: AppLayout.isCompact(MediaQuery.sizeOf(context).width)
            ? AppSpacing.summaryPanelPaddingHCompact
            : AppSpacing.summaryPanelPaddingH,
        vertical: AppSpacing.summaryPanelPaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MetricRow(
            label: AppStrings.sessionRecoil,
            capsule: _gradedCapsule(
              recoilText(metrics.recoilPercentage),
              recoilRating(metrics.recoilPercentage),
            ),
          ),
          SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionRate,
            capsule: _gradedCapsule(
              rateText(metrics.rateCpm),
              rateRating(metrics.rateCpm),
            ),
          ),
          SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionDepth,
            capsule: _gradedCapsule(
              depthText(metrics.depthCm),
              depthRating(metrics.depthCm),
            ),
          ),
          SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionCcf,
            capsule: _valueCapsule(percentText(metrics.ccfPercent)),
          ),
          SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionCompressions,
            capsule: _valueCapsule('${metrics.totalCompressions}'),
          ),
          SizedBox(height: AppSpacing.summaryDurationGap),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.summaryRowPaddingH,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    AppStrings.sessionDuration,
                    style: AppTypography.style(
                      size: AppTypography.summaryDurationLabelSize,
                      weight: AppTypography.headingWeight,
                      color: AppColors.summaryRowLabelText,
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.summaryRowGap),
                Text(
                  durationText(durationSeconds),
                  style: AppTypography.style(
                    size: AppTypography.summaryDurationLabelSize,
                    weight: AppTypography.headingWeight,
                    color: AppColors.summaryRowLabelText,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.summaryDurationBottomPadding),
        ],
      ),
    );
  }
}

/// One white row with a black edge: label on the left, value capsule on the
/// right.
class _MetricRow extends StatelessWidget {
  final String label;
  final Widget capsule;

  const _MetricRow({required this.label, required this.capsule});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: AppSizes.summaryRowMinHeight),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.summaryRowPaddingH,
        vertical: AppSpacing.tiny,
      ),
      decoration: BoxDecoration(
        color: AppColors.summaryRowBackground,
        borderRadius: BorderRadius.circular(AppSizes.summaryRowRadius),
        border: Border.all(
          color: AppColors.summaryRowBorder,
          width: AppSizes.summaryRowBorderWidth,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AppTypography.style(
                size: AppTypography.summaryRowLabelSize,
                weight: FontWeight.bold,
                color: AppColors.summaryRowLabelText,
              ),
            ),
          ),
          SizedBox(width: AppSpacing.summaryRowGap),
          capsule,
        ],
      ),
    );
  }
}
