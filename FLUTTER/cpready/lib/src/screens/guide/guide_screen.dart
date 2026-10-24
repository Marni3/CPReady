/// Step-by-step CPR guide, opened from the Practice tab.
///
/// Full-screen: there is no top bar and no bottom nav — just a small
/// transparent back button, the blue title, and eight numbered step cards.
/// The back button and title stay pinned while the step cards scroll, so the
/// cards always hug their own text instead of being squeezed to fit.
///
/// Every visual value comes from `lib/src/config/`; this file only composes
/// widgets.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../widgets/widgets.dart';

/// Step-by-step guide screen.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

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
              top: AppSpacing.guideTopPadding,
              bottom: AppSpacing.item,
              left: page,
              right: page,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const GuideBackButton(),
                    const SizedBox(width: AppSpacing.guideBackTitleGap),
                    Expanded(
                      child: Text(
                        AppStrings.guideTitle,
                        style: AppTypography.style(
                          size: AppTypography.guideTitleSize,
                          weight: AppTypography.headingWeight,
                          color: AppColors.guideTitleText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.guideTitleGap),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.guideCardSideInset,
                    ),
                    itemCount: AppGuideSteps.steps.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.guideStepGap),
                    itemBuilder: (_, int index) => GuideStepCard(
                      number: index + 1,
                      step: AppGuideSteps.steps[index],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small, transparent back button: just the arrow, sitting on the same line as
/// the title. Tapping it returns to the screen that opened the guide (Practice).
class GuideBackButton extends StatelessWidget {
  const GuideBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.pop(),
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.only(
          top: AppSpacing.guideBackTapV,
          bottom: AppSpacing.guideBackTapV,
          right: AppSpacing.guideBackTapRight,
        ),
        child: Icon(
          Icons.arrow_back,
          size: AppSizes.guideBackIconSize,
          color: AppColors.guideBackIcon,
        ),
      ),
    );
  }
}

/// One numbered step: a red circle with the number, then the sentence with its
/// opening phrase in bold. Height follows the amount of text.
class GuideStepCard extends StatelessWidget {
  const GuideStepCard({super.key, required this.number, required this.step});

  /// 1-based step number shown in the circle.
  final int number;

  /// Copy for this step.
  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.guideStepPaddingH,
        vertical: AppSpacing.guideStepPaddingV,
      ),
      decoration: BoxDecoration(
        color: AppColors.guideStepCardBackground,
        borderRadius: BorderRadius.circular(AppSizes.guideStepCardRadius),
        border: Border.all(
          color: AppColors.guideStepCardBorder,
          width: AppSizes.guideStepCardBorderWidth,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: AppSizes.guideNumberCircleSize,
            height: AppSizes.guideNumberCircleSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.guideStepNumberBackground,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppTypography.style(
                size: AppTypography.guideNumberSize,
                weight: FontWeight.bold,
                color: AppColors.guideStepNumberText,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.guideNumberGap),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: step.lead,
                    style: AppTypography.style(
                      size: AppTypography.guideStepSize,
                      weight: FontWeight.bold,
                      color: AppColors.guideStepText,
                    ),
                  ),
                  TextSpan(
                    text: step.body,
                    style: AppTypography.style(
                      size: AppTypography.guideStepSize,
                      weight: FontWeight.normal,
                      color: AppColors.guideStepText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
