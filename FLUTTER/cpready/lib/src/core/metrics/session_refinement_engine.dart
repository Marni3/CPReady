/// Post-session Retroactive Refinement Engine & Live Unsteady Depth Stabilizer.
///
/// ## Purpose
/// Real-time single-MPU double integration (`DepthEstimator::closedCycleDepthCm`)
/// enforces zero mean acceleration ($\bar{a} = 0$) and zero mean velocity
/// ($\bar{v} = 0$) over each causal stroke window. While exact for steady
/// periodic compressions (`1.62 mm` MAE across the 10 Laerdal ground-truth
/// trials), unsteady rhythm introduces three causal artifacts:
/// 1. **Case A — True Split Strokes**: A hesitant release or double-peaked push
///    splits one physical compression into two detections whose combined period
///    $\Delta t_1 + \Delta t_2 \le 1.30\,T_{\text{median}}$, inflating stroke
///    count and replacing one normal depth with two small fragments.
/// 2. **Case B — Premature-Cut + Carryover Pairs**: Stroke $i$ terminates early
///    at $\Delta t_i < 320\text{ ms}$ on a minor dip, and the state machine
///    absorbs the remainder of Stroke $i$ plus all of Stroke $i+1$ into a
///    $\Delta t_{i+1} > 700\text{ ms}$ window ($\Delta t_i + \Delta t_{i+1} \approx 2\,T_{\text{median}}$).
/// 3. **Case C — Unmasked Gap Strokes & Boundary-Velocity Mismatch ($\Delta v \neq 0$)**:
///    Sudden deep-to-shallow transitions across gaps $> 720\text{ ms}$ can miss
///    a stroke, and unsteady transition strokes (`!isSteadyCadence` or
///    `isWindowClamped`) experience single-window boundary velocity mismatch.
///
/// ## Four-Stage Hybrid Refinement Pipeline (`R3 + Zero-Phase filtfilt`)
/// When a session ends (`STOP`), [SessionRefinementEngine.refineSession] runs:
/// - **Stage 0 (Zero-Phase Forward-Backward `filtfilt` Trajectory)**: When 100 Hz
///   raw chest accelerometer samples (`rawSamples`) are available, computes the
///   zero-phase 2nd-order Butterworth high-pass ($f_c = 0.55\text{ Hz}$) forward-
///   backward (`filtfilt`) displacement waveform $x_{\text{ff}}(t)$, self-
///   calibrated against the session's steady closed-cycle strokes, and blends
///   unsteady transition strokes (`60%` self-calibrated `filtfilt` + `40%`
///   closed-cycle) to remove $\Delta v \neq 0$ boundary error.
/// - **Stage 1 (Case A vs. Case B Pair Resolution)**: Merges true split-stroke
///   fragments (Case A) into a single re-integrated stroke and re-balances
///   premature-cut + carryover pairs (Case B) via displacement conservation.
/// - **Stage 2 (100 Hz Gap Stroke Recovery)**: Scans any inter-stroke gap
///   $> 720\text{ ms}$ in the 100 Hz waveform to recover missed shallow or
///   hesitant compressions.
/// - **Stage 3 (Local Steady-Median Winsorization)**: Clamps any remaining
///   unsteady/window-clamped transition outliers to within $\pm 5.0\text{ mm}$
///   of the local 5-stroke steady median depth.

import 'dart:math' as math;

import '../../config/config.dart';
import '../telemetry/raw_frame.dart';
import 'cpr_metrics.dart';

/// Stabilizes the live displayed depth capsule during unsteady cadence using a
/// 3-stroke rolling median so a single transition spike does not flash an
/// egregious number on screen while `_cadenceWarning` is active.
class LiveDepthStabilizer {
  final List<double> _recentDepthsCm = <double>[];
  int _lastStrokeCount = 0;

  void reset() {
    _recentDepthsCm.clear();
    _lastStrokeCount = 0;
  }

  /// Updates the rolling buffer when a new stroke arrives and returns the
  /// depth (in cm) to display on the live screen.
  ///
  /// When [unsteadyActive] is false and the stroke is steady, returns the raw
  /// `metrics.depthCm` directly. When unsteady (or on a sub-period bounce),
  /// returns the 3-stroke rolling median.
  double stabilize(CprMetrics? metrics, {required bool unsteadyActive}) {
    if (metrics == null) return 0.0;
    if (metrics.packetType != AppBleConfig.packetRealtime) {
      return metrics.depthCm;
    }

    final int count = metrics.totalCompressions;
    if (count > _lastStrokeCount && metrics.depthCm > 0.0) {
      _lastStrokeCount = count;
      if (!metrics.isSubPeriodBounce) {
        _recentDepthsCm.add(metrics.depthCm);
        if (_recentDepthsCm.length > 3) {
          _recentDepthsCm.removeAt(0);
        }
      }
    }

    if (_recentDepthsCm.isEmpty) {
      return metrics.depthCm;
    }

    if (unsteadyActive ||
        !metrics.isSteadyCadence ||
        metrics.isSubPeriodBounce ||
        metrics.isWindowClamped) {
      final List<double> sorted = List<double>.of(_recentDepthsCm)..sort();
      return sorted[sorted.length ~/ 2];
    }

    return metrics.depthCm;
  }
}

