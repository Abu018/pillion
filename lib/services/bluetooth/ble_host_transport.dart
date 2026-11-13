import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';

import '../../core/ble_ids.dart';
import '../../core/room_advert.dart';

class BleTransportException implements Exception {
  const BleTransportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HostInbound {
  const HostInbound(this.deviceId, this.characteristicId, this.value);
  final String deviceId;
  final String characteristicId;
  final Uint8List value;
}

class _Outgoing {
  _Outgoing(this.characteristicId, this.deviceId, this.build);
  final String characteristicId;
  final String? deviceId;
  final Uint8List Function() build;
}

/// Host side: GATT server + advertising.
class BleHostTransport {
  /// Android allows one outstanding indication per device, and the plugin does
  /// not queue, so sends are paced.
  static const _sendGap = Duration(milliseconds: 45);

  final StreamController<HostInbound> _inbound = StreamController.broadcast();
  final StreamController<({String deviceId, bool connected})> _connections =
      StreamController.broadcast();
  final StreamController<String> _errors = StreamController.broadcast();
  final Queue<_Outgoing> _queue = Queue();
  bool _draining = false;
  bool _running = false;
  bool _initialized = false;

  /// Value served from the RoomInfo characteristic.
  Uint8List Function() roomInfo = () => Uint8List(0);

  Stream<HostInbound> get inbound => _inbound.stream;
  Stream<({String deviceId, bool connected})> get connections => _connections.stream;
  Stream<String> get errors => _errors.stream;
  bool get running => _running;

  Future<void> start(RoomAdvert advert) async {
    if (!_initialized) {
      await BlePeripheral.initialize();
      _initialized = true;
    }
    if (!await BlePeripheral.isSupported()) {
      throw const BleTransportException(
          "This phone can't host rooms (Bluetooth LE advertising is not supported). You can still join rooms.");
    }

    BlePeripheral.setWriteRequestCallback((deviceId, characteristicId, offset, value) {
      if (value != null && offset == 0) {
        _inbound.add(HostInbound(deviceId, characteristicId.toLowerCase(), value));
      }
      return null;
    });
    BlePeripheral.setReadRequestCallback((deviceId, characteristicId, offset, value) {
      if (characteristicId.toLowerCase() != BleIds.roomInfo) return null;
      final data = roomInfo();
      return ReadRequestResult(value: offset < data.length ? data.sublist(offset) : Uint8List(0));
    });
    BlePeripheral.setConnectionStateChangeCallback((deviceId, connected) {
      _connections.add((deviceId: deviceId, connected: connected));
    });
    BlePeripheral.setAdvertisingStatusUpdateCallback((advertising, error) {
      if (error != null) _errors.add('Advertising failed: $error');
    });

    await BlePeripheral.clearServices();
    await BlePeripheral.addService(_buildService(), timeout: const Duration(seconds: 5));
    // No localName: the plugin would rename the phone's Bluetooth adapter, and
    // the device name may contain personal info. The room name travels in
    // manufacturer data instead.
    await BlePeripheral.startAdvertising(
      services: [BleIds.service],
      manufacturerData: ManufacturerData(
        manufacturerId: BleIds.manufacturerId,
        data: advert.encode(),
      ),
      addManufacturerDataInScanResponse: true,
    );
    _running = true;
  }

  /// Queues a message. [build] runs at send time so timestamps stay fresh.
  void send(String characteristicId, Uint8List Function() build, {String? deviceId}) {
    if (!_running) return;
    _queue.add(_Outgoing(characteristicId, deviceId, build));
    _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty && _running) {
      final next = _queue.removeFirst();
      try {
        await BlePeripheral.updateCharacteristic(
          characteristicId: next.characteristicId,
          value: next.build(),
          deviceId: next.deviceId,
        );
      } catch (_) {
        // Target device disconnected; the connection callback handles it.
      }
      await Future<void>.delayed(_sendGap);
    }
    _draining = false;
  }

  /// Waits for queued messages (e.g. ROOM_CLOSED) to go out.
  Future<void> flush({Duration timeout = const Duration(seconds: 2)}) async {
    final deadline = DateTime.now().add(timeout);
    while ((_queue.isNotEmpty || _draining) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<void> stop() async {
    _running = false;
    _queue.clear();
    try {
      await BlePeripheral.stopAdvertising();
      await BlePeripheral.clearServices();
    } catch (_) {}
  }

  static BleService _buildService() {
    BleCharacteristic uplink(String uuid) => BleCharacteristic(
          uuid: uuid,
          properties: [
            CharacteristicProperties.write.index,
            CharacteristicProperties.indicate.index,
          ],
          permissions: [
            AttributePermissions.readable.index,
            AttributePermissions.writeable.index,
          ],
        );

    return BleService(
      uuid: BleIds.service,
      primary: true,
      characteristics: [
        BleCharacteristic(
          uuid: BleIds.roomInfo,
          properties: [CharacteristicProperties.read.index],
          permissions: [AttributePermissions.readable.index],
        ),
        BleCharacteristic(
          uuid: BleIds.control,
          properties: [
            CharacteristicProperties.read.index,
            CharacteristicProperties.indicate.index,
          ],
          permissions: [AttributePermissions.readable.index],
        ),
        uplink(BleIds.sync),
        uplink(BleIds.voiceState),
        uplink(BleIds.participantState),
      ],
    );
  }
}
