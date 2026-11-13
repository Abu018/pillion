import 'dart:math';

enum RoomRole { none, host, participant, solo }

enum TrackReadiness {
  unknown('Checking track'),
  ready('Track ready'),
  missing('Track missing'),
  mismatch('Track mismatch');

  const TrackReadiness(this.label);
  final String label;

  static TrackReadiness parse(String value) =>
      TrackReadiness.values.firstWhere((t) => t.name == value, orElse: () => unknown);
}

enum SyncStatus {
  idle('Waiting'),
  synced('Synced'),
  adjusting('Adjusting'),
  outOfSync('Out of sync');

  const SyncStatus(this.label);
  final String label;

  static SyncStatus parse(String value) =>
      SyncStatus.values.firstWhere((s) => s.name == value, orElse: () => idle);
}

enum ConnectionStatus { disconnected, connecting, connected, reconnecting, lost }

class TrackInfo {
  const TrackInfo({
    required this.hash,
    required this.title,
    required this.path,
    this.durationMs,
  });

  final String hash;
  final String title;
  final String path;
  final int? durationMs;

  String get shortHash => hash.substring(0, 8);

  TrackInfo copyWith({int? durationMs}) =>
      TrackInfo(hash: hash, title: title, path: path, durationMs: durationMs ?? this.durationMs);

  Map<String, Object?> toJson() => {'hash': hash, 'title': title, 'path': path};

  static TrackInfo fromJson(Map<String, Object?> json) => TrackInfo(
        hash: json['hash']! as String,
        title: json['title']! as String,
        path: json['path']! as String,
      );
}

/// Track identity as announced by the host (no local path).
class RoomTrack {
  const RoomTrack({required this.hash, required this.title, required this.durationMs});

  final String hash;
  final String title;
  final int durationMs;
}

class ParticipantInfo {
  ParticipantInfo({
    required this.id,
    required this.name,
    this.deviceId,
    this.connected = true,
    this.track = TrackReadiness.unknown,
    this.sync = SyncStatus.idle,
    this.driftMs,
    this.voiceActive = false,
    this.isHost = false,
    this.isSelf = false,
  });

  final String id;
  String name;
  String? deviceId;
  bool connected;
  TrackReadiness track;
  SyncStatus sync;
  int? driftMs;
  bool voiceActive;
  final bool isHost;
  final bool isSelf;
  DateTime? disconnectedAt;
}

/// The group's playback timeline, expressed in host clock time.
class PlaybackAnchor {
  const PlaybackAnchor({
    required this.playing,
    required this.positionMs,
    required this.hostTimeMs,
  });

  const PlaybackAnchor.stopped()
      : playing = false,
        positionMs = 0,
        hostTimeMs = 0;

  final bool playing;
  final int positionMs;
  final int hostTimeMs;

  int expectedPositionAt(int hostNowMs) =>
      playing ? positionMs + max(0, hostNowMs - hostTimeMs) : positionMs;

  bool sameAs(PlaybackAnchor other) =>
      playing == other.playing &&
      positionMs == other.positionMs &&
      hostTimeMs == other.hostTimeMs;
}

class DiscoveredRoom {
  DiscoveredRoom({
    required this.code,
    required this.name,
    required this.rssi,
    required this.deviceId,
    required this.lastSeen,
  });

  final String code;
  String name;
  int rssi;
  final String deviceId;
  DateTime lastSeen;

  /// 0-4 bars from RSSI.
  int get signalBars {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }
}
