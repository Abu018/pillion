import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/ble_ids.dart';
import '../core/clock.dart';
import '../core/models.dart';
import '../core/protocol.dart';
import '../core/room_advert.dart';
import 'audio_playback_service.dart';
import 'bluetooth/ble_host_transport.dart';
import 'bluetooth/ble_peer_transport.dart';
import 'ducking_controller.dart';
import 'permissions_service.dart';
import 'settings_service.dart';
import 'sync_service.dart';
import 'track_service.dart';
import 'voice/voice_activity_service.dart';

class SessionException implements Exception {
  const SessionException(this.message, {this.rejected = false});
  final String message;

  /// The host explicitly refused the join (wrong PIN, removed, room full).
  final bool rejected;

  @override
  String toString() => message;
}

/// Coordinates room, playback, sync, voice and reconnection state.
class SessionCoordinator extends ChangeNotifier {
  SessionCoordinator({
    required this.settings,
    required this.tracks,
    required this.playback,
    required this.voice,
    required this.ducking,
    required this.permissions,
    BleHostTransport? hostTransport,
    BlePeerTransport? peerTransport,
  })  : _host = hostTransport ?? BleHostTransport(),
        _peer = peerTransport ?? BlePeerTransport();

  /// Host + up to 4 participants.
  static const maxParticipants = 4;
  static const _playLeadMs = 800;
  static const _seekLatencyMs = 80;
  static const _maxNameLength = 20;
  static const _maxTitleLength = 40;
  static const _driftInterval = Duration(seconds: 5);
  static const _stateInterval = Duration(seconds: 5);
  static const _pingInterval = Duration(seconds: 10);
  static const _voiceRefresh = Duration(seconds: 2);
  static const _remoteVoiceTimeoutMs = 5000;
  static const _joinTimeout = Duration(seconds: 8);

  final SettingsService settings;
  final TrackService tracks;
  final AudioPlaybackService playback;
  final VoiceActivityService voice;
  final DuckingController ducking;
  final PermissionsService permissions;
  final BleHostTransport _host;
  final BlePeerTransport _peer;
  final MonotonicClock _clock = MonotonicClock.instance;
  final ClockOffsetEstimator _estimator = ClockOffsetEstimator();
  final StreamController<String> _notices = StreamController.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  final String selfId = 'p-${_randomHex(8)}';

  RoomRole role = RoomRole.none;
  String? roomName;
  String? roomCode;
  String? pin;
  String? hostName;
  RoomTrack? roomTrack;
  TrackInfo? localTrack;
  TrackReadiness myTrack = TrackReadiness.unknown;
  ConnectionStatus connection = ConnectionStatus.disconnected;
  SyncStatus mySync = SyncStatus.idle;
  int? myDriftMs;
  PlaybackAnchor anchor = const PlaybackAnchor.stopped();
  bool bluetoothOn = true;
  bool hostLost = false;
  bool localPlaybackInterrupted = false;
  bool micDenied = false;

  /// Reason the last session ended (room closed, removed, ...), if not by the user.
  String? endedReason;

  RoomCodec? _codec;
  String? _hostId;
  String? _hostDeviceId;
  RoomAdvert? _advert;
  final Map<String, ParticipantInfo> _others = {};
  final Set<String> _banned = {};
  final Map<String, int> _remoteVoice = {};

  Completer<RoomMessage>? _joinCompleter;
  int _scheduleToken = 0;
  int _reconnectAttempt = 0;
  bool _waitingForStart = false;
  bool _nudging = false;
  bool _micOwned = false;
  bool? _lastDuckingEnabled;
  bool _lastGroupDucking = false;

  Timer? _driftTimer;
  Timer? _stateTimer;
  Timer? _pingTimer;
  Timer? _housekeepingTimer;
  Timer? _nudgeTimer;
  Timer? _voiceRefreshTimer;

  Stream<String> get notices => _notices.stream;
  bool get inSession => role != RoomRole.none;
  bool get controlsPlayback => role == RoomRole.host || role == RoomRole.solo;
  bool get waitingForStart => _waitingForStart;
  int? get clockOffsetMs => _estimator.hasEstimate ? _estimator.offsetMs : null;
  int? get clockRttMs => _estimator.bestRttMs;

  bool get allParticipantsReady => _others.values
      .where((p) => !p.isHost && p.connected)
      .every((p) => p.track == TrackReadiness.ready);

  List<ParticipantInfo> get participants {
    final self = ParticipantInfo(
      id: selfId,
      name: settings.displayName,
      isHost: role == RoomRole.host,
      isSelf: true,
      connected: role == RoomRole.host || connection == ConnectionStatus.connected,
      track: myTrack,
      sync: mySync,
      driftMs: myDriftMs,
      voiceActive: voice.speaking && _micOwned,
    );
    final others = _others.values.toList()
      ..sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return [self, ...others];
  }

