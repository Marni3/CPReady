/// Last known device configuration, persisted on the phone.
///
/// Older firmware cannot report its configuration, so this row is what Device
/// Settings and Practice Setup show before the first successful read-back. Values written here are the app's best knowledge, not
/// a device acknowledgement: only a Type 6 report is authoritative.

import '../../config/config.dart';
import '../ble/kinematic_profile.dart';

class DeviceSettings {
  const DeviceSettings({
    required this.profile,
    required this.depthK,
    required this.practiceDurationSec,
    required this.updatedAt,
  });

  /// Safe values for a fresh install or a factory reset.
  factory DeviceSettings.defaults({DateTime? now}) {
    return DeviceSettings(
      profile: KinematicProfile.manikin,
      depthK: null,
      practiceDurationSec: AppDeviceSettings.defaultPracticeDurationSec,
      updatedAt: now ?? DateTime.now(),
    );
  }

  final KinematicProfile profile;

  /// Calibrated depth scalar, or null when it is unknown. A profile switch
  /// clears it (the other profile's K is not known until read back) and so
  /// does a factory reset.
  final double? depthK;

  final int practiceDurationSec;
  final DateTime updatedAt;

  /// Row representation for SQLite. The id is fixed because there is one row.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      AppDeviceSettings.columnId: AppDeviceSettings.singleRowId,
      AppDeviceSettings.columnProfile: profile.name,
      AppDeviceSettings.columnDepthK: depthK,
      AppDeviceSettings.columnPracticeDurationSec: practiceDurationSec,
      AppDeviceSettings.columnUpdatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Parses a stored row, rejecting damage rather than showing a false value.
  factory DeviceSettings.fromMap(Map<String, Object?> map) {
    final Object? rawProfile = map[AppDeviceSettings.columnProfile];
    if (rawProfile is! String) {
      throw const FormatException('Missing device profile');
    }

    final KinematicProfile profile = KinematicProfile.values.firstWhere(
      (KinematicProfile value) => value.name == rawProfile,
      orElse: () =>
          throw FormatException('Unknown device profile: $rawProfile'),
    );

    final Object? rawDepthK = map[AppDeviceSettings.columnDepthK];
    double? depthK;
    if (rawDepthK != null) {
      if (rawDepthK is! num) {
        throw const FormatException('Invalid depth K value');
      }
      depthK = rawDepthK.toDouble();
      if (depthK < AppBleConfig.depthKMin || depthK > AppBleConfig.depthKMax) {
        throw FormatException('Depth K out of range: $depthK');
      }
    }

    final Object? rawDuration =
        map[AppDeviceSettings.columnPracticeDurationSec];
    if (rawDuration is! int || rawDuration <= 0) {
      throw const FormatException('Invalid practice duration');
    }

    final Object? rawUpdatedAt = map[AppDeviceSettings.columnUpdatedAt];
    final DateTime? updatedAt = rawUpdatedAt is String
        ? DateTime.tryParse(rawUpdatedAt)
        : null;
    if (updatedAt == null) {
      throw const FormatException('Invalid settings timestamp');
    }

    return DeviceSettings(
      profile: profile,
      depthK: depthK,
      practiceDurationSec: rawDuration,
      updatedAt: updatedAt.toLocal(),
    );
  }
}