/// Diagnostic report produced alongside the refined [CprMetrics] summary.
class SessionRefinementResult {
  /// The refined summary to display on `SessionCompleteScreen` and save to `History`.
  final CprMetrics refinedSummary;

  /// The raw summary originally reported by the ESP32 firmware.
  final CprMetrics firmwareSummary;

  /// Number of split-stroke fragment pairs (Case A) merged into single strokes.
  final int mergedSplitStrokes;

  /// Number of boundary-shifted stroke pairs (Case B) rebalanced.
  final int rebalancedCarryoverPairs;

  /// Number of missed shallow/hesitant strokes recovered from 100 Hz gaps.
  final int recoveredGapStrokes;

  /// Number of unsteady transition strokes Winsorized against the steady median.
  final int winsorizedUnsteadyStrokes;

  /// True when the 100 Hz raw waveform buffer was complete enough (>=85%) to
  /// run zero-phase `filtfilt` and gap stroke recovery.
  final bool usedRawWaveform;

  const SessionRefinementResult({
    required this.refinedSummary,
    required this.firmwareSummary,
    this.mergedSplitStrokes = 0,
    this.rebalancedCarryoverPairs = 0,
    this.recoveredGapStrokes = 0,
    this.winsorizedUnsteadyStrokes = 0,
    this.usedRawWaveform = false,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'used_raw_waveform': usedRawWaveform,
        'merged_split_strokes': mergedSplitStrokes,
        'rebalanced_carryover_pairs': rebalancedCarryoverPairs,
        'recovered_gap_strokes': recoveredGapStrokes,
        'winsorized_unsteady_strokes': winsorizedUnsteadyStrokes,
        'firmware_summary': <String, Object?>{
          'rate_cpm': firmwareSummary.rateCpm,
          'depth_tenths_mm': (firmwareSummary.depthCm * 100).round(),
          'recoil_percent': firmwareSummary.recoilPercentage,
          'ccf_percent': firmwareSummary.ccfPercent,
          'total_compressions': firmwareSummary.totalCompressions,
          'elapsed_sec': firmwareSummary.elapsedSeconds,
          'quality_flags': firmwareSummary.qualityFlags,
        },
        'refined_summary': <String, Object?>{
          'rate_cpm': refinedSummary.rateCpm,
          'depth_tenths_mm': (refinedSummary.depthCm * 100).round(),
          'recoil_percent': refinedSummary.recoilPercentage,
          'ccf_percent': refinedSummary.ccfPercent,
          'total_compressions': refinedSummary.totalCompressions,
          'elapsed_sec': refinedSummary.elapsedSeconds,
          'quality_flags': refinedSummary.qualityFlags,
        },
      };
}

class _StrokeEntry {
  int strokeNum;
  int onsetIdx;
  int endIdx;
  double depthMm;
  int rawPeriodMs;
  int flags;
  bool recoilOk;

  _StrokeEntry({
    required this.strokeNum,
    required this.onsetIdx,
    required this.endIdx,
    required this.depthMm,
    required this.rawPeriodMs,
    required this.flags,
    required this.recoilOk,
  });

  bool get isSteady => (flags & AppBleConfig.qualitySteadyCadence) != 0;
  bool get isFirstStroke => (flags & AppBleConfig.qualityFirstStroke) != 0;
  bool get isSubPeriodBounce =>
      (flags & AppBleConfig.qualitySubPeriodBounce) != 0;
  bool get isWindowClamped => (flags & AppBleConfig.qualityWindowClamped) != 0;
  bool get isHesitationOnset =>
      (flags & AppBleConfig.qualityHesitationOnset) != 0;
}

class _ProcessedSample {
  final int nowMs;
  final double dt;
  final double rawNetG;
  final double filteredG;

  const _ProcessedSample({
    required this.nowMs,
    required this.dt,
    required this.rawNetG,
    required this.filteredG,
  });
}

/// Retroactive refinement engine executed on the phone when a session finishes.
class SessionRefinementEngine {
  static const double _gCm = 980.665;
  static const double _nominalK = 11.20;
  static const double _defaultManikinK = 10.85;

