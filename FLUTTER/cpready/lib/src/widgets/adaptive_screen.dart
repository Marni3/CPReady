/// Full-screen body that fills the viewport when its content fits and scrolls
/// when it does not.
///
/// Screens built on this widget never overflow: the content gets the viewport
/// height as a minimum, so `SpaceBetween`/`SpaceEvenly` and centred layouts
/// still work on tall screens, while a short screen (or a larger text scale)
/// scrolls instead of overflowing.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Scroll-safe screen body with the app's content-width bound.
class AdaptiveScreen extends StatelessWidget {
  const AdaptiveScreen({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.background,
    this.maxContentWidth = AppLayout.contentMaxWidth,
  });

  /// Screen content, normally a [Column].
  final Widget child;

  /// Padding between the safe area and [child].
  final EdgeInsets padding;

  /// Page background; defaults to the scaffold surface.
  final Color? background;

  /// Widest the content column may get; extra width becomes side margin.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background ?? AppColors.surfaceScaffold,
      body: SafeArea(
        child: ContentBounds(
          maxWidth: maxContentWidth,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SingleChildScrollView(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - padding.vertical).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: child,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Caps the content width and centres it, so a wide screen gains side margin
/// instead of stretched cards and very long text lines.
class ContentBounds extends StatelessWidget {
  const ContentBounds({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
