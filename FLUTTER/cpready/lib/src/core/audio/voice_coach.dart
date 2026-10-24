/// Plays the firmware's coaching cues as bundled audio.
///
/// The firmware decides *when* to coach; this layer only turns its cue code
/// into the matching sound. A silent implementation keeps widget tests free of
/// platform audio channels.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../config/config.dart';

/// One voice-cue player, addressed by the firmware's `audio_prompt_code`.
abstract class VoiceCoach {
  /// Loads every cue so the first one starts without decode delay.
  Future<void> preload();

  /// Plays the cue for [cueCode]; unknown or silent codes are ignored.
  Future<void> play(int cueCode);

  /// Stops any cue that is currently speaking.
  Future<void> stop();

  /// Releases the players.
  Future<void> dispose();
}

/// A coach that never makes a sound, used by tests and by builds without
/// audio.
class SilentVoiceCoach implements VoiceCoach {
  const SilentVoiceCoach();

  @override
  Future<void> preload() async {}

  @override
  Future<void> play(int cueCode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Production coach backed by `audioplayers`.
///
/// Each cue keeps its own preloaded player. A cue is replayed by stopping its
/// player and resuming it, which restarts the asset from the beginning.
class AssetVoiceCoach implements VoiceCoach {
  final Map<int, AudioPlayer> _players = <int, AudioPlayer>{};
  bool _disposed = false;

  /// Prefix that `audioplayers` puts in front of every [AssetSource] path.
  static const String _bundlePrefix = 'assets/';

  /// Converts a bundle path from [AppAssets] into the path `audioplayers`
  /// expects.
  ///
  /// The plugin looks assets up through its `AudioCache`, whose default prefix
  /// is `assets/`, so an [AssetSource] takes a path *inside* the assets
  /// folder. [AppAssets] stores complete bundle paths (`assets/audio/...`),
  /// so the prefix is removed here — passing them through unchanged makes the
  /// plugin request `assets/assets/audio/...`, which does not exist.
  static String _sourcePath(String bundlePath) =>
      bundlePath.startsWith(_bundlePrefix)
      ? bundlePath.substring(_bundlePrefix.length)
      : bundlePath;

  /// Spoken coaching, tagged as speech on the media stream.
  ///
  /// The usage has to be `media`, not `assistanceSonification`: Android maps
  /// sonification to `STREAM_SYSTEM`, and that stream is muted whenever the
  /// phone is on silent/vibrate, so every cue would be inaudible with no error.
  /// The media stream is never muted by the ringer mode and is the one the
  /// user controls with the volume keys. Transient focus keeps the cue from
  /// talking over music the listener started.
  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
  );

  @override
  Future<void> preload() async {
    if (_disposed) return;

    for (final MapEntry<int, String> entry in AppAssets.voicePrompts.entries) {
      if (_disposed) return;
      if (_players.containsKey(entry.key)) continue;

      AudioPlayer? player;
      try {
        player = AudioPlayer();
        await player.setAudioContext(_context);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(_sourcePath(entry.value)));
        _players[entry.key] = player;
      } catch (error) {
        // A cue that fails to load is retried on the next preload instead of
        // leaving the coach permanently silent.
        debugPrint('Voice cue preload failed for code ${entry.key}: $error');
        await player?.dispose();
      }
    }
  }

  @override
  Future<void> play(int cueCode) async {
    final AudioPlayer? player = _players[cueCode];
    if (player == null || _disposed) return;

    try {
      await player.stop();
      await player.resume();
    } catch (error) {
      debugPrint('Voice cue playback failed for code $cueCode: $error');
    }
  }

  @override
  Future<void> stop() async {
    for (final AudioPlayer player in _players.values) {
      try {
        await player.stop();
      } catch (error) {
        debugPrint('Voice cue stop failed: $error');
      }
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final AudioPlayer player in _players.values) {
      try {
        await player.dispose();
      } catch (error) {
        debugPrint('Voice cue dispose failed: $error');
      }
    }
    _players.clear();
  }
}
