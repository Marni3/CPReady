/// Baseline calibration: Type 2 progress, Type 3 gating, and failures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/calibration/calibration_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/src/widgets/widgets.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';

CprMetrics _packet(int type, {int elapsedSeconds = 0}) => CprMetrics(
  packetType: type,
  recoilComplete: true,
  recoilPercentage: 100,
  rateCpm: 0,
  depthCm: 0,
  depthMm: 0,
  ccfPercent: 0,
  audioPromptCode: 0,
  totalCompressions: 0,
  elapsedSeconds: elapsedSeconds,
);

Future<void> _deliver(
  WidgetTester tester,
  FakeBleController controller,
  CprMetrics packet,
) async {
  controller.debugDeliver(packet);
  await tester.pump();
  await tester.pump();
}

Future<FakeBleController> _pumpScreen(WidgetTester tester) async {
  final FakeBleController controller = FakeBleController();
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      repository: FakeSessionRepository(),
      voiceCoach: const SilentVoiceCoach(),
      child: MaterialApp(
        theme: appThemeData().theme,
        home: const CalibrationScreen(traineeName: 'Alexandra'),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('sends CALIBRATE and shows the zeroing countdown', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = await _pumpScreen(tester);

    expect(controller.commands, <String>[AppBleConfig.commandCalibrate]);
    expect(find.text(AppStrings.calibrationWaiting), findsOneWidget);

    await _deliver(
      tester,
      controller,
      _packet(AppBleConfig.packetCalibrating, elapsedSeconds: 1),
    );

    expect(find.text(AppStrings.calibrationCountdown(1)), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('enables Begin Session only after Type 3', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = await _pumpScreen(tester);

    final Finder button = find.widgetWithText(
      FlatActionButton,
      AppStrings.calibrationBeginSession,
    );
    expect(tester.widget<FlatActionButton>(button).onPressed, isNull);

    await _deliver(
      tester,
      controller,
      _packet(AppBleConfig.packetCalibrationDone),
    );

    expect(find.text(AppStrings.calibrationReady), findsOneWidget);
    expect(tester.widget<FlatActionButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('times out when the device never reports progress', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = await _pumpScreen(tester);

    await tester.pump(
      AppDurations.calibrationTimeout + const Duration(seconds: 1),
    );

    expect(find.text(AppStrings.calibrationTimeout), findsOneWidget);
    expect(find.text(AppStrings.calibrationRetry), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows the rejection message on Type 5', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = await _pumpScreen(tester);

    await _deliver(tester, controller, _packet(AppBleConfig.packetError));

    expect(find.text(AppStrings.calibrationRejected), findsOneWidget);
    expect(find.text(AppStrings.calibrationRetry), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
