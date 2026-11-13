import 'dart:async';
import 'dart:math';

import 'package:just_audio/just_audio.dart';

/// Local playback of the room's track.
///
/// Output volume is `userVolume * duckMultiplier`; the two are kept separate
/// so ducking can always restore the user's level.
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  String? _loadedPath;
  double _userVolume = 0.8;
  double _duckMultiplier = 1.0;
  double _speed = 1.0;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<void> get completed => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  bool get isPlaying => _player.playing && _player.processingState != ProcessingState.completed;
  bool get isLoaded => _loadedPath != null;
  int get positionMs => _player.position.inMilliseconds;
  int? get durationMs => _player.duration?.inMilliseconds;
  double get speed => _speed;

  /// Loads a file. Returns its duration in ms, if known.
  Future<int?> load(String path) async {
    if (_loadedPath == path) return durationMs;
    final duration = await _player.setFilePath(path);
    _loadedPath = path;
    return duration?.inMilliseconds;
  }

  /// Starts playback without waiting (just_audio's play() future only
  /// completes when playback stops).
  void play() => unawaited(_player.play());

  Future<void> pause() => _player.pause();

  Future<void> seek(int positionMs) {
    final upper = durationMs;
    var target = max(0, positionMs);
    if (upper != null) target = min(target, upper);
    return _player.seek(Duration(milliseconds: target));
  }

  Future<void> setSpeed(double speed) async {
    if (speed == _speed) return;
    _speed = speed;
    await _player.setSpeed(speed);
  }

  set userVolume(double value) {
    _userVolume = value.clamp(0.0, 1.0);
    _applyVolume();
  }

  set duckMultiplier(double value) {
    _duckMultiplier = value.clamp(0.0, 1.0);
    _applyVolume();
  }

  void _applyVolume() => unawaited(_player.setVolume(_userVolume * _duckMultiplier));

  Future<void> unload() async {
    await _player.stop();
    await setSpeed(1.0);
    _loadedPath = null;
  }

  Future<void> dispose() => _player.dispose();
}