  void init() {
    playback.userVolume = settings.musicVolume;
    ducking.addListener(() => playback.duckMultiplier = ducking.multiplier);
    settings.addListener(_applySettings);
    voice.addListener(_onVoiceServiceChanged);
    _applySettings();

    _subscriptions
      ..add(voice.speechChanges.listen(_onLocalSpeech))
      ..add(playback.completed.listen((_) => _onTrackCompleted()))
      ..add(playback.playerStateStream.listen((_) {
        if (role == RoomRole.solo) notifyListeners();
      }))
      ..add(_host.inbound.listen(_onHostInbound))
      ..add(_host.connections.listen(_onHostConnectionChange))
      ..add(_host.errors.listen(_notice))
      ..add(_peer.inbound.listen(_onPeerInbound))
      ..add(_peer.connectionLost.listen((_) => _reconnect()))
      ..add(FlutterBluePlus.adapterState.listen(_onAdapterState));
  }

  // ---------------------------------------------------------------------------
  // Host
  // ---------------------------------------------------------------------------

  Future<void> createRoom({
    required String name,
    required String pin,
    required TrackInfo track,
  }) async {
    _ensureIdle();
    await _ensureBluetooth(hosting: true);

    final code = RoomAdvert.generateCode();
    final roomName = name.trim().isEmpty ? 'Room $code' : name.trim();
    final durationMs = await _loadTrack(track);

    _codec = RoomCodec(sessionId: code, pin: pin, senderId: selfId);
    _advert = RoomAdvert(code: code, name: roomName);
    this.roomName = roomName;
    roomCode = code;
    this.pin = pin;
    hostName = settings.displayName;
    localTrack = track.copyWith(durationMs: durationMs);
    roomTrack = RoomTrack(hash: track.hash, title: track.title, durationMs: durationMs ?? 0);
    myTrack = TrackReadiness.ready;
    anchor = const PlaybackAnchor.stopped();
    role = RoomRole.host;
    connection = ConnectionStatus.connected;
    endedReason = null;
    _host.roomInfo = _roomInfoBytes;

    try {
      await _host.start(_advert!);
    } catch (e) {
      await _resetSession();
      throw SessionException(e.toString());
    }

    _stateTimer = Timer.periodic(_stateInterval, (_) => _sendState());
    _driftTimer = Timer.periodic(_driftInterval, (_) => _driftCheck());
    _housekeepingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _housekeeping());
    notifyListeners();
    await _updateMicMonitoring();
  }

  void hostPlay() {
    if (role == RoomRole.solo) return _soloPlay();
    if (role != RoomRole.host || anchor.playing) return;
    final start = _clock.nowMs() + _playLeadMs;
    final position = _clampPosition(anchor.positionMs);
    _sendControl(Msg.playAt, {
      'trackHash': roomTrack!.hash,
      'positionMs': position,
      'hostStartTimeMs': start,
    });
    _applyAnchor(PlaybackAnchor(playing: true, positionMs: position, hostTimeMs: start));
  }

  void hostPause() {
    if (role == RoomRole.solo) {
      playback.pause();
      return;
    }
    if (role != RoomRole.host || !anchor.playing) return;
    final now = _clock.nowMs();
    final position = _clampPosition(anchor.expectedPositionAt(now));
    _sendControl(Msg.pause, {'positionMs': position});
    _applyAnchor(PlaybackAnchor(playing: false, positionMs: position, hostTimeMs: now));
  }

  void hostSeek(int positionMs) {
    final position = _clampPosition(positionMs);
    if (role == RoomRole.solo) {
      playback.seek(position);
      return;
    }
    if (role != RoomRole.host) return;
    if (anchor.playing) {
      final start = _clock.nowMs() + _playLeadMs;
      _sendControl(Msg.playAt, {
        'trackHash': roomTrack!.hash,
        'positionMs': position,
        'hostStartTimeMs': start,
      });
      _applyAnchor(PlaybackAnchor(playing: true, positionMs: position, hostTimeMs: start));
    } else {
      _sendControl(Msg.seek, {'positionMs': position});
      _applyAnchor(PlaybackAnchor(playing: false, positionMs: position, hostTimeMs: _clock.nowMs()));
    }
  }

  void hostStop() {
    if (role == RoomRole.solo) {
      playback.pause();
      playback.seek(0);
      return;
    }
    if (role != RoomRole.host) return;
    _sendControl(Msg.stop);
    _applyAnchor(PlaybackAnchor(playing: false, positionMs: 0, hostTimeMs: _clock.nowMs()));
  }

  void kick(String participantId) {
    if (role != RoomRole.host) return;
    final p = _others[participantId];
    if (p == null) return;
    final codec = _codec!;
    if (p.deviceId != null) {
      _host.send(BleIds.control, () => codec.encode(Msg.kick), deviceId: p.deviceId);
    }
    _banned.add(participantId);
    _removeParticipant(participantId);
    _notice('${p.name} was removed from the room.');
  }

  void _onHostInbound(HostInbound inbound) {
    final codec = _codec;
    if (role != RoomRole.host || codec == null) return;
    final allowed = switch (inbound.characteristicId) {
      BleIds.participantState => AllowedTypes.hostFromParticipantState,
      BleIds.sync => AllowedTypes.hostFromSync,
      BleIds.voiceState => AllowedTypes.hostFromVoice,
      _ => null,
    };
    if (allowed == null) return;

    final result = codec.decode(inbound.value, allowedTypes: allowed);
    if (!result.isOk) {
      if (result.error == DecodeError.badSignature &&
          inbound.characteristicId == BleIds.participantState) {
        _host.send(
          BleIds.participantState,
          () => codec.encodeUnsigned(Msg.joinRejected, {'reason': 'wrong_pin'}),
          deviceId: inbound.deviceId,
        );
      }
      return;
    }
    final msg = result.message!;

    if (msg.type == Msg.join) {
      _handleJoin(msg, inbound.deviceId);
      return;
    }

    final p = _others[msg.senderId];
    if (p == null || p.deviceId != inbound.deviceId) return;

    switch (msg.type) {
      case Msg.leave:
        _removeParticipant(p.id);
        _notice('${p.name} left the room.');
      case Msg.trackStatus:
        p.track = TrackReadiness.parse(msg.str('track'));
        _broadcastParticipant(p);
      case Msg.ping:
        final t0 = msg.integer('t0');
        _host.send(
          BleIds.sync,
          () => codec.encode(Msg.pong, {'t0': t0, 'hostTimeMs': _clock.nowMs()}),
          deviceId: inbound.deviceId,
        );
      case Msg.syncReport:
        p.sync = SyncStatus.parse(msg.str('status'));
        p.driftMs = msg.integer('driftMs');
      case Msg.requestState:
        _sendState(deviceId: inbound.deviceId);
      case Msg.voiceActive || Msg.voiceInactive:
        final active = msg.type == Msg.voiceActive;
        p.voiceActive = active;
        _onRemoteVoice(p.id, active);
        _host.send(BleIds.voiceState, () => codec.encode(msg.type, {'participantId': p.id}));
    }
    notifyListeners();
  }

  void _handleJoin(RoomMessage msg, String deviceId) {
    final codec = _codec!;
    void reject(String reason) => _host.send(
          BleIds.participantState,
          () => codec.encode(Msg.joinRejected, {'reason': reason}),
          deviceId: deviceId,
        );

    final id = msg.senderId;
    if (_banned.contains(id)) return reject('removed');
    final existing = _others[id];
    final connectedCount = _others.values.where((p) => p.connected).length;
    if (existing == null && connectedCount >= maxParticipants) return reject('full');

    final name = _truncate(msg.str('name'), _maxNameLength);
    _others.removeWhere((key, p) => key != id && p.deviceId == deviceId);
    final p = existing ?? ParticipantInfo(id: id, name: name);
    p
      ..name = name
      ..deviceId = deviceId
      ..connected = true
      ..disconnectedAt = null;
    _others[id] = p;

    _host.send(
      BleIds.participantState,
      () => codec.encode(Msg.joinAccepted, {'roomName': roomName!, 'hostName': hostName!}),
      deviceId: deviceId,
    );
    _sendState(deviceId: deviceId);
    for (final other in _others.values) {
      if (other.id != id) _sendParticipantUpdate(other, deviceId: deviceId);
    }
    _broadcastParticipant(p);
    if (existing == null) _notice('$name joined.');
    notifyListeners();
  }

  void _onHostConnectionChange(({String deviceId, bool connected}) change) {
    if (role != RoomRole.host || change.connected) return;
    for (final p in _others.values) {
      if (p.deviceId == change.deviceId && p.connected) {
        p
          ..connected = false
          ..disconnectedAt = DateTime.now()
          ..sync = SyncStatus.idle
          ..voiceActive = false;
        _onRemoteVoice(p.id, false);
        _broadcastParticipant(p);
        _notice('${p.name} disconnected.');
      }
    }
    notifyListeners();
  }

  void _housekeeping() {
    _pruneRemoteVoice();
    if (role != RoomRole.host) return;
    final cutoff = DateTime.now().subtract(Duration(seconds: settings.reconnectWindowSec + 10));
    final expired = _others.values
        .where((p) => !p.connected && (p.disconnectedAt?.isBefore(cutoff) ?? false))
        .map((p) => p.id)
        .toList();
    for (final id in expired) {
      _removeParticipant(id);
    }
  }

  void _removeParticipant(String id) {
    final removed = _others.remove(id);
    if (removed == null) return;
    _onRemoteVoice(id, false);
    final codec = _codec!;
    _host.send(BleIds.participantState, () => codec.encode(Msg.participantLeft, {'participantId': id}));
    notifyListeners();
  }

  void _broadcastParticipant(ParticipantInfo p) => _sendParticipantUpdate(p);

  void _sendParticipantUpdate(ParticipantInfo p, {String? deviceId}) {
    final codec = _codec!;
    _host.send(
      BleIds.participantState,
      () => codec.encode(Msg.participantUpdate, {
        'participantId': p.id,
        'name': p.name,
        'track': p.track.name,
        'connected': p.connected,
      }),
      deviceId: deviceId,
    );
  }

  void _sendState({String? deviceId}) {
    final codec = _codec;
    final track = roomTrack;
    if (role != RoomRole.host || codec == null || track == null) return;
    final a = anchor;
    _host.send(
      BleIds.control,
      () => codec.encode(Msg.state, {
        'trackHash': track.hash,
        'title': _truncate(track.title, _maxTitleLength),
        'durationMs': track.durationMs,
        'playing': a.playing,
        'positionMs': a.positionMs,
        'hostTimeMs': a.hostTimeMs,
      }),
      deviceId: deviceId,
    );
  }

  void _sendControl(String type, [Map<String, Object?> fields = const {}]) {
    final codec = _codec!;
    _host.send(BleIds.control, () => codec.encode(type, fields));
  }

  Uint8List _roomInfoBytes() => Uint8List.fromList(utf8.encode(jsonEncode({
        'v': 1,
        'room': roomName,
        'code': roomCode,
        'participants': _others.values.where((p) => p.connected).length,
        'playing': anchor.playing,
      })));

  // ---------------------------------------------------------------------------
  // Participant
  // ---------------------------------------------------------------------------

  Future<void> joinRoom(DiscoveredRoom room, String pin) async {
    _ensureIdle();
    await _ensureBluetooth(hosting: false);

    role = RoomRole.participant;
    roomCode = room.code;
    roomName = room.name;
    this.pin = pin;
    endedReason = null;
    connection = ConnectionStatus.connecting;
    _hostDeviceId = room.deviceId;
    _codec = RoomCodec(sessionId: room.code, pin: pin, senderId: selfId);
    _estimator.reset();
    notifyListeners();

    try {
      await _peer.connect(room.deviceId);
      await _sendJoinAndWait();
    } catch (e) {
      await _resetSession();
      if (e is SessionException) rethrow;
      throw SessionException(e.toString());
    }

    connection = ConnectionStatus.connected;
    unawaited(_syncBurst());
    _pingTimer = Timer.periodic(_pingInterval, (_) => _sendPing());
    _driftTimer = Timer.periodic(_driftInterval, (_) => _driftCheck());
    _housekeepingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _housekeeping());
    notifyListeners();
    await _updateMicMonitoring();
  }

  /// Lets a participant pick the host's track from their files.
  Future<void> selectTrackForRoom() async {
    final expected = roomTrack;
    if (role != RoomRole.participant || expected == null) return;
    final picked = await tracks.pickAndImport();
    if (picked == null) return;
    if (picked.hash == expected.hash) {
      await _useLocalTrack(picked);
    } else {
      myTrack = TrackReadiness.mismatch;
      _notice("That file doesn't match the host's track (different fingerprint).");
      _sendTrackStatus();
      notifyListeners();
    }
  }

  Future<void> _sendJoinAndWait() async {
    final codec = _codec!;
    final completer = _joinCompleter = Completer<RoomMessage>();
    await _peer.write(
      BleIds.participantState,
      codec.encode(Msg.join, {'name': _truncate(settings.displayName, _maxNameLength)}),
    );
    final RoomMessage reply;
    try {
      reply = await completer.future.timeout(_joinTimeout);
    } on TimeoutException {
      throw const SessionException('The host did not respond. Check that the room is still open.');
    } finally {
      _joinCompleter = null;
    }
    if (reply.type == Msg.joinRejected) {
      throw SessionException(_rejectionMessage(reply.str('reason')), rejected: true);
    }
    _hostId = reply.senderId;
    roomName = reply.str('roomName');
    hostName = reply.str('hostName');
    _others[reply.senderId] = (_others[reply.senderId] ??
        ParticipantInfo(
          id: reply.senderId,
          name: hostName!,
          isHost: true,
          track: TrackReadiness.ready,
        ))
      ..connected = true;
  }

  void _onPeerInbound(PeerInbound inbound) {
    final codec = _codec;
    if (role != RoomRole.participant || codec == null) return;
    final allowed = switch (inbound.characteristicId) {
      BleIds.control => AllowedTypes.peerFromControl,
      BleIds.sync => AllowedTypes.peerFromSync,
      BleIds.voiceState => AllowedTypes.peerFromVoice,
      BleIds.participantState => AllowedTypes.peerFromParticipantState,
      _ => null,
    };
    if (allowed == null) return;
    final result = codec.decode(
      inbound.value,
      allowedTypes: allowed,
      unsignedTypes: const {Msg.joinRejected},
    );
    if (!result.isOk) return;
    final msg = result.message!;

    if (msg.type == Msg.joinAccepted || msg.type == Msg.joinRejected) {
      final completer = _joinCompleter;
      if (completer != null && !completer.isCompleted) completer.complete(msg);
      return;
    }
    if (_hostId == null || msg.senderId != _hostId) return;

    switch (msg.type) {
      case Msg.state:
        _applyHostState(msg);
      case Msg.playAt:
        if (msg.str('trackHash') != roomTrack?.hash) return;
        _applyAnchor(PlaybackAnchor(
          playing: true,
          positionMs: msg.integer('positionMs'),
          hostTimeMs: msg.integer('hostStartTimeMs'),
        ));
      case Msg.pause || Msg.seek:
        _applyAnchor(PlaybackAnchor(
          playing: false,
          positionMs: msg.integer('positionMs'),
          hostTimeMs: _hostNow(),
        ));
      case Msg.stop:
        _applyAnchor(PlaybackAnchor(playing: false, positionMs: 0, hostTimeMs: _hostNow()));
      case Msg.kick:
        unawaited(_endSession('The host removed you from the room.'));
      case Msg.roomClosed:
        unawaited(_endSession('The host closed the room.'));
      case Msg.pong:
        _onPong(msg);
      case Msg.participantUpdate:
        final id = msg.str('participantId');
        if (id == selfId) return;
        final p = _others.putIfAbsent(id, () => ParticipantInfo(id: id, name: msg.str('name')));
        p
          ..name = msg.str('name')
          ..track = TrackReadiness.parse(msg.str('track'))
          ..connected = msg.boolean('connected');
      case Msg.participantLeft:
        final id = msg.str('participantId');
        _others.remove(id);
        _onRemoteVoice(id, false);
      case Msg.voiceActive || Msg.voiceInactive:
        final id = msg.str('participantId');
        if (id == selfId) return;
        final active = msg.type == Msg.voiceActive;
        _others[id]?.voiceActive = active;
        _onRemoteVoice(id, active);
    }
    notifyListeners();
  }

  void _applyHostState(RoomMessage msg) {
    final hash = msg.str('trackHash');
    final trackChanged = roomTrack?.hash != hash;
    roomTrack = RoomTrack(hash: hash, title: msg.str('title'), durationMs: msg.integer('durationMs'));
    final next = PlaybackAnchor(
      playing: msg.boolean('playing'),
      positionMs: msg.integer('positionMs'),
      hostTimeMs: msg.integer('hostTimeMs'),
    );
    if (trackChanged || myTrack == TrackReadiness.unknown) {
      anchor = next;
      unawaited(_checkLocalTrack());
    } else if (!next.sameAs(anchor)) {
      _applyAnchor(next);
    }
  }

  Future<void> _checkLocalTrack() async {
    final expected = roomTrack;
    if (expected == null) return;
    final local = tracks.findByHash(expected.hash);
    if (local != null) {
      await _useLocalTrack(local);
    } else {
      if (myTrack != TrackReadiness.mismatch) myTrack = TrackReadiness.missing;
      _sendTrackStatus();
      notifyListeners();
    }
  }

  Future<void> _useLocalTrack(TrackInfo track) async {
    try {
      final durationMs = await _loadTrack(track);
      localTrack = track.copyWith(durationMs: durationMs);
      myTrack = TrackReadiness.ready;
    } on SessionException catch (e) {
      myTrack = TrackReadiness.missing;
      _notice(e.message);
    }
    _sendTrackStatus();
    notifyListeners();
    if (myTrack == TrackReadiness.ready) _applyAnchor(anchor);
  }

  void _sendTrackStatus() => _peerSend(BleIds.participantState, Msg.trackStatus, {'track': myTrack.name});

  Future<void> _syncBurst() async {
    for (var i = 0; i < 8 && role == RoomRole.participant && _peer.connected; i++) {
      await _sendPing();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _sendPing() => _peerSend(BleIds.sync, Msg.ping, {'t0': _clock.nowMs()});

  void _onPong(RoomMessage msg) {
    final now = _clock.nowMs();
    final sent = msg.integer('t0');
    if (now - sent > 5000) return;
    final hadEstimate = _estimator.hasEstimate;
    _estimator.addSample(
      sentAtLocalMs: sent,
      hostTimeMs: msg.integer('hostTimeMs'),
      receivedAtLocalMs: now,
    );
    if (!hadEstimate && _estimator.hasEstimate) _applyAnchor(anchor);
  }

  Future<void> _peerSend(String characteristicId, String type, [Map<String, Object?> fields = const {}]) async {
    final codec = _codec;
    if (codec == null || !_peer.connected) return;
    try {
      await _peer.write(characteristicId, codec.encode(type, fields));
    } catch (_) {
      // Connection loss is handled by the reconnect flow.
    }
  }

  Future<void> _reconnect() async {
    if (role != RoomRole.participant) return;
    final attempt = ++_reconnectAttempt;
    connection = ConnectionStatus.reconnecting;
    _others[_hostId]?.connected = false;
    _notice('Lost connection to the host. Reconnecting…');
    notifyListeners();

    final deadline = DateTime.now().add(Duration(seconds: settings.reconnectWindowSec));
    while (DateTime.now().isBefore(deadline) &&
        role == RoomRole.participant &&
        attempt == _reconnectAttempt) {
      if (!bluetoothOn) {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      try {
        await _peer.connect(_hostDeviceId!, timeout: const Duration(seconds: 8));
        await _sendJoinAndWait();
        if (attempt != _reconnectAttempt) return;
        connection = ConnectionStatus.connected;
        _sendTrackStatus();
        unawaited(_syncBurst());
        _notice('Reconnected to the host.');
        notifyListeners();
        return;
      } on SessionException catch (e) {
        if (e.rejected) {
          await _endSession(e.message);
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 3));
    }

    if (role == RoomRole.participant && attempt == _reconnectAttempt) {
      await _peer.disconnect();
      connection = ConnectionStatus.lost;
      hostLost = true;
      notifyListeners();
    }
  }

  /// After the host is gone: keep playing locally with local controls.
  void continueIndependently() {
    if (role != RoomRole.participant) return;
    _reconnectAttempt++;
    _driftTimer?.cancel();
    _pingTimer?.cancel();
    _scheduleToken++;
    _cancelNudge();
    _others.clear();
    _remoteVoice.clear();
    ducking.setRemoteSpeech(false);
    role = RoomRole.solo;
    hostLost = false;
    connection = ConnectionStatus.disconnected;
    mySync = SyncStatus.idle;
    myDriftMs = null;
    notifyListeners();
  }

  void _soloPlay() {
    if (!playback.isLoaded) return;
    final duration = playback.durationMs;
    if (duration != null && playback.positionMs >= duration - 200) playback.seek(0);
    playback.play();
  }

  // ---------------------------------------------------------------------------
  // Shared playback scheduling and drift correction
  // ---------------------------------------------------------------------------

  bool get _canPlayLocally =>
      playback.isLoaded &&
      myTrack == TrackReadiness.ready &&
      (role == RoomRole.host || _estimator.hasEstimate);

  int get _offsetMs => role == RoomRole.participant ? _estimator.offsetMs : 0;

  int _hostNow() => _clock.nowMs() + _offsetMs;

  Future<void> _applyAnchor(PlaybackAnchor next) async {
    anchor = next;
    final token = ++_scheduleToken;
    _waitingForStart = false;
    localPlaybackInterrupted = false;
    _cancelNudge();
    notifyListeners();
    if (!_canPlayLocally) return;

    if (!next.playing) {
      await playback.pause();
      await playback.seek(next.positionMs);
      mySync = SyncStatus.idle;
      myDriftMs = null;
      notifyListeners();
      return;
    }

    final localStart = next.hostTimeMs - _offsetMs;
    if (localStart - _clock.nowMs() > 40) {
      _waitingForStart = true;
      notifyListeners();
      await playback.pause();
      await playback.seek(next.positionMs);
      final remaining = localStart - _clock.nowMs();
      if (remaining > 0) await Future<void>.delayed(Duration(milliseconds: remaining));
      if (token != _scheduleToken) return;
      _waitingForStart = false;
      playback.play();
    } else {
      // Joining late or after reconnecting: jump to the group's position.
      final target = next.expectedPositionAt(_hostNow()) + _seekLatencyMs;
      final duration = playback.durationMs;
      if (duration != null && target >= duration) {
        await playback.pause();
        return;
      }
      await playback.seek(target);
      if (token != _scheduleToken) return;
      playback.play();
    }
    mySync = SyncStatus.adjusting;
    notifyListeners();

    Timer(const Duration(milliseconds: 1500), () {
      if (token == _scheduleToken) _driftCheck();
    });
  }

  /// Re-aligns after local playback was interrupted (call, other app, ...).
  void resyncNow() => _applyAnchor(anchor);

  void _driftCheck() {
    if (role != RoomRole.host && role != RoomRole.participant) return;
    if (!anchor.playing || !_canPlayLocally || _waitingForStart || _nudging) return;

    final expected = anchor.expectedPositionAt(_hostNow());
    final duration = playback.durationMs;
    if (duration != null && expected >= duration - 300) return;

    if (!playback.isPlaying) {
      localPlaybackInterrupted = true;
      mySync = SyncStatus.outOfSync;
      myDriftMs = null;
      _reportSync(0);
      notifyListeners();
      return;
    }

    final drift = playback.positionMs - expected;
    final decision = DriftPolicy.decide(driftMs: drift, thresholdMs: settings.syncThresholdMs);
    mySync = decision.status;
    myDriftMs = drift;
    switch (decision.action) {
      case DriftAction.none:
        playback.setSpeed(1.0);
      case DriftAction.nudge:
        _nudging = true;
        playback.setSpeed(decision.speed);
        _nudgeTimer = Timer(decision.duration, () {
          _nudging = false;
          playback.setSpeed(1.0);
        });
      case DriftAction.seek:
        playback.seek(expected + _seekLatencyMs);
    }
    _reportSync(drift);
    notifyListeners();
  }

  void _reportSync(int driftMs) {
    if (role == RoomRole.participant) {
      _peerSend(BleIds.sync, Msg.syncReport, {'driftMs': driftMs, 'status': mySync.name});
    }
  }

  void _cancelNudge() {
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    if (_nudging) {
      _nudging = false;
      playback.setSpeed(1.0);
    }
  }

  void _onTrackCompleted() {
    if (role == RoomRole.host && anchor.playing) {
      hostStop();
    } else {
      notifyListeners();
    }
  }

  int _clampPosition(int positionMs) {
    final duration = roomTrack?.durationMs ?? playback.durationMs ?? 0;
    return duration > 0 ? positionMs.clamp(0, duration) : max(0, positionMs);
  }

  // ---------------------------------------------------------------------------
  // Voice ducking
  // ---------------------------------------------------------------------------

  void _onLocalSpeech(bool speaking) {
    if (!inSession || !_micOwned) return;
    ducking.setLocalSpeech(speaking);
    if (settings.groupDucking && role != RoomRole.solo) {
      _shareVoice(speaking);
      _voiceRefreshTimer?.cancel();
      if (speaking) {
        _voiceRefreshTimer = Timer.periodic(_voiceRefresh, (_) => _shareVoice(true));
      }
    }
    notifyListeners();
  }

  void _shareVoice(bool active) {
    final codec = _codec;
    if (codec == null) return;
    final type = active ? Msg.voiceActive : Msg.voiceInactive;
    final fields = {'participantId': selfId};
    if (role == RoomRole.host) {
      _host.send(BleIds.voiceState, () => codec.encode(type, fields));
    } else if (role == RoomRole.participant) {
      _peerSend(BleIds.voiceState, type, fields);
    }
  }

  void _onRemoteVoice(String participantId, bool active) {
    if (active) {
      _remoteVoice[participantId] = _clock.nowMs();
    } else {
      _remoteVoice.remove(participantId);
    }
    _updateRemoteDucking();
  }

  void _pruneRemoteVoice() {
    final cutoff = _clock.nowMs() - _remoteVoiceTimeoutMs;
    final before = _remoteVoice.length;
    _remoteVoice.removeWhere((_, lastSeen) => lastSeen < cutoff);
    if (_remoteVoice.length != before) {
      for (final p in _others.values) {
        if (!_remoteVoice.containsKey(p.id)) p.voiceActive = false;
      }
      _updateRemoteDucking();
      notifyListeners();
    }
  }

  void _updateRemoteDucking() =>
      ducking.setRemoteSpeech(settings.groupDucking && _remoteVoice.isNotEmpty);

  Future<void> _updateMicMonitoring() async {
    final want = inSession && settings.duckingEnabled;
    if (want && !_micOwned) {
      _micOwned = true;
      final outcome = await permissions.requestMicrophone();
      if (outcome != PermissionOutcome.granted) {
        _micOwned = false;
        micDenied = true;
        _notice('Microphone permission denied. Voice ducking is off.');
        notifyListeners();
        return;
      }
      micDenied = false;
      if (!await voice.acquire(this)) {
        _micOwned = false;
        _notice(voice.error ?? 'Could not start the microphone.');
      }
      notifyListeners();
    } else if (!want && _micOwned) {
      _micOwned = false;
      _voiceRefreshTimer?.cancel();
      await voice.release(this);
      ducking.setLocalSpeech(false);
      if (settings.groupDucking) _shareVoice(false);
      notifyListeners();
    }
  }

  void _onVoiceServiceChanged() {
    if (_micOwned && !voice.active && voice.error != null) {
      _micOwned = false;
      ducking.setLocalSpeech(false);
      _notice('${voice.error}. Voice ducking paused.');
      notifyListeners();
    }
  }

  void _applySettings() {
    ducking.configure(
      enabled: settings.duckingEnabled,
      duckFactor: settings.duckLevel,
      attackMs: settings.duckAttackMs,
      releaseDelayMs: settings.releaseDelayMs,
      restoreRampMs: settings.restoreRampMs,
    );
    playback.userVolume = settings.musicVolume;
    voice.sensitivity = settings.vadSensitivity;

    if (_lastGroupDucking && !settings.groupDucking) {
      if (ducking.localSpeech) _shareVoice(false);
      _voiceRefreshTimer?.cancel();
    }
    _lastGroupDucking = settings.groupDucking;
    _updateRemoteDucking();

    if (_lastDuckingEnabled != settings.duckingEnabled) {
      _lastDuckingEnabled = settings.duckingEnabled;
      unawaited(_updateMicMonitoring());
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> leave() async {
    switch (role) {
      case RoomRole.host:
        final codec = _codec!;
        _host.send(BleIds.control, () => codec.encode(Msg.roomClosed));
        await _host.flush();
      case RoomRole.participant:
        await _peerSend(BleIds.participantState, Msg.leave);
      case RoomRole.solo:
      case RoomRole.none:
        break;
    }
    endedReason = null;
    await _resetSession();
  }

  Future<void> _endSession(String reason) async {
    endedReason = reason;
    _notice(reason);
    await _resetSession();
  }

  Future<void> _resetSession() async {
    _driftTimer?.cancel();
    _stateTimer?.cancel();
    _pingTimer?.cancel();
    _housekeepingTimer?.cancel();
    _voiceRefreshTimer?.cancel();
    _cancelNudge();
    _scheduleToken++;
    _reconnectAttempt++;
    final completer = _joinCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const SessionException('Cancelled'));
    }
    _joinCompleter = null;

    if (_host.running) await _host.stop();
    await _peer.disconnect();
    await playback.unload();
    if (_micOwned) {
      _micOwned = false;
      await voice.release(this);
    }
    ducking.reset();

    role = RoomRole.none;
    roomName = null;
    roomCode = null;
    pin = null;
    hostName = null;
    roomTrack = null;
    localTrack = null;
    myTrack = TrackReadiness.unknown;
    connection = ConnectionStatus.disconnected;
    mySync = SyncStatus.idle;
    myDriftMs = null;
    anchor = const PlaybackAnchor.stopped();
    hostLost = false;
    localPlaybackInterrupted = false;
    _waitingForStart = false;
    _codec = null;
    _hostId = null;
    _hostDeviceId = null;
    _advert = null;
    _others.clear();
    _banned.clear();
    _remoteVoice.clear();
    _estimator.reset();
    notifyListeners();
  }

  void _onAdapterState(BluetoothAdapterState state) {
    final on = state == BluetoothAdapterState.on || state == BluetoothAdapterState.unknown;
    if (on == bluetoothOn) return;
    bluetoothOn = on;
    if (!on && role == RoomRole.host) {
      _notice('Bluetooth is off. Participants have been disconnected.');
    }
    if (on && role == RoomRole.host && _advert != null) {
      _host.start(_advert!).catchError((Object e) => _notice('Could not restart the room: $e'));
    }
    notifyListeners();
  }

  void _ensureIdle() {
    if (role != RoomRole.none) {
      throw const SessionException('Leave the current room first.');
    }
  }

  Future<void> _ensureBluetooth({required bool hosting}) async {
    final outcome = await permissions.requestBluetooth(hosting: hosting);
    if (outcome == PermissionOutcome.permanentlyDenied) {
      throw const SessionException(
          'Bluetooth permission is blocked. Enable "Nearby devices" for this app in system settings.');
    }
    if (outcome != PermissionOutcome.granted) {
      throw const SessionException('Bluetooth permission is required to find and connect to rooms.');
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
      final state = await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 8), onTimeout: () => BluetoothAdapterState.off);
      if (state != BluetoothAdapterState.on) {
        throw const SessionException('Turn on Bluetooth to use rooms.');
      }
    }
  }

  Future<int?> _loadTrack(TrackInfo track) async {
    try {
      return await playback.load(track.path);
    } catch (e) {
      throw SessionException("This phone can't play \"${track.title}\": $e");
    }
  }

  void _notice(String message) => _notices.add(message);

  static String _rejectionMessage(String reason) => switch (reason) {
        'wrong_pin' => 'Wrong room PIN.',
        'full' => 'The room is full.',
        'removed' => 'The host removed you from this room.',
        _ => 'The host declined the request.',
      };

  static String _truncate(String value, int maxChars) {
    final runes = value.runes.toList();
    return runes.length <= maxChars ? value : String.fromCharCodes(runes.take(maxChars));
  }

  static String _randomHex(int length) {
    final r = Random.secure();
    return List.generate(length, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    settings.removeListener(_applySettings);
    voice.removeListener(_onVoiceServiceChanged);
    _resetSession();
    _notices.close();
    super.dispose();
  }
}
