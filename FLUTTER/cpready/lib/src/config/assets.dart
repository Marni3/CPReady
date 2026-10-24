/// Asset paths (images, logos, and the coaching cues).
///
/// Keep these in sync with the `assets:` section in `pubspec.yaml`.
/// To swap an image, either replace the file (same name) or change the path
/// here — no widget or screen code needs to change.

import 'ble.dart';

class AppAssets {
  /// White CPReady logo, used on dark backgrounds (e.g. the splash screen).
  static const String logoWhite = 'assets/images/cpready_logo_white.png';

  /// Blue CPReady logo, used on light backgrounds.
  static const String logoBlue = 'assets/images/cpready_logo_blue.png';

  /// Illustration shown on the "begin session" prompt.
  static const String beginSession = 'assets/images/begin_session.png';

  /// Hand-placement guide illustration.
  static const String handPlacementGuide =
      'assets/images/handplacement_guide.png';

  /// Bluetooth illustration shown when no device is connected.
  static const String bluetoothUnconnected =
      'assets/images/bluetooth_unconnected.png';

  /// Bluetooth illustration shown while connecting / once connected.
  static const String bluetoothConnected =
      'assets/images/bluetooth_connected.png';

  // -----------------------------------------------------------------------
  // Icon artwork (tinted at render time by [AppAssetIcon])
  // -----------------------------------------------------------------------

  /// House glyph — bottom-nav "Home" tab.
  static const String iconHome = 'assets/images/home.png';

  /// ECG / heartbeat glyph — bottom-nav "Practice" tab and the "Start
  /// practice" option card.
  static const String iconHeartbeat = 'assets/images/heartbeat.png';

  /// Clock glyph — bottom-nav "History" tab.
  static const String iconClock = 'assets/images/clock.png';

  /// Open-book glyph — "Step-by-step Guide" option card.
  static const String iconBook = 'assets/images/book.png';

  // -----------------------------------------------------------------------
  // Voice coaching cues
  // -----------------------------------------------------------------------

  /// Coaching-cue audio, keyed by the firmware's `audio_prompt_code`.
  ///
  /// Codes without an entry (0, the "nothing to say" value) are never played.
  static const Map<int, String> voicePrompts = <int, String>{
    AppBleConfig.cuePushHarder: 'assets/audio/push_harder.mp3',
    AppBleConfig.cuePushShallower: 'assets/audio/push_shallower.mp3',
    AppBleConfig.cueReleaseFully: 'assets/audio/release_chest.mp3',
    AppBleConfig.cueSpeedUp: 'assets/audio/speed_up.mp3',
    AppBleConfig.cueSlowDown: 'assets/audio/slow_down.mp3',
    AppBleConfig.cueGoodJob: 'assets/audio/good_compressions.mp3',
  };
}
