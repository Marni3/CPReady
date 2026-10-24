import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/ble/ble_controller.dart';
import 'package:cpready/src/core/history/session_repository.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/manikin_calibration/manikin_calibration_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';

class _FailingDatabaseFactory implements DatabaseFactory {
  const _FailingDatabaseFactory();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('History storage is out of scope for this test');
  }
}

/// Records every command the screen hands to the BLE layer.
class _RecordingController extends BleController {
  final List<String> commands = <String>[];

  @override
  Future<void> sendCommand(String command) async {
    commands.add(command);
  }
}

CprMetrics _summary(double depthCm) => CprMetrics(
  packetType: AppBleConfig.packetFinalSummary,
  recoilComplete: false,
  recoilPercentage: 90,
  rateCpm: 110,
  depthCm: depthCm,
  depthMm: depthCm * 10,
  ccfPercent: 95,
  audioPromptCode: 0,
  totalCompressions: 28,
  elapsedSeconds: 15,
);

void main() {
  testWidgets('manikin calibration sends CALIBRATE_TARGET to the device', (
    WidgetTester tester,
  ) async {
    final _RecordingController controller = _RecordingController();
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        repository: SessionRepository(
          factory: const _FailingDatabaseFactory(),
          databasePath: 'tmp-manikin-test.db',
        ),
        voiceCoach: const SilentVoiceCoach(),
        child: MaterialApp(
          theme: appThemeData().theme,
          home: const ManikinCalibrationScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(AppStrings.manikinStart));
    await tester.pump();
    print('after trial start: ${controller.commands}');

    controller.debugDeliver(
      CprMetrics(
        packetType: AppBleConfig.packetCalibrationDone,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 0,
        depthCm: 0,
        depthMm: 0,
        ccfPercent: 0,
        audioPromptCode: 0,
        totalCompressions: 0,
        elapsedSeconds: 0,
      ),
    );
    await tester.pump();
    print('after calibration done: ${controller.commands}');

    controller.debugDeliver(_summary(5.5));
    await tester.pump();
    print('after summary: ${controller.commands}');
    expect(find.text(AppStrings.manikinMeanDepth), findsOneWidget);

    await tester.enterText(find.byType(TextField), '6.0');
    await tester.pump();
    await tester.tap(find.text(AppStrings.manikinSave));
    await tester.pump();
    await tester.pump();
    print('after save: ${controller.commands}');

    expect(controller.commands, contains('CALIBRATE_TARGET:6.0'));
    expect(find.text(AppStrings.manikinSentTitle), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
