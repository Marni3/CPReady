/// Session Summary: shown when a practice session ends, and reused by the
/// History detail screen for a stored session.
///
/// Full-screen (no top header, no bottom nav) and with no back button — the
/// only exit is Return to Home, which resets the route stack to the tab shell
/// on the Home tab.
///
/// Every visual value comes from `lib/src/config/`; this file only composes
/// widgets.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/feedback/metric_feedback.dart';
import '../../core/metrics/cpr_metrics.dart';
import '../../core/tab_state.dart';
import '../../widgets/widgets.dart';

/// Result screen shown after a session ends.
class SessionCompleteScreen extends StatelessWidget {
  /// Trainee the session is filed under.
  final String traineeName;

  /// True when the firmware's FINAL_SUMMARY arrived.
  final bool saved;

  /// Firmware summary; null when the session was interrupted.
  final CprMetrics? summary;

  /// Firmware-reported duration when a summary exists, otherwise the
  /// app-measured span.
  final int durationSeconds;

  /// False when the session could not be written to the History database.
  final bool historySaved;

  const SessionCompleteScreen({
    super.key,
    required this.traineeName,
    required this.saved,
    required this.summary,
    required this.durationSeconds,
    this.historySaved = true,
  });

  void _returnToHome(BuildContext context) {
    // Home is tab 0 of the shell; reset to the root and let MainShell open it.
    selectedTabNotifier.value = 0;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // explicit exit only, never back into the session
      child: AdaptiveScreen(
        padding: const EdgeInsets.only(
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
                  padding: const EdgeInsets.symmetric(
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
                const SizedBox(height: AppSpacing.summaryBannerGap),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.summaryTitleInsetH,
                  ),
                  child: _SavedBanner(saved: saved, historySaved: historySaved),
                ),
                const SizedBox(height: AppSpacing.summaryTraineeGap),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.summaryTitleInsetH,
                  ),
                  child: Text(
                    '${AppStrings.sessionTrainee}: $traineeName',
                    style: AppTypography.style(
                      size: AppTypography.summaryTraineeSize,
                      weight: AppTypography.headingWeight,
                      color: AppColors.summaryHeadingText,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.summaryPanelGap),
                if (summary != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.summaryPanelInsetH,
                    ),
                    child: _MetricsPanel(
                      metrics: summary!,
                      durationSeconds: durationSeconds,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.summaryActionTopGap,
                left: AppSpacing.summaryActionInsetH,
                right: AppSpacing.summaryActionInsetH,
              ),
              child: FlatActionButton(
                label: AppStrings.sessionReturnToHome,
                onPressed: () => _returnToHome(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green "Session Saved" bar, or the red interrupted bar plus the
/// history-write warning.
class _SavedBanner extends StatelessWidget {
  final bool saved;
  final bool historySaved;

  const _SavedBanner({required this.saved, required this.historySaved});

  @override
  Widget build(BuildContext context) {
    final Color background = saved
        ? AppColors.summarySavedBackground
        : AppColors.summaryFailedBackground;
    final Color foreground = saved
        ? AppColors.summarySavedText
        : AppColors.summaryFailedText;
    final bool compact = AppLayout.isCompact(MediaQuery.sizeOf(context).width);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          constraints: BoxConstraints(
            minHeight: saved ? AppSizes.summarySavedBannerHeight : 0,
          ),
          padding: const EdgeInsets.symmetric(
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
                saved ? AppStrings.sessionSaved : AppStrings.sessionInterrupted,
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
                const SizedBox(height: AppSpacing.small),
                Text(
                  AppStrings.sessionInterruptedDetail,
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
        if (!historySaved) ...<Widget>[
          const SizedBox(height: AppSpacing.small),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.warning_amber_rounded,
                size: AppSizes.iconSmall,
                color: AppColors.summaryFailedText,
              ),
              const SizedBox(width: AppSpacing.small),
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
      height: AppSizes.summaryCapsuleHeight,
      radius: AppSizes.summaryCapsuleRadius,
      textSize: AppTypography.summaryCapsuleSize,
      width: AppSizes.summaryCapsuleWidth,
    );
  }

  Widget _valueCapsule(String text) {
    return ValueCapsule(
      text: text,
      background: AppColors.summaryCapsuleBackground,
      foreground: AppColors.summaryCapsuleText,
      height: AppSizes.summaryCapsuleHeight,
      radius: AppSizes.summaryCapsuleRadius,
      textSize: AppTypography.summaryCapsuleSize,
      textWeight: AppTypography.headingWeight,
      width: AppSizes.summaryCapsuleWidth,
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
          const SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionRate,
            capsule: _gradedCapsule(
              rateText(metrics.rateCpm),
              rateRating(metrics.rateCpm),
            ),
          ),
          const SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionDepth,
            capsule: _gradedCapsule(
              depthText(metrics.depthCm),
              depthRating(metrics.depthCm),
            ),
          ),
          const SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionCcf,
            capsule: _valueCapsule(percentText(metrics.ccfPercent)),
          ),
          const SizedBox(height: AppSpacing.summaryRowGap),
          _MetricRow(
            label: AppStrings.sessionCompressions,
            capsule: _valueCapsule('${metrics.totalCompressions}'),
          ),
          const SizedBox(height: AppSpacing.summaryDurationGap),
          Padding(
            padding: const EdgeInsets.symmetric(
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
                const SizedBox(width: AppSpacing.summaryRowGap),
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
          const SizedBox(height: AppSpacing.summaryDurationBottomPadding),
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
      constraints: const BoxConstraints(
        minHeight: AppSizes.summaryRowMinHeight,
      ),
      padding: const EdgeInsets.symmetric(
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.style(
                size: AppTypography.summaryRowLabelSize,
                weight: FontWeight.bold,
                color: AppColors.summaryRowLabelText,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.summaryRowGap),
          capsule,
        ],
      ),
    );
  }
}
