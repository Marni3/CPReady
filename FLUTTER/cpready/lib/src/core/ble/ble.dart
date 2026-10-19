/// CPReady BLE transport: scan, connect, discover GATT, telemetry stream.
///
/// Moved from lib/ble.dart. Configuration (UUIDs, device name) lives in
/// [lib/src/config/ble.dart].

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../config/config.dart';
import '../metrics/cpr_metrics.dart';

class EspBle {
  static final Guid serviceUuid = Guid(AppBleConfig.serviceUuid);
  static final Guid notifyUuid = Guid(AppBleConfig.notifyUuid);
  static final Guid commandUuid = Guid(AppBleConfig.commandUuid);

  BluetoothDevice? device;
  BluetoothCharacteristic? telemetryCharacteristic;
  BluetoothCharacteristic? commandCharacteristic;

  /// Advertised name of the device found by the most recent [scan], kept as
  /// provenance for the History record.
  String? advertisedName;

  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  StreamController<CprMetrics>? _telemetryController;

  /// Invoked when the ESP32 disconnects unexpectedly (not via [disconnect]).
  VoidCallback? onDisconnected;

  bool _intentionalDisconnect = false;

  /// Broadcast stream of decoded telemetry packets. Recreated after
  /// [disconnect], so callers should subscribe after each successful connect.
  Stream<CprMetrics> get telemetry {
    final controller =
        _telemetryController ??= StreamController<CprMetrics>.broadcast();
    return controller.stream;
  }

  /// Whether the phone's Bluetooth adapter is currently switched on.
  Future<bool> isAdapterOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Opens Android's system prompt asking the user to turn Bluetooth on.
  Future<void> requestAdapterOn() => FlutterBluePlus.turnOn();

  /// Scan for the ESP32.
  Future<BluetoothDevice?> scan() async {
    BluetoothDevice? foundDevice;

    await scanSubscription?.cancel();
    scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName;

        debugPrint('Found: $name (${result.device.remoteId})');

        if (name == AppBleConfig.deviceName) {
          foundDevice = result.device;
          advertisedName = name;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withNames: const [AppBleConfig.deviceName],
      timeout: Duration(seconds: AppBleConfig.scanTimeoutSeconds),
    );

    await FlutterBluePlus.isScanning
        .where((scanning) => scanning == false)
        .first;

    await scanSubscription?.cancel();
    scanSubscription = null;

    return foundDevice;
  }

  /// Connect and discover the CPReady GATT characteristics.
  Future<void> connect(BluetoothDevice device) async {
    this.device = device;
    _intentionalDisconnect = false;

    await device.connect(
      license: License.nonprofit,
    );

    debugPrint('Connected to ESP32');

    // Watch for the ESP32 dropping the link while the app is using it.
    await _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          !_intentionalDisconnect) {
        debugPrint('ESP32 disconnected unexpectedly');
        onDisconnected?.call();
      }
    });

    final services = await device.discoverServices();

    for (final service in services) {
      debugPrint('Service: ${service.uuid}');

      if (service.uuid != serviceUuid) {
        continue;
      }

      for (final characteristic in service.characteristics) {
        debugPrint('Characteristic: ${characteristic.uuid}');

        if (characteristic.uuid == notifyUuid) {
          telemetryCharacteristic = characteristic;
        }

        if (characteristic.uuid == commandUuid) {
          commandCharacteristic = characteristic;
        }
      }
    }

    if (telemetryCharacteristic == null) {
      throw Exception('ESP32 telemetry characteristic not found');
    }

    if (commandCharacteristic == null) {
      throw Exception('ESP32 command characteristic not found');
    }

    debugPrint('ESP32 characteristics found');
  }

  /// Start receiving telemetry notifications.
  Future<void> startTelemetry() async {
    final characteristic = telemetryCharacteristic;

    if (characteristic == null) {
      throw Exception('Not connected to ESP32');
    }

    await characteristic.setNotifyValue(true);

    await _notifySub?.cancel();
    _notifySub = characteristic.lastValueStream.listen(_onTelemetryChunk);
  }

  void _onTelemetryChunk(List<int> value) {
    if (value.isEmpty) return;

    try {
      final metrics = CprMetrics.fromBytes(value);
      _telemetryController?.add(metrics);
    } catch (error) {
      debugPrint('Telemetry decode failed: $error');
      debugPrint('Raw bytes: $value');
    }
  }

  /// Send a text command.
  Future<void> sendCommand(String command) async {
    final characteristic = commandCharacteristic;

    if (characteristic == null) {
      throw Exception('Not connected to ESP32');
    }

    await characteristic.write(
      utf8.encode(command),
    );
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;

    await _connectionSub?.cancel();
    _connectionSub = null;

    await _notifySub?.cancel();
    _notifySub = null;

    await device?.disconnect();

    await _telemetryController?.close();
    _telemetryController = null;

    device = null;
    telemetryCharacteristic = null;
    commandCharacteristic = null;
  }
}
