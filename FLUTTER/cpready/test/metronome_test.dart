/// Widget coverage for the live metronome toggle and its beat rules.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/live_practice/live_practice_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/src/widgets/widgets.dart';

import 'support/fake_ble_controller.dart';
import 'support/fake_session_repository.dart';
import 'support/recording_metronome.dart';
import 'support/recording_voice_coach.dart';

CprMetrics _live({int count = 1, int prompt = 0}) => CprMetrics(
      packetType: AppBleConfig.packetRealtime,
      recoilComplete: true,
      recoilPercentage: 100,
      rateCpm: 110,
      depthCm: 5.5,
      depthMm: 55,
      ccfPercent: 90,
      audioPromptCode: prompt,
      totalCompressions: count,
      elapsedSeconds: 5,
      qualityFlags: AppBleConfig.qualitySteadyCadence,
    );

Widget _harness({
  required FakeBleController controller,
  required RecordingMetronome metronome,
  RecordingVoiceCoach? coach,
}) {
  return AppScope(
    controller: controller,
    repository: FakeSessionRepository(),
    voiceCoach: coach ?? RecordingVoiceCoach(),
    child: MaterialApp(
      theme: appThemeData().theme,
      home: LivePracticeScreen(
        traineeName: 'Alexandra',
        practiceDurationSec: 120,
        metronome: metronome,
      ),
    ),
  );
}

/// Finds the metronome glyph by the on/off state it is drawing.
Finder _metronomeIcon({required bool enabled}) => find.byWidgetPredicate(
      (Widget widget) => widget is MetronomeIcon && widget.enabled == enabled,
    );

Future<void> _startCompressions(
  WidgetTester tester,
  FakeBleController controller,
) async {
  controller.debugDeliver(_live());
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('metronome is on by default and the header toggles it', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = FakeBleController();
    final RecordingMetronome metronome = RecordingMetronome();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller: controller, metronome: metronome),
    );
    await tester.pump();

    expect(_metronomeIcon(enabled: true), findsOneWidget);
    expect(_metronomeIcon(enabled: false), findsNothing);

    // The header toggle uses the provided artwork, not a font icon.
    final Image artwork = tester.widget<Image>(
      find.descendant(
        of: find.byType(MetronomeIcon),
        matching: find.byType(Image),
      ),
    );
    expect((artwork.image as AssetImage).assetName, AppAssets.iconMetronome);

    // The 40 px tap box must not stretch the glyph: it keeps its own size.
    expect(
      tester.getSize(find.byType(MetronomeIcon)),
      Size.square(AppSizes.liveMetronomeIconSize),
    );
    expect(AppSizes.liveMetronomeIconSize, lessThan(AppSizes.liveMuteTapSize));

    await tester.tap(_metronomeIcon(enabled: true));
    await tester.pump();

    expect(_metronomeIcon(enabled: false), findsOneWidget);
    expect(_metronomeIcon(enabled: true), findsNothing);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppMetronome.enabledKey), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a saved OFF choice starts silent', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppMetronome.enabledKey: false,
    });
    final FakeBleController controller = FakeBleController();
    final RecordingMetronome metronome = RecordingMetronome();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller: controller, metronome: metronome),
    );
    await tester.pump();
    expect(_metronomeIcon(enabled: false), findsOneWidget);

    await _startCompressions(tester, controller);
    await tester.pump(AppMetronome.beatInterval(110) * 3);

    expect(metronome.ticks, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('beats while compressions are active', (WidgetTester tester) async {
    final FakeBleController controller = FakeBleController();
    final RecordingMetronome metronome = RecordingMetronome();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller: controller, metronome: metronome),
    );
    await tester.pump();
    await _startCompressions(tester, controller);

    // The first beat fires as soon as the session goes live.
    expect(metronome.ticks, greaterThan(0));
    final int firstBeat = metronome.ticks;

    await tester.pump(AppMetronome.beatInterval(110) * 2);
    expect(metronome.ticks, greaterThan(firstBeat));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a voice cue plays over the beat instead of pausing it', (
    WidgetTester tester,
  ) async {
    final FakeBleController controller = FakeBleController();
    final RecordingMetronome metronome = RecordingMetronome();
    final RecordingVoiceCoach coach = RecordingVoiceCoach();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller: controller, metronome: metronome, coach: coach),
    );
    await tester.pump();
    await _startCompressions(tester, controller);
    expect(metronome.ticks, greaterThan(0));

    controller.debugDeliver(
      _live(count: 2, prompt: AppBleConfig.cuePushHarder),
    );
    await tester.pump();
    expect(coach.played, contains(AppBleConfig.cuePushHarder));

    // The cue is speaking, and the beat keeps its own pace underneath it.
    final int duringCue = metronome.ticks;
    await tester.pump(AppMetronome.beatInterval(110) * 3);
    expect(metronome.ticks, greaterThan(duringCue));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
