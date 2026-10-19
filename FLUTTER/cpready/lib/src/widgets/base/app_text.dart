/// A [Text] widget styled from [AppTypography] config.
///
/// Preferred over raw [Text] so font/size/weight changes live in config.

import 'package:flutter/material.dart';



/// Text styled via config typography.
class AppText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;

  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}

/// Convenience: body text.
class AppBodyText extends StatelessWidget {
  final String data;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppBodyText(
    this.data, {
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return AppText(
      data,
      style: Theme.of(context).textTheme.bodyMedium,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Convenience: small body text.
class AppBodySmallText extends StatelessWidget {
  final String data;
  final TextAlign? textAlign;
  final Color? color;

  const AppBodySmallText(
    this.data, {
    super.key,
    this.textAlign,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppText(
      data,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: color),
      textAlign: textAlign,
    );
  }
}

/// Convenience: title/heading text.
class AppTitleText extends StatelessWidget {
  final String data;
  final TextAlign? textAlign;

  const AppTitleText(
    this.data, {
    super.key,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return AppText(
      data,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: textAlign,
    );
  }
}
