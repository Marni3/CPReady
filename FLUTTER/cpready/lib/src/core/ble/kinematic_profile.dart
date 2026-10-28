/// The two kinematic profiles the firmware can run.
///
/// Each profile keeps its own depth scalar (K) on the device, so switching
/// profiles changes the K in use; the choice is sent only when the user
/// changes it.

import '../../config/ble.dart';

enum KinematicProfile {
  /// Adult-manikin thresholds (the firmware default).
  manikin,

  /// Relaxed thresholds for pressing by hand on a desk.
  bench,
}

extension KinematicProfileCommand on KinematicProfile {
  /// The text command that selects this profile on the device.
  String get command => switch (this) {
    KinematicProfile.manikin => AppBleConfig.commandProfileManikin,
    KinematicProfile.bench => AppBleConfig.commandProfileBench,
  };
}
