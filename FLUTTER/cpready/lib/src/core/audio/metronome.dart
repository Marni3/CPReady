
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class Metronome {
  Future<void> preload();
  Future<void> tick();
  Future<void> stop();
  Future<void> dispose();
}

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

class AssetMetronome implements Metronome {
  static const MethodChannel _channel =
      MethodChannel('cpready/metronome');

  Future<void>? _preloadFuture;
  bool _disposed = false;
  int _generation = 0;

  @override
  Future<void> preload() {
    if (_disposed) return Future<void>.value();

    return _preloadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      await _channel.invokeMethod<void>('preload');
      debugPrint('Native metronome loaded');
    } catch (error) {
      _preloadFuture = null;
      debugPrint('Native metronome preload failed: $error');
      rethrow;
    }
  }

  @override
  Future<void> tick() async {
    if (_disposed) return;

    final generation = _generation;

    try {
      await preload();

      if (_disposed || generation != _generation) {
        return;
      }

      await _channel.invokeMethod<void>('tick');
    } catch (error) {
      debugPrint('Native metronome tick failed: $error');
    }
  }

  @override
  Future<void> stop() async {
    _generation++;

    // Short WAV clicks finish naturally.
    // This prevents abrupt cuts between beats.
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _generation++;

    try {
      await _preloadFuture;
    } catch (_) {
      // Ignore an earlier loading failure.
    }

    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (error) {
      debugPrint('Native metronome dispose failed: $error');
    }
  }
}
