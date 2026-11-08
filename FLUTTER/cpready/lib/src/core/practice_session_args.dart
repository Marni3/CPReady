/// Values the practice flow carries between screens in GoRouter's `extra`.
///
/// Kept as one object because the flow grows: every screen between Practice
/// Setup and Live Practice must forward the trainee name, the session duration
/// and the metronome tempo without losing any of them.

import '../config/config.dart';

class PracticeSessionArgs {
  const PracticeSessionArgs({
    required this.traineeName,
    required this.practiceDurationSec,
    this.metronomeTempoBpm = AppMetronome.defaultTempoBpm,
  });

  /// Name the session is filed under.
  final String traineeName;

  /// Chosen session length in seconds; 0 means unlimited (manual stop only).
  final int practiceDurationSec;

  /// Metronome pace chosen on Practice Setup, in beats per minute.
  final int metronomeTempoBpm;
}
