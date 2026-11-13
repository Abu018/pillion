import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

class TrackImportException implements Exception {
  const TrackImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Imports local audio files into app storage and fingerprints them (SHA-256).
///
/// Supported formats: MP3 and M4A/AAC.
class TrackService extends ChangeNotifier {
  TrackService(this._prefs);

  static const supportedExtensions = ['mp3', 'm4a', 'aac'];
  static const _libraryKey = 'trackLibrary';

  final SharedPreferences _prefs;
  List<TrackInfo> _library = [];
  bool _importing = false;

  List<TrackInfo> get library => List.unmodifiable(_library);
  bool get importing => _importing;

  static Future<TrackService> load() async {
    final service = TrackService(await SharedPreferences.getInstance());
    await service._restore();
    return service;
  }

  Future<void> _restore() async {
    final raw = _prefs.getString(_libraryKey);
    if (raw == null) return;
    final entries = (jsonDecode(raw) as List).cast<Map<String, Object?>>();
    _library = [
      for (final e in entries)
        if (File(e['path']! as String).existsSync()) TrackInfo.fromJson(e),
    ];
  }

  TrackInfo? findByHash(String hash) {
    for (final t in _library) {
      if (t.hash == hash) return t;
    }
    return null;
  }

  /// Lets the user pick a file. Returns null if the picker was cancelled.
  Future<TrackInfo?> pickAndImport() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choose an MP3 or M4A file',
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    if (picked == null) return null;

    final extension = (picked.extension ?? '').toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw TrackImportException('Unsupported file type ".$extension". Use MP3 or M4A/AAC.');
    }

    _importing = true;
    notifyListeners();
    try {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'tracks'));
      await dir.create(recursive: true);
      final temp = File(p.join(dir.path, 'import-${DateTime.now().microsecondsSinceEpoch}.$extension'));

      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      final out = temp.openWrite();
      await for (final chunk in picked.readAsByteStream()) {
        hasher.add(chunk);
        out.add(chunk);
      }
      hasher.close();
      await out.close();

      final hash = digestSink.value.toString();
      final existing = findByHash(hash);
      if (existing != null) {
        await temp.delete();
        return existing;
      }

      final finalPath = p.join(dir.path, '$hash.$extension');
      await temp.rename(finalPath);
      final track = TrackInfo(
        hash: hash,
        title: p.basenameWithoutExtension(picked.name),
        path: finalPath,
      );
      _library = [..._library, track];
      await _persist();
      return track;
    } on FileSystemException catch (e) {
      throw TrackImportException('Could not import the file: ${e.message}');
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  Future<void> remove(TrackInfo track) async {
    _library = _library.where((t) => t.hash != track.hash).toList();
    final file = File(track.path);
    if (await file.exists()) await file.delete();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() =>
      _prefs.setString(_libraryKey, jsonEncode([for (final t in _library) t.toJson()]));
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
