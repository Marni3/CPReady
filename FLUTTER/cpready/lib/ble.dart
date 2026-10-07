import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'cpr_metrics.dart';

class EspBle {
  static final Guid serviceUuid = Guid(
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  );

  static final Guid notifyUuid = Guid(
    '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
  );

  static final Guid commandUuid = Guid(
    '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  );

  BluetoothDevice? device;
  BluetoothCharacteristic? telemetryCharacteristic;
  BluetoothCharacteristic? commandCharacteristic;

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

  /// Scan for the ESP32.
  Future<BluetoothDevice?> scan() async {
    BluetoothDevice? foundDevice;

    await scanSubscription?.cancel();
    scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName;

        debugPrint('Found: $name (${result.device.remoteId})');

        if (name == 'CPReady') {
          foundDevice = result.device;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withNames: const ['CPReady'],
      timeout: const Duration(seconds: 5),
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
