/// Unit tests for SessionRefinementEngine, LiveDepthStabilizer, and
/// LiveCoachingController.

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/audio/live_coaching_controller.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/core/metrics/session_refinement_engine.dart';
import 'package:cpready/src/core/telemetry/raw_frame.dart';

CprMetrics _stroke({
  required int count,
  required double depthCm,
  required int rateCpm,
  int? elapsedSeconds,
  bool steady = true,
  bool firstStroke = false,
  bool bounce = false,
  bool windowClamped = false,
  bool hesitationOnset = false,
  bool recoilOk = true,
}) {
  int flags = 0;
  if (firstStroke) flags |= AppBleConfig.qualityFirstStroke;
  if (steady) flags |= AppBleConfig.qualitySteadyCadence;
  if (bounce) flags |= AppBleConfig.qualitySubPeriodBounce;
  if (windowClamped) flags |= AppBleConfig.qualityWindowClamped;
  if (hesitationOnset) flags |= AppBleConfig.qualityHesitationOnset;

  return CprMetrics(
    packetType: AppBleConfig.packetRealtime,
    recoilComplete: recoilOk,
    recoilPercentage: recoilOk ? 100 : 0,
    rateCpm: rateCpm,
    depthCm: depthCm,
    depthMm: depthCm * 10.0,
    ccfPercent: 95,
    audioPromptCode: 0,
    totalCompressions: count,
    elapsedSeconds: elapsedSeconds ?? (count * 0.55).round(),
    qualityFlags: flags,
    sequence: count,
  );
}

