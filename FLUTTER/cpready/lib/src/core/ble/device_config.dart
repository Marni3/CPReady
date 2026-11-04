/// Decoded Type 6 configuration report (F-01).
///
/// Layout (12 bytes, little-endian):
///   0      packet_type (6)
///   1      profile (0 = MANIKIN, 1 = BENCH)
///   2..3   depth_k_x100 (uint16)
///   4      config_flags
///   5..6   practice_duration_sec (uint16)
///   7..8   default_duration_sec (uint16)
///   9      protocol_version
///   10..11 reserved
///
/// The firmware sends it in reply to GET_CONFIG. [fromBytes] validates it so
/// malformed or future-version reports are ignored instead of populating the
/// UI with invented values.

import 'dart:typed_data';

import '../../config/ble.dart';
import 'kinematic_profile.dart';

class DeviceConfig {
  const DeviceConfig({
    required this.profile,
    required this.depthK,
    required this.configFlags,
    required this.practiceDurationSeconds,
    required this.defaultDurationSeconds,
    required this.protocolVersion,
    this.minStartThresholdG = 0.08,
    this.recoilArmFraction = 0.15,
  });

  final KinematicProfile profile;
  final double depthK;
  final int configFlags;
  final int practiceDurationSeconds;
  final int defaultDurationSeconds;
  final int protocolVersion;
  final double minStartThresholdG;
  final double recoilArmFraction;

  /// Firmware reports that the relaxed bench profile is active.
  bool get isBenchActive =>
      configFlags & AppBleConfig.configFlagBenchActive != 0;

  /// Firmware reports that K differs from the profile's factory default.
  bool get hasCustomK => configFlags & AppBleConfig.configFlagCustomK != 0;

  /// Firmware reports that 2-MPU differential mode is active (false = 1-MPU chest only).
  bool get useDualMpu => configFlags & AppBleConfig.configFlagDualMpu != 0;

  /// Sensitivity preset code: 0 = BALANCED, 1 = HIGH, 2 = STRICT, 3 = CUSTOM.
  int get sensitivityPreset =>
      (configFlags & AppBleConfig.configSensitivityMask) >>
      AppBleConfig.configSensitivityShift;

  String get sensitivityLabel => switch (sensitivityPreset) {
        1 => 'HIGH',
        2 => 'STRICT',
        3 => 'CUSTOM',
        _ => 'BALANCED',
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'profile': profile.name,
        'depth_k': depthK,
        'has_custom_k': hasCustomK,
        'sensor_mode': useDualMpu ? '2_mpu_differential' : '1_mpu_chest',
        'sensitivity_preset': sensitivityLabel,
        'min_start_threshold_g': minStartThresholdG,
        'recoil_arm_fraction': recoilArmFraction,
        'practice_duration_sec': practiceDurationSeconds,
      };

  static DeviceConfig fromBytes(List<int> bytes) {
    if (bytes.length != AppBleConfig.configReportLength) {
      throw ArgumentError(
        'Expected ${AppBleConfig.configReportLength} config bytes, '
        'got ${bytes.length}',
      );
    }

    final ByteData data = ByteData.sublistView(Uint8List.fromList(bytes));
    final int type = data.getUint8(0);
    if (type != AppBleConfig.packetConfigReport) {
      throw ArgumentError('Expected config report type 6, got $type');
    }

    final int rawProfile = data.getUint8(1);
    final KinematicProfile profile = switch (rawProfile) {
      AppBleConfig.configProfileManikin => KinematicProfile.manikin,
      AppBleConfig.configProfileBench => KinematicProfile.bench,
      _ => throw ArgumentError('Unknown config profile: $rawProfile'),
    };

    final double depthK =
        data.getUint16(2, Endian.little) / AppBleConfig.depthKScale;
    if (depthK < AppBleConfig.depthKMin || depthK > AppBleConfig.depthKMax) {
      throw ArgumentError('Config depth K out of range: $depthK');
    }

    final int practiceDuration = data.getUint16(5, Endian.little);
    final int defaultDuration = data.getUint16(7, Endian.little);
    if (practiceDuration <= 0 || defaultDuration <= 0) {
      throw ArgumentError(
        'Invalid config durations: $practiceDuration / $defaultDuration',
      );
    }

    final int protocolVersion = data.getUint8(9);
    if (protocolVersion != AppBleConfig.configProtocolVersion) {
      throw ArgumentError('Unsupported config protocol: $protocolVersion');
    }

    final int trigRaw = data.getUint8(10);
    final int armRaw = data.getUint8(11);

    return DeviceConfig(
      profile: profile,
      depthK: depthK,
      configFlags: data.getUint8(4),
      practiceDurationSeconds: practiceDuration,
      defaultDurationSeconds: defaultDuration,
      protocolVersion: protocolVersion,
      minStartThresholdG: trigRaw > 0 ? trigRaw / 1000.0 : 0.08,
      recoilArmFraction: armRaw > 0 ? armRaw / 100.0 : 0.15,
    );
  }
}