  /// Refines the completed session using the recorded [sessionPackets] and
  /// optional 100 Hz [rawSamples] buffer.
  static SessionRefinementResult refineSession({
    required CprMetrics firmwareSummary,
    required List<CprMetrics> sessionPackets,
    List<RawTelemetrySample> rawSamples = const <RawTelemetrySample>[],
    double depthK = _defaultManikinK,
    String sensitivityPreset = 'BALANCED',
  }) {
    // Extract distinct realtime stroke packets (where totalCompressions advances).
    final List<CprMetrics> realtimeStrokes = <CprMetrics>[];
    int lastCount = 0;
    for (final CprMetrics pkt in sessionPackets) {
      if (pkt.packetType == AppBleConfig.packetRealtime &&
          pkt.totalCompressions > lastCount) {
        realtimeStrokes.add(pkt);
        lastCount = pkt.totalCompressions;
      }
    }

    // If fewer than 4 strokes were captured in packets, keep firmware summary.
    if (realtimeStrokes.length < 4) {
      return SessionRefinementResult(
        refinedSummary: firmwareSummary,
        firmwareSummary: firmwareSummary,
      );
    }

    // Reconstruct 100 Hz waveform if rawSamples has sufficient continuity.
    final List<_ProcessedSample> waveform = _buildWaveform(rawSamples);
    final bool hasUsableWaveform = waveform.length >= 150;

    // Build initial stroke table from packets (linking sample indices if waveform exists).
    final List<_StrokeEntry> entries = _buildStrokeEntries(
      realtimeStrokes,
      waveform,
       preset: sensitivityPreset,
    );

    if (entries.isEmpty) {
      return SessionRefinementResult(
        refinedSummary: firmwareSummary,
        firmwareSummary: firmwareSummary,
      );
    }

    // Stage 0: Zero-Phase Forward-Backward (filtfilt) Unsteady Stroke Correction
    if (hasUsableWaveform) {
      _applyZeroPhaseFiltfiltToUnsteadyStrokes(waveform, entries);
    }

    // Compute steady session reference period & depth
    final List<int> steadyPeriods = entries
        .where((e) => e.isSteady && e.rawPeriodMs >= 320 && e.rawPeriodMs <= 1200)
        .map((e) => e.rawPeriodMs)
        .toList();
    final double medPeriod = steadyPeriods.isNotEmpty
        ? _medianInt(steadyPeriods)
        : 560.0;

    final List<double> steadyDepths = entries
        .where((e) => e.isSteady && e.depthMm > 0.0)
        .map((e) => e.depthMm)
        .toList();
    final double globalMedDepth = steadyDepths.isNotEmpty
        ? _medianDouble(steadyDepths)
        : _medianDouble(entries.map((e) => e.depthMm).toList());

    // Stage 1: Case A (True Split Stroke Merge) vs. Case B (Boundary-Shifted Carryover Pair)
    int mergedCount = 0;
    int rebalancedCount = 0;
    final List<_StrokeEntry> stage1 = <_StrokeEntry>[];
    int i = 0;
    while (i < entries.length) {
      final _StrokeEntry cur = entries[i];
      if (i + 1 < entries.length) {
        final _StrokeEntry nxt = entries[i + 1];
        final int pairPeriod = cur.rawPeriodMs + nxt.rawPeriodMs;

        // Case A: 1 real compression split into 2 fragments (pairPeriod <= 1.30 * medPeriod)
        final bool isCaseASplit =
            (cur.rawPeriodMs < 330 ||
                nxt.rawPeriodMs < 330 ||
                cur.isSubPeriodBounce ||
                nxt.isSubPeriodBounce) &&
            pairPeriod <= math.max(700.0, 1.30 * medPeriod);

        if (isCaseASplit) {
          double mergedDepthMm =
              math.min(100.0, math.sqrt(cur.depthMm * cur.depthMm + nxt.depthMm * nxt.depthMm));
          if (hasUsableWaveform && nxt.endIdx > cur.onsetIdx) {
            final int prevEnd = stage1.isNotEmpty ? stage1.last.endIdx : 0;
            int sIdx = math.max(prevEnd, nxt.onsetIdx - 22);
            if (nxt.endIdx - sIdx > 62) {
              sIdx = nxt.endIdx - 62;
            }
            final double? dCm = _closedCycleDepthCm(waveform, sIdx, nxt.endIdx);
            if (dCm != null && dCm >= 0.25) {
              final double reintMm =
                  math.min(100.0, math.max(0.0, dCm * (depthK / _nominalK) * 10.0));
              if (reintMm >= math.max(cur.depthMm, nxt.depthMm)) {
                mergedDepthMm = reintMm;
              }
            }
          }
          stage1.add(
            _StrokeEntry(
              strokeNum: cur.strokeNum,
              onsetIdx: cur.onsetIdx,
              endIdx: nxt.endIdx,
              depthMm: mergedDepthMm,
              rawPeriodMs: pairPeriod,
              flags: nxt.flags | AppBleConfig.qualitySteadyCadence,
              recoilOk: cur.recoilOk || nxt.recoilOk,
            ),
          );
          mergedCount++;
          i += 2;
          continue;
        }

        // Case B: 2 real compressions whose shared boundary shifted early
        final bool isCaseBCurryover =
            (cur.rawPeriodMs < 320 || cur.isSubPeriodBounce) &&
            nxt.rawPeriodMs > 700 &&
            pairPeriod >= 1.55 * medPeriod;

        if (isCaseBCurryover) {
          final double avgPairDepth = 0.5 * (cur.depthMm + nxt.depthMm);
          final int halfPeriod = (0.5 * pairPeriod).round();
          cur.depthMm = avgPairDepth;
          nxt.depthMm = avgPairDepth;
          cur.rawPeriodMs = halfPeriod;
          nxt.rawPeriodMs = halfPeriod;
          cur.flags |= AppBleConfig.qualitySteadyCadence;
          nxt.flags |= AppBleConfig.qualitySteadyCadence;
          stage1.add(cur);
          stage1.add(nxt);
          rebalancedCount++;
          i += 2;
          continue;
        }
      }
      stage1.add(cur);
      i++;
    }

    // Stage 2: Recover any missed shallow/hesitant strokes in long gaps (>72 samples)
    int recoveredCount = 0;
    final List<_StrokeEntry> stage2 = <_StrokeEntry>[];
    final double pTrig = sensitivityPreset == 'HIGH'
        ? 0.06
        : (sensitivityPreset == 'STRICT' ? 0.12 : 0.08);
    final double pArmMin = sensitivityPreset == 'HIGH'
        ? 0.030
        : (sensitivityPreset == 'STRICT' ? 0.070 : 0.040);
    final double pMinDepthCm = sensitivityPreset == 'STRICT' ? 0.50 : 0.25;

    for (int idx = 0; idx < stage1.length; idx++) {
      final _StrokeEntry p = stage1[idx];
      if (hasUsableWaveform && p.onsetIdx > 0) {
        int prevEnd = idx > 0 ? stage1[idx - 1].endIdx : 0;
        final int gapSamples = p.onsetIdx - prevEnd;
        if (gapSamples > 72 && p.onsetIdx <= waveform.length) {
          final int gStart = prevEnd + 10;
          final int gEnd = p.onsetIdx - 10;
          int scan = gStart;
          while (scan < gEnd - 22) {
            if (waveform[scan].filteredG > pTrig) {
              double pkVal = waveform[scan].filteredG;
              int kScan = scan + 1;
              while (kScan < gEnd && waveform[kScan].filteredG >= 0.0) {
                if (waveform[kScan].filteredG > pkVal) {
                  pkVal = waveform[kScan].filteredG;
                }
                kScan++;
              }
              double trVal = 0.0;
              while (kScan < gEnd && waveform[kScan].filteredG < -0.02) {
                if (waveform[kScan].filteredG < trVal) {
                  trVal = waveform[kScan].filteredG;
                }
                kScan++;
              }
              if (trVal < -math.max(pArmMin, 0.15 * pkVal) &&
                  (kScan - scan) >= 19) {
                final int sIdx = math.max(prevEnd, scan - 20);
                final int eIdx = math.min(waveform.length, kScan + 1);
                final double? dCm = _closedCycleDepthCm(waveform, sIdx, eIdx);
                if (dCm != null && dCm >= pMinDepthCm) {
                  final double scaledMm = math.min(
                    100.0,
                    math.max(0.0, dCm * (depthK / _nominalK) * 10.0),
                  );
                  final int prevMs =
                      prevEnd > 0 && prevEnd < waveform.length
                          ? waveform[prevEnd].nowMs
                          : waveform.first.nowMs;
                  stage2.add(
                    _StrokeEntry(
                      strokeNum: -1,
                      onsetIdx: scan,
                      endIdx: eIdx,
                      depthMm: scaledMm,
                      rawPeriodMs: waveform[kScan].nowMs - prevMs,
                      flags: AppBleConfig.qualitySteadyCadence,
                      recoilOk: trVal < -0.35,
                    ),
                  );
                  recoveredCount++;
                  prevEnd = eIdx;
                  scan = kScan + 8;
                  continue;
                }
              }
            }
            scan++;
          }
        }
      }
      stage2.add(p);
    }

    // Stage 3: Winsorize remaining unsteady / window-clamped transition outliers
    int winsorizedCount = 0;
    final List<double> finalDepthsMm = <double>[];
    int goodRecoilCount = 0;
    for (int idx = 0; idx < stage2.length; idx++) {
      final _StrokeEntry p = stage2[idx];
      if (p.recoilOk) goodRecoilCount++;
      double d = p.depthMm;
      final bool isUnsteady =
          !p.isSteady || p.isWindowClamped || p.isHesitationOnset;
      if (isUnsteady && d > 0.0) {
        final int lo = math.max(0, idx - 2);
        final int hi = math.min(stage2.length, idx + 3);
        final List<double> localSteady = <double>[];
        for (int j = lo; j < hi; j++) {
          if (stage2[j].isSteady && stage2[j].depthMm > 0.0) {
            localSteady.add(stage2[j].depthMm);
          }
        }
        final double refD =
            localSteady.isNotEmpty ? _medianDouble(localSteady) : globalMedDepth;
        if ((d - refD).abs() > 5.0) {
          d = refD + (d > refD ? 5.0 : -5.0);
          winsorizedCount++;
        }
      }
      if (d > 0.0) {
        finalDepthsMm.add(d);
      }
    }

    final bool anyCorrection = hasUsableWaveform ||
        mergedCount > 0 ||
        rebalancedCount > 0 ||
        recoveredCount > 0 ||
        winsorizedCount > 0;
    if (!anyCorrection) {
      return SessionRefinementResult(
        refinedSummary: firmwareSummary,
        firmwareSummary: firmwareSummary,
      );
    }

    final double refinedMeanDepthMm = finalDepthsMm.isNotEmpty
        ? finalDepthsMm.reduce((a, b) => a + b) / finalDepthsMm.length
        : firmwareSummary.depthMm;
    final int refinedDepthTenthsMm = (refinedMeanDepthMm * 10.0).round();

    final List<int> validPeriods = stage2
        .where((e) => !e.isFirstStroke && e.rawPeriodMs >= 300 && e.rawPeriodMs <= 1500)
        .map((e) => e.rawPeriodMs)
        .toList();
    final int refinedRateCpm = validPeriods.isNotEmpty
        ? (60000.0 * validPeriods.length / validPeriods.reduce((a, b) => a + b))
            .round()
        : firmwareSummary.rateCpm;

    final int refinedCount = stage2.length;
    final int refinedRecoilPct = refinedCount > 0
        ? ((goodRecoilCount / refinedCount) * 100.0).round().clamp(0, 100)
        : firmwareSummary.recoilPercentage;

    final CprMetrics refined = CprMetrics(
      packetType: AppBleConfig.packetFinalSummary,
      recoilComplete: refinedRecoilPct >= 100,
      recoilPercentage: refinedRecoilPct,
      rateCpm: refinedRateCpm.clamp(0, AppBleConfig.maxPlausibleRateCpm),
      depthCm: refinedDepthTenthsMm / 100.0,
      depthMm: refinedDepthTenthsMm / 10.0,
      ccfPercent: firmwareSummary.ccfPercent,
      audioPromptCode: 0,
      totalCompressions: refinedCount,
      elapsedSeconds: firmwareSummary.elapsedSeconds,
      qualityFlags: firmwareSummary.qualityFlags,
      sequence: firmwareSummary.sequence,
    );

    return SessionRefinementResult(
      refinedSummary: refined,
      firmwareSummary: firmwareSummary,
      mergedSplitStrokes: mergedCount,
      rebalancedCarryoverPairs: rebalancedCount,
      recoveredGapStrokes: recoveredCount,
      winsorizedUnsteadyStrokes: winsorizedCount,
      usedRawWaveform: hasUsableWaveform,
    );
  }

