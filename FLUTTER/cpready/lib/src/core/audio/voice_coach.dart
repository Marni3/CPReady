
/// Plays CPReady's coaching cues as bundled audio.
///
/// Only one voice instruction plays at a time. Incoming cues are discarded
/// while another instruction is speaking, rather than queued or interrupted.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../config/config.dart';
import 'audio_context.dart';

/// One voice-cue player, addressed by its audio prompt code.
abstract class VoiceCoach {
  bool get isBusy;
  
  /// Loads every cue so the first one starts without decode delay.
  Future<void> preload();

  /// Plays the cue for [cueCode]; unknown or silent codes are ignored.
  Future<void> play(int cueCode);

  /// Stops any cue that is currently speaking.
  Future<void> stop();

  /// Releases the players.
  Future<void> dispose();
}

/// A coach that never makes a sound, used by tests and builds without audio.
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

  @override
  bool get isBusy => false;
}

/// Production voice coach backed by audioplayers.
///
/// Each cue has a preloaded player, but only one player can be active.
/// New requests are discarded while playback is busy.
class AssetVoiceCoach implements VoiceCoach {
  final Map<int, AudioPlayer> _players = <int, AudioPlayer>{};
  final Map<int, Future<AudioPlayer?>> _loading =
      <int, Future<AudioPlayer?>>{};

  Future<void>? _preloadFuture;
  AudioPlayer? _activePlayer;

  int _playGeneration = 0;
  bool _disposed = false;
  bool _isSpeaking = false;

  // Prevent a new cue from starting while stop() is still running.
  Future<void>? _stopFuture;
  @override
  bool get isBusy => _isSpeaking || _stopFuture != null;

  static const String _bundlePrefix = 'assets/';

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
    for (final MapEntry<int, String> entry
        in AppAssets.voicePrompts.entries) {
      if (_disposed) return;
      await _loadCue(entry.key);
    }
  }

  Future<AudioPlayer?> _loadCue(int cueCode) {
    if (_disposed) return Future<AudioPlayer?>.value();

    final AudioPlayer? existing = _players[cueCode];
    if (existing != null) {
      return Future<AudioPlayer?>.value(existing);
    }

    final String? bundlePath = AppAssets.voicePrompts[cueCode];
    if (bundlePath == null) {
      return Future<AudioPlayer?>.value();
    }

    return _loading.putIfAbsent(
      cueCode,
      () => _createPlayer(cueCode, bundlePath),
    );
  }

  Future<AudioPlayer?> _createPlayer(
    int cueCode,
    String bundlePath,
  ) async {
    AudioPlayer? player;

    try {
      if (kDebugMode) {
        debugPrint('Voice cue $cueCode loading');
      }

      player = AudioPlayer();

      await player.setAudioContext(AppAudioContext.voiceCues);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(1.0);
      await player.setSource(
        AssetSource(_sourcePath(bundlePath)),
      );

      if (_disposed) {
        await player.dispose();
        return null;
      }

      _players[cueCode] = player;

      player.onPlayerComplete.listen((_) {
        if (_disposed) return;

        if (!identical(_activePlayer, player)) return;

        _activePlayer = null;
        _isSpeaking = false;

        if (kDebugMode) {
          debugPrint('Voice cue $cueCode completed');
        }
      });

      if (kDebugMode) {
        debugPrint('Voice cue $cueCode preloaded');
      }

      return player;
    } catch (error) {
      debugPrint(
        'Voice cue load failed for code $cueCode: $error',
      );

      await player?.dispose();
      return null;
    } finally {
      _loading.remove(cueCode);
    }
  }

  @override
  Future<void> play(int cueCode) async {
    if (_disposed) return;

    if (!AppAssets.voicePrompts.containsKey(cueCode)) {
      return;
    }

    // Do not interrupt or queue instructions.
    // Also reject requests while a stop operation is underway.
    if (_isSpeaking || _stopFuture != null) {
      if (kDebugMode) {
        debugPrint(
          'Voice cue $cueCode skipped: coach busy',
        );
      }
      return;
    }

    // Reserve the playback slot synchronously, before the first await.
    // This prevents simultaneous play() requests from starting together.
    _isSpeaking = true;

    final int generation = ++_playGeneration;
    final Stopwatch stopwatch = Stopwatch()..start();

    if (kDebugMode) {
      debugPrint(
        'Voice cue $cueCode play requested at '
        '${DateTime.now().toIso8601String()}',
      );
    }

    AudioPlayer? player;

    try {
      player = await _loadCue(cueCode);

      if (_disposed || generation != _playGeneration) {
        return;
      }

      if (player == null) {
        _isSpeaking = false;
        return;
      }

      _activePlayer = player;

      await player.seek(Duration.zero);

      if (_disposed || generation != _playGeneration) {
        return;
      }

      await player.resume();

      if (_disposed || generation != _playGeneration) {
        return;
      }

      if (kDebugMode) {
        debugPrint(
          'Voice cue $cueCode started after '
          '${stopwatch.elapsedMilliseconds} ms',
        );
      }

      // Keep _isSpeaking true until onPlayerComplete fires.
    } catch (error) {
      debugPrint(
        'Voice cue playback failed for code $cueCode: $error',
      );

      if (!_disposed && generation == _playGeneration) {
        _activePlayer = null;
        _isSpeaking = false;

        // Stop a partially started player after a playback error.
        if (player != null) {
          unawaited(
            player.stop().catchError((Object error) {
              debugPrint('Voice cue cleanup failed: $error');
            }),
          );
        }
      }
    }
  }

  @override
  Future<void> stop() {
    if (_disposed) return Future<void>.value();

    // Invalidate any pending playback request immediately.
    _playGeneration++;
    _isSpeaking = false;
    _activePlayer = null;

    // Reuse an existing stop operation rather than overlapping stops.
    return _stopFuture ??= _stopAll().whenComplete(() {
      _stopFuture = null;
    });
  }

  Future<void> _stopAll() async {
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
    if (_disposed) return;

    _disposed = true;
    _playGeneration++;
    _isSpeaking = false;
    _activePlayer = null;

    // Finish any stop operation before disposing the players.
    final Future<void>? pendingStop = _stopFuture;
    if (pendingStop != null) {
      await pendingStop;
    }

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
