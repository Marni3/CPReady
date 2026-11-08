/// Plays the firmware's coaching cues as bundled audio.
///
/// The firmware decides *when* to coach; this layer only turns its cue code
/// into the matching sound. A silent implementation keeps widget tests free of
/// platform audio channels.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../config/config.dart';
import 'audio_context.dart';

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
/// Each cue keeps its own preloaded player. A cue is replayed by seeking it to
/// zero and resuming it, so the player does not abandon and re-request audio
/// focus on every cue.
class AssetVoiceCoach implements VoiceCoach {
  final Map<int, AudioPlayer> _players = <int, AudioPlayer>{};
  final Map<int, Future<AudioPlayer?>> _loading = <int, Future<AudioPlayer?>>{};
  Future<void>? _preloadFuture;
  AudioPlayer? _activePlayer;
  int _playGeneration = 0;
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

  @override
  Future<void> preload() {
    if (_disposed) return Future<void>.value();
    return _preloadFuture ??= _preloadAll();
  }

  Future<void> _preloadAll() async {
    for (final MapEntry<int, String> entry in AppAssets.voicePrompts.entries) {
      if (_disposed) return;
      await _loadCue(entry.key);
    }
  }

  /// Returns the loaded player for [cueCode], waiting for an in-flight load or
  /// starting one if necessary. A player is never silently skipped just
  /// because the live screen opened while preload was still running.
  Future<AudioPlayer?> _loadCue(int cueCode) {
    final AudioPlayer? existing = _players[cueCode];
    if (existing != null) return Future<AudioPlayer?>.value(existing);

    final String? bundlePath = AppAssets.voicePrompts[cueCode];
    if (bundlePath == null) return Future<AudioPlayer?>.value();

    return _loading.putIfAbsent(
      cueCode,
      () => _createPlayer(cueCode, bundlePath),
    );
  }

  Future<AudioPlayer?> _createPlayer(int cueCode, String bundlePath) async {
    AudioPlayer? player;
    try {
      if (kDebugMode) {
        debugPrint('Voice cue $cueCode loading');
      }
      player = AudioPlayer();
      await player.setAudioContext(AppAudioContext.voiceCues);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource(_sourcePath(bundlePath)));

      if (_disposed) {
        await player.dispose();
        return null;
      }

      _players[cueCode] = player;
      player.onPlayerComplete.listen((_) {
        if (_disposed) return;
        if (!identical(_activePlayer, player)) return;
        _activePlayer = null;
      });
      if (kDebugMode) {
        debugPrint('Voice cue $cueCode preloaded');
      }
      return player;
    } catch (error) {
      debugPrint('Voice cue load failed for code $cueCode: $error');
      await player?.dispose();
      return null;
    } finally {
      _loading.remove(cueCode);
    }
  }

  @override
  Future<void> play(int cueCode) async {
    if (_disposed) return;

    final int generation = ++_playGeneration;
    if (kDebugMode) {
      debugPrint(
        'Voice cue $cueCode play requested at '
        '${DateTime.now().toIso8601String()}',
      );
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    final AudioPlayer? player = await _loadCue(cueCode);
    if (player == null || _disposed || generation != _playGeneration) {
      if (kDebugMode) {
        debugPrint(
            'Voice cue $cueCode not played: player unavailable or stale');
      }
      return;
    }

    try {
      final AudioPlayer? previous = _activePlayer;
      _activePlayer = player;
      if (previous != null && previous != player) {
        // Pause rather than stop: stop() abandons audio focus, which makes the
        // next cue wait for a fresh focus grant before it can start.
        try {
          await previous.pause();
        } catch (error) {
          debugPrint('Voice cue pause failed for previous cue: $error');
        }
        if (_disposed || generation != _playGeneration) return;
      }

      // Seek to zero instead of stop()+resume(). This restarts the preloaded
      // asset without the extra focus release/request cycle.
      await player.seek(Duration.zero);
      if (_disposed || generation != _playGeneration) return;
      await player.resume();
      if (_disposed || generation != _playGeneration) return;

      if (kDebugMode) {
        debugPrint(
          'Voice cue $cueCode started after '
          '${stopwatch.elapsedMilliseconds} ms',
        );
      }
    } catch (error) {
      debugPrint('Voice cue playback failed for code $cueCode: $error');
      if (identical(_activePlayer, player)) {
        _activePlayer = null;
      }
    }
  }

  @override
  Future<void> stop() async {
    _playGeneration++;
    _activePlayer = null;
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
    _playGeneration++;
    _activePlayer = null;
    for (final AudioPlayer player in _players.values) {
      try {
        await player.dispose();
      } catch (error) {
        debugPrint('Voice cue dispose failed: $error');
      }
    }
    _players.clear();
    _loading.clear();
  }
}
