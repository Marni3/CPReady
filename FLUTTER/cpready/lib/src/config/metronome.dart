/// Metronome defaults and the values the Practice Setup picker offers.
///
/// The tempo presets sit inside the AHA target band so the pacing cue matches
/// the same range the rate capsule is graded against. The preference keys are
/// read by `MetronomePreferences` in `core/settings/`.

class AppMetronome {
  /// The metronome is on the first time Live Practice opens.
  static const bool defaultEnabled = true;

  /// Tempo used before the trainee picks one (the middle of the target band).
  static const int defaultTempoBpm = 110;

  /// Tempos offered on Practice Setup, in beats per minute.
  static const List<int> tempoOptionsBpm = <int>[100, 110, 120];

  /// `shared_preferences` key for the on/off choice.
  static const String enabledKey = 'metronome_enabled';

  /// `shared_preferences` key for the chosen tempo.
  static const String tempoKey = 'metronome_tempo_bpm';

  /// Time between two beats at [bpm].
  static Duration beatInterval(int bpm) =>
      Duration(milliseconds: (60000 / bpm).round());

  /// Metronome tick volume, kept consistent and never lowered for voice cues.
  /// Range 0.0 (silent) to 1.0 (full).
  static const double volume = 1.0;
}
