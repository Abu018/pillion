import '../core/models.dart';

/// Estimates `hostClock - localClock` from PING/PONG round trips.
///
/// Uses the sample with the lowest round-trip time among recent probes, since
/// it has the smallest possible asymmetry error.
class ClockOffsetEstimator {
  static const _maxSamples = 12;
  static const _maxRttMs = 2000;

  final List<({int rttMs, int offsetMs})> _samples = [];

  bool get hasEstimate => _samples.isNotEmpty;

  int get offsetMs => _best?.offsetMs ?? 0;

  int? get bestRttMs => _best?.rttMs;

  ({int rttMs, int offsetMs})? get _best {
    if (_samples.isEmpty) return null;
    return _samples.reduce((a, b) => a.rttMs <= b.rttMs ? a : b);
  }

  /// Returns false if the sample was discarded.
  bool addSample({
    required int sentAtLocalMs,
    required int hostTimeMs,
    required int receivedAtLocalMs,
  }) {
    final rtt = receivedAtLocalMs - sentAtLocalMs;
    if (rtt < 0 || rtt > _maxRttMs) return false;
    final offset = hostTimeMs - (sentAtLocalMs + rtt ~/ 2);
    _samples.add((rttMs: rtt, offsetMs: offset));
    if (_samples.length > _maxSamples) _samples.removeAt(0);
    return true;
  }

  void reset() => _samples.clear();
}

enum DriftAction { none, nudge, seek }

class DriftDecision {
  const DriftDecision({
    required this.action,
    required this.status,
    this.speed = 1.0,
    this.duration = Duration.zero,
  });

  final DriftAction action;
  final SyncStatus status;
  final double speed;
  final Duration duration;
}

/// Decides how to correct a measured drift (`actual - expected`, in ms).
///
/// Small drift is corrected with a temporary playback-rate change; large drift
/// with a seek.
abstract final class DriftPolicy {
  static const seekThresholdMs = 750;
  static const rateDelta = 0.05;

  static DriftDecision decide({required int driftMs, required int thresholdMs}) {
    final magnitude = driftMs.abs();
    if (magnitude <= thresholdMs) {
      return const DriftDecision(action: DriftAction.none, status: SyncStatus.synced);
    }
    if (magnitude <= seekThresholdMs) {
      return DriftDecision(
        action: DriftAction.nudge,
        status: SyncStatus.adjusting,
        speed: driftMs > 0 ? 1 - rateDelta : 1 + rateDelta,
        duration: Duration(milliseconds: (magnitude / rateDelta).round()),
      );
    }
    return const DriftDecision(action: DriftAction.seek, status: SyncStatus.outOfSync);
  }
}