  // -------------------------------------------------------------------------
  // Waveform Reconstruction & Zero-Phase Forward-Backward (filtfilt) Helpers
  // -------------------------------------------------------------------------

  static List<_ProcessedSample> _buildWaveform(
    List<RawTelemetrySample> rawSamples,
  ) {
    if (rawSamples.length < 30) return const <_ProcessedSample>[];

    // Find quietest 25-sample window to learn gravity vector (ux, uy, uz, mag)
    double bestSpread = 999.0;
    int bestStart = 0;
    final int limit = math.min(rawSamples.length - 25, 250);
    for (int i = 0; i <= limit; i += 5) {
      double minZ = 999.0;
      double maxZ = -999.0;
      for (int j = i; j < i + 25; j++) {
        final double z = rawSamples[j].chestZMg / 1000.0;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }
      if (maxZ - minZ < bestSpread) {
        bestSpread = maxZ - minZ;
        bestStart = i;
      }
    }

    double mx = 0.0, my = 0.0, mz = 0.0;
    for (int j = bestStart; j < bestStart + 25; j++) {
      mx += rawSamples[j].chestXMg / 1000.0;
      my += rawSamples[j].chestYMg / 1000.0;
      mz += rawSamples[j].chestZMg / 1000.0;
    }
    mx /= 25.0;
    my /= 25.0;
    mz /= 25.0;
    final double mag = math.sqrt(mx * mx + my * my + mz * mz);
    final double ux = mag > 0.1 ? mx / mag : 0.0;
    final double uy = mag > 0.1 ? my / mag : 0.0;
    final double uz = mag > 0.1 ? mz / mag : 1.0;

    final List<_ProcessedSample> out = <_ProcessedSample>[];
    final int t0 = rawSamples.first.timeUs;
    int? prevT;
    double filtered = 0.0;
    const double alpha = 0.25;

    for (final RawTelemetrySample r in rawSamples) {
      double dt = (prevT != null && r.timeUs > prevT)
          ? (r.timeUs - prevT) / 1e6
          : 0.01;
      if (dt > 0.100 || dt <= 0.0) dt = 0.01;
      prevT = r.timeUs;

      final double cx = r.chestXMg / 1000.0;
      final double cy = r.chestYMg / 1000.0;
      final double cz = r.chestZMg / 1000.0;
      final double aChestG = (cx * ux + cy * uy + cz * uz) - mag;
      final double rawNetG = -aChestG;
      filtered = alpha * rawNetG + (1.0 - alpha) * filtered;
      final int nowMs = ((r.timeUs - t0) ~/ 1000) + 1000;

      out.add(
        _ProcessedSample(
          nowMs: nowMs,
          dt: dt,
          rawNetG: rawNetG,
          filteredG: filtered,
        ),
      );
    }
    return out;
  }

