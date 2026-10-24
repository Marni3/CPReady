/// Hand-placement step of the practice flow.
///
/// Full-screen (no top header, no bottom nav): a small back arrow beside the
/// title, one large panel holding the illustration and the instruction, and the
/// Begin Session button near the bottom. Continue from here to Calibration.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../widgets/widgets.dart';

/// Hand-placement screen.
class HandPlacementScreen extends StatelessWidget {
  /// Trainee name captured on the setup screen; carried through the flow.
  final String traineeName;

  const HandPlacementScreen({super.key, required this.traineeName});

  void _begin(BuildContext context) {
    context.pushNamed(AppRoutes.calibration, extra: traineeName);
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );
    final TextStyle titleStyle = AppTypography.style(
      size: AppTypography.flowTitleSize,
      weight: AppTypography.headingWeight,
      color: AppColors.flowHeadingText,
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
                Expanded(
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          // The card takes the space the title leaves over. The
                          // title is measured with the style it is painted with,
                          // so the figure is exact; the whole block scrolls if
                          // it still does not fit.
                          final double titleHeight = measureTextHeight(
                            context,
                            AppStrings.handPlacementTitle,
                            titleStyle,
                            maxWidth:
                                constraints.maxWidth -
                                AppSizes.flowBackIconSize -
                                AppSpacing.flowBackTapRight -
                                AppSpacing.flowBackTitleGap,
                          );
                          final double cardSpace = math.max(
                            0.0,
                            constraints.maxHeight -
                                math.max(
                                  titleHeight,
                                  AppSizes.flowBackIconSize +
                                      2 * AppSpacing.flowBackTapV,
                                ) -
                                AppSpacing.flowTitleGap,
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
                                        AppStrings.handPlacementTitle,
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
                                    caption:
                                        AppStrings.handPlacementInstruction,
                                    availableHeight: cardSpace,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                  ),
                ),
                SizedBox(height: AppSpacing.section),
                FlatActionButton(
                  label: AppStrings.handPlacementBegin,
                  onPressed: () => _begin(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
