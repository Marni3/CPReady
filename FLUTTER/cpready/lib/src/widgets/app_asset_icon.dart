/// A PNG glyph (from `assets/images/`) rendered as a tinted icon.
///
/// The source artwork is a single-color shape with transparency, so it is
/// recolored with [BlendMode.srcIn]: the alpha is kept and every opaque pixel
/// takes [color]. That lets one asset serve both the selected and unselected
/// bottom-nav states, and the white-on-gradient option cards.

import 'package:flutter/material.dart';

class AppAssetIcon extends StatelessWidget {
  const AppAssetIcon({
    super.key,
    required this.asset,
    this.size,
    this.color,
  });

  /// Asset path (see `AppAssets`).
  final String asset;

  /// Rendered box size; omit to use the artwork's intrinsic size.
  final double? size;

  /// Tint applied to the artwork's opaque pixels.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}
