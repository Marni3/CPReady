/// Text measurement helpers.
///
/// A few layouts have to know how large a text will be before they place it:
/// the illustration card reserves room for its caption, the compression counter
/// sizes its circle, the history row decides whether the name still fits beside
/// the badges, and the practice cards share one height. Measuring with the same
/// style the text itself will use keeps those decisions exact instead of
/// guessing from the character count.

import 'package:flutter/material.dart';

/// Height of [text] laid out in [style] within [maxWidth].
double measureTextHeight(
  BuildContext context,
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: _effectiveStyle(context, style)),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);
  final double height = painter.height;
  painter.dispose();
  return height;
}

/// Width of [text] laid out on a single line in [style].
double measureTextWidth(BuildContext context, String text, TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: _effectiveStyle(context, style)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

/// The style a [Text] actually paints with: an inherited style picks up the
/// line height and letter spacing of the ambient default first, so measuring
/// the raw style alone would miss the ambient line height.
TextStyle _effectiveStyle(BuildContext context, TextStyle style) =>
    style.inherit ? DefaultTextStyle.of(context).style.merge(style) : style;
