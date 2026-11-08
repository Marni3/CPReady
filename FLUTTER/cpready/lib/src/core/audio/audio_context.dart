/// Audio routing shared by everything CPReady plays.
///
/// Both contexts use [AndroidUsageType.media], which is never muted by the
/// phone's ringer mode and is controlled by the volume keys.
///
/// Neither context requests audio focus. The metronome ticks every half second,
/// so taking focus per beat would interrupt other audio; and because a tick and
/// a coaching cue are meant to overlap, a cue must not duck or pause the beat
/// either.

import 'package:audioplayers/audioplayers.dart';

class AppAudioContext {
  /// Spoken coaching on the media stream, mixed with whatever else is playing
  /// (including the metronome).
  static final AudioContext voiceCues = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  /// Metronome ticks: music on the media stream, mixed with the coaching cues.
  static final AudioContext metronome = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
  );
}
