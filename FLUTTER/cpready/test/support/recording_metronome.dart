import 'package:cpready/src/core/audio/metronome.dart';

/// Metronome that records beats instead of playing them.
class RecordingMetronome implements Metronome {
  /// Beats requested with [tick].
  int ticks = 0;

  /// Calls to [stop].
  int stops = 0;

  bool preloaded = false;
  bool disposed = false;

  @override
  Future<void> preload() async {
    preloaded = true;
  }

  @override
  Future<void> tick() async {
    ticks++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
