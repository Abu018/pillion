import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/models.dart';
import '../../services/ducking_controller.dart';
import '../../services/session_coordinator.dart';
import '../widgets/status_chips.dart';
import 'settings_screen.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  StreamSubscription<String>? _notices;
  late SessionCoordinator _session;
  bool _hostLostDialogOpen = false;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = AppScope.of(context).session;
    _notices ??= _session.notices.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    _session.removeListener(_onSessionChanged);
    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _notices?.cancel();
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted || _closing) return;
    if (!_session.inSession) {
      _closing = true;
      final reason = _session.endedReason;
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      if (reason != null) {
        showDialog<void>(
          context: navigator.context,
          builder: (context) => AlertDialog(
            title: const Text('Session ended'),
            content: Text(reason),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
      return;
    }
    if (_session.hostLost && !_hostLostDialogOpen) {
      _hostLostDialogOpen = true;
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Host disconnected'),
          content: const Text(
              "The host couldn't be reached. You can stop playback, or keep listening on this phone on your own."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stop playback')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue alone')),
          ],
        ),
      ).then((continueAlone) {
        _hostLostDialogOpen = false;
        if (continueAlone ?? false) {
          _session.continueIndependently();
        } else {
          _session.leave();
        }
      });
    }
  }

  Future<void> _confirmLeave() async {
    final isHost = _session.role == RoomRole.host;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isHost ? 'Close room?' : 'Leave room?'),
        content: Text(isHost
            ? 'Playback stops for everyone and participants are disconnected.'
            : 'Playback and voice detection stop on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isHost ? 'Close room' : 'Leave'),
          ),
        ],
      ),
    );
    if (ok ?? false) await _session.leave();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          final s = _session;
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.roomName ?? 'Room'),
                  Text(
                    switch (s.role) {
                      RoomRole.host => 'Hosting · room ${s.roomCode}',
                      RoomRole.solo => 'Listening alone',
                      _ => 'Room ${s.roomCode ?? ''}',
                    },
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
                TextButton(
                  onPressed: s.inSession ? _confirmLeave : null,
                  child: Text(s.role == RoomRole.host ? 'Close' : 'Leave'),
                ),
              ],
              bottom: const TabBar(tabs: [Tab(text: 'Lobby'), Tab(text: 'Now Playing')]),
            ),
            body: Column(
              children: [
                _StatusBanner(session: s),
                const Expanded(child: TabBarView(children: [_LobbyTab(), _NowPlayingTab()])),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.session});
  final SessionCoordinator session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    Widget banner(IconData icon, String text, Color color, {Widget? action}) => Material(
          color: color.withValues(alpha: 0.18),
          child: ListTile(dense: true, leading: Icon(icon, color: color), title: Text(text), trailing: action),
        );

    if (!s.bluetoothOn && s.role != RoomRole.solo) {
      return banner(Icons.bluetooth_disabled, 'Bluetooth is off. Turn it on to stay connected.', Colors.red);
    }
    if (s.connection == ConnectionStatus.reconnecting) {
      return banner(Icons.sync_problem, 'Connection lost. Reconnecting…', Colors.orange);
    }
    if (s.connection == ConnectionStatus.connecting) {
      return banner(Icons.bluetooth_searching, 'Connecting…', Colors.blue);
    }
    if (s.localPlaybackInterrupted) {
      return banner(
        Icons.pause_circle,
        'Playback was interrupted on this phone.',
        Colors.orange,
        action: TextButton(onPressed: s.resyncNow, child: const Text('Resume in sync')),
      );
    }
    if (s.micDenied && s.settings.duckingEnabled) {
      return banner(Icons.mic_off, 'Microphone permission denied. Voice ducking is off.', Colors.grey);
    }
    return const SizedBox.shrink();
  }
}

class _LobbyTab extends StatelessWidget {
  const _LobbyTab();

