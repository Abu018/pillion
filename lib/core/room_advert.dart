import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Payload carried in the BLE scan response's manufacturer data.
///
/// Layout: `[version][6-byte room code][room name, UTF-8, <= 16 bytes]`.
/// Contains no device or personal identifiers.
class RoomAdvert {
  const RoomAdvert({required this.code, required this.name});

  static const version = 1;
  static const codeLength = 6;
  static const maxNameBytes = 16;
  static const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final String code;
  final String name;

  static String generateCode([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(
      codeLength,
      (_) => codeAlphabet[r.nextInt(codeAlphabet.length)],
    ).join();
  }

  static bool isValidCode(String code) =>
      code.length == codeLength &&
      code.split('').every((c) => codeAlphabet.contains(c));

  Uint8List encode() {
    return Uint8List.fromList([
      version,
      ...ascii.encode(code),
      ...truncateUtf8(name, maxNameBytes),
    ]);
  }

  static RoomAdvert? decode(List<int> data) {
    if (data.length < 1 + codeLength || data[0] != version) return null;
    final codeBytes = data.sublist(1, 1 + codeLength);
    if (codeBytes.any((b) => b > 127)) return null;
    final code = ascii.decode(codeBytes);
    if (!isValidCode(code)) return null;
    final name = utf8.decode(data.sublist(1 + codeLength), allowMalformed: true);
    return RoomAdvert(code: code, name: name.isEmpty ? 'Room $code' : name);
  }

  /// Truncates on a character boundary so the result is valid UTF-8.
  static List<int> truncateUtf8(String value, int maxBytes) {
    final out = <int>[];
    for (final rune in value.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (out.length + bytes.length > maxBytes) break;
      out.addAll(bytes);
    }
    return out;
  }
}
