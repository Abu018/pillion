import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'vad_detector.dart';

/// Captures the microphone in memory and runs local voice activity detection.
///
/// Audio is processed frame by frame and discarded; nothing is recorded,
/// stored or transmitted.
class VoiceActivityService extends ChangeNotifier {
  VoiceActivityService();

  static const _sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  final VadDetector _detector = VadDetector(sampleRate: _sampleRate);
  final Set<Object> _owners = {};
  final StreamController<bool> _speechChanges = StreamController.broadcast();

  StreamSubscription<Uint8List>? _subscription;
  bool _active = false;
  bool _starting = false;
  String? _error;

  bool get active => _active;
  bool get speaking => _detector.speaking;
  double get level => _detector.meterLevel;
  double get noiseFloorDb => _detector.noiseFloorDb;
  String? get error => _error;
  Stream<bool> get speechChanges => _speechChanges.stream;

  set sensitivity(double value) => _detector.sensitivity = value;

  /// Starts monitoring on behalf of [owner] (e.g. the session or the mic test).
  /// Returns false if the microphone is unavailable or permission is denied.
  Future<bool> acquire(Object owner) async {
    _owners.add(owner);
    if (_active) return true;
    if (_starting) return false;
    _starting = true;
    try {
      if (!await _recorder.hasPermission()) {
        _error = 'Microphone permission denied';
        _owners.remove(owner);
        notifyListeners();
        return false;
      }
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: AndroidRecordConfig(manageBluetooth: false),
      ));
      _detector.reset();
      _subscription = stream.listen(
        _onAudio,
        onError: (Object e) => _fail('Microphone stopped: $e'),
        onDone: () {
          if (_active) _fail('Microphone stream ended');
        },
      );
      _active = true;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _owners.remove(owner);
      _error = 'Could not start microphone: $e';
      notifyListeners();
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<void> release(Object owner) async {
    _owners.remove(owner);
    if (_owners.isEmpty) await _stop();
  }

  void _onAudio(Uint8List bytes) {
    final wasSpeaking = _detector.speaking;
    final nowSpeaking = _detector.addPcm16(bytes);
    if (nowSpeaking != wasSpeaking) _speechChanges.add(nowSpeaking);
    notifyListeners();
  }

  Future<void> _fail(String message) async {
    _error = message;
    _owners.clear();
    await _stop();
  }

  Future<void> _stop() async {
    final wasSpeaking = _detector.speaking;
    await _subscription?.cancel();
    _subscription = null;
    if (_active) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    _active = false;
    _detector.reset();
    if (wasSpeaking) _speechChanges.add(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _recorder.dispose();
    _speechChanges.close();
    super.dispose();
  }
}
