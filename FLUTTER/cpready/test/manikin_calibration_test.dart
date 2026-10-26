/// Manikin calibration: command order, Type 3 ACK, and failure paths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/manikin_calibration/manikin_calibration_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';

CprMetrics _packet(int type) => CprMetrics(
  packetType: type,
  recoilComplete: true,
  recoilPercentage: 100,
  rateCpm: 0,
  depthCm: 0,
  depthMm: 0,
  ccfPercent: 0,
  audioPromptCode: 0,
  totalCompressions: 0,
  elapsedSeconds: 0,
);

CprMetrics _summary() => const CprMetrics(
  packetType: AppBleConfig.packetFinalSummary,
  recoilComplete: false,
  recoilPercentage: 90,
  rateCpm: 110,
  depthCm: 5.5,
  depthMm: 55,
  ccfPercent: 95,
  audioPromptCode: 0,
  totalCompressions: 28,
  elapsedSeconds: 15,
);

Widget _harness() {
  final FakeBleController controller = FakeBleController();
  return AppScope(
    controller: controller,
    repository: FakeSessionRepository(),
    voiceCoach: const SilentVoiceCoach(),
    child: MaterialApp(
      theme: appThemeData().theme,
      home: const ManikinCalibrationScreen(),
    ),
  );
}

Future<void> _deliver(
  WidgetTester tester,
  FakeBleController controller,
  CprMetrics packet,
) async {
  controller.debugDeliver(packet);
  await tester.pump();
  await tester.pump();
}

Future<FakeBleController> _controllerInTree(WidgetTester tester) async {
  await tester.pumpWidget(_harness());
  await tester.pump();
  final AppScope scope = tester.widget<AppScope>(find.byType(AppScope));
  return scope.controller as FakeBleController;
}

Future<void> _reachTargetEntry(
  WidgetTester tester,
  FakeBleController controller,
) async {
  await tester.tap(find.text(AppStrings.manikinStartZeroing));
  await tester.pump();

  expect(controller.commands, <String>[
    AppBleConfig.commandSetTime(AppDurations.manikinTrialSeconds),
    AppBleConfig.commandCalibrate,
  ]);

  await _deliver(
    tester,
    controller,
    _packet(AppBleConfig.packetCalibrationDone),
  );
  expect(find.text(AppStrings.manikinStart), findsOneWidget);

  await tester.tap(find.text(AppStrings.manikinStart));
  await tester.pump();
  expect(controller.commands, contains(AppBleConfig.commandStart));

  await _deliver(tester, controller, _summary());
  expect(find.text(AppStrings.manikinMeanDepth), findsOneWidget);

  await tester.enterText(find.byType(TextField), '6.0');
  await tester.pump();
}

void main() {
  testWidgets('saves only after the Type 3 ACK', (WidgetTester tester) async {
    final FakeBleController controller = await _controllerInTree(tester);
    await _reachTargetEntry(tester, controller);

    await tester.tap(find.text(AppStrings.manikinSave));
    await tester.pump();

    expect(controller.commands.last, AppBleConfig.commandCalibrateTarget(6.0));
    expect(find.text(AppStrings.manikinSentTitle), findsNothing);

    await _deliver(
      tester,
      controller,
      _packet(AppBleConfig.packetCalibrationDone),
    );

    expect(find.text(AppStrings.manikinSentTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows a failure and stays on target entry after Type 5', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = await _controllerInTree(tester);
    await _reachTargetEntry(tester, controller);

    await tester.tap(find.text(AppStrings.manikinSave));
    await tester.pump();

    await _deliver(tester, controller, _packet(AppBleConfig.packetError));

    expect(find.text(AppStrings.manikinSentTitle), findsNothing);
    expect(find.text(AppStrings.manikinTargetRejected), findsOneWidget);
    expect(find.text(AppStrings.manikinMeanDepth), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows a failure when the Type 3 ACK times out', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = await _controllerInTree(tester);
    await _reachTargetEntry(tester, controller);

    await tester.tap(find.text(AppStrings.manikinSave));
    await tester.pump();
    await tester.pump(
      AppDurations.targetAckTimeout + const Duration(seconds: 1),
    );
    await tester.pump();

    expect(find.text(AppStrings.manikinSentTitle), findsNothing);
    expect(find.text(AppStrings.manikinTargetTimeout), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a disconnect while entering the target requires a restart', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = await _controllerInTree(tester);
    await _reachTargetEntry(tester, controller);

    controller.disconnectForTest();
    await tester.pump();

    expect(find.text(AppStrings.manikinNoDeviceConnected), findsOneWidget);
    expect(find.text(AppStrings.manikinMeanDepth), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
