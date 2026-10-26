/// Live session end: summary, GET_RESULTS, interruption, and no-save rules.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/live_practice/live_practice_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/src/widgets/widgets.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';

CprMetrics _live({int count = 5, int flags = 0x01}) => CprMetrics(
  packetType: AppBleConfig.packetRealtime,
  recoilComplete: true,
  recoilPercentage: 100,
  rateCpm: 110,
  depthCm: 5.5,
  depthMm: 55,
  ccfPercent: 90,
  audioPromptCode: 0,
  totalCompressions: count,
  elapsedSeconds: 10,
  qualityFlags: flags,
);

CprMetrics _summary({int count = 30, int flags = 0x01}) => CprMetrics(
  packetType: AppBleConfig.packetFinalSummary,
  recoilComplete: true,
  recoilPercentage: 100,
  rateCpm: 112,
  depthCm: 5.4,
  depthMm: 54,
  ccfPercent: 88,
  audioPromptCode: 0,
  totalCompressions: count,
  elapsedSeconds: 120,
  qualityFlags: flags,
);

Widget _harness(
  FakeBleController controller,
  FakeSessionRepository repository,
) {
  return AppScope(
    controller: controller,
    repository: repository,
    voiceCoach: const SilentVoiceCoach(),
    child: MaterialApp(
      theme: appThemeData().theme,
      home: const LivePracticeScreen(traineeName: 'Alexandra'),
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

Future<void> _startLive(
  WidgetTester tester,
  FakeBleController controller,
  FakeSessionRepository repository,
) async {
  await tester.pumpWidget(_harness(controller, repository));
  await tester.pump();
  await _deliver(tester, controller, _live());
}

Future<void> _holdEnd(WidgetTester tester) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(find.byType(HoldFillButton)),
  );
  await tester.pump();
  await tester.pump(
    AppDurations.holdSession + const Duration(milliseconds: 100),
  );
  await gesture.up();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('STOP + Type 4 saves one completed session', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _holdEnd(tester);
    expect(controller.commands, contains(AppBleConfig.commandStop));

    await _deliver(tester, controller, _summary(flags: 0x05));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionSaved), findsOneWidget);
    expect(repository.inserted, hasLength(1));
    expect(repository.inserted.single.qualityFlags, 0x05);
    expect(find.text(AppStrings.liveBenchBadge), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a missed Type 4 is recovered with GET_RESULTS', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _holdEnd(tester);
    await tester.pump(
      AppDurations.finalSummaryTimeout + const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.commands, contains(AppBleConfig.commandGetResults));

    await _deliver(tester, controller, _summary());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionSaved), findsOneWidget);
    expect(repository.inserted, hasLength(1));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('two timeouts show Results Unavailable and save nothing', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _holdEnd(tester);
    await tester.pump(
      AppDurations.finalSummaryTimeout + const Duration(seconds: 1),
    );
    await tester.pump(
      AppDurations.getResultsTimeout + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionResultsUnavailable), findsOneWidget);
    expect(repository.inserted, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a zero-compression Type 4 is not completed or saved', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _deliver(tester, controller, _summary(count: 0));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionResultsUnavailable), findsOneWidget);
    expect(repository.inserted, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a disconnect shows Session Interrupted and saves nothing', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    controller.disconnectForTest();
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionInterrupted), findsOneWidget);
    expect(repository.inserted, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
