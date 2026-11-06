/// Values the practice flow carries between screens in GoRouter's `extra`.
///
/// Kept as one object because the flow grows: every screen between Practice
/// Setup and Live Practice must forward the trainee name and the session
/// duration without losing either.
class PracticeSessionArgs {
  const PracticeSessionArgs({
    required this.traineeName,
    required this.practiceDurationSec,
  });

  /// Name the session is filed under.
  final String traineeName;

  /// Chosen session length in seconds; 0 means unlimited (manual stop only).
  final int practiceDurationSec;
}