  static List<_StrokeEntry> _buildStrokeEntries(
    List<CprMetrics> realtimeStrokes,
    List<_ProcessedSample> waveform, {
    required String preset,
  }) {
    // If we have the 100 Hz waveform, run the exact state-machine index tracker
    // to obtain exact (onsetIdx, endIdx, rawPeriodMs) for each stroke while
    // pairing with the firmware's reported depths/flags.
    if (waveform.length >= 150) {
      final double pTrig =
          preset == 'HIGH' ? 0.06 : (preset == 'STRICT' ? 0.12 : 0.08);
      final double pAdap =
          preset == 'HIGH' ? 0.25 : (preset == 'STRICT' ? 0.40 : 0.30);
      final double pArmF =
          preset == 'HIGH' ? 0.20 : (preset == 'STRICT' ? 0.25 : 0.15);
      final double pArmM =
          preset == 'HIGH' ? 0.030 : (preset == 'STRICT' ? 0.070 : 0.040);
      final double pMinD = preset == 'STRICT' ? 0.50 : 0.25;

      String state = 'WAITING';
      double env = 0.0;
      int strokeStartMs = 0;
      int lastPeakMs = waveform.first.nowMs;
      int onsetIdx = 0;
      int peakIdx = 0;
      int lastEndIdx = 0;
      double peakAccel = 0.0;
      double troughAccel = 0.0;
      bool recoilArmed = false;

      final List<_StrokeEntry> simEntries = <_StrokeEntry>[];
      final List<int> periods = <int>[];
      final List<int> recentPeriods = <int>[];

      for (int idx = 0; idx < waveform.length; idx++) {
        final _ProcessedSample s = waveform[idx];
        final bool isIdleUnmask =
            state == 'WAITING' && (s.nowMs - lastPeakMs > 650);
        env *= isIdleUnmask ? 0.960 : 0.993;
        if (s.filteredG.abs() > env) env = s.filteredG.abs();

        final double startThresh =
            math.min(0.28, math.max(pTrig, pAdap * env));
        final double armLevel = -math.max(pArmM, pArmF * peakAccel);

        if ((state == 'COMPRESSING' || state == 'RECOILING') &&
            strokeStartMs > 0 &&
            (s.nowMs - strokeStartMs > 2000)) {
          state = 'WAITING';
          peakAccel = 0.0;
          troughAccel = 0.0;
        }

        if (state == 'WAITING') {
          final bool onsetOk =
              strokeStartMs == 0 || (s.nowMs - strokeStartMs > 300);
          final bool quietOk = (s.nowMs - lastPeakMs > 80);
          if (s.filteredG > startThresh && onsetOk && quietOk) {
            state = 'COMPRESSING';
            strokeStartMs = s.nowMs;
            onsetIdx = idx;
            peakIdx = idx;
            peakAccel = s.filteredG;
            troughAccel = s.filteredG;
            recoilArmed = false;
          }
        } else if (state == 'COMPRESSING') {
          if (s.filteredG > peakAccel) {
            peakAccel = s.filteredG;
            peakIdx = idx;
          }
          if (s.filteredG < 0.0) {
            state = 'RECOILING';
            troughAccel = s.filteredG;
            recoilArmed = false;
          }
        } else if (state == 'RECOILING') {
          if (s.filteredG < troughAccel) troughAccel = s.filteredG;
          if (s.filteredG < armLevel) recoilArmed = true;
          final bool minDurOk = (s.nowMs - strokeStartMs >= 190);
          if (recoilArmed && minDurOk && s.filteredG >= -0.02) {
            final int rawPeriodMs = s.nowMs - lastPeakMs;
            final bool isPostPause =
                rawPeriodMs > 1500 || simEntries.isEmpty;
            final int strokeEndIdx = idx + 1;

            bool winClamped = false;
            double? physCm;
            if (!isPostPause) {
              int preS = 22;
              if (periods.isNotEmpty) {
                final List<int> tail = periods.length > 5
                    ? periods.sublist(periods.length - 5)
                    : List<int>.of(periods);
                tail.sort();
                final int medP = tail[tail.length ~/ 2];
                preS = ((0.40 * (medP / 10.0)).round()).clamp(16, 26);
              }
              int sIdx = math.max(lastEndIdx, onsetIdx - preS);
              if (strokeEndIdx - sIdx >= 66) {
                sIdx = strokeEndIdx - 66;
                winClamped = true;
              }
              physCm = _closedCycleDepthCm(waveform, sIdx, strokeEndIdx);
            }
            physCm ??= _fromRestDepthCm(waveform, onsetIdx, strokeEndIdx);
            physCm ??= _closedCycleDepthCm(
              waveform,
              math.max(0, onsetIdx - 8),
              strokeEndIdx,
            );

            if (physCm != null && physCm < pMinD) {
              state = 'WAITING';
              continue;
            }

            final bool rateValid = !isPostPause && rawPeriodMs >= 300;
            final List<int> tempRecent = List<int>.of(recentPeriods);
            if (rateValid) {
              tempRecent.add(rawPeriodMs);
              if (tempRecent.length > 4) tempRecent.removeAt(0);
            }
            bool isSteady = true;
            if (rateValid && tempRecent.length >= 3) {
              final double mp =
                  tempRecent.reduce((a, b) => a + b) / tempRecent.length;
              double sumDev = 0.0;
              for (final int x in tempRecent) {
                sumDev += (x - mp).abs();
              }
              final double md = sumDev / tempRecent.length;
              isSteady = mp > 0 ? (md / mp <= 0.25) : true;
            } else if (!rateValid) {
              isSteady = false;
            }

            lastPeakMs = s.nowMs;
            lastEndIdx = strokeEndIdx;
            if (rateValid) {
              periods.add(rawPeriodMs);
              recentPeriods.add(rawPeriodMs);
              if (recentPeriods.length > 4) recentPeriods.removeAt(0);
            } else {
              recentPeriods.clear();
            }

            int flags = 0;
            if (isSteady) flags |= AppBleConfig.qualitySteadyCadence;
            if (isPostPause) flags |= AppBleConfig.qualityFirstStroke;
            if (!isPostPause && rawPeriodMs < 300) {
              flags |= AppBleConfig.qualitySubPeriodBounce;
            }
            if (winClamped) flags |= AppBleConfig.qualityWindowClamped;
            if (peakIdx - onsetIdx > 12) {
              flags |= AppBleConfig.qualityHesitationOnset;
            }

            final int pktIdx = simEntries.length;
            final double depthMm = pktIdx < realtimeStrokes.length
                ? realtimeStrokes[pktIdx].depthMm
                : math.min(
                    100.0,
                    math.max(0.0, (physCm ?? 0.0) * (_defaultManikinK / _nominalK) * 10.0),
                  );

            simEntries.add(
              _StrokeEntry(
                strokeNum: pktIdx + 1,
                onsetIdx: onsetIdx,
                endIdx: strokeEndIdx,
                depthMm: depthMm,
                rawPeriodMs: rawPeriodMs,
                flags: pktIdx < realtimeStrokes.length
                    ? (realtimeStrokes[pktIdx].qualityFlags | flags)
                    : flags,
                recoilOk: troughAccel < -0.35,
              ),
            );
            state = 'WAITING';
          }
        }
      }

      if (simEntries.isNotEmpty) {
        return simEntries;
      }
    }

    // Packet-only fallback when raw 100 Hz waveform is unavailable
    final List<_StrokeEntry> pktEntries = <_StrokeEntry>[];
    for (int i = 0; i < realtimeStrokes.length; i++) {
      final CprMetrics m = realtimeStrokes[i];
      int estPeriodMs = 550;
      if (m.isFirstStroke) {
        estPeriodMs = 1600;
      } else if (m.isSubPeriodBounce || m.rateCpm == 0) {
        estPeriodMs = 280;
      } else if (m.rateCpm > 0) {
        estPeriodMs = (60000.0 / m.rateCpm).round();
      }
      pktEntries.add(
        _StrokeEntry(
          strokeNum: m.totalCompressions,
          onsetIdx: 0,
          endIdx: 0,
          depthMm: m.depthMm,
          rawPeriodMs: estPeriodMs,
          flags: m.qualityFlags,
          recoilOk: m.recoilComplete,
        ),
      );
    }
    return pktEntries;
  }

