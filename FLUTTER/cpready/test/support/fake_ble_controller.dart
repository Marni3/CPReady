import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/ble/ble_controller.dart';
import 'package:cpready/src/core/ble/device_config.dart';

/// Connected BLE controller that records commands instead of writing them.
class FakeBleController extends BleController {
  FakeBleController({bool connected = true}) {
    status = connected ? BleStatus.connected : BleStatus.disconnected;
  }

  /// Commands sent by the screen under test, in order.
  final List<String> commands = <String>[];

  /// Report returned by [requestConfig]; null models older firmware that never
  /// answers GET_CONFIG.
  DeviceConfig? configReport;

  /// When true, [sendCommand] throws as it would on a dropped link.
  bool failCommands = false;

  @override
  Future<void> sendCommand(String command) async {
    if (failCommands) {
      throw StateError('BLE is not connected; command not sent: $command');
    }
    commands.add(command);
  }

  @override
  Future<DeviceConfig?> requestConfig({required Duration timeout}) async {
    if (!isConnected) {
      throw StateError('BLE is not connected; GET_CONFIG not sent');
    }
    commands.add(AppBleConfig.commandGetConfig);
    return configReport;
  }

  /// Simulates an unexpected link drop for the listener-based screens.
  void disconnectForTest() {
    status = BleStatus.error;
    lastError = 'BLE disconnected';
    notifyListeners();
  }

  /// Restores the link after a [disconnectForTest] so reconnect behavior can be
  /// tested without a real device.
  void reconnectForTest() {
    status = BleStatus.connected;
    lastError = '';
    notifyListeners();
  }
}
