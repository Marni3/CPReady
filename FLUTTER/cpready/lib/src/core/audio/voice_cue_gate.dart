/// Decides whether an incoming firmware cue should be spoken.
///
/// The firmware already arbitrates and rate-limits its prompts (one at most
/// every five seconds), so this gate only protects against duplicate packets
/// and against two cues starting on top of each other.

import '../../config/config.dart';

class VoiceCueGate {
  VoiceCueGate({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Injected clock, so tests can advance time without waiting.
  final DateTime Function() _clock;

  int? _lastCode;
  DateTime? _lastPlayedAt;

  /// True when [cueCode] maps to an asset and enough time has passed since the
  /// previous cue. An accepted cue is recorded immediately.
  bool allows(int cueCode) {
    if (!AppAssets.voicePrompts.containsKey(cueCode)) return false;

    final DateTime now = _clock();
    final DateTime? lastAt = _lastPlayedAt;
    if (lastAt != null) {
      final Duration elapsed = now.difference(lastAt);
      if (_lastCode == cueCode && elapsed < AppDurations.voiceCueDuplicate) {
        return false;
      }
      if (elapsed < AppDurations.voiceCueMinGap) return false;
    }

    _lastCode = cueCode;
    _lastPlayedAt = now;
    return true;
  }

  /// Forgets the last cue, so a new session starts with a clean gate.
  void reset() {
    _lastCode = null;
    _lastPlayedAt = null;
  }
}
