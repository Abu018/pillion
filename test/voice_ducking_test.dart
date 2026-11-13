import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillion/services/ducking_controller.dart';
import 'package:pillion/services/voice/vad_detector.dart';

Uint8List _pcm({required int ms, required double amplitude, double frequency = 220, int seed = 1}) {
  const rate = 16000;
  final samples = rate * ms ~/ 1000;
  final data = ByteData(samples * 2);
  final noise = Random(seed);
  for (var i = 0; i < samples; i++) {
    final tone = sin(2 * pi * frequency * i / rate);
    final jitter = (noise.nextDouble() - 0.5) * 0.1;
    final v = ((tone + jitter) * amplitude * 32767).round().clamp(-32768, 32767);
    data.setInt16(i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('VadDetector', () {
    test('stays silent on quiet background noise', () {
      final vad = VadDetector();
      for (var i = 0; i < 50; i++) {
        vad.addPcm16(_pcm(ms: 20, amplitude: 0.002, seed: i));
      }
      expect(vad.speaking, isFalse);
    });

    test('detects sustained speech-level sound and releases after it stops', () {
      final vad = VadDetector();
      for (var i = 0; i < 50; i++) {
        vad.addPcm16(_pcm(ms: 20, amplitude: 0.002, seed: i));
      }
      vad.addPcm16(_pcm(ms: 300, amplitude: 0.3));
      expect(vad.speaking, isTrue);

      vad.addPcm16(_pcm(ms: 600, amplitude: 0.002, seed: 99));
      expect(vad.speaking, isFalse);
    });

    test('ignores a single short click', () {
      final vad = VadDetector();
      for (var i = 0; i < 50; i++) {
        vad.addPcm16(_pcm(ms: 20, amplitude: 0.002, seed: i));
      }
      vad.addPcm16(_pcm(ms: 40, amplitude: 0.5));
      vad.addPcm16(_pcm(ms: 60, amplitude: 0.002, seed: 7));
      expect(vad.speaking, isFalse);
    });

    test('handles chunks split mid-sample', () {
      final vad = VadDetector();
      final bytes = _pcm(ms: 400, amplitude: 0.3);
      vad.addPcm16(bytes.sublist(0, 101));
      vad.addPcm16(bytes.sublist(101));
      expect(vad.speaking, isTrue);
    });
  });

  group('DuckingController', () {
    test('ducks smoothly, waits for the release delay, then restores', () {
      fakeAsync((async) {
        final c = DuckingController()
          ..configure(duckFactor: 0.25, attackMs: 200, releaseDelayMs: 1000, restoreRampMs: 700);

        c.setLocalSpeech(true);
        expect(c.state, DuckState.ducking);
        async.elapse(const Duration(milliseconds: 100));
        expect(c.multiplier, closeTo(0.625, 0.05));
        async.elapse(const Duration(milliseconds: 150));
        expect(c.state, DuckState.ducked);
        expect(c.multiplier, 0.25);

        c.setLocalSpeech(false);
        async.elapse(const Duration(milliseconds: 900));
        expect(c.state, DuckState.ducked, reason: 'release delay not over yet');

        async.elapse(const Duration(milliseconds: 200));
        expect(c.state, DuckState.restoring);
        async.elapse(const Duration(milliseconds: 750));
        expect(c.state, DuckState.normal);
        expect(c.multiplier, 1.0);
        c.dispose();
      });
    });

    test('speech between words does not cause flicker', () {
      fakeAsync((async) {
        final c = DuckingController()..configure(releaseDelayMs: 1000);
        c.setLocalSpeech(true);
        async.elapse(const Duration(milliseconds: 300));
        for (var i = 0; i < 5; i++) {
          c.setLocalSpeech(false);
          async.elapse(const Duration(milliseconds: 400));
          c.setLocalSpeech(true);
          async.elapse(const Duration(milliseconds: 200));
        }
        expect(c.state, DuckState.ducked);
        c.dispose();
      });
    });

    test('speech during restore ducks again', () {
      fakeAsync((async) {
        final c = DuckingController()..configure(releaseDelayMs: 100, restoreRampMs: 700);
        c.setLocalSpeech(true);
        async.elapse(const Duration(milliseconds: 300));
        c.setLocalSpeech(false);
        async.elapse(const Duration(milliseconds: 300));
        expect(c.state, DuckState.restoring);
        c.setLocalSpeech(true);
        expect(c.state, DuckState.ducking);
        c.dispose();
      });
    });

    test('remote speech ducks too; disabling restores', () {
      fakeAsync((async) {
        final c = DuckingController();
        c.setRemoteSpeech(true);
        async.elapse(const Duration(milliseconds: 300));
        expect(c.state, DuckState.ducked);
        c.configure(enabled: false);
        async.elapse(const Duration(seconds: 1));
        expect(c.state, DuckState.normal);
        expect(c.multiplier, 1.0);
        c.dispose();
      });
    });
  });
}
