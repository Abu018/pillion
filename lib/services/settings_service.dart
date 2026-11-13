import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  static Future<SettingsService> load() async =>
      SettingsService(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  set onboarded(bool v) => _set('onboarded', v);

  String get displayName => _prefs.getString('displayName') ?? 'Listener';
  set displayName(String v) => _set('displayName', v.trim().isEmpty ? 'Listener' : v.trim());

  /// The user's chosen music volume. Ducking never writes to this.
  double get musicVolume => _prefs.getDouble('musicVolume') ?? 0.8;
  set musicVolume(double v) => _set('musicVolume', v.clamp(0.0, 1.0));

  bool get duckingEnabled => _prefs.getBool('duckingEnabled') ?? true;
  set duckingEnabled(bool v) => _set('duckingEnabled', v);

  bool get groupDucking => _prefs.getBool('groupDucking') ?? false;
  set groupDucking(bool v) => _set('groupDucking', v);

  /// Fraction of the selected volume used while ducked.
  double get duckLevel => _prefs.getDouble('duckLevel') ?? 0.25;
  set duckLevel(double v) => _set('duckLevel', v.clamp(0.0, 1.0));

  int get duckAttackMs => _prefs.getInt('duckAttackMs') ?? 200;
  set duckAttackMs(int v) => _set('duckAttackMs', v);

  int get releaseDelayMs => _prefs.getInt('releaseDelayMs') ?? 1000;
  set releaseDelayMs(int v) => _set('releaseDelayMs', v);

  int get restoreRampMs => _prefs.getInt('restoreRampMs') ?? 700;
  set restoreRampMs(int v) => _set('restoreRampMs', v);

  double get vadSensitivity => _prefs.getDouble('vadSensitivity') ?? 0.5;
  set vadSensitivity(double v) => _set('vadSensitivity', v.clamp(0.0, 1.0));

  int get syncThresholdMs => _prefs.getInt('syncThresholdMs') ?? 120;
  set syncThresholdMs(int v) => _set('syncThresholdMs', v);

  int get reconnectWindowSec => _prefs.getInt('reconnectWindowSec') ?? 30;
  set reconnectWindowSec(int v) => _set('reconnectWindowSec', v);

  // Ride mode
  double get rideSensitivity => _prefs.getDouble('rideSensitivity') ?? 0.4;
  set rideSensitivity(double v) => _set('rideSensitivity', v.clamp(0.0, 1.0));

  /// Intercom voice loudness multiplier.
  double get rideVoiceGain => _prefs.getDouble('rideVoiceGain') ?? 2.0;
  set rideVoiceGain(double v) => _set('rideVoiceGain', v.clamp(0.5, 6.0));

  int get rideMusicReturnDelayMs => _prefs.getInt('rideMusicReturnDelayMs') ?? 1500;
  set rideMusicReturnDelayMs(int v) => _set('rideMusicReturnDelayMs', v);

  bool get rideDuckMusic => _prefs.getBool('rideDuckMusic') ?? true;
  set rideDuckMusic(bool v) => _set('rideDuckMusic', v);

  /// Address of the headset that hears the intercom voice (the partner's).
  /// Null means every headset hears it, including the person talking.
  String? get rideVoiceTarget => _prefs.getString('rideVoiceTarget');
  set rideVoiceTarget(String? v) {
    if (v == null) {
      _prefs.remove('rideVoiceTarget');
      notifyListeners();
    } else {
      _set('rideVoiceTarget', v);
    }
  }

  void _set(String key, Object value) {
    switch (value) {
      case bool b:
        _prefs.setBool(key, b);
      case int i:
        _prefs.setInt(key, i);
      case double d:
        _prefs.setDouble(key, d);
      case String s:
        _prefs.setString(key, s);
    }
    notifyListeners();
  }
}
