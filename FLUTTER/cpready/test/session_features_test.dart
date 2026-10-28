/// Widget coverage for the training-mode selector and the live voice toggle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/ble/ble_controller.dart';
import 'package:cpready/src/core/ble/kinematic_profile.dart';
import 'package:cpready/src/core/history/session_repository.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/core/settings/device_settings.dart';
import 'package:cpready/src/screens/live_practice/live_practice_screen.dart';
import 'package:cpready/src/screens/setup/practice_setup_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/src/widgets/profile_selector.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';

/// History is not what these tests exercise, so the database is never opened.
class _FailingDatabaseFactory implements DatabaseFactory {
  const _FailingDatabaseFactory();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('History storage is out of scope for these tests');
  }
}

Widget _harness(
  Widget screen,
  BleController controller, {
  SessionRepository? repository,
}) {
  return AppScope(
    controller: controller,
    repository:
        repository ??
        SessionRepository(
          factory: const _FailingDatabaseFactory(),
          databasePath: 'session-features-test.db',
        ),
    voiceCoach: const SilentVoiceCoach(),
    child: MaterialApp(theme: appThemeData().theme, home: screen),
  );
}

CprMetrics _packet({int qualityFlags = 0, int totalCompressions = 1}) {
  return CprMetrics(
    packetType: AppBleConfig.packetRealtime,
    recoilComplete: false,
    recoilPercentage: 90,
    rateCpm: 110,
    depthCm: 5.0,
    depthMm: 50,
    ccfPercent: 90,
    audioPromptCode: 0,
    totalCompressions: totalCompressions,
    elapsedSeconds: 1,
    qualityFlags: qualityFlags,
  );
}

void main() {
  testWidgets('setup offers both training modes', (WidgetTester tester) async {
    final BleController controller = BleController();
    await tester.pumpWidget(_harness(const PracticeSetupScreen(), controller));
    await tester.pump();

    expect(find.text(AppStrings.setupTrainingMode), findsOneWidget);
    expect(find.text(AppStrings.setupProfileManikin), findsOneWidget);
    expect(find.text(AppStrings.setupProfileBench), findsOneWidget);
    expect(find.text(AppStrings.setupProfileSendFailed), findsNothing);

    // Each profile has its own K, so the app confirms before switching.
    await tester.tap(find.text(AppStrings.setupProfileBench));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.profileSwitchWarningTitle), findsOneWidget);

    // No device is connected in this test, so the write fails and the failed
    // mode is rolled back instead of being shown as applied.
    await tester.tap(find.text(AppStrings.profileSwitchConfirm));
    await tester.pump();
    await tester.pump();

    expect(find.text(AppStrings.setupProfileSendFailed), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('setup restores the last known profile from local settings', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = FakeBleController();
    final FakeSessionRepository repository = FakeSessionRepository()
      ..deviceSettings = DeviceSettings(
        profile: KinematicProfile.bench,
        depthK: 14.0,
        practiceDurationSec: 120,
        updatedAt: DateTime(2026, 10, 26, 10),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(const PracticeSetupScreen(), controller, repository: repository),
    );
    await tester.pumpAndSettle();

    final ProfileSelector selector = tester.widget<ProfileSelector>(
      find.byType(ProfileSelector),
    );
    expect(selector.profile, KinematicProfile.bench);

    await tester.tap(find.text(AppStrings.setupProfileManikin));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.profileSwitchConfirm));
    await tester.pumpAndSettle();

    expect(controller.commands, contains('SET_PROFILE:MANIKIN'));
    expect(repository.deviceSettings?.profile, KinematicProfile.manikin);
    expect(repository.deviceSettings?.depthK, isNull);
    expect(find.text(AppStrings.profileSwitchResetNotice), findsOneWidget);
  });

  testWidgets('live header toggles the voice cues', (
    WidgetTester tester,
  ) async {
    final BleController controller = BleController();
    await tester.pumpWidget(
      _harness(const LivePracticeScreen(traineeName: 'Alexandra'), controller),
    );
    await tester.pump();

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.byIcon(Icons.volume_off), findsNothing);

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();

    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('cadence warning needs a sustained unsteady run', (
    WidgetTester tester,
  ) async {
    final BleController controller = BleController();
    await tester.pumpWidget(
      _harness(const LivePracticeScreen(traineeName: 'Alexandra'), controller),
    );
    await tester.pump();

    // The first stroke is expected to be unsteady and must not warn.
    for (int count = 1; count <= 3; count++) {
      controller.debugDeliver(
        _packet(
          qualityFlags: AppBleConfig.qualityFirstStroke,
          totalCompressions: count,
        ),
      );
      await tester.pump();
    }
    expect(find.text(AppStrings.liveCadenceWarning), findsNothing);

    for (int count = 4; count <= 6; count++) {
      controller.debugDeliver(_packet(totalCompressions: count));
      await tester.pump();
    }
    expect(find.text(AppStrings.liveCadenceWarning), findsOneWidget);

    controller.debugDeliver(
      _packet(
        qualityFlags: AppBleConfig.qualitySteadyCadence,
        totalCompressions: 7,
      ),
    );
    await tester.pump();
    expect(find.text(AppStrings.liveCadenceWarning), findsNothing);

    controller.debugDeliver(
      _packet(
        qualityFlags:
            AppBleConfig.qualitySteadyCadence | AppBleConfig.qualityBenchMode,
        totalCompressions: 8,
      ),
    );
    await tester.pump();
    expect(find.text(AppStrings.liveBenchBadge), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
