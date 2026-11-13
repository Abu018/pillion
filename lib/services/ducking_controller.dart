import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

enum DuckState { normal, ducking, ducked, restoring }

/// Volume ducking state machine.
///
/// ```text
/// NORMAL    -- speech -->                 DUCKING
/// DUCKING   -- reached duck level -->     DUCKED
/// DUCKED    -- silence for release -->    RESTORING
/// RESTORING -- speech -->                 DUCKING
/// RESTORING -- reached full volume -->    NORMAL
/// ```
///
/// Produces a [multiplier] applied on top of the user's volume; the user's
/// selected volume is never modified.
class DuckingController extends ChangeNotifier {
  DuckingController({this.tick = const Duration(milliseconds: 20)});

  final Duration tick;

  bool _enabled = true;
  double _duckFactor = 0.25;
  int _attackMs = 200;
  int _releaseDelayMs = 1000;
  int _restoreRampMs = 700;

  DuckState _state = DuckState.normal;
  double _multiplier = 1.0;
  bool _localSpeech = false;
  bool _remoteSpeech = false;

  Timer? _ticker;
  Timer? _releaseTimer;

  DuckState get state => _state;
  double get multiplier => _multiplier;
  bool get enabled => _enabled;
  double get duckFactor => _duckFactor;
  bool get localSpeech => _localSpeech;
  bool get remoteSpeech => _remoteSpeech;

  bool get _speech => _enabled && (_localSpeech || _remoteSpeech);

  void configure({
    bool? enabled,
    double? duckFactor,
    int? attackMs,
    int? releaseDelayMs,
    int? restoreRampMs,
  }) {
    _enabled = enabled ?? _enabled;
    _duckFactor = (duckFactor ?? _duckFactor).clamp(0.0, 1.0);
    _attackMs = max(1, attackMs ?? _attackMs);
    _releaseDelayMs = max(0, releaseDelayMs ?? _releaseDelayMs);
    _restoreRampMs = max(1, restoreRampMs ?? _restoreRampMs);
    if (_state == DuckState.ducked && _multiplier != _duckFactor) {
      _state = DuckState.ducking;
      _ensureTicker();
    }
    _evaluate();
    notifyListeners();
  }

  void setLocalSpeech(bool active) {
    if (_localSpeech == active) return;
    _localSpeech = active;
    _evaluate();
    notifyListeners();
  }

  void setRemoteSpeech(bool active) {
    if (_remoteSpeech == active) return;
    _remoteSpeech = active;
    _evaluate();
    notifyListeners();
  }

  /// Back to full volume immediately (e.g. when leaving a session).
  void reset() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _ticker?.cancel();
    _ticker = null;
    _localSpeech = false;
    _remoteSpeech = false;
    _state = DuckState.normal;
    _multiplier = 1.0;
    notifyListeners();
  }

  void _evaluate() {
    if (_speech) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      if (_state == DuckState.normal || _state == DuckState.restoring) {
        _state = DuckState.ducking;
        _ensureTicker();
      }
      return;
    }

    if (!_enabled) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      if (_state != DuckState.normal) {
        _state = DuckState.restoring;
        _ensureTicker();
      }
      return;
    }

    if ((_state == DuckState.ducking || _state == DuckState.ducked) && _releaseTimer == null) {
      _releaseTimer = Timer(Duration(milliseconds: _releaseDelayMs), () {
        _releaseTimer = null;
        if (_speech) return;
        _state = DuckState.restoring;
        _ensureTicker();
        notifyListeners();
      });
    }
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(tick, (_) => _onTick());
  }

  void _onTick() {
    final dt = tick.inMicroseconds / 1000.0;
    final span = max(1.0 - _duckFactor, 0.01);
    switch (_state) {
      case DuckState.ducking:
        _multiplier = _moveToward(_multiplier, _duckFactor, span * dt / _attackMs);
        if (_multiplier == _duckFactor) {
          _state = DuckState.ducked;
          _stopTicker();
        }
      case DuckState.restoring:
        _multiplier = _moveToward(_multiplier, 1.0, span * dt / _restoreRampMs);
        if (_multiplier == 1.0) {
          _state = DuckState.normal;
          _stopTicker();
        }
      case DuckState.normal:
      case DuckState.ducked:
        _stopTicker();
    }
    notifyListeners();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  static double _moveToward(double value, double target, double step) {
    if ((target - value).abs() <= step) return target;
    return value < target ? value + step : value - step;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _releaseTimer?.cancel();
    super.dispose();
  }
}