  static void _applyZeroPhaseFiltfiltToUnsteadyStrokes(
    List<_ProcessedSample> waveform,
    List<_StrokeEntry> entries,
  ) {
    if (waveform.length < 32 || entries.isEmpty) return;

    final List<double> aRaw =
        waveform.map((s) => s.rawNetG * _gCm).toList(growable: false);
    final List<double> aHp = _filtfiltHighPass(aRaw, fc: 0.55, fs: 100.0);

    final List<double> v = List<double>.filled(waveform.length, 0.0);
    for (int i = 1; i < waveform.length; i++) {
      v[i] = v[i - 1] + 0.5 * (aHp[i - 1] + aHp[i]) * waveform[i].dt;
    }
    final List<double> vHp = _filtfiltHighPass(v, fc: 0.55, fs: 100.0);

    final List<double> x = List<double>.filled(waveform.length, 0.0);
    for (int i = 1; i < waveform.length; i++) {
      x[i] = x[i - 1] + 0.5 * (vHp[i - 1] + vHp[i]) * waveform[i].dt;
    }
    final List<double> xHp = _filtfiltHighPass(x, fc: 0.35, fs: 100.0);

    final List<double> ffStrokesMm = <double>[];
    final List<double> steadyRatios = <double>[];

    for (final _StrokeEntry e in entries) {
      final int lo = math.max(0, e.onsetIdx - 15);
      final int hi = math.min(xHp.length, e.endIdx + 5);
      if (hi > lo) {
        double minX = xHp[lo];
        double maxX = xHp[lo];
        for (int k = lo + 1; k < hi; k++) {
          if (xHp[k] < minX) minX = xHp[k];
          if (xHp[k] > maxX) maxX = xHp[k];
        }
        final double ffMm = (maxX - minX) * 10.0;
        ffStrokesMm.add(ffMm);
        if (e.isSteady && ffMm > 5.0 && e.depthMm > 5.0) {
          steadyRatios.add(e.depthMm / ffMm);
        }
      } else {
        ffStrokesMm.add(0.0);
      }
    }

    final double sessionScale =
        steadyRatios.isNotEmpty ? _medianDouble(steadyRatios) : 1.158;

    for (int i = 0; i < entries.length; i++) {
      final _StrokeEntry e = entries[i];
      final double ffMm = ffStrokesMm[i];
      final bool isUnsteady =
          !e.isSteady || e.isWindowClamped || e.isHesitationOnset;
      if (isUnsteady && !e.isSubPeriodBounce && ffMm > 5.0) {
        final double dFfCal = math.min(100.0, ffMm * sessionScale);
        e.depthMm = 0.60 * dFfCal + 0.40 * e.depthMm;
      }
    }
  }

