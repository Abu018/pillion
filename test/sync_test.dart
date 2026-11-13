import 'package:flutter_test/flutter_test.dart';
import 'package:pillion/core/models.dart';
import 'package:pillion/services/sync_service.dart';

void main() {
  group('ClockOffsetEstimator', () {
    test('uses the lowest-latency sample', () {
      final e = ClockOffsetEstimator()
        // True offset is +1000 ms. Slow sample with asymmetric delay is off by 100.
        ..addSample(sentAtLocalMs: 0, hostTimeMs: 1200, receivedAtLocalMs: 200)
        ..addSample(sentAtLocalMs: 500, hostTimeMs: 1520, receivedAtLocalMs: 540);
      expect(e.bestRttMs, 40);
      expect(e.offsetMs, 1000);
    });

    test('discards impossible samples', () {
      final e = ClockOffsetEstimator();
      expect(e.addSample(sentAtLocalMs: 100, hostTimeMs: 0, receivedAtLocalMs: 50), isFalse);
      expect(e.addSample(sentAtLocalMs: 0, hostTimeMs: 0, receivedAtLocalMs: 9000), isFalse);
      expect(e.hasEstimate, isFalse);
    });
  });

  group('DriftPolicy', () {
    test('within threshold is synced', () {
      final d = DriftPolicy.decide(driftMs: 80, thresholdMs: 120);
      expect(d.action, DriftAction.none);
      expect(d.status, SyncStatus.synced);
    });

    test('moderate drift nudges playback rate in the right direction', () {
      final ahead = DriftPolicy.decide(driftMs: 300, thresholdMs: 120);
      expect(ahead.action, DriftAction.nudge);
      expect(ahead.speed, lessThan(1));
      expect(ahead.duration.inMilliseconds, 6000);

      final behind = DriftPolicy.decide(driftMs: -300, thresholdMs: 120);
      expect(behind.speed, greaterThan(1));
      expect(behind.status, SyncStatus.adjusting);
    });

    test('large drift seeks', () {
      final d = DriftPolicy.decide(driftMs: -2000, thresholdMs: 120);
      expect(d.action, DriftAction.seek);
      expect(d.status, SyncStatus.outOfSync);
    });
  });

  test('PlaybackAnchor projects position forward only while playing', () {
    const playing = PlaybackAnchor(playing: true, positionMs: 10000, hostTimeMs: 5000);
    expect(playing.expectedPositionAt(7500), 12500);
    expect(playing.expectedPositionAt(4000), 10000);
    const paused = PlaybackAnchor(playing: false, positionMs: 10000, hostTimeMs: 5000);
    expect(paused.expectedPositionAt(9000), 10000);
  });
}
