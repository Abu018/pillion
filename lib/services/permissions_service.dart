import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum PermissionOutcome { granted, denied, permanentlyDenied }

/// Requests permissions only when the related feature is used.
class PermissionsService {
  int? _androidSdk;

  Future<int> _sdk() async =>
      _androidSdk ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  Future<PermissionOutcome> requestBluetooth({required bool hosting}) async {
    final List<Permission> permissions;
    if (Platform.isAndroid) {
      if (await _sdk() >= 31) {
        permissions = [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          if (hosting) Permission.bluetoothAdvertise,
        ];
      } else {
        // Android 11 and lower require location access for BLE scanning.
        permissions = [Permission.locationWhenInUse];
      }
    } else {
      permissions = [Permission.bluetooth];
    }
    return _request(permissions);
  }

  Future<PermissionOutcome> requestMicrophone() => _request([Permission.microphone]);

  /// Needed on Android 13+ to show the "intercom is on" notification.
  Future<PermissionOutcome> requestNotifications() async {
    if (!Platform.isAndroid || await _sdk() < 33) return PermissionOutcome.granted;
    return _request([Permission.notification]);
  }

  Future<PermissionOutcome> _request(List<Permission> permissions) async {
    final results = await permissions.request();
    if (results.values.every((s) => s.isGranted || s.isLimited)) {
      return PermissionOutcome.granted;
    }
    if (results.values.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return PermissionOutcome.permanentlyDenied;
    }
    return PermissionOutcome.denied;
  }

  Future<void> openSettings() => openAppSettings();
}