void main() {
  group('LiveDepthStabilizer', () {
    test('passes through steady depths unchanged and median-filters unsteady spikes', () {
      final stabilizer = LiveDepthStabilizer();

      expect(
        stabilizer.stabilize(
          _stroke(count: 1, depthCm: 5.2, rateCpm: 110),
          unsteadyActive: false,
        ),
        closeTo(5.2, 1e-6),
      );
      expect(
        stabilizer.stabilize(
          _stroke(count: 2, depthCm: 5.4, rateCpm: 110),
          unsteadyActive: false,
        ),
        closeTo(5.4, 1e-6),
      );
      // Unsteady transition spike (8.1 cm): stabilized by 3-stroke rolling median
      expect(
        stabilizer.stabilize(
          _stroke(count: 3, depthCm: 8.1, rateCpm: 78, steady: false),
          unsteadyActive: true,
        ),
        closeTo(5.4, 1e-6),
      );
    });
  });

  group('LiveCoachingController', () {
    test('suppresses depth cues while cadence is unsteady, but allows rate cues', () {
      DateTime now = DateTime(2026, 11, 7, 12, 0, 0);
      final controller = LiveCoachingController(clock: () => now);

      // Warm-up strokes 1..3
      for (int i = 1; i <= 3; i++) {
        expect(
          controller.evaluate(
            _stroke(count: i, depthCm: 5.5, rateCpm: 110),
            cadenceWarningActive: false,
          ),
          0,
        );
      }

      // 6 unsteady strokes with shallow depth (3.8 cm) over 6 seconds -> depth cue MUST be suppressed
      for (int i = 4; i <= 9; i++) {
        now = now.add(const Duration(seconds: 1));
        expect(
          controller.evaluate(
            _stroke(count: i, depthCm: 3.8, rateCpm: 110, steady: false),
            cadenceWarningActive: true,
          ),
          0,
        );
      }

      // Rate cues ARE allowed while unsteady: 5 slow strokes (80 CPM) trigger cueSpeedUp
      for (int i = 10; i <= 13; i++) {
        now = now.add(const Duration(milliseconds: 600));
        expect(
          controller.evaluate(
            _stroke(count: i, depthCm: 3.8, rateCpm: 80, steady: false),
            cadenceWarningActive: true,
          ),
          0,
        );
      }
      now = now.add(const Duration(milliseconds: 600));
      expect(
        controller.evaluate(
          _stroke(count: 14, depthCm: 3.8, rateCpm: 80, steady: false),
          cadenceWarningActive: true,
        ),
        AppBleConfig.cueSpeedUp,
      );

      // Once cadence stabilizes (after 5s cooldown), 5 consecutive shallow strokes trigger Push Harder
      now = now.add(const Duration(seconds: 6));
      for (int i = 15; i <= 18; i++) {
        now = now.add(const Duration(milliseconds: 550));
        expect(
          controller.evaluate(
            _stroke(count: i, depthCm: 3.8, rateCpm: 110, steady: true),
            cadenceWarningActive: false,
          ),
          0,
        );
      }
      now = now.add(const Duration(milliseconds: 550));
      expect(
        controller.evaluate(
          _stroke(count: 19, depthCm: 3.8, rateCpm: 110, steady: true),
          cadenceWarningActive: false,
        ),
        AppBleConfig.cuePushHarder,
      );
    });
  });

  group('SessionRefinementEngine', () {
    test('Case A: merges true split-stroke fragments into 1 stroke', () {
      final packets = <CprMetrics>[
        _stroke(count: 1, depthCm: 5.0, rateCpm: 110, firstStroke: true),
        _stroke(count: 2, depthCm: 5.0, rateCpm: 110),
        _stroke(count: 3, depthCm: 5.0, rateCpm: 110),
        // Split stroke pair: two fragments (~3.5 cm each) with bounce flag
        _stroke(count: 4, depthCm: 3.5, rateCpm: 0, steady: false, bounce: true),
        _stroke(count: 5, depthCm: 3.6, rateCpm: 195, steady: false),
        _stroke(count: 6, depthCm: 5.0, rateCpm: 110),
      ];
      const fwSummary = CprMetrics(
        packetType: AppBleConfig.packetFinalSummary,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 115,
        depthCm: 4.52,
        depthMm: 45.2,
        ccfPercent: 98,
        audioPromptCode: 0,
        totalCompressions: 6,
        elapsedSeconds: 4,
      );

      final result = SessionRefinementEngine.refineSession(
        firmwareSummary: fwSummary,
        sessionPackets: packets,
        rawSamples: const <RawTelemetrySample>[],
      );

      expect(result.mergedSplitStrokes, 1);
      expect(result.refinedSummary.totalCompressions, 5);
      expect(result.refinedSummary.depthMm, closeTo(50.0, 1.0));
    });

    test('Case B: rebalances premature-cut + carryover pair while preserving 2 strokes', () {
      final packets = <CprMetrics>[
        _stroke(count: 1, depthCm: 4.5, rateCpm: 108, firstStroke: true),
        _stroke(count: 2, depthCm: 4.5, rateCpm: 108),
        _stroke(count: 3, depthCm: 4.5, rateCpm: 108),
        // Premature cut (1.5 cm, <320ms bounce) followed by carryover (7.5 cm, 75 CPM / 800ms)
        _stroke(count: 4, depthCm: 1.5, rateCpm: 0, steady: false, bounce: true),
        _stroke(count: 5, depthCm: 7.5, rateCpm: 75, steady: false, windowClamped: true),
        _stroke(count: 6, depthCm: 4.5, rateCpm: 108),
      ];
      const fwSummary = CprMetrics(
        packetType: AppBleConfig.packetFinalSummary,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 108,
        depthCm: 4.5,
        depthMm: 45.0,
        ccfPercent: 98,
        audioPromptCode: 0,
        totalCompressions: 6,
        elapsedSeconds: 4,
      );

      final result = SessionRefinementEngine.refineSession(
        firmwareSummary: fwSummary,
        sessionPackets: packets,
        rawSamples: const <RawTelemetrySample>[],
      );

      expect(result.rebalancedCarryoverPairs, 1);
      expect(result.refinedSummary.totalCompressions, 6);
      expect(result.refinedSummary.depthMm, closeTo(45.0, 0.5));
    });

    test('CCF refinement: excludes pre-start waiting time when compressions run until session end', () {
      // Simulate 10s wait on 'Start When Ready' before Stroke #1, then continuous 110 CPM until session end (13s)
      final packets = <CprMetrics>[
        _stroke(count: 1, depthCm: 5.2, rateCpm: 0, elapsedSeconds: 10, firstStroke: true, steady: false),
        _stroke(count: 2, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 11),
        _stroke(count: 3, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 11),
        _stroke(count: 4, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 12),
        _stroke(count: 5, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 12),
        _stroke(count: 6, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 13),
      ];
      const fwSummary = CprMetrics(
        packetType: AppBleConfig.packetFinalSummary,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 110,
        depthCm: 5.2,
        depthMm: 52.0,
        ccfPercent: 25, // Old firmware summary penalized by 10s wait before Stroke #1
        audioPromptCode: 0,
        totalCompressions: 6,
        elapsedSeconds: 13,
      );

      final result = SessionRefinementEngine.refineSession(
        firmwareSummary: fwSummary,
        sessionPackets: packets,
        rawSamples: const <RawTelemetrySample>[],
      );

      expect(result.refinedSummary.ccfPercent, 100);
    });

    test('CCF refinement: preserves trailing idle time when trainee stops compressing early before STOP', () {
      // Simulate 10s pre-wait, 6 strokes (3.3s active), and then 2s of trailing hands-off time before STOP (15s)
      final packets = <CprMetrics>[
        _stroke(count: 1, depthCm: 5.2, rateCpm: 0, elapsedSeconds: 10, firstStroke: true, steady: false),
        _stroke(count: 2, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 11),
        _stroke(count: 3, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 11),
        _stroke(count: 4, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 12),
        _stroke(count: 5, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 12),
        _stroke(count: 6, depthCm: 5.2, rateCpm: 110, elapsedSeconds: 13),
      ];
      const fwSummary = CprMetrics(
        packetType: AppBleConfig.packetFinalSummary,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 110,
        depthCm: 5.2,
        depthMm: 52.0,
        ccfPercent: 22,
        audioPromptCode: 0,
        totalCompressions: 6,
        elapsedSeconds: 15, // Stopped compressing 2s before STOP
      );

      final result = SessionRefinementEngine.refineSession(
        firmwareSummary: fwSummary,
        sessionPackets: packets,
        rawSamples: const <RawTelemetrySample>[],
      );

      // Active = 3280 ms, Window = 3280 + 2000 = 5280 ms -> 62% (NOT 100%)
      expect(result.refinedSummary.ccfPercent, closeTo(62, 2));
    });

    test('CCF refinement: preserves genuine mid-session pause penalty on Stroke #3+', () {
      // Rhythmic compressions on Strokes #1..#3, then a 5s mid-session pause before Stroke #4..#6
      final packets = <CprMetrics>[
        _stroke(count: 1, depthCm: 5.2, rateCpm: 0, elapsedSeconds: 1, firstStroke: true, steady: false),
        _stroke(count: 2, depthCm: 5.2, rateCpm: 109, elapsedSeconds: 2),
        _stroke(count: 3, depthCm: 5.2, rateCpm: 109, elapsedSeconds: 2),
        _stroke(count: 4, depthCm: 5.2, rateCpm: 0, elapsedSeconds: 7, firstStroke: true, steady: false),
        _stroke(count: 5, depthCm: 5.2, rateCpm: 109, elapsedSeconds: 8),
        _stroke(count: 6, depthCm: 5.2, rateCpm: 109, elapsedSeconds: 8),
      ];
      const fwSummary = CprMetrics(
        packetType: AppBleConfig.packetFinalSummary,
        recoilComplete: true,
        recoilPercentage: 100,
        rateCpm: 109,
        depthCm: 5.2,
        depthMm: 52.0,
        ccfPercent: 45,
        audioPromptCode: 0,
        totalCompressions: 6,
        elapsedSeconds: 9,
      );

      final result = SessionRefinementEngine.refineSession(
        firmwareSummary: fwSummary,
        sessionPackets: packets,
        rawSamples: const <RawTelemetrySample>[],
      );

      // Active time = 6 * 550ms = 3300ms; Active window = 3*550 + 5000 + 2*550 = 7750ms -> ~43%
      expect(result.refinedSummary.ccfPercent, lessThan(60));
    });
  });
}

