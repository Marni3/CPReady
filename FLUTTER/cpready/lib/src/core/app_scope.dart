/// Simple InheritedWidget exposing the app-level [BleController], the History
/// [SessionRepository] and the [VoiceCoach].
///
/// Moved from lib/main.dart. All three objects are owned by [CpReadyApp] and
/// provided down the widget tree via [AppScope].

import 'package:flutter/material.dart';

import 'audio/voice_coach.dart';
import 'ble/ble_controller.dart';
import 'history/session_repository.dart';

/// AppScope exposes the shared app services to descendants.
class AppScope extends InheritedWidget {
  final BleController controller;
  final SessionRepository repository;
  final VoiceCoach voiceCoach;

  const AppScope({
    super.key,
    required this.controller,
    required this.repository,
    required this.voiceCoach,
    required super.child,
  });

  static AppScope _scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  static BleController of(BuildContext context) => _scopeOf(context).controller;

  /// The History store — the single writer for saved practice sessions.
  static SessionRepository history(BuildContext context) =>
      _scopeOf(context).repository;

  /// The coach that speaks the firmware's cue codes.
  static VoiceCoach voice(BuildContext context) => _scopeOf(context).voiceCoach;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      controller != oldWidget.controller ||
      repository != oldWidget.repository ||
      voiceCoach != oldWidget.voiceCoach;
}
