import 'package:cpready/src/core/audio/voice_coach.dart';

/// Voice coach that records the cue codes it was asked to play.
class RecordingVoiceCoach implements VoiceCoach {
  /// Cue codes passed to [play], in order.
  final List<int> played = <int>[];

  @override
  Future<void> preload() async {}

  @override
  Future<void> play(int cueCode) async {
    played.add(cueCode);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
