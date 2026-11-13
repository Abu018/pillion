import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pillion/core/protocol.dart';
import 'package:pillion/core/room_advert.dart';

void main() {
  RoomCodec codec({String pin = '1234', String sender = 'host', String session = 'ABC234'}) =>
      RoomCodec(sessionId: session, pin: pin, senderId: sender);

  const control = AllowedTypes.peerFromControl;

  test('round-trips a signed PLAY_AT message', () {
    final host = codec();
    final peer = codec(sender: 'p-1');
    final bytes = host.encode(Msg.playAt, {
      'trackHash': 'a' * 64,
      'positionMs': 1500,
      'hostStartTimeMs': 1730000000000,
    });
    final result = peer.decode(bytes, allowedTypes: control);
    expect(result.isOk, isTrue);
    expect(result.message!.type, Msg.playAt);
    expect(result.message!.integer('positionMs'), 1500);
    expect(result.message!.senderId, 'host');
  });

  test('rejects messages signed with a different PIN', () {
    final bytes = codec(pin: '0000').encode(Msg.stop);
    expect(codec(sender: 'p-1').decode(bytes, allowedTypes: control).error, DecodeError.badSignature);
  });

  test('rejects tampered payloads', () {
    final raw = utf8.decode(codec().encode(Msg.pause, {'positionMs': 10}));
    final tampered = utf8.encode(raw.replaceFirst('"positionMs":10', '"positionMs":99'));
    expect(codec(sender: 'p').decode(tampered, allowedTypes: control).error, DecodeError.badSignature);
  });

  test('rejects replayed messages', () {
    final peer = codec(sender: 'p-1');
    final bytes = codec().encode(Msg.stop);
    expect(peer.decode(bytes, allowedTypes: control).isOk, isTrue);
    expect(peer.decode(bytes, allowedTypes: control).error, DecodeError.replay);
  });

  test('rejects other sessions, wrong channels, and malformed data', () {
    final peer = codec(sender: 'p-1');
    expect(
      peer.decode(codec(session: 'ZZZ234').encode(Msg.stop), allowedTypes: control).error,
      anyOf(DecodeError.badSignature, DecodeError.wrongSession),
    );
    expect(
      peer.decode(codec().encode(Msg.ping, {'t0': 1}), allowedTypes: control).error,
      DecodeError.disallowedType,
    );
    expect(peer.decode(utf8.encode('garbage'), allowedTypes: control).error, DecodeError.malformed);
    expect(peer.decode(List.filled(600, 65), allowedTypes: control).error, DecodeError.tooLarge);
  });

  test('rejects messages with missing or invalid fields', () {
    final bytes = codec().encode(Msg.pause, {'positionMs': -5});
    expect(codec(sender: 'p').decode(bytes, allowedTypes: control).error, DecodeError.invalidFields);
  });

  test('unsigned messages are only accepted for whitelisted types', () {
    final host = codec();
    final rejected = host.encodeUnsigned(Msg.joinRejected, {'reason': 'wrong_pin'});
    final peer = codec(pin: '9999', sender: 'p');
    expect(
      peer.decode(rejected, allowedTypes: AllowedTypes.peerFromParticipantState).error,
      DecodeError.badSignature,
    );
    expect(
      peer
          .decode(rejected,
              allowedTypes: AllowedTypes.peerFromParticipantState, unsignedTypes: {Msg.joinRejected})
          .isOk,
      isTrue,
    );
  });

  test('a re-created codec continues with fresh sequence numbers', () {
    final receiver = codec(sender: 'host');
    final first = codec(sender: 'p-1').encode(Msg.leave);
    expect(receiver.decode(first, allowedTypes: {Msg.leave}).isOk, isTrue);
    final second = codec(sender: 'p-1').encode(Msg.leave);
    expect(receiver.decode(second, allowedTypes: {Msg.leave}).isOk, isTrue);
  });

  group('RoomAdvert', () {
    test('round-trips and fits in a scan response', () {
      const advert = RoomAdvert(code: 'K7Q2XM', name: 'Rooftop party night');
      final bytes = advert.encode();
      expect(bytes.length, lessThanOrEqualTo(27));
      final decoded = RoomAdvert.decode(bytes)!;
      expect(decoded.code, 'K7Q2XM');
      expect(decoded.name, 'Rooftop party ni');
    });

    test('truncates multi-byte names on character boundaries', () {
      final bytes = RoomAdvert.truncateUtf8('ééééééééé', 5);
      expect(utf8.decode(bytes), 'éé');
    });

    test('ignores foreign manufacturer data', () {
      expect(RoomAdvert.decode([2, 1, 2, 3]), isNull);
      expect(RoomAdvert.decode([1, ...'abc!!!'.codeUnits]), isNull);
    });
  });
}
