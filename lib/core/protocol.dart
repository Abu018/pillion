import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'clock.dart';

abstract final class Msg {
  static const join = 'JOIN';
  static const joinAccepted = 'JOIN_ACCEPTED';
  static const joinRejected = 'JOIN_REJECTED';
  static const leave = 'LEAVE';
  static const participantUpdate = 'PARTICIPANT_UPDATE';
  static const participantLeft = 'PARTICIPANT_LEFT';
  static const trackStatus = 'TRACK_STATUS';
  static const state = 'STATE';
  static const requestState = 'REQUEST_STATE';
  static const playAt = 'PLAY_AT';
  static const pause = 'PAUSE';
  static const seek = 'SEEK';
  static const stop = 'STOP';
  static const ping = 'PING';
  static const pong = 'PONG';
  static const syncReport = 'SYNC_REPORT';
  static const voiceActive = 'VOICE_ACTIVE';
  static const voiceInactive = 'VOICE_INACTIVE';
  static const kick = 'KICK';
  static const roomClosed = 'ROOM_CLOSED';
}

enum _Kind { string, integer, nonNegativeInt, boolean }

/// Required fields (and their kinds) for every message type.
const Map<String, Map<String, _Kind>> _schemas = {
  Msg.join: {'name': _Kind.string},
  Msg.joinAccepted: {'roomName': _Kind.string, 'hostName': _Kind.string},
  Msg.joinRejected: {'reason': _Kind.string},
  Msg.leave: {},
  Msg.participantUpdate: {
    'participantId': _Kind.string,
    'name': _Kind.string,
    'track': _Kind.string,
    'connected': _Kind.boolean,
  },
  Msg.participantLeft: {'participantId': _Kind.string},
  Msg.trackStatus: {'track': _Kind.string},
  Msg.state: {
    'trackHash': _Kind.string,
    'title': _Kind.string,
    'durationMs': _Kind.nonNegativeInt,
    'playing': _Kind.boolean,
    'positionMs': _Kind.nonNegativeInt,
    'hostTimeMs': _Kind.nonNegativeInt,
  },
  Msg.requestState: {},
  Msg.playAt: {
    'trackHash': _Kind.string,
    'positionMs': _Kind.nonNegativeInt,
    'hostStartTimeMs': _Kind.nonNegativeInt,
  },
  Msg.pause: {'positionMs': _Kind.nonNegativeInt},
  Msg.seek: {'positionMs': _Kind.nonNegativeInt},
  Msg.stop: {},
  Msg.ping: {'t0': _Kind.nonNegativeInt},
  Msg.pong: {'t0': _Kind.nonNegativeInt, 'hostTimeMs': _Kind.nonNegativeInt},
  Msg.syncReport: {'driftMs': _Kind.integer, 'status': _Kind.string},
  Msg.voiceActive: {'participantId': _Kind.string},
  Msg.voiceInactive: {'participantId': _Kind.string},
  Msg.kick: {},
  Msg.roomClosed: {},
};

/// Message types each side accepts, per characteristic it arrives on.
abstract final class AllowedTypes {
  static const hostFromParticipantState = {Msg.join, Msg.leave, Msg.trackStatus};
  static const hostFromSync = {Msg.ping, Msg.syncReport, Msg.requestState};
  static const hostFromVoice = {Msg.voiceActive, Msg.voiceInactive};

  static const peerFromControl = {
    Msg.state,
    Msg.playAt,
    Msg.pause,
    Msg.seek,
    Msg.stop,
    Msg.kick,
    Msg.roomClosed,
  };
  static const peerFromSync = {Msg.pong};
  static const peerFromVoice = {Msg.voiceActive, Msg.voiceInactive};
  static const peerFromParticipantState = {
    Msg.joinAccepted,
    Msg.joinRejected,
    Msg.participantUpdate,
    Msg.participantLeft,
  };
}

class RoomMessage {
  const RoomMessage({
    required this.type,
    required this.sessionId,
    required this.sequence,
    required this.senderId,
    required this.fields,
    required this.signed,
  });

  final String type;
  final String sessionId;
  final int sequence;
  final String senderId;
  final Map<String, Object?> fields;
  final bool signed;

  String str(String key) => fields[key]! as String;
  int integer(String key) => fields[key]! as int;
  bool boolean(String key) => fields[key]! as bool;
}

enum DecodeError {
  tooLarge,
  malformed,
  badSignature,
  wrongSession,
  unknownType,
  disallowedType,
  invalidFields,
  replay,
}

class DecodeResult {
  const DecodeResult.ok(RoomMessage this.message) : error = null;
  const DecodeResult.failed(DecodeError this.error) : message = null;

  final RoomMessage? message;
  final DecodeError? error;

  bool get isOk => message != null;
}

/// Encodes, signs, validates and de-duplicates control messages.
///
/// Wire format: `<16 hex chars HMAC-SHA256>.<JSON>`. The HMAC key is derived
/// from the room code and PIN, so only devices that know the PIN can produce
/// messages the room accepts.
class RoomCodec {
  RoomCodec({
    required this.sessionId,
    required String pin,
    required this.senderId,
  }) : _key = sha256.convert(utf8.encode('pillion-room-v1|$sessionId|$pin')).bytes;

