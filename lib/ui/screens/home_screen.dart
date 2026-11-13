import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../theme.dart';
import '../widgets/app_page.dart';
import 'create_room_screen.dart';
import 'discover_rooms_screen.dart';
import 'room_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenRide});

  final VoidCallback onOpenRide;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final session = scope.session;
    final ride = scope.ride;

    return ListenableBuilder(
      listenable: Listenable.merge([session, ride, scope.settings]),
      builder: (context, _) {
        final roomsLocked = session.inSession || ride.running;
        return AppPage(
          leading: Avatar(scope.settings.displayName),
          title: scope.settings.displayName,
          subtitle: ride.running ? 'Intercom is on' : 'Ready to ride?',
          children: [
            if (session.inSession) ...[
              SoftCard(
                color: AppColors.green,
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  leading: const Icon(Icons.music_note, color: AppColors.ink),
                  title: Text('In room: ${session.roomName ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Tap to return'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RoomScreen())),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FeatureCard(
              color: AppColors.orange,
              icon: Icons.two_wheeler,
              height: 180,
              title: 'Ride mode',
              subtitle: ride.running
                  ? (ride.speaking ? 'Talking… music lowered' : 'Intercom on · listening')
                  : 'Two headsets, one phone.\nSpotify + talk to each other.',
              onTap: onOpenRide,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    color: AppColors.lavender,
                    icon: Icons.headphones,
                    value: '${ride.wirelessHeadsets}',
                    label: ride.wirelessHeadsets == 1 ? 'headset' : 'headsets',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    color: ride.running ? AppColors.green : Colors.white,
                    icon: ride.running ? Icons.mic : Icons.mic_off,
                    value: ride.running ? 'On' : 'Off',
                    label: 'intercom',
                  ),
                ),
              ],
            ),
            const SectionTitle('Getting started'),
            const _Step(
              color: AppColors.lavender,
              icon: Icons.bluetooth,
              title: 'Connect both headsets',
              body: 'Pair your two Bluetooth headsets to this phone.',
            ),
            const _Step(
              color: AppColors.pink,
              icon: Icons.speaker_group,
              title: 'Turn on Dual Audio',
              body: 'Quick Settings → Media output → tick both headsets.',
            ),
            const _Step(
              color: AppColors.green,
              icon: Icons.music_note,
              title: 'Play Spotify',
              body: 'Or any music app. Both of you hear the same song.',
            ),
            const _Step(
              color: AppColors.yellow,
              icon: Icons.record_voice_over,
              title: 'Start the intercom',
              body: 'Choose who hears the voice, then just talk.',
            ),
            SectionTitle(
              'Music rooms',
              trailing: Tag(roomsLocked && ride.running ? 'Stop intercom first' : 'Phone to phone'),
            ),
            if (!session.bluetoothOn)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SoftCard(
                  color: AppColors.yellow,
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth_disabled),
                      SizedBox(width: 12),
                      Expanded(child: Text('Bluetooth is off. Turn it on to create or join a room.')),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FeatureCard(
                    color: AppColors.blue,
                    icon: Icons.add_circle,
                    height: 150,
                    title: 'Create',
                    subtitle: 'Host a room',
                    onTap: roomsLocked
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateRoomScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FeatureCard(
                    color: AppColors.purple,
                    icon: Icons.wifi_tethering,
                    height: 150,
                    title: 'Join',
                    subtitle: 'Find nearby rooms',
                    onTap: roomsLocked
                        ? null
                        : () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiscoverRoomsScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Rooms play the same MP3/M4A file in sync on several phones, each with its own headset.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.color, required this.icon, required this.value, required this.label});

  final Color color;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => SoftCard(
        color: color,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: AppColors.ink),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ],
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.color, required this.icon, required this.title, required this.body});

  final Color color;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: AppColors.ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(body, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
