import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../config/config.dart';
import 'ble.dart';
import '../metrics/cpr_metrics.dart';

/// High-level connection status surfaced to the UI.
enum BleStatus { disconnected, scanning, connecting, connected, error }

/// Internal FIFO queue that executes BLE commands sequentially with safety pacing.
class _CommandQueue {
  final List<_QueuedCommand> _queue = [];
  bool _processing = false;
  static const Duration interCommandPacing = Duration(milliseconds: 150);

  Future<void> enqueue(Future<void> Function() action) {
    final completer = Completer<void>();
    _queue.add(_QueuedCommand(action, completer));
    _processNext();
    return completer.future;
  }

  void clear() {
    for (final item in _queue) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(
          StateError('BLE command cancelled due to disconnection'),
        );
      }
    }
    _queue.clear();
  }

  Future<void> _processNext() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;

    while (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      try {
        await item.action();
        if (!item.completer.isCompleted) {
          item.completer.complete();
        }
      } catch (e, st) {
        if (!item.completer.isCompleted) {
          item.completer.completeError(e, st);
        }
      }
      if (_queue.isNotEmpty) {
        await Future<void>.delayed(interCommandPacing);
      }
    }

    _processing = false;
  }
}

class _QueuedCommand {
  final Future<void> Function() action;
  final Completer<void> completer;
  _QueuedCommand(this.action, this.completer);
}

/// App-level BLE session state: connection status, live telemetry fan-out,
/// command sending, and in-memory packet recording for the active session.
class BleController extends ChangeNotifier {
  final EspBle ble = EspBle();
  final _CommandQueue _commandQueue = _CommandQueue();

  BleStatus status = BleStatus.disconnected;
  String lastError = '';

  StreamSubscription<CprMetrics>? _packetSub;
  final StreamController<CprMetrics> _packets =
      StreamController<CprMetrics>.broadcast();

  /// Packets recorded for the current practice session.
  final List<CprMetrics> sessionPackets = [];
  bool recording = false;

  /// Timestamp of the most recent telemetry packet (null before first one).
  DateTime? lastPacketAt;

  /// Wall-clock start of the current session, stamped by [startRecording].
  /// Retained after [stopRecording] so the session can be persisted.
  DateTime? sessionStartedAt;

  /// Wall-clock end of the current session, stamped by [stopRecording].
  DateTime? sessionEndedAt;

  BleController() {
    ble.onDisconnected = _handleUnexpectedDisconnect;
  }

  bool get isConnected => status == BleStatus.connected;
  bool get isBusy =>
      status == BleStatus.scanning || status == BleStatus.connecting;

  /// Advertised name of the device found by the last scan (History provenance).
  String? get deviceName => ble.advertisedName;

  /// Decoded telemetry packets (broadcast; subscribe after connecting).
  Stream<CprMetrics> get packets => _packets.stream;

  void _handleUnexpectedDisconnect() {
    _commandQueue.clear();
    if (status == BleStatus.disconnected) return;
    status = BleStatus.error;
    lastError = 'BLE disconnected';
    if (recording) {
      recording = false;
    }
    notifyListeners();
  }

  /// Scan, connect, discover services, enable notifications.
  /// Returns true when connected.
  Future<bool> connect() async {
    if (isBusy) return false;

    // Phone's Bluetooth is off: surface the error and let Android ask the user
    // to switch it on, instead of scanning into the void.
    if (!await ble.isAdapterOn()) {
      await _handleBluetoothOff();
      return false;
    }

    status = BleStatus.scanning;
    lastError = '';
    notifyListeners();

    try {
      // Drop the old GATT handle first (this also clears the phone's
      // cached connection after an unexpected drop) and give the firmware
      // a moment to restart advertising before scanning again.
      if (ble.device != null) {
        await _packetSub?.cancel();
        _packetSub = null;
        await ble.disconnect();
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      final device = await ble.scan();

      if (device == null) {
        status = BleStatus.error;
        lastError = 'CPReady device not found';
        notifyListeners();
        return false;
      }

      status = BleStatus.connecting;
      notifyListeners();

      await ble.connect(device);
      await ble.startTelemetry();

      await _packetSub?.cancel();
      _packetSub = ble.telemetry.listen(_onPacket);

      status = BleStatus.connected;
      notifyListeners();
      return true;
    } catch (e) {
      status = BleStatus.error;
      lastError = 'Connection failed: ';
      notifyListeners();
      return false;
    }
  }

  /// Error handler for a connect attempt made while Bluetooth is switched off:
  /// records the error and opens Android's 'turn on Bluetooth' prompt.
  Future<void> _handleBluetoothOff() async {
    status = BleStatus.error;
    lastError = AppStrings.bleErrorOff;
    notifyListeners();

    try {
      await ble.requestAdapterOn();
    } catch (e) {
      lastError = AppStrings.bleErrorTurnOnFailed;
      notifyListeners();
    }
  }

  void _onPacket(CprMetrics metrics) {
    lastPacketAt = DateTime.now();
    if (recording) {
      sessionPackets.add(metrics);
    }
    if (!_packets.isClosed) {
      _packets.add(metrics);
    }
  }

  /// Send a text command to the ESP32 (e.g. START / STOP).
  ///
  /// Serialized through a sequential FIFO queue with 150ms pacing between
  /// successive GATT writes to protect the BLE stack and prevent command loss.
  Future<void> sendCommand(String command) {
    if (!isConnected) {
      debugPrint('[BLE] Not connected; skipping command: ');
      return Future.value();
    }
    return _commandQueue.enqueue(() => ble.sendCommand(command));
  }

  /// Runs a packet through the normal fan-out without a device, so widget
  /// tests can drive the live screens.
  @visibleForTesting
  void debugDeliver(CprMetrics metrics) => _onPacket(metrics);

  /// Clear and start recording telemetry for a new practice session.
  void startRecording() {
    sessionPackets.clear();
    recording = true;
    lastPacketAt = null;
    sessionStartedAt = DateTime.now();
    sessionEndedAt = null;
  }

  /// Stop recording; returns the recorded packets.
  List<CprMetrics> stopRecording() {
    recording = false;
    sessionEndedAt = DateTime.now();
    return List<CprMetrics>.unmodifiable(sessionPackets);
  }

  Future<void> disconnect() async {
    _commandQueue.clear();
    await _packetSub?.cancel();
    _packetSub = null;
    recording = false;
    await ble.disconnect();
    status = BleStatus.disconnected;
    lastError = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _commandQueue.clear();
    ble.onDisconnected = null;
    _packetSub?.cancel();
    _packets.close();
    ble.disconnect();
    super.dispose();
  }
}