  static const maxMessageBytes = 500;
  static const maxStringLength = 96;
  static const _macLength = 16;
  static const _unsignedMac = '----------------';

  final String sessionId;
  final String senderId;
  final List<int> _key;
  final Map<String, _ReplayWindow> _replay = {};

  // Shared by all codecs and seeded from the clock (in microsecond units, still
  // below 2^53), so a participant that leaves and rejoins never reuses a
  // sequence number the host has already seen, even after an app restart.
  static int _lastSequence = 0;

  static int _nextSequence() =>
      _lastSequence = max(_lastSequence + 1, MonotonicClock.instance.nowMs() * 1000);

  Uint8List encode(String type, [Map<String, Object?> fields = const {}]) =>
      _encode(type, fields, signed: true);

  /// Only for replies to peers that failed authentication (wrong PIN).
  Uint8List encodeUnsigned(String type, [Map<String, Object?> fields = const {}]) =>
      _encode(type, fields, signed: false);

  Uint8List _encode(String type, Map<String, Object?> fields, {required bool signed}) {
    final json = jsonEncode({
      'type': type,
      'sessionId': sessionId,
      'sequence': _nextSequence(),
      'from': senderId,
      ...fields,
    });
    final mac = signed ? _mac(json) : _unsignedMac;
    final bytes = utf8.encode('$mac.$json');
    if (bytes.length > maxMessageBytes) {
      throw StateError('$type message is ${bytes.length} bytes; limit is $maxMessageBytes');
    }
    return Uint8List.fromList(bytes);
  }

  DecodeResult decode(
    List<int> bytes, {
    required Set<String> allowedTypes,
    Set<String> unsignedTypes = const {},
  }) {
    if (bytes.length > maxMessageBytes) return const DecodeResult.failed(DecodeError.tooLarge);

    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException {
      return const DecodeResult.failed(DecodeError.malformed);
    }
    if (raw.length <= _macLength + 1 || raw[_macLength] != '.') {
      return const DecodeResult.failed(DecodeError.malformed);
    }
    final mac = raw.substring(0, _macLength);
    final json = raw.substring(_macLength + 1);

    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const DecodeResult.failed(DecodeError.malformed);
    }
    if (decoded is! Map<String, Object?>) return const DecodeResult.failed(DecodeError.malformed);

    final type = decoded['type'];
    final session = decoded['sessionId'];
    final sequence = decoded['sequence'];
    final from = decoded['from'];
    if (type is! String || session is! String || sequence is! int || from is! String) {
      return const DecodeResult.failed(DecodeError.malformed);
    }
    if (from.isEmpty || from.length > 40) return const DecodeResult.failed(DecodeError.malformed);

    final signed = mac != _unsignedMac;
    if (signed) {
      if (!_constantTimeEquals(mac, _mac(json))) {
        return const DecodeResult.failed(DecodeError.badSignature);
      }
    } else if (!unsignedTypes.contains(type)) {
      return const DecodeResult.failed(DecodeError.badSignature);
    }

    if (session != sessionId) return const DecodeResult.failed(DecodeError.wrongSession);
    final schema = _schemas[type];
    if (schema == null) return const DecodeResult.failed(DecodeError.unknownType);
    if (!allowedTypes.contains(type)) return const DecodeResult.failed(DecodeError.disallowedType);

    final fields = Map<String, Object?>.of(decoded)
      ..remove('type')
      ..remove('sessionId')
      ..remove('sequence')
      ..remove('from');
    for (final entry in schema.entries) {
      if (!_matches(fields[entry.key], entry.value)) {
        return const DecodeResult.failed(DecodeError.invalidFields);
      }
    }

    if (signed && !_replay.putIfAbsent(from, _ReplayWindow.new).accept(sequence)) {
      return const DecodeResult.failed(DecodeError.replay);
    }

    return DecodeResult.ok(RoomMessage(
      type: type,
      sessionId: session,
      sequence: sequence,
      senderId: from,
      fields: fields,
      signed: signed,
    ));
  }

  String _mac(String json) =>
      Hmac(sha256, _key).convert(utf8.encode(json)).toString().substring(0, _macLength);

  static bool _matches(Object? value, _Kind kind) => switch (kind) {
        _Kind.string => value is String && value.length <= maxStringLength,
        _Kind.integer => value is int,
        _Kind.nonNegativeInt => value is int && value >= 0,
        _Kind.boolean => value is bool,
      };

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Accepts each sequence number once, tolerating reordering among the last
/// [_size] messages.
class _ReplayWindow {
  static const _size = 64;
  final SplayTreeSet<int> _recent = SplayTreeSet();

  bool accept(int sequence) {
    if (_recent.contains(sequence)) return false;
    if (_recent.length >= _size && sequence < _recent.first) return false;
    _recent.add(sequence);
    if (_recent.length > _size) _recent.remove(_recent.first);
    return true;
  }
}
