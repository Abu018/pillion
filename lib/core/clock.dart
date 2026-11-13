/// Wall-clock-anchored monotonic time.
///
/// `DateTime.now()` can jump when the OS adjusts the clock, which would break
/// scheduled playback. This clock reads the wall clock once and then advances
/// with a monotonic [Stopwatch].
class MonotonicClock {
  MonotonicClock._()
      : _epochAtStart = DateTime.now().millisecondsSinceEpoch,
        _stopwatch = Stopwatch()..start();

  static final MonotonicClock instance = MonotonicClock._();

  final int _epochAtStart;
  final Stopwatch _stopwatch;

  int nowMs() => _epochAtStart + _stopwatch.elapsedMilliseconds;
}
