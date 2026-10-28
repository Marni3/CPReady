/// Command catalog and BleController protocol helpers.

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/ble/ble_controller.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';

CprMetrics _summary() => const CprMetrics(
  packetType: AppBleConfig.packetFinalSummary,
  recoilComplete: true,
  recoilPercentage: 100,
  rateCpm: 110,
  depthCm: 5.5,
  depthMm: 55,
  ccfPercent: 90,
  audioPromptCode: 0,
  totalCompressions: 30,
  elapsedSeconds: 120,
);

void main() {
  test('command strings match the firmware contract', () {
    expect(AppBleConfig.commandCalibrate, 'CALIBRATE');
    expect(AppBleConfig.commandStart, 'START');
    expect(AppBleConfig.commandStop, 'STOP');
    expect(AppBleConfig.commandGetResults, 'GET_RESULTS');
    expect(AppBleConfig.commandPause, 'PAUSE');
    expect(AppBleConfig.commandResume, 'RESUME');
    expect(AppBleConfig.commandProfileManikin, 'SET_PROFILE:MANIKIN');
    expect(AppBleConfig.commandProfileBench, 'SET_PROFILE:BENCH');
    expect(AppBleConfig.commandResetConfig, 'RESET_CONFIG');
    expect(AppBleConfig.commandGetConfig, 'GET_CONFIG');
    expect(AppBleConfig.commandSetTime(120), 'SET_TIME:120');
    expect(AppBleConfig.commandCalibrateTarget(5.5), 'CALIBRATE_TARGET:5.5');
    expect(AppBleConfig.commandSetK(11.2), 'SET_K:11.20');
  });

  test('sendCommand throws when the link is down', () {
    final controller = BleController();
    expect(
      () => controller.sendCommand(AppBleConfig.commandStart),
      throwsStateError,
    );
    controller.dispose();
  });

  test('awaitPacketWhere resolves the matching packet', () async {
    final controller = BleController();
    final future = controller.awaitPacketWhere(
      (CprMetrics metrics) =>
          metrics.packetType == AppBleConfig.packetFinalSummary,
      timeout: const Duration(seconds: 1),
    );

    controller.debugDeliver(_summary());

    expect((await future)?.totalCompressions, 30);
    controller.dispose();
  });

  test('awaitPacketWhere returns null on timeout', () async {
    final controller = BleController();
    final reply = await controller.awaitPacketWhere(
      (CprMetrics metrics) =>
          metrics.packetType == AppBleConfig.packetFinalSummary,
      timeout: const Duration(milliseconds: 10),
    );

    expect(reply, isNull);
    controller.dispose();
  });

  test('sequence gaps count as lost packets, wrap-around and restarts do not', () {
    CprMetrics live(int sequence) => CprMetrics(
      packetType: AppBleConfig.packetRealtime,
      recoilComplete: true,
      recoilPercentage: 100,
      rateCpm: 110,
      depthCm: 5.5,
      depthMm: 55,
      ccfPercent: 90,
      audioPromptCode: 0,
      totalCompressions: 1,
      elapsedSeconds: 1,
      sequence: sequence,
    );

    final controller = BleController()..startRecording();
    for (final int sequence in <int>[65533, 65534, 65535, 0, 1, 4, 5]) {
      controller.debugDeliver(live(sequence));
    }
    expect(controller.sessionPacketsLost, 2, reason: '2 and 3 are missing');

    // A firmware restart resets the counter; that is not loss.
    controller.debugDeliver(live(30000));
    expect(controller.sessionPacketsLost, 2);

    controller.startRecording();
    expect(controller.sessionPacketsLost, 0);
    controller.dispose();
  });

  test('awaitPacketWhere ignores packets that do not match', () async {
    final controller = BleController();
    final future = controller.awaitPacketWhere(
      (CprMetrics metrics) =>
          metrics.packetType == AppBleConfig.packetFinalSummary,
      timeout: const Duration(seconds: 1),
    );

    controller.debugDeliver(
      const CprMetrics(
        packetType: AppBleConfig.packetRealtime,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 110,
        depthCm: 5.5,
        depthMm: 55,
        ccfPercent: 90,
        audioPromptCode: 0,
        totalCompressions: 3,
        elapsedSeconds: 2,
      ),
    );
    controller.debugDeliver(_summary());

    expect((await future)?.packetType, AppBleConfig.packetFinalSummary);
    controller.dispose();
  });

  test('resetSessionData clears recording provenance', () {
    final controller = BleController()
      ..startRecording()
      ..debugDeliver(_summary());

    expect(controller.sessionPackets, hasLength(1));
    expect(controller.sessionStartedAt, isNotNull);

    controller.resetSessionData();

    expect(controller.sessionPackets, isEmpty);
    expect(controller.recording, isFalse);
    expect(controller.sessionStartedAt, isNull);
    expect(controller.sessionEndedAt, isNull);
    controller.dispose();
  });
}
