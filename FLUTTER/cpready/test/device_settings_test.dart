/// Device Settings: local fallback, Type 6 read-back, edits and reset.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/ble/device_config.dart';
import 'package:cpready/src/core/ble/kinematic_profile.dart';
import 'package:cpready/src/core/settings/device_settings.dart';
import 'package:cpready/src/screens/device_settings/device_settings_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/src/widgets/profile_selector.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';

DeviceSettings _settings({
  KinematicProfile profile = KinematicProfile.manikin,
  double? depthK,
  int duration = 120,
}) {
  return DeviceSettings(
    profile: profile,
    depthK: depthK,
    practiceDurationSec: duration,
    updatedAt: DateTime(2026, 10, 26, 10),
  );
}

DeviceConfig _config({
  KinematicProfile profile = KinematicProfile.manikin,
  double depthK = 11.2,
  int duration = 120,
}) {
  return DeviceConfig(
    profile: profile,
    depthK: depthK,
    configFlags: profile == KinematicProfile.bench
        ? AppBleConfig.configFlagBenchActive
        : 0,
    practiceDurationSeconds: duration,
    defaultDurationSeconds: AppDeviceSettings.defaultPracticeDurationSec,
    protocolVersion: AppBleConfig.configProtocolVersion,
  );
}

class _Fixture {
  _Fixture({
    DeviceSettings? initial,
    DeviceConfig? report,
    bool connected = true,
  }) {
    controller = FakeBleController(connected: connected)..configReport = report;
    repository = FakeSessionRepository()..deviceSettings = initial;
  }

  late final FakeBleController controller;
  late final FakeSessionRepository repository;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        repository: repository,
        voiceCoach: const SilentVoiceCoach(),
        child: MaterialApp(
          theme: appThemeData().theme,
          home: const DeviceSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    controller.dispose();
  }
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  DeviceSettings? initial,
  DeviceConfig? report,
  bool connected = true,
}) async {
  final _Fixture fixture = _Fixture(
    initial: initial,
    report: report,
    connected: connected,
  );
  addTearDown(fixture.dispose);
  await fixture.pump(tester);
  return fixture;
}

Finder _profileOption(String label) {
  return find.descendant(
    of: find.byType(ProfileSelector),
    matching: find.text(label),
  );
}