  static List<double> _filtfiltHighPass(
    List<double> x, {
    required double fc,
    double fs = 100.0,
  }) {
    if (x.length < 16) return List<double>.of(x);
    final double w0 = 2.0 * math.pi * fc / fs;
    final double cosW0 = math.cos(w0);
    final double sinW0 = math.sin(w0);
    final double alpha = sinW0 / math.sqrt2;
    final double a0 = 1.0 + alpha;
    final double b0 = ((1.0 + cosW0) / 2.0) / a0;
    final double b1 = (-(1.0 + cosW0)) / a0;
    final double b2 = ((1.0 + cosW0) / 2.0) / a0;
    final double a1 = (-2.0 * cosW0) / a0;
    final double a2 = (1.0 - alpha) / a0;

    List<double> runBiquad(List<double> input) {
      final List<double> y = List<double>.filled(input.length, 0.0);
      double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
      for (int i = 0; i < input.length; i++) {
        final double xi = input[i];
        final double yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        y[i] = yi;
        x2 = x1;
        x1 = xi;
        y2 = y1;
        y1 = yi;
      }
      return y;
    }

    final int pad = math.min(40, x.length - 1);
    final List<double> padded = <double>[
      for (int i = pad; i >= 1; i--) 2.0 * x.first - x[i],
      ...x,
      for (int i = 1; i <= pad; i++) 2.0 * x.last - x[x.length - 1 - i],
    ];
    final List<double> forward = runBiquad(padded);
    final List<double> backward =
        runBiquad(forward.reversed.toList()).reversed.toList();
    return backward.sublist(pad, pad + x.length);
  }

