/// Live session end: summary, GET_RESULTS, interruption, and no-save rules.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/metronome.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/live_practice/live_practice_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/src/widgets/widgets.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';
import 'support/recording_voice_coach.dart';

CprMetrics _live({
  int count = 5,
  int flags = 0x01,
  int cue = 0,
  int rateCpm = 110,
  double depthCm = 5.5,
  int recoilPercentage = 100,
  int? sequence,
}) =>
    CprMetrics(
      packetType: AppBleConfig.packetRealtime,
      recoilComplete: recoilPercentage >= AppTargets.recoilFullPercent,
      recoilPercentage: recoilPercentage,
      rateCpm: rateCpm,
      depthCm: depthCm,
      depthMm: depthCm * 10.0,
      ccfPercent: 90,
      audioPromptCode: cue,
      totalCompressions: count,
      elapsedSeconds: 10,
      qualityFlags: flags,
      sequence: sequence,
    );

CprMetrics _summary({int count = 30, int flags = 0x01, int? sequence}) =>
    CprMetrics(
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
      sequence: sequence,
    );

CprMetrics _status(int type, {int code = 0}) => CprMetrics(
      packetType: type,
      recoilComplete: true,
      recoilPercentage: 100,
      rateCpm: 0,
      depthCm: 0,
      depthMm: 0,
      ccfPercent: 0,
      audioPromptCode: code,
      totalCompressions: 0,
      elapsedSeconds: 0,
    );

