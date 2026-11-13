import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../core/models.dart';
import '../../services/bluetooth/room_scanner.dart';
import '../../services/permissions_service.dart';
import 'room_screen.dart';

class DiscoverRoomsScreen extends StatefulWidget {
  const DiscoverRoomsScreen({super.key});

  @override
  State<DiscoverRoomsScreen> createState() => _DiscoverRoomsScreenState();
}

class _DiscoverRoomsScreenState extends State<DiscoverRoomsScreen> {
  final RoomScanner _scanner = RoomScanner();
  String? _permissionError;
  bool _permanentlyDenied = false;
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    final outcome = await AppScope.of(context).permissions.requestBluetooth(hosting: false);
    if (!mounted) return;
    if (outcome != PermissionOutcome.granted) {
      setState(() {
        _permanentlyDenied = outcome == PermissionOutcome.permanentlyDenied;
        _permissionError = 'Bluetooth permission is needed to find nearby rooms.';
      });
      return;
    }
    setState(() => _permissionError = null);
    await _scanner.start();
  }

  Future<void> _join(DiscoveredRoom room) async {
    final pin = await showDialog<String>(context: context, builder: (_) => _PinDialog(room: room));
    if (pin == null || !mounted) return;
    setState(() => _joiningId = room.deviceId);
    await _scanner.stop();
    if (!mounted) return;
    try {
      await AppScope.of(context).session.joinRoom(room, pin);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RoomScreen()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _joiningId = null);
      await _scanner.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby rooms'),
        actions: [
          ListenableBuilder(
            listenable: _scanner,
            builder: (context, _) => _scanner.scanning
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(icon: const Icon(Icons.refresh), tooltip: 'Scan again', onPressed: _startScan),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_scanner, session]),
        builder: (context, _) {
          if (!session.bluetoothOn) {
            return const _Message(
              icon: Icons.bluetooth_disabled,
              text: 'Bluetooth is off. Turn it on to look for rooms.',
            );
          }
          if (_permissionError != null) {
            return _Message(
              icon: Icons.block,
              text: _permissionError!,
              action: _permanentlyDenied
                  ? FilledButton(
                      onPressed: AppScope.of(context).permissions.openSettings,
                      child: const Text('Open settings'),
                    )
                  : FilledButton(onPressed: _startScan, child: const Text('Try again')),
            );
          }
          if (_scanner.error != null) {
            return _Message(icon: Icons.error_outline, text: _scanner.error!);
          }
          final rooms = _scanner.rooms;
          if (rooms.isEmpty) {
            return _Message(
              icon: Icons.bluetooth_searching,
              text: _scanner.scanning
                  ? 'Looking for rooms nearby…\nMake sure the host has started a room.'
                  : 'No rooms found.',
              action: _scanner.scanning
                  ? null
                  : FilledButton(onPressed: _startScan, child: const Text('Scan again')),
            );
          }
          return ListView(
            children: [
              for (final room in rooms)
                ListTile(
                  leading: _SignalIcon(bars: room.signalBars),
                  title: Text(room.name),
                  subtitle: Text('Room ${room.code} · ${room.rssi} dBm'),
                  trailing: _joiningId == room.deviceId
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  enabled: _joiningId == null,
                  onTap: () => _join(room),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.room});
  final DiscoveredRoom room;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Join ${widget.room.name}'),
      content: TextField(
        controller: _pin,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Room PIN'),
        onSubmitted: (v) => v.length == 4 ? Navigator.pop(context, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _pin,
          builder: (context, _) => FilledButton(
            onPressed: _pin.text.length == 4 ? () => Navigator.pop(context, _pin.text) : null,
            child: const Text('Join'),
          ),
        ),
      ],
    );
  }
}

class _SignalIcon extends StatelessWidget {
  const _SignalIcon({required this.bars});
  final int bars;

  @override
  Widget build(BuildContext context) {
    final icon = switch (bars) {
      4 => Icons.signal_cellular_alt,
      3 => Icons.signal_cellular_alt_2_bar,
      2 || 1 => Icons.signal_cellular_alt_1_bar,
      _ => Icons.signal_cellular_0_bar,
    };
    return Icon(icon);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