  Future<void> _play(BuildContext context, SessionCoordinator s) async {
    if (!s.allParticipantsReady) {
      final start = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not everyone is ready'),
          content: const Text(
              "Some participants don't have the matching track yet. They'll join in once they do."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wait')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start anyway')),
          ],
        ),
      );
      if (!(start ?? false)) return;
    }
    s.hostPlay();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session;
    return ListenableBuilder(listenable: s, builder: (context, _) => _build(context, s));
  }

  Widget _build(BuildContext context, SessionCoordinator s) {
    final theme = Theme.of(context);
    final track = s.roomTrack;
    final participants = s.participants;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room code: ${s.roomCode ?? '-'}', style: theme.textTheme.titleMedium),
                if (s.role == RoomRole.host) ...[
                  const SizedBox(height: 4),
                  Text('PIN: ${s.pin}', style: theme.textTheme.headlineSmall),
                  const Text('Share the PIN with people who should join.'),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.music_note),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        track?.title ?? 'Waiting for track info…',
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (track != null)
                  Text('Fingerprint ${track.hash.substring(0, 12)}…', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        if (s.role == RoomRole.participant &&
            (s.myTrack == TrackReadiness.missing || s.myTrack == TrackReadiness.mismatch))
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.myTrack == TrackReadiness.missing
                        ? "You don't have this track yet"
                        : "Your file doesn't match the host's track",
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select the exact same file the host is using ("${track?.title ?? ''}"). '
                    "You won't hear playback until the fingerprints match.",
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: s.selectTrackForRoom,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Select matching file'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('People (${participants.length})', style: theme.textTheme.titleMedium),
        for (final p in participants) _ParticipantTile(participant: p, session: s),
        if (s.role == RoomRole.host) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: s.anchor.playing ? s.hostPause : () => _play(context, s),
            icon: Icon(s.anchor.playing ? Icons.pause : Icons.play_arrow),
            label: Text(s.anchor.playing
                ? 'Pause for everyone'
                : s.allParticipantsReady
                    ? 'Play for everyone'
                    : 'Play (not everyone is ready)'),
          ),
        ],
        if (s.role == RoomRole.participant && s.myTrack == TrackReadiness.ready && !s.anchor.playing)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Ready. Waiting for the host to start playback.', textAlign: TextAlign.center),
          ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant, required this.session});

  final ParticipantInfo participant;
  final SessionCoordinator session;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final name = [p.name, if (p.isSelf) '(you)', if (p.isHost) '· host'].join(' ');
    final showSync = session.role == RoomRole.host || p.isSelf;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(p.voiceActive ? Icons.record_voice_over : (p.isHost ? Icons.star : Icons.person)),
      ),
      title: Text(name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (!p.connected)
              const StatusChip(label: 'Disconnected', color: Colors.red, icon: Icons.link_off)
            else ...[
              TrackChip(p.track),
              if (showSync && session.anchor.playing) SyncChip(p.sync, driftMs: p.driftMs),
            ],
          ],
        ),
      ),
      trailing: session.role == RoomRole.host && !p.isSelf
          ? IconButton(
              tooltip: 'Remove from room',
              icon: const Icon(Icons.person_remove),
              onPressed: () => session.kick(p.id),
            )
          : null,
    );
  }
}

