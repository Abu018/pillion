import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

/// Energy-based voice activity detector for 16-bit mono PCM.
///
/// Splits audio into 20 ms frames, tracks an adaptive noise floor, and reports
/// speech once enough recent frames rise clearly above it. A short hangover
/// bridges gaps between syllables; the longer "release" delay lives in the
/// ducking controller.
class VadDetector {
  VadDetector({this.sampleRate = 16000, this.sensitivity = 0.5})
      : _frame = Int16List(sampleRate * frameMs ~/ 1000);

  static const frameMs = 20;
  static const windowFrames = 10;
  static const activationFrames = 6;
  static const hangoverFrames = 10;

  final int sampleRate;

  /// 0 (needs loud, clear speech) .. 1 (reacts to quiet speech).
  double sensitivity;

  final Int16List _frame;
  int _frameFill = 0;
  int? _pendingLowByte;

  final Queue<bool> _window = Queue();
  int _hangover = 0;

  double noiseFloorDb = -60;
  double levelDb = -90;
  bool speaking = false;

  /// 0..1 level for a microphone meter.
  double get meterLevel => ((levelDb + 70) / 60).clamp(0.0, 1.0);

  double get marginDb => 18 - 12 * sensitivity;

  /// Feeds little-endian PCM16 bytes. Returns the current speaking state.
  bool addPcm16(Uint8List bytes) {
    var i = 0;
    if (_pendingLowByte != null && bytes.isNotEmpty) {
      _pushSample(_toInt16(_pendingLowByte!, bytes[0]));
      _pendingLowByte = null;
      i = 1;
    }
    for (; i + 1 < bytes.length; i += 2) {
      _pushSample(_toInt16(bytes[i], bytes[i + 1]));
    }
    if (i < bytes.length) _pendingLowByte = bytes[i];
    return speaking;
  }

  void reset() {
    _frameFill = 0;
    _pendingLowByte = null;
    _window.clear();
    _hangover = 0;
    noiseFloorDb = -60;
    levelDb = -90;
    speaking = false;
  }

  static int _toInt16(int low, int high) {
    final v = (high << 8) | low;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  void _pushSample(int sample) {
    _frame[_frameFill++] = sample;
    if (_frameFill == _frame.length) {
      _processFrame();
      _frameFill = 0;
    }
  }

  void _processFrame() {
    var sumSquares = 0.0;
    var zeroCrossings = 0;
    for (var i = 0; i < _frame.length; i++) {
      final s = _frame[i];
      sumSquares += s * s;
      if (i > 0 && (s >= 0) != (_frame[i - 1] >= 0)) zeroCrossings++;
    }
    final rms = sqrt(sumSquares / _frame.length) / 32768.0;
    levelDb = 20 * log(rms + 1e-9) / ln10;
    final zcr = zeroCrossings / _frame.length;

    final minAbsoluteDb = -50 - 10 * sensitivity;
    final isSpeechFrame = levelDb > noiseFloorDb + marginDb &&
        levelDb > minAbsoluteDb &&
        zcr > 0.01 &&
        zcr < 0.5;

    if (levelDb < noiseFloorDb) {
      noiseFloorDb += (levelDb - noiseFloorDb) * 0.2;
    } else {
      // Rise slowly, and much slower during speech, so steady background
      // sound is eventually absorbed into the floor.
      noiseFloorDb += (levelDb - noiseFloorDb) * (isSpeechFrame ? 0.002 : 0.02);
    }
    noiseFloorDb = noiseFloorDb.clamp(-90.0, -15.0);

    _window.addLast(isSpeechFrame);
    if (_window.length > windowFrames) _window.removeFirst();
    final speechCount = _window.where((f) => f).length;

    if (speechCount >= activationFrames) {
      speaking = true;
      _hangover = hangoverFrames;
    } else if (speaking) {
      _hangover--;
      if (_hangover <= 0) speaking = false;
    }
  }
}
