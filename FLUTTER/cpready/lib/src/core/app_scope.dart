/// Simple InheritedWidget exposing the app-level [BleController] and the
/// History [SessionRepository].
///
/// Moved from lib/main.dart. Both objects are owned by [CpReadyApp] and
/// provided down the widget tree via [AppScope].

import 'package:flutter/material.dart';

import 'ble/ble_controller.dart';
import 'history/session_repository.dart';

/// AppScope exposes the shared [BleController] and [SessionRepository] to
/// descendants.
class AppScope extends InheritedWidget {
  final BleController controller;
  final SessionRepository repository;

  const AppScope({
    super.key,
    required this.controller,
    required this.repository,
    required super.child,
  });

  static AppScope _scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  static BleController of(BuildContext context) => _scopeOf(context).controller;

  /// The History store — the single writer for saved practice sessions.
  static SessionRepository history(BuildContext context) =>
      _scopeOf(context).repository;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      controller != oldWidget.controller || repository != oldWidget.repository;
}