  static double? _closedCycleDepthCm(
    List<_ProcessedSample> waveform,
    int startIdx,
    int endIdx,
  ) {
    if (startIdx < 0 ||
        endIdx <= startIdx ||
        endIdx > waveform.length ||
        (endIdx - startIdx) < 15 ||
        (endIdx - startIdx) > 128) {
      return null;
    }

    double totalT = 0.0;
    double weightedSumA = 0.0;
    for (int i = startIdx; i < endIdx; i++) {
      final double dt = waveform[i].dt;
      weightedSumA += waveform[i].rawNetG * dt;
      totalT += dt;
    }
    if (totalT <= 0.001) return null;
    final double meanA = weightedSumA / totalT;

    double v = 0.0;
    double weightedSumV = 0.0;
    for (int i = startIdx; i < endIdx; i++) {
      final double dt = waveform[i].dt;
      final double a = (waveform[i].rawNetG - meanA) * _gCm;
      v += a * dt;
      weightedSumV += v * dt;
    }
    final double meanV = weightedSumV / totalT;

    v = 0.0;
    double x = 0.0;
    double minX = 0.0;
    double maxX = 0.0;
    for (int i = startIdx; i < endIdx; i++) {
      final double dt = waveform[i].dt;
      final double a = (waveform[i].rawNetG - meanA) * _gCm;
      v += a * dt;
      x += (v - meanV) * dt;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
    }
    return maxX - minX;
  }

  static double? _fromRestDepthCm(
    List<_ProcessedSample> waveform,
    int onsetIdx,
    int endIdx,
  ) {
    if (endIdx <= onsetIdx || endIdx > waveform.length) return null;
    final int startIdx = onsetIdx > 8 ? onsetIdx - 8 : 0;
    if (startIdx < 8) return null;
    final int restStart = startIdx - 8;
    double restMin = 999.0;
    double restMax = -999.0;
    for (int i = restStart; i < startIdx; i++) {
      final double g = waveform[i].rawNetG;
      if (g < restMin) restMin = g;
      if (g > restMax) restMax = g;
    }
    if (restMax - restMin > 0.15) return null;
    return _closedCycleDepthCm(waveform, startIdx, endIdx);
  }

  static double _medianDouble(List<double> values) {
    if (values.isEmpty) return 0.0;
    final List<double> sorted = List<double>.of(values)..sort();
    final int mid = sorted.length ~/ 2;
    if (sorted.length.isEven) {
      return 0.5 * (sorted[mid - 1] + sorted[mid]);
    }
    return sorted[mid];
  }

  static double _medianInt(List<int> values) {
    if (values.isEmpty) return 0.0;
    final List<int> sorted = List<int>.of(values)..sort();
    final int mid = sorted.length ~/ 2;
    if (sorted.length.isEven) {
      return 0.5 * (sorted[mid - 1] + sorted[mid]);
    }
    return sorted[mid].toDouble();
  }
}
