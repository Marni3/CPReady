/// Splits a finished session's duration into active compression time and pause
/// time using the firmware's CCF percentage.
///
/// The firmware's final CCF is the total active compression time over the span
/// from the first detected compression to the end of the session, which is the
/// same span as the saved session duration. Deriving the split from CCF keeps
/// these figures consistent with the CCF capsule and with each other.
///
/// CCF is transmitted as a whole percent, so the derived values are accurate to
/// about one second on a two-minute session.

import 'dart:math' as math;

class CompressionTimeBreakdown {
  /// Seconds spent actively compressing.
  final int compressionSeconds;

  /// Seconds of the session that were not active compression.
  final int pauseSeconds;

  const CompressionTimeBreakdown({
    required this.compressionSeconds,
    required this.pauseSeconds,
  });

  /// Breakdown for a session with [durationSeconds] and [ccfPercent], or null
  /// when there is nothing to derive from (interrupted session or no time).
  ///
  /// The two values always add up to [durationSeconds].
  static CompressionTimeBreakdown? fromCcf({
    required int? ccfPercent,
    required int durationSeconds,
  }) {
    if (ccfPercent == null || durationSeconds <= 0) return null;

    final int ccf = math.min(math.max(ccfPercent, 0), 100);
    final int rounded = ((durationSeconds * ccf) / 100).round();
    final int compression = math.min(math.max(rounded, 0), durationSeconds);

    return CompressionTimeBreakdown(
      compressionSeconds: compression,
      pauseSeconds: durationSeconds - compression,
    );
  }
}
