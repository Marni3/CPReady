/// Illustration card shared by Hand Placement and Calibration.
///
/// The card keeps its designed size while the middle of the screen is tall
/// enough. When the available height, the screen width or the system text size
/// leaves less room, the illustration shrinks first — down to
/// [AppSizes.flowHandImageMinSize] — and the caption keeps its full size. If
/// even the caption alone is taller than the space available, the card grows
/// past the viewport and the screen scrolls it, so nothing is ever cropped.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/config.dart';
import 'flow_panel.dart';
import 'text_metrics.dart';

/// Panel with the hand-placement illustration and one caption line.
class FlowIllustrationCard extends StatelessWidget {
  const FlowIllustrationCard({
    super.key,
    required this.caption,
    required this.availableHeight,
  });

  /// Text under the illustration.
  final String caption;

  /// Height of the region the card should fit into.
  final double availableHeight;

  @override
  Widget build(BuildContext context) {
    final TextStyle captionStyle = AppTypography.style(
      size: AppTypography.flowPanelHeadingSize,
      weight: AppTypography.headingWeight,
      color: AppColors.flowHeadingText,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = math.min(
          AppSizes.flowCardWidth,
          constraints.maxWidth,
        );
        final double innerWidth = math.max(
          0.0,
          width -
              2 * AppSpacing.flowPanelPadding -
              2 * AppSizes.flowPanelBorderWidth,
        );
        final double captionHeight = measureTextHeight(
          context,
          caption,
          captionStyle,
          maxWidth: innerWidth,
        );

        // Panel padding plus the caption, with no room for the illustration.
        final double textBlock =
            2 * AppSpacing.flowPanelPadding +
            2 * AppSizes.flowPanelBorderWidth +
            captionHeight;

        // The card aims for its designed height but keeps room for at least a
        // small illustration; it only exceeds the region when the caption
        // alone does not fit.
        final double designHeight = math.min(
          AppSizes.flowCardMinHeight,
          availableHeight,
        );
        final double height = math.max(
          designHeight,
          textBlock +
              AppSpacing.flowPanelContentGap +
              AppSizes.flowHandImageMinSize,
        );

        final double image = math
            .min(
              AppSizes.flowHandImageSize,
              height - textBlock - AppSpacing.flowPanelContentGap,
            )
            .clamp(0.0, AppSizes.flowHandImageSize);

        return Align(
          alignment: AppSpacing.flowCardAlignment,
          child: SizedBox(
            width: width,
            height: height,
            child: FlowPanel(
              border: AppColors.flowCardBorder,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (image > 0) ...<Widget>[
                    SizedBox.square(
                      dimension: image,
                      child: Image.asset(
                        AppAssets.handPlacementGuide,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: AppSpacing.flowPanelContentGap),
                  ],
                  Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: captionStyle,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
