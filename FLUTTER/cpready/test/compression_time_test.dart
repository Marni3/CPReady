/// Compression / pause split derived from the firmware's CCF.

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/core/metrics/compression_time.dart';

void main() {
  test('splits a session so the two values add up to the duration', () {
    final CompressionTimeBreakdown times =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: 88,
      durationSeconds: 110,
    )!;

    expect(times.compressionSeconds, 97); // 96.8 s rounds up
    expect(times.pauseSeconds, 13);
    expect(times.compressionSeconds + times.pauseSeconds, 110);
  });

  test('handles the 0% and 100% ends', () {
    final CompressionTimeBreakdown none =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: 0,
      durationSeconds: 60,
    )!;
    expect(none.compressionSeconds, 0);
    expect(none.pauseSeconds, 60);

    final CompressionTimeBreakdown all =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: 100,
      durationSeconds: 60,
    )!;
    expect(all.compressionSeconds, 60);
    expect(all.pauseSeconds, 0);
  });

  test('clamps out-of-range CCF values', () {
    final CompressionTimeBreakdown over =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: 140,
      durationSeconds: 60,
    )!;
    expect(over.compressionSeconds, 60);
    expect(over.pauseSeconds, 0);

    final CompressionTimeBreakdown under =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: -5,
      durationSeconds: 60,
    )!;
    expect(under.compressionSeconds, 0);
    expect(under.pauseSeconds, 60);
  });

  test('returns null when there is nothing to derive from', () {
    expect(
      CompressionTimeBreakdown.fromCcf(
        ccfPercent: null,
        durationSeconds: 60,
      ),
      isNull,
    );
    expect(
      CompressionTimeBreakdown.fromCcf(
        ccfPercent: 88,
        durationSeconds: 0,
      ),
      isNull,
    );
    expect(
      CompressionTimeBreakdown.fromCcf(
        ccfPercent: 88,
        durationSeconds: -1,
      ),
      isNull,
    );
  });

  test('rounds half seconds up and below half down', () {
    // 1% of 60 s = 0.6 s.
    final CompressionTimeBreakdown up =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: 1,
      durationSeconds: 60,
    )!;
    expect(up.compressionSeconds, 1);

    // 1% of 40 s = 0.4 s.
    final CompressionTimeBreakdown down =
        CompressionTimeBreakdown.fromCcf(
      ccfPercent: 1,
      durationSeconds: 40,
    )!;
    expect(down.compressionSeconds, 0);
    expect(down.pauseSeconds, 40);
  });
}
