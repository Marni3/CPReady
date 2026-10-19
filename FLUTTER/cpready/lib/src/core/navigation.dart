/// GoRouter navigation: named routes derived from [AppRoutes] config.
///
/// Screens navigate via [AppRoutes.*] names rather than raw paths.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/config.dart';

/// Builds the [GoRouter] from configured route names and screen builders.
///
/// [routeBuilder] maps a route name to its Widget builder. Screens should
/// register themselves here when created.
GoRouter buildRouter({
  required Map<String, Widget Function(BuildContext)> routeBuilder,
  required String initialRoute,
}) {
  return GoRouter(
    initialLocation: initialRoute,
    routes: AppRoutes.all
        .where((name) => routeBuilder.containsKey(name))
        .map((name) {
          return GoRoute(
            path: name,
            name: name,
            builder: (context, state) => routeBuilder[name]!(context),
          );
        }).toList(),
  );
}
