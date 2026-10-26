/// Type 6 configuration report parsing and validation.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/ble/device_config.dart';
import 'package:cpready/src/core/ble/kinematic_profile.dart';

List<int> _report({
  int type = AppBleConfig.packetConfigReport,
  int profile = AppBleConfig.configProfileManikin,
  int depthKX100 = 1120,
  int flags = 0,
  int practiceDuration = 120,
  int defaultDuration = 120,
  int protocol = AppBleConfig.configProtocolVersion,
  int length = AppBleConfig.configReportLength,
}) {
  final ByteData data = ByteData(length);
  if (length > 0) data.setUint8(0, type);
  if (length > 1) data.setUint8(1, profile);
  if (length > 3) data.setUint16(2, depthKX100, Endian.little);
  if (length > 4) data.setUint8(4, flags);
  if (length > 6) data.setUint16(5, practiceDuration, Endian.little);
  if (length > 8) data.setUint16(7, defaultDuration, Endian.little);
  if (length > 9) data.setUint8(9, protocol);
  return data.buffer.asUint8List();
}

void main() {
  test('parses the proposed Type 6 layout', () {
    final DeviceConfig config = DeviceConfig.fromBytes(
      _report(
        profile: AppBleConfig.configProfileBench,
        depthKX100: 1324,
        flags:
            AppBleConfig.configFlagBenchActive | AppBleConfig.configFlagCustomK,
        practiceDuration: 15,
      ),
    );

    expect(config.profile, KinematicProfile.bench);
    expect(config.depthK, 13.24);
    expect(config.isBenchActive, isTrue);
    expect(config.hasCustomK, isTrue);
    expect(config.practiceDurationSeconds, 15);
    expect(config.defaultDurationSeconds, 120);
    expect(config.protocolVersion, 1);
  });

  test('rejects malformed or unsupported reports', () {
    expect(
      () => DeviceConfig.fromBytes(_report(length: 11)),
      throwsArgumentError,
    );
    expect(
      () => DeviceConfig.fromBytes(_report(type: AppBleConfig.packetRealtime)),
      throwsArgumentError,
    );
    expect(
      () => DeviceConfig.fromBytes(_report(profile: 2)),
      throwsArgumentError,
    );
    expect(
      () => DeviceConfig.fromBytes(_report(depthKX100: 99)),
      throwsArgumentError,
    );
    expect(
      () => DeviceConfig.fromBytes(_report(depthKX100: 3001)),
      throwsArgumentError,
    );
    expect(
      () => DeviceConfig.fromBytes(_report(practiceDuration: 0)),
      throwsArgumentError,
    );
    expect(
      () => DeviceConfig.fromBytes(_report(defaultDuration: 0)),
      throwsArgumentError,
    );
    expect(
      () => DeviceConfig.fromBytes(_report(protocol: 2)),
      throwsArgumentError,
    );
  });
}
