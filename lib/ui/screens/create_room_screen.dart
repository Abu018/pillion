import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../core/models.dart';
import '../../services/track_service.dart';
import 'room_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController(text: (Random.secure().nextInt(9000) + 1000).toString());
  TrackInfo? _track;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _importTrack() async {
    try {
      final track = await AppScope.of(context).tracks.pickAndImport();
      if (track != null) setState(() => _track = track);
    } on TrackImportException catch (e) {
      _show(e.message);
    }
  }

  Future<void> _create() async {
    final track = _track;
    if (track == null) return _show('Choose a track first.');
    if (_pin.text.length != 4) return _show('The PIN must be 4 digits.');
    setState(() => _busy = true);
    try {
      await AppScope.of(context).session.createRoom(name: _name.text, pin: _pin.text, track: track);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RoomScreen()));
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tracks = AppScope.of(context).tracks;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Room')),
      body: ListenableBuilder(
        listenable: tracks,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              maxLength: 16,
              decoration: const InputDecoration(
                labelText: 'Room name',
                helperText: 'Visible to nearby phones. Avoid personal details.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Room PIN',
                helperText: 'Share this PIN with people you want to let in.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Track', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _track?.hash,
              onChanged: (hash) => setState(() => _track = tracks.findByHash(hash!)),
              child: Column(
                children: [
                  for (final t in tracks.library)
                    RadioListTile<String>(
                      value: t.hash,
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Fingerprint ${t.shortHash}'),
                    ),
                ],
              ),
            ),
            if (tracks.library.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No tracks yet. Import an MP3 or M4A file from your phone.'),
              ),
            OutlinedButton.icon(
              onPressed: tracks.importing ? null : _importTrack,
              icon: tracks.importing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.library_music),
              label: Text(tracks.importing ? 'Importing and fingerprinting…' : 'Import a track'),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy || _track == null ? null : _create,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Start room'),
            ),
          ],
        ),
      ),
    );
  }
}
