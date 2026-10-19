/// Tab 2 — Practice: choose between the step-by-step guide and a practice run.
///
/// Mirrors Home's chrome (the shared [ScreenHeader] on top and the shared
/// bottom nav underneath), with a big blue "Practice" heading, a slim dotted
/// "Choose an option below." box, and two gradient option cards.
///
/// Every visual value comes from `lib/src/config/`; this file only composes
/// widgets.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../widgets/widgets.dart';

/// Practice tab screen.
class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          ScreenHeader(pageLabel: AppStrings.practiceHeaderPage),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.page,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: AppSpacing.practiceTopPadding),
                    Text(
                      AppStrings.practiceTitle,
                      style: AppTypography.style(
                        size: AppTypography.practiceTitleSize,
                        weight: AppTypography.headingWeight,
                        color: AppColors.practiceTitleText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.practiceTitleGap),
                    const _ChooseOptionBox(),
                    const SizedBox(height: AppSpacing.practiceOptionTopGap),
                    PracticeOptionCard(
                      title: AppStrings.practiceGuide,
                      body: AppStrings.practiceGuideBody,
                      iconAsset: AppAssets.iconBook,
                      onTap: () => context.pushNamed(AppRoutes.guide),
                    ),
                    const SizedBox(height: AppSpacing.practiceOptionGap),
                    PracticeOptionCard(
                      title: AppStrings.practiceStart,
                      body: AppStrings.practiceStartBody,
                      iconAsset: AppAssets.iconHeartbeat,
                      onTap: () => context.pushNamed(AppRoutes.setup),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim dotted-outline box holding the bold "Choose an option below." prompt.
class _ChooseOptionBox extends StatelessWidget {
  const _ChooseOptionBox();

  @override
  Widget build(BuildContext context) {
    return DottedBorder(
      color: AppColors.practiceDottedBorder,
      strokeWidth: AppSizes.practiceDottedThickness,
      radius: AppSizes.practiceDottedRadius,
      dash: AppSizes.practiceDottedDash,
      gap: AppSizes.practiceDottedGap,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.practiceDottedPaddingV,
        horizontal: AppSpacing.practiceDottedPaddingH,
      ),
      child: Text(
        AppStrings.practiceSubtitle,
        textAlign: TextAlign.left,
        style: AppTypography.style(
          size: AppTypography.practiceOptionSubtitleSize,
          weight: FontWeight.bold,
          color: AppColors.practiceTitleText,
        ),
      ),
    );
  }
}

/// Gradient-filled option card: the logo sits on the left, with the bold title
/// and its non-bold supporting text filling the rest of the card.
///
/// The guide card opens the Step-by-step Guide; the "Start practice" card opens
/// the practice flow (Practice Setup first).
class PracticeOptionCard extends StatelessWidget {
  const PracticeOptionCard({
    super.key,
    required this.title,
    required this.body,
    required this.iconAsset,
    this.onTap,
  });

  /// Bold title line.
  final String title;

  /// Non-bold supporting line under [title].
  final String body;

  /// Logo shown on the left (see `AppAssets`); tinted white.
  final String iconAsset;

  /// Tap handler; the card is inert when null.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.brandVertical,
        borderRadius: BorderRadius.circular(AppSizes.practiceCardRadius),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.practiceOptionPaddingH,
        vertical: AppSpacing.practiceOptionPaddingV,
      ),
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(
              left:
                  AppSpacing.practiceOptionIconGap +
                  AppSizes.practiceOptionIconWidth,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTypography.style(
                      size: AppTypography.practiceOptionTitleSize,
                      weight: FontWeight.bold,
                      color: AppColors.practiceOptionText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    body,
                    style: AppTypography.style(
                      size: AppTypography.practiceOptionBodySize,
                      weight: FontWeight.normal,
                      color: AppColors.practiceOptionText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The logo spans the full height of the text block beside it.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: AppSizes.practiceOptionIconWidth,
            child: FittedBox(
              fit: BoxFit.contain,
              child: AppAssetIcon(
                asset: iconAsset,
                color: AppColors.practiceOptionText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
