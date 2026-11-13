import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../permissions_service.dart';
import '../settings_service.dart';

class AudioOutput {
  const AudioOutput({required this.name, required this.kind, required this.address});

  final String name;
  final String address;

  /// bluetooth, le_audio, broadcast, wired or usb.
  final String kind;

  bool get isWireless => kind == 'bluetooth' || kind == 'le_audio' || kind == 'broadcast';
}

/// Ride mode: one phone, the music app of your choice, and a phone-mic
/// intercom into every connected headset. Audio work happens natively
/// (see android/.../ride/IntercomEngine.kt); this class drives it.
class RideController extends ChangeNotifier {
  RideController({required this.settings, required this.permissions}) {
    _events = _eventChannel.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    settings.addListener(_pushConfig);
    _pushConfig();
    refreshOutputs();
  }

  static const _methods = MethodChannel('pillion/ride');
  static const _eventChannel = EventChannel('pillion/ride/events');

  static const spotifyPackage = 'com.spotify.music';
  static const youtubeMusicPackage = 'com.google.android.apps.youtube.music';

  final SettingsService settings;
  final PermissionsService permissions;
  late final StreamSubscription<Object?> _events;

  List<AudioOutput> outputs = const [];
  bool running = false;
  bool starting = false;
  bool speaking = false;
  bool ducking = false;
  double level = 0;
  String? error;

  /// Name of the headset the voice is actually routed to, as reported natively.
  String? voiceRoute;

  int get wirelessHeadsets => outputs.where((o) => o.isWireless).length;
  bool get hasHeadphones => outputs.isNotEmpty;

  /// The connected headset that hears the voice, or null if all of them do.
  AudioOutput? get listener {
    final target = settings.rideVoiceTarget;
    if (target == null) return null;
    for (final o in outputs) {
      if (o.address == target) return o;
    }
    return null;
  }

  /// True when the person talking will also hear themselves.
  bool get hearsOwnVoice => outputs.length > 1 && listener == null;

  void setListener(AudioOutput? output) => settings.rideVoiceTarget = output?.address;

  /// Hand the voice to the other headset, e.g. when the phone changes hands.
  void swapListener() {
    if (outputs.length < 2) return;
    final current = listener;
    final next = current == null
        ? outputs.first
        : outputs[(outputs.indexOf(current) + 1) % outputs.length];
    setListener(next);
  }

  /// Returns null on success, otherwise a message for the user.
  Future<String?> start() async {
    if (running || starting) return null;
    if (!hasHeadphones) {
      return 'Connect your headsets first. Without them the phone speaker would feed back into the mic.';
    }
    starting = true;
    error = null;
    notifyListeners();
    try {
      final mic = await permissions.requestMicrophone();
      if (mic != PermissionOutcome.granted) {
        return 'Microphone permission is needed for the intercom.';
      }
      await permissions.requestNotifications();
      await _pushConfig();
      await _methods.invokeMethod<void>('start');
      return null;
    } on PlatformException catch (e) {
      return 'Could not start the intercom: ${e.message}';
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() => _methods.invokeMethod<void>('stop');

  Future<void> refreshOutputs() async {
    try {
      final raw = await _methods.invokeListMethod<Object?>('getOutputs');
      _setOutputs(raw ?? const []);
      await _pushConfig();
    } on PlatformException {
      // Not available (e.g. non-Android); leave outputs empty.
    } on MissingPluginException {
      // Same.
    }
  }

  Future<void> openBluetoothSettings() => _methods.invokeMethod<void>('openBluetoothSettings');

  /// Returns false if the app isn't installed.
  Future<bool> launchApp(String package) async =>
      await _methods.invokeMethod<bool>('launchApp', {'package': package}) ?? false;

  Future<void> _pushConfig() async {
    try {
      await _methods.invokeMethod<void>('configure', {
        'sensitivity': settings.rideSensitivity,
        'voiceGain': settings.rideVoiceGain,
        'musicReturnDelayMs': settings.rideMusicReturnDelayMs,
        'duckMusic': settings.rideDuckMusic,
        'voiceTarget': listener?.address,
      });
    } on MissingPluginException {
      // Ride mode is Android-only.
    }
  }

  void _onEvent(Object? event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'state':
        running = event['running'] == true;
        speaking = event['speaking'] == true;
        ducking = event['ducking'] == true;
        level = (event['level'] as num?)?.toDouble() ?? 0;
        voiceRoute = event['voiceRoute'] as String?;
        final message = event['error'] as String?;
        if (message != null) error = message;
      case 'outputs':
        _setOutputs(event['outputs'] as List<Object?>? ?? const []);
        _pushConfig();
    }
    notifyListeners();
  }

  void _setOutputs(List<Object?> raw) {
    outputs = [
      for (final o in raw.whereType<Map<Object?, Object?>>())
        AudioOutput(
          name: o['name'] as String? ?? 'Headset',
          kind: o['kind'] as String? ?? 'bluetooth',
          address: o['address'] as String? ?? '',
        ),
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    _events.cancel();
    settings.removeListener(_pushConfig);
    super.dispose();
  }
}
