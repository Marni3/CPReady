import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble.dart';
import 'cpr_metrics.dart';

/// High-level connection status surfaced to the UI.
enum BleStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// App-level BLE session state: connection status, live telemetry fan-out,
/// command sending, and in-memory packet recording for the active session.
class BleController extends ChangeNotifier {
  final EspBle ble = EspBle();

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

  BleController() {
    ble.onDisconnected = _handleUnexpectedDisconnect;
  }

  bool get isConnected => status == BleStatus.connected;
  bool get isBusy => status == BleStatus.scanning || status == BleStatus.connecting;

  /// Decoded telemetry packets (broadcast; subscribe after connecting).
  Stream<CprMetrics> get packets => _packets.stream;

  void _handleUnexpectedDisconnect() {
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
      lastError = 'Connection failed: $e';
      notifyListeners();
      return false;
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
  Future<void> sendCommand(String command) => ble.sendCommand(command);

  /// Clear and start recording telemetry for a new practice session.
  void startRecording() {
    sessionPackets.clear();
    recording = true;
    lastPacketAt = null;
  }

  /// Stop recording; returns the recorded packets.
  List<CprMetrics> stopRecording() {
    recording = false;
    return List<CprMetrics>.unmodifiable(sessionPackets);
  }

  Future<void> disconnect() async {
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
    ble.onDisconnected = null;
    _packetSub?.cancel();
    _packets.close();
    ble.disconnect();
    super.dispose();
  }
}
