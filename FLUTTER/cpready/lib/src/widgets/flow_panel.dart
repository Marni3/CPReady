/// Large instructional panel: a soft blue fill inside a thin grey edge.
///
/// Used by the flow screens (Hand Placement, Calibration) and by the Session
/// Summary, which overrides the fill and edge from config.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Rounded panel used to group the flow screens' main content.
class FlowPanel extends StatelessWidget {
  const FlowPanel({
    super.key,
    required this.child,
    this.padding,
    this.background,
    this.border,
    this.radius,
    this.borderWidth,
    this.width = double.infinity,
    this.minHeight,
  });

  /// Panel content.
  final Widget child;

  /// Panel width. Defaults to full width; pass a fixed width (the flow cards)
  /// or null to let the panel hug its content.
  final double? width;

  /// Minimum panel height. Defaults to hugging the content; the flow cards pass
  /// a floor so both cards share a size and still grow if their text wraps.
  final double? minHeight;

  /// Inner padding; defaults to [AppSpacing.flowPanelPadding].
  final EdgeInsetsGeometry? padding;

  /// Fill; defaults to [AppColors.flowPanelBackground].
  final Color? background;

  /// Edge color; defaults to [AppColors.flowPanelBorder].
  final Color? border;

  /// Corner radius; defaults to [AppSizes.flowPanelRadius].
  final double? radius;

  /// Edge thickness; defaults to [AppSizes.flowPanelBorderWidth].
  final double? borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: minHeight == null
          ? null
          : BoxConstraints(minHeight: minHeight!),
      padding: padding ?? const EdgeInsets.all(AppSpacing.flowPanelPadding),
      decoration: BoxDecoration(
        color: background ?? AppColors.flowPanelBackground,
        borderRadius: BorderRadius.circular(radius ?? AppSizes.flowPanelRadius),
        border: Border.all(
          color: border ?? AppColors.flowPanelBorder,
          width: borderWidth ?? AppSizes.flowPanelBorderWidth,
        ),
      ),
      child: child,
    );
  }
}