void main() {
  test('last known settings round-trip through their row map', () {
    final DeviceSettings settings = _settings(
      profile: KinematicProfile.bench,
      depthK: 13.24,
    );
    final DeviceSettings loaded = DeviceSettings.fromMap(settings.toMap());

    expect(loaded.profile, KinematicProfile.bench);
    expect(loaded.depthK, 13.24);
    expect(loaded.practiceDurationSec, 120);
    expect(loaded.updatedAt.toUtc(), settings.updatedAt.toUtc());
  });

  test('damaged saved settings are rejected', () {
    final Map<String, Object?> map = <String, Object?>{
      AppDeviceSettings.columnProfile: 'unknown',
      AppDeviceSettings.columnDepthK: null,
      AppDeviceSettings.columnPracticeDurationSec: 120,
      AppDeviceSettings.columnUpdatedAt: DateTime(2026).toIso8601String(),
    };

    expect(() => DeviceSettings.fromMap(map), throwsA(isA<FormatException>()));

    map[AppDeviceSettings.columnProfile] = KinematicProfile.manikin.name;
    map[AppDeviceSettings.columnDepthK] = 0.5;
    expect(() => DeviceSettings.fromMap(map), throwsA(isA<FormatException>()));
  });

  testWidgets('unsupported firmware keeps the local values visible', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _fixture(
      tester,
      initial: _settings(profile: KinematicProfile.bench, depthK: 12.34),
    );

    expect(
      fixture.controller.commands,
      contains(AppBleConfig.commandGetConfig),
    );
    expect(find.text(AppStrings.deviceSettingsUnsupported), findsOneWidget);
    expect(find.text('12.34'), findsWidgets);
    expect(find.text(AppStrings.deviceSettingsSourceLocal), findsOneWidget);
    expect(find.text(AppStrings.setupProfileBench), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Type 6 read-back replaces the local fallback', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _fixture(
      tester,
      initial: _settings(profile: KinematicProfile.bench, depthK: 13),
      report: _config(profile: KinematicProfile.manikin, depthK: 11.2),
    );

    expect(find.text(AppStrings.deviceSettingsReadBack), findsOneWidget);
    expect(find.text(AppStrings.deviceSettingsSourceDevice), findsOneWidget);
    expect(find.text(AppStrings.setupProfileManikin), findsNWidgets(2));
    expect(find.text('11.20'), findsWidgets);
    expect(
      fixture.repository.deviceSettings?.profile,
      KinematicProfile.manikin,
    );
    expect(fixture.repository.deviceSettings?.depthK, 11.2);
  });

  testWidgets('SET_K validates the range before writing', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _fixture(
      tester,
      initial: _settings(depthK: 11.2),
    );

    await tester.enterText(find.byType(TextField), '0.5');
    await tester.ensureVisible(find.text(AppStrings.deviceSettingsKSet));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.deviceSettingsKSet));
    await tester.pump();

    expect(find.text(AppStrings.deviceSettingsKInvalid), findsOneWidget);
    expect(
      fixture.controller.commands.where(
        (String command) => command.startsWith('SET_K:'),
      ),
      isEmpty,
    );

    await tester.enterText(find.byType(TextField), '13.2');
    await tester.ensureVisible(find.text(AppStrings.deviceSettingsKSet));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.deviceSettingsKSet));
    await tester.pumpAndSettle();

    expect(fixture.controller.commands, contains('SET_K:13.20'));
    expect(fixture.repository.deviceSettings?.depthK, 13.2);
    expect(find.text(AppStrings.deviceSettingsKSent), findsOneWidget);
    expect(find.text(AppStrings.deviceSettingsSourceLocal), findsOneWidget);
  });

  testWidgets('profile changes require confirmation and clear K', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _fixture(
      tester,
      initial: _settings(depthK: 11.2),
    );

    await tester.ensureVisible(_profileOption(AppStrings.setupProfileBench));
    await tester.pumpAndSettle();
    await tester.tap(_profileOption(AppStrings.setupProfileBench));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profileSwitchWarningTitle), findsOneWidget);
    expect(fixture.controller.commands, isNot(contains('SET_PROFILE:BENCH')));

    await tester.tap(find.text(AppStrings.profileSwitchConfirm));
    await tester.pumpAndSettle();

    expect(fixture.controller.commands, contains('SET_PROFILE:BENCH'));
    expect(fixture.repository.deviceSettings?.profile, KinematicProfile.bench);
    expect(fixture.repository.deviceSettings?.depthK, isNull);
    expect(find.text(AppStrings.profileSwitchResetNotice), findsOneWidget);

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('factory reset is hold-to-confirm and restores defaults', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _fixture(
      tester,
      initial: _settings(profile: KinematicProfile.bench, depthK: 14),
    );

    await tester.ensureVisible(find.text(AppStrings.deviceSettingsResetHold));
    await tester.pumpAndSettle();
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text(AppStrings.deviceSettingsResetHold)),
    );
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(fixture.controller.commands, contains('RESET_CONFIG'));
    expect(
      fixture.repository.deviceSettings?.profile,
      KinematicProfile.manikin,
    );
    expect(fixture.repository.deviceSettings?.depthK, isNull);
    expect(
      fixture.repository.deviceSettings?.practiceDurationSec,
      AppDeviceSettings.defaultPracticeDurationSec,
    );
    expect(find.text(AppStrings.deviceSettingsResetDone), findsOneWidget);

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('reconnect refreshes the configuration again', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _fixture(
      tester,
      initial: _settings(depthK: 11.2),
    );

    expect(
      fixture.controller.commands
          .where((String command) => command == AppBleConfig.commandGetConfig)
          .length,
      1,
    );

    fixture.controller.disconnectForTest();
    await tester.pump();
    expect(find.text(AppStrings.deviceSettingsOffline), findsOneWidget);

    fixture.controller.configReport = _config(depthK: 12.5);
    fixture.controller.reconnectForTest();
    await tester.pumpAndSettle();

    expect(
      fixture.controller.commands
          .where((String command) => command == AppBleConfig.commandGetConfig)
          .length,
      2,
    );
    expect(find.text(AppStrings.deviceSettingsReadBack), findsOneWidget);
    expect(fixture.repository.deviceSettings?.depthK, 12.5);
  });
}
