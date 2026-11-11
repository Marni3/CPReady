/// The CPR pacing click.
///
/// One preloaded player is restarted for every beat. The packaged tick's
/// audible transient ends well inside the shortest beat gap (500 ms at
/// 120 BPM), so restarting it cuts only inaudible decay.
///
/// Widget tests inject [SilentMetronome] so no platform audio channel is
/// touched.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../config/config.dart';
import 'audio_context.dart';

/// Volume applied to every metronome tick so it stays consistent and is never
/// lowered when a coaching cue plays.
const double kMetronomeVolume = AppMetronome.volume;

/// Plays one metronome beat on demand.
abstract class Metronome {
  /// Loads the tick so the first beat starts without decode delay.
  Future<void> preload();

  /// Plays one beat, restarting the tick if it is still ringing.
  Future<void> tick();

  /// Stops the current beat.
  Future<void> stop();

  /// Releases the player.
  Future<void> dispose();
}

/// A metronome that never makes a sound, for tests and audio-less builds.
class SilentMetronome implements Metronome {
  const SilentMetronome();

  @override
  Future<void> preload() async {}

  @override
  Future<void> tick() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Production metronome backed by `audioplayers`.
class AssetMetronome implements Metronome {
  AudioPlayer? _player;
  Future<void>? _preloadFuture;
  int _generation = 0;
  bool _disposed = false;

  /// Prefix that `audioplayers` puts in front of every [AssetSource] path.
  static const String _bundlePrefix = 'assets/';

  static String _sourcePath(String bundlePath) =>
      bundlePath.startsWith(_bundlePrefix)
          ? bundlePath.substring(_bundlePrefix.length)
          : bundlePath;

  @override
  Future<void> preload() {
    if (_disposed) return Future<void>.value();
    return _preloadFuture ??= _load();
  }

  Future<void> _load() async {
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setAudioContext(AppAudioContext.metronome);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(kMetronomeVolume);
      await player.setSource(
        AssetSource(_sourcePath(AppAssets.metronomeClick)),
      );

      if (_disposed) {
        await player.dispose();
        return;
      }

      _player = player;
      if (kDebugMode) {
        debugPrint('Metronome tick preloaded');
      }
    } catch (error) {
      debugPrint('Metronome tick load failed: $error');
      await player?.dispose();
      // Let a later beat retry the load instead of caching the failure.
      _preloadFuture = null;
    }
  }

  @override
  Future<void> tick() async {
    if (_disposed) return;
    await preload();

    final AudioPlayer? player = _player;
    if (player == null || _disposed) return;

    // A beat that is still seeking when the next one starts is superseded;
    // only the newest beat is resumed.
    final int generation = ++_generation;
    try {
      await player.seek(Duration.zero);
      await player.setVolume(kMetronomeVolume);
      if (_disposed || generation != _generation) return;
      await player.resume();
    } catch (error) {
      debugPrint('Metronome tick failed: $error');
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    try {
      await _player?.stop();
    } catch (error) {
      debugPrint('Metronome stop failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    final AudioPlayer? player = _player;
    _player = null;
    _preloadFuture = null;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (error) {
      debugPrint('Metronome dispose failed: $error');
    }
  }
}
