/// Home entry points for Device Settings and the manikin-profile gate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/ble/kinematic_profile.dart';
import 'package:cpready/src/core/navigation.dart';
import 'package:cpready/src/core/settings/device_settings.dart';
import 'package:cpready/src/screens/home/home_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';

DeviceSettings _settings(KinematicProfile profile) {
  return DeviceSettings(
    profile: profile,
    depthK: profile == KinematicProfile.manikin ? 11.2 : null,
    practiceDurationSec: 120,
    updatedAt: DateTime(2026, 10, 26, 10),
  );
}

Future<FakeSessionRepository> _pumpHome(WidgetTester tester) async {
  final FakeBleController controller = FakeBleController();
  final FakeSessionRepository repository = FakeSessionRepository()
    ..deviceSettings = _settings(KinematicProfile.bench);
  addTearDown(controller.dispose);

  final GoRouter router = buildRouter(
    initialRoute: AppRoutes.home,
    routeBuilder: <String, Widget Function(BuildContext)>{
      AppRoutes.home: (_) => const Scaffold(body: HomeScreen()),
      AppRoutes.deviceSettings: (_) =>
          const Scaffold(body: Text('SETTINGS DESTINATION')),
      AppRoutes.manikinCalibration: (_) =>
          const Scaffold(body: Text('CALIBRATION DESTINATION')),
    },
  );

  await tester.pumpWidget(
    AppScope(
      controller: controller,
      repository: repository,
      voiceCoach: const SilentVoiceCoach(),
      child: MaterialApp.router(
        theme: appThemeData().theme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('Home exposes Device Settings on the connected card', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    expect(find.text(AppStrings.homeDeviceSettings), findsOneWidget);
    expect(find.text(AppStrings.homeManikinCalibration), findsOneWidget);

    await tester.ensureVisible(find.text(AppStrings.homeDeviceSettings));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.homeDeviceSettings));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS DESTINATION'), findsOneWidget);
  });

  testWidgets('header settings button opens Device Settings', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    expect(find.byTooltip(AppStrings.settingsTooltip), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.settingsTooltip));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS DESTINATION'), findsOneWidget);
  });

  testWidgets(
    'bench mode gates manikin calibration and allows it after switch',
    (WidgetTester tester) async {
      final FakeSessionRepository repository = await _pumpHome(tester);

      await tester.ensureVisible(find.text(AppStrings.homeManikinCalibration));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.homeManikinCalibration));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.homeCalibrationRequiresManikinTitle),
        findsOneWidget,
      );
      expect(find.text('CALIBRATION DESTINATION'), findsNothing);

      await tester.tap(find.text(AppStrings.actionCancel));
      await tester.pumpAndSettle();

      await repository.saveDeviceSettings(_settings(KinematicProfile.manikin));
      await tester.tap(find.text(AppStrings.homeManikinCalibration));
      await tester.pumpAndSettle();

      expect(find.text('CALIBRATION DESTINATION'), findsOneWidget);
    },
  );
}
