import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/ble_ids.dart';
import '../../core/models.dart';
import '../../core/room_advert.dart';

/// Scans for nearby rooms. Rooms not seen for a while are dropped.
class RoomScanner extends ChangeNotifier {
  static const _staleAfter = Duration(seconds: 8);
  static const _scanDuration = Duration(seconds: 45);

  final Map<String, DiscoveredRoom> _rooms = {};
  StreamSubscription<List<ScanResult>>? _resultsSub;
  StreamSubscription<bool>? _scanningSub;
  Timer? _pruneTimer;
  bool _scanning = false;
  String? _error;

  List<DiscoveredRoom> get rooms =>
      _rooms.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  bool get scanning => _scanning;
  String? get error => _error;

  Future<void> start() async {
    _error = null;
    try {
      _resultsSub ??= FlutterBluePlus.onScanResults.listen(_onResults);
      _scanningSub ??= FlutterBluePlus.isScanning.listen((s) {
        _scanning = s;
        notifyListeners();
      });
      _pruneTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _prune());
      await FlutterBluePlus.startScan(
        withServices: [Guid(BleIds.service)],
        timeout: _scanDuration,
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (e) {
      _error = 'Could not scan: $e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await FlutterBluePlus.stopScan();
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final data = r.advertisementData.manufacturerData[BleIds.manufacturerId];
      if (data == null) continue;
      final advert = RoomAdvert.decode(data);
      if (advert == null) continue;
      final id = r.device.remoteId.str;
      final existing = _rooms[id];
      if (existing == null) {
        _rooms[id] = DiscoveredRoom(
          code: advert.code,
          name: advert.name,
          rssi: r.rssi,
          deviceId: id,
          lastSeen: DateTime.now(),
        );
      } else {
        existing
          ..name = advert.name
          ..rssi = r.rssi
          ..lastSeen = DateTime.now();
      }
    }
    notifyListeners();
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(_staleAfter);
    final before = _rooms.length;
    _rooms.removeWhere((_, room) => room.lastSeen.isBefore(cutoff));
    if (_rooms.length != before) notifyListeners();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _resultsSub?.cancel();
    _scanningSub?.cancel();
    _pruneTimer?.cancel();
    super.dispose();
  }
}
