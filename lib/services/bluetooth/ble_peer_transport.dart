import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/ble_ids.dart';
import 'ble_host_transport.dart' show BleTransportException;

class PeerInbound {
  const PeerInbound(this.characteristicId, this.value);
  final String characteristicId;
  final List<int> value;
}

/// Participant side: GATT client connected to the host.
class BlePeerTransport {
  final StreamController<PeerInbound> _inbound = StreamController.broadcast();
  final StreamController<void> _lost = StreamController.broadcast();
  final Map<String, BluetoothCharacteristic> _characteristics = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];

  BluetoothDevice? _device;
  bool _connected = false;
  bool _closing = false;

  Stream<PeerInbound> get inbound => _inbound.stream;

  /// Fires when the link drops without [disconnect] being called.
  Stream<void> get connectionLost => _lost.stream;

  bool get connected => _connected;

  Future<void> connect(String deviceId, {Duration timeout = const Duration(seconds: 12)}) async {
    await _teardown();
    _closing = false;
    final device = BluetoothDevice.fromId(deviceId);
    _device = device;

    try {
      await device.connect(timeout: timeout);
      final services = await device.discoverServices();
      final service = services.where((s) => s.uuid == Guid(BleIds.service)).firstOrNull;
      if (service == null) {
        throw const BleTransportException('That device is not hosting a room.');
      }
      _characteristics
        ..clear()
        ..addEntries(service.characteristics.map((c) => MapEntry(c.uuid.str128.toLowerCase(), c)));

      for (final id in BleIds.downlinkCharacteristics) {
        final characteristic = _characteristics[id];
        if (characteristic == null) {
          throw const BleTransportException('The host is running an incompatible version.');
        }
        final sub = characteristic.onValueReceived.listen((value) => _inbound.add(PeerInbound(id, value)));
        device.cancelWhenDisconnected(sub);
        _subscriptions.add(sub);
        await characteristic.setNotifyValue(true);
      }

      _subscriptions.add(device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _connected) {
          _connected = false;
          if (!_closing) _lost.add(null);
        }
      }));
      _connected = true;
    } catch (e) {
      await _teardown();
      if (e is BleTransportException) rethrow;
      throw BleTransportException('Could not connect to the host: ${_describe(e)}');
    }
  }

  Future<void> write(String characteristicId, Uint8List value) async {
    final characteristic = _characteristics[characteristicId];
    if (characteristic == null || !_connected) {
      throw const BleTransportException('Not connected to the host.');
    }
    await characteristic.write(value);
  }

  Future<void> disconnect() async {
    _closing = true;
    await _teardown();
  }

  Future<void> _teardown() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _characteristics.clear();
    final device = _device;
    _connected = false;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  static String _describe(Object e) =>
      e is FlutterBluePlusException ? (e.description ?? e.function) : e.toString();
}