class _NowPlayingTab extends StatelessWidget {
  const _NowPlayingTab();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.session,
      builder: (context, _) => _build(context, scope),
    );
  }

  Widget _build(BuildContext context, AppScope scope) {
    final s = scope.session;
    final theme = Theme.of(context);
    final controls = s.controlsPlayback;
    final playingNow = s.role == RoomRole.solo ? s.playback.isPlaying : s.anchor.playing;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.album, size: 120, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          s.roomTrack?.title ?? s.localTrack?.title ?? 'No track',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Center(
          child: s.role == RoomRole.solo
              ? const StatusChip(label: 'Not synced (alone)', color: Colors.grey)
              : s.waitingForStart
                  ? const StatusChip(label: 'Starting…', color: Colors.blue, icon: Icons.timer)
                  : SyncChip(s.mySync, driftMs: s.myDriftMs),
        ),
        const SizedBox(height: 16),
        _ProgressBar(session: s, seekable: controls),
        const SizedBox(height: 8),
        if (controls)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                iconSize: 32,
                tooltip: 'Stop',
                onPressed: s.hostStop,
                icon: const Icon(Icons.stop),
              ),
              const SizedBox(width: 24),
              IconButton.filled(
                iconSize: 48,
                tooltip: playingNow ? 'Pause' : 'Play',
                onPressed: playingNow ? s.hostPause : s.hostPlay,
                icon: Icon(playingNow ? Icons.pause : Icons.play_arrow),
              ),
            ],
          )
        else
          Text(
            s.myTrack == TrackReadiness.ready
                ? 'The host controls playback.'
                : 'Select the matching track in the Lobby to hear playback.',
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: scope.settings,
          builder: (context, _) => Row(
            children: [
              const Icon(Icons.volume_down),
              Expanded(
                child: Slider(
                  value: scope.settings.musicVolume,
                  onChanged: (v) => scope.settings.musicVolume = v,
                ),
              ),
              const Icon(Icons.volume_up),
            ],
          ),
        ),
        const _DuckingCard(),
        if (s.role == RoomRole.participant && s.clockOffsetMs != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Clock offset ${s.clockOffsetMs} ms · round trip ${s.clockRttMs} ms',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.session, required this.seekable});
  final SessionCoordinator session;
  final bool seekable;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragValue;

  static String _format(int ms) {
    final total = ms ~/ 1000;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final duration = s.roomTrack?.durationMs ?? s.playback.durationMs ?? 0;
    return StreamBuilder<Duration>(
      stream: s.playback.positionStream,
      builder: (context, snapshot) {
        final position = (snapshot.data?.inMilliseconds ?? 0).clamp(0, duration > 0 ? duration : 0);
        final value = _dragValue ?? position.toDouble();
        return Column(
          children: [
            Slider(
              max: duration > 0 ? duration.toDouble() : 1,
              value: duration > 0 ? value.clamp(0, duration.toDouble()) : 0,
              onChanged: widget.seekable && duration > 0 ? (v) => setState(() => _dragValue = v) : null,
              onChangeEnd: widget.seekable
                  ? (v) {
                      s.hostSeek(v.round());
                      setState(() => _dragValue = null);
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(_format(value.round())), Text(_format(duration))],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DuckingCard extends StatelessWidget {
  const _DuckingCard();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.ducking, scope.voice, settings]),
      builder: (context, _) {
        final ducking = scope.ducking;
        final voice = scope.voice;
        final (label, color) = switch (ducking.state) {
          DuckState.normal => ('Full volume', Colors.green),
          DuckState.ducking => ('Lowering for speech…', Colors.amber.shade800),
          DuckState.ducked => ('Ducked for speech', Colors.amber.shade800),
          DuckState.restoring => ('Restoring volume…', Colors.blue),
        };
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Lower music when someone talks'),
                value: settings.duckingEnabled,
                onChanged: (v) => settings.duckingEnabled = v,
              ),
              SwitchListTile(
                title: const Text('Group ducking'),
                subtitle: const Text('Duck every phone when anyone in the room speaks'),
                value: settings.groupDucking,
                onChanged: settings.duckingEnabled ? (v) => settings.groupDucking = v : null,
              ),
              ListTile(
                leading: Icon(
                  voice.active ? (voice.speaking ? Icons.mic : Icons.mic_none) : Icons.mic_off,
                  color: voice.active ? Colors.red : null,
                ),
                title: Text(voice.active ? 'Voice detection is on' : 'Voice detection is off'),
                subtitle: voice.active
                    ? LinearProgressIndicator(value: voice.level, minHeight: 6)
                    : const Text('No microphone audio is being processed'),
                trailing: StatusChip(
                  label: '$label · ${(ducking.multiplier * 100).round()}%',
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
