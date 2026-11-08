/// The metronome's on/off choice and tempo, remembered across sessions.
///
/// Every read falls back to the [AppMetronome] defaults, so a missing key or a
/// storage failure can never leave the metronome silently off.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/config.dart';

class MetronomePreferences {
  const MetronomePreferences();

  /// The saved on/off choice, or the default (on) before anything is saved.
  Future<bool> loadEnabled() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(AppMetronome.enabledKey) ??
          AppMetronome.defaultEnabled;
    } catch (error) {
      debugPrint('Metronome preference read failed: $error');
      return AppMetronome.defaultEnabled;
    }
  }

  /// The saved tempo, or the default when the stored value is missing or is
  /// not one of the offered presets.
  Future<int> loadTempoBpm() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? stored = prefs.getInt(AppMetronome.tempoKey);
      if (stored == null || !AppMetronome.tempoOptionsBpm.contains(stored)) {
        return AppMetronome.defaultTempoBpm;
      }
      return stored;
    } catch (error) {
      debugPrint('Metronome tempo read failed: $error');
      return AppMetronome.defaultTempoBpm;
    }
  }

  Future<void> saveEnabled(bool enabled) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppMetronome.enabledKey, enabled);
    } catch (error) {
      debugPrint('Metronome preference save failed: $error');
    }
  }

  Future<void> saveTempoBpm(int bpm) async {
    if (!AppMetronome.tempoOptionsBpm.contains(bpm)) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(AppMetronome.tempoKey, bpm);
    } catch (error) {
      debugPrint('Metronome tempo save failed: $error');
    }
  }
}
