/// Standard page shell: [Scaffold] + [AppBar] + [SafeArea] + page padding.

import 'package:flutter/material.dart';



/// Wraps a page body in the standard app scaffold with configured page
/// padding and an optional [AppBar] title.
class AppScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final bool automaticallyImplyLeading;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final bool centerTitle;
  final bool resizeToAvoidBottomInset;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.automaticallyImplyLeading = true,
    this.actions,
    this.bottomNavigationBar,
    this.centerTitle = false,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title != null
          ? AppBar(
              title: Text(title!),
              automaticallyImplyLeading: automaticallyImplyLeading,
              centerTitle: centerTitle,
              actions: actions,
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: body,
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}
