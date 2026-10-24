/// Hand-placement step of the practice flow.
///
/// Full-screen (no top header, no bottom nav): a small back arrow beside the
/// title, one large panel holding the illustration and the instruction, and the
/// Begin Session button near the bottom. Continue from here to Calibration.

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
                        AppStrings.handPlacementTitle,
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
                                        AppStrings.handPlacementInstruction,
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
                const SizedBox(height: AppSpacing.section),
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