Widget _harness(
  FakeBleController controller,
  FakeSessionRepository repository, {
  VoiceCoach? voiceCoach,
  DateTime Function()? cueClock,
}) {
  return AppScope(
    controller: controller,
    repository: repository,
    voiceCoach: voiceCoach ?? SilentVoiceCoach(),
    child: MaterialApp(
      theme: appThemeData().theme,
      home: LivePracticeScreen(
        traineeName: 'Alexandra',
        practiceDurationSec: 120,
        cueClock: cueClock,
        metronome: const SilentMetronome(),
      ),
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
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

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
    // 120 s summary minus the 10 s before the first compression, 88% CCF.
    expect(repository.inserted.single.durationSeconds, 110);
    expect(repository.inserted.single.compressionSeconds, 97);
    expect(repository.inserted.single.pauseSeconds, 13);
    expect(find.text(AppStrings.liveBenchBadge), findsOneWidget);

    // The summary shows the stored split as neutral capsules under
    // Compressions: 97 s and 13 s in the shared clock format.
    expect(find.text(AppStrings.sessionCompressionTime), findsOneWidget);
    expect(find.text(AppStrings.sessionPauseTime), findsOneWidget);
    expect(find.text('01:37'), findsOneWidget);
    expect(find.text('00:13'), findsOneWidget);
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

  testWidgets('a cue repeated by the 5 Hz heartbeat plays once', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    final coach = RecordingVoiceCoach();
    // The cue gate reads this clock; it advances with every pump below, so
    // the gate's 1 s duplicate window really expires during the test.
    DateTime now = DateTime(2026);
    await tester.pumpWidget(
      _harness(controller, repository, voiceCoach: coach, cueClock: () => now),
    );
    await tester.pump();

    Future<void> deliverAndWait(CprMetrics packet) async {
      controller.debugDeliver(packet);
      await tester.pump(const Duration(milliseconds: 300));
      now = now.add(const Duration(milliseconds: 300));
    }

    // Older firmware repeats the cue code in every packet until the next
    // stroke; here it stays for 1.8 s, longer than the 1 s duplicate window.
    for (int i = 0; i < 6; i++) {
      await deliverAndWait(_live(count: 6, cue: AppBleConfig.cuePushHarder));
    }
    expect(coach.played, <int>[AppBleConfig.cuePushHarder]);

    // A later, separate cue of the same kind still plays.
    await deliverAndWait(_live(count: 7));
    await deliverAndWait(_live(count: 8, cue: AppBleConfig.cuePushHarder));
    expect(coach.played, <int>[
      AppBleConfig.cuePushHarder,
      AppBleConfig.cuePushHarder,
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('calibration packets do not count as the session starting', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await tester.pumpWidget(_harness(controller, repository));
    await tester.pump();

    // A device that re-runs its baseline instead of starting the session.
    controller.debugDeliver(_status(AppBleConfig.packetCalibrating));
    await tester.pump();
    controller.debugDeliver(_status(AppBleConfig.packetCalibrationDone));
    await tester.pump(AppDurations.startWatchdog + const Duration(seconds: 1));
    await tester.pump();

    expect(find.text(AppStrings.liveStartFailedTitle), findsOneWidget);
    expect(repository.inserted, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a sensor fault ends the session and saves nothing', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _deliver(
      tester,
      controller,
      _status(AppBleConfig.packetError, code: AppBleConfig.errI2cFault),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionSensorFault), findsOneWidget);
    expect(repository.inserted, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a rejected side command does not end a running session', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _deliver(
      tester,
      controller,
      _status(AppBleConfig.packetError, code: AppBleConfig.errWrongState),
    );
    expect(find.text(AppStrings.liveStartFailedTitle), findsNothing);

    await _deliver(tester, controller, _summary());
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.sessionSaved), findsOneWidget);
    expect(repository.inserted, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('lost notifications are counted from sequence gaps and saved', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await tester.pumpWidget(_harness(controller, repository));
    await tester.pump();

    await _deliver(tester, controller, _live(count: 1, sequence: 40));
    await _deliver(tester, controller, _live(count: 2, sequence: 41));
    await _deliver(tester, controller, _live(count: 4, sequence: 44));
    await _deliver(tester, controller, _summary(sequence: 45));
    await tester.pumpAndSettle();

    expect(repository.inserted, hasLength(1));
    expect(repository.inserted.single.packetsLost, 2);
    expect(repository.inserted.single.packetCount, 4);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('older firmware without sequence numbers saves no loss figure', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _deliver(tester, controller, _summary());
    await tester.pumpAndSettle();

    expect(repository.inserted.single.packetsLost, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('the compression counter keeps counting past 255', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await _startLive(tester, controller, repository);

    await _deliver(tester, controller, _live(count: 300));
    expect(find.text('300'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('live depth capsule renders stabilized median and rejects isolated ~1 cm glitch', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await tester.pumpWidget(_harness(controller, repository));
    await tester.pump();

    await _deliver(tester, controller, _live(count: 1, depthCm: 5.4));
    await _deliver(tester, controller, _live(count: 2, depthCm: 5.5));
    await _deliver(tester, controller, _live(count: 3, depthCm: 5.6));
    expect(find.text('5.50cm'), findsOneWidget);

    // Isolated 1.1 cm bounce/split glitch must not flash 1.10cm on screen.
    await _deliver(tester, controller, _live(count: 4, depthCm: 1.1));
    expect(find.text('1.10cm'), findsNothing);
    expect(find.text('5.50cm'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('live rate holds across brief rate=0 glitch and clears to -- after >2.5s idle pause', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    DateTime now = DateTime(2026, 11, 24, 14, 0, 0);
    await tester.pumpWidget(
      _harness(controller, repository, cueClock: () => now),
    );
    await tester.pump();

    await _deliver(tester, controller, _live(count: 1, rateCpm: 112));
    expect(find.text('112cpm'), findsOneWidget);

    // Mid-set rate=0 glitch arrives 250 ms later -> holds 112cpm, never flashes --
    now = now.add(const Duration(milliseconds: 250));
    await _deliver(tester, controller, _live(count: 2, rateCpm: 0, flags: 0x10));
    expect(find.text('112cpm'), findsOneWidget);
    expect(find.text(AppStrings.liveNoValue), findsNothing);

    // Genuine >2.5 s hands-off pause -> periodic tick clears Rate to --
    now = now.add(const Duration(seconds: 3));
    await tester.pump(AppDurations.liveTick);
    expect(find.text('112cpm'), findsNothing);
    expect(find.text(AppStrings.liveNoValue), findsOneWidget);

    // First resume stroke arrives with rateCpm=0 -> holds 112cpm until next period
    await _deliver(tester, controller, _live(count: 3, rateCpm: 0, flags: 0x02));
    expect(find.text('112cpm'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('live recoil capsule debounces single partial stroke and flips on 2nd consecutive partial', (
    WidgetTester tester,
  ) async {
    final controller = FakeBleController();
    final repository = FakeSessionRepository();
    await tester.pumpWidget(_harness(controller, repository));
    await tester.pump();

    await _deliver(tester, controller, _live(count: 1, recoilPercentage: 100));
    expect(find.text(AppStrings.liveRecoilFull), findsOneWidget);

    // Single isolated partial stroke does not flicker to Partial
    await _deliver(tester, controller, _live(count: 2, recoilPercentage: 0));
    expect(find.text(AppStrings.liveRecoilFull), findsOneWidget);
    expect(find.text(AppStrings.liveRecoilPartial), findsNothing);

    // 5 Hz heartbeat repeat of the same stroke must not increment partial streak
    await _deliver(tester, controller, _live(count: 2, recoilPercentage: 0));
    expect(find.text(AppStrings.liveRecoilFull), findsOneWidget);

    // Second consecutive partial stroke flips live capsule to Partial
    await _deliver(tester, controller, _live(count: 3, recoilPercentage: 0));
    expect(find.text(AppStrings.liveRecoilPartial), findsOneWidget);

    // Next full release immediately clears back to Full
    await _deliver(tester, controller, _live(count: 4, recoilPercentage: 100));
    expect(find.text(AppStrings.liveRecoilFull), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
