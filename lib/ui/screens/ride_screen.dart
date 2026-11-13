import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../services/ride/ride_controller.dart';
import '../theme.dart';
import '../widgets/app_page.dart';

/// One phone, two headsets: shared music from any app plus a phone-mic intercom.
class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Bluetooth settings or the music app: re-check headsets.
    if (state == AppLifecycleState.resumed) AppScope.of(context).ride.refreshOutputs();
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _toggle(RideController ride) async {
    if (ride.running) {
      await ride.stop();
      return;
    }
    if (AppScope.of(context).session.inSession) {
      return _show('Leave the music room first. Both features need the microphone.');
    }
    final problem = await ride.start();
    if (problem != null && mounted) _show(problem);
  }

  Future<void> _openMusic(RideController ride, String package, String name) async {
    if (!await ride.launchApp(package) && mounted) _show('$name is not installed on this phone.');
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final ride = scope.ride;
    final settings = scope.settings;

    return ListenableBuilder(
      listenable: Listenable.merge([ride, settings]),
      builder: (context, _) => AppPage(
        title: 'Ride mode',
        subtitle: switch (ride.wirelessHeadsets) {
          0 => ride.hasHeadphones ? 'Wired headphones connected' : 'No headsets connected',
          1 => '1 Bluetooth headset connected',
          final n => '$n Bluetooth headsets connected',
        },
        actions: [
          CircleIconButton(icon: Icons.refresh, tooltip: 'Refresh headsets', onTap: ride.refreshOutputs),
          const SizedBox(width: 8),
          CircleIconButton(icon: Icons.bluetooth, tooltip: 'Bluetooth settings', onTap: ride.openBluetoothSettings),
        ],
        children: [
          _TalkCard(ride: ride, onToggle: () => _toggle(ride)),
          SectionTitle(
            'Who hears the voice',
            trailing: ride.outputs.length >= 2
                ? TextButton.icon(
                    onPressed: ride.swapListener,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Swap'),
                  )
                : null,
          ),
          _VoiceRouting(ride: ride),
          const SectionTitle('Music'),
          _MusicCard(
            onSpotify: () => _openMusic(ride, RideController.spotifyPackage, 'Spotify'),
            onYoutube: () => _openMusic(ride, RideController.youtubeMusicPackage, 'YouTube Music'),
          ),
          const SectionTitle('Tuning'),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Lower music while talking', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: settings.rideDuckMusic,
                  onChanged: (v) => settings.rideDuckMusic = v,
                ),
                _Slider(
                  title: 'Voice volume',
                  label: '${settings.rideVoiceGain.toStringAsFixed(1)}×',
                  value: settings.rideVoiceGain,
                  min: 0.5,
                  max: 6,
                  onChanged: (v) => settings.rideVoiceGain = v,
                ),
                _Slider(
                  title: 'Voice sensitivity',
                  label: switch (settings.rideSensitivity) {
                    < 0.34 => 'Low (better in wind/traffic)',
                    < 0.67 => 'Medium',
                    _ => 'High (quiet voices)',
                  },
                  value: settings.rideSensitivity,
                  min: 0,
                  max: 1,
                  onChanged: (v) => settings.rideSensitivity = v,
                ),
                _Slider(
                  title: 'Music returns after',
                  label: '${(settings.rideMusicReturnDelayMs / 1000).toStringAsFixed(1)} s of silence',
                  value: settings.rideMusicReturnDelayMs.toDouble(),
                  min: 500,
                  max: 4000,
                  divisions: 14,
                  onChanged: (v) => settings.rideMusicReturnDelayMs = v.round(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Tips: the phone mic hears whoever is closest, so the person holding the phone (or with it in a chest '
              'pocket) is the talker. Headset mics are not used because they switch the headset to call mode and stop '
              'the music. Microphone audio is never recorded or sent anywhere.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TalkCard extends StatelessWidget {
  const _TalkCard({required this.ride, required this.onToggle});

  final RideController ride;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = ride.running && ride.speaking;
    final ring = !ride.running
        ? const Color(0xFFE6E6F0)
        : active
            ? AppColors.green
            : AppColors.lavender;
    final grow = ride.running ? ride.level * 36 : 0.0;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          SizedBox(
            height: 170,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 120 + grow,
                height: 120 + grow,
                decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
                child: Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ride.running ? AppColors.ink : Colors.white,
                      border: Border.all(color: AppColors.ink, width: 2),
                    ),
                    child: Icon(
                      active ? Icons.record_voice_over : (ride.running ? Icons.mic : Icons.mic_none),
                      size: 42,
                      color: ride.running ? Colors.white : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            !ride.running
                ? 'Intercom off'
                : active
                    ? 'Talking…'
                    : 'Listening',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            !ride.running
                ? 'Talk near the phone. Your partner hears you and the music softens.'
                : ride.ducking
                    ? 'Music lowered'
                    : 'Music at full volume',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ride.running ? AppColors.danger : AppColors.ink,
              ),
              onPressed: ride.starting ? null : onToggle,
              icon: Icon(ride.running ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(ride.running ? 'Stop intercom' : 'Start intercom'),
            ),
          ),
          if (ride.error != null && !ride.running) ...[
            const SizedBox(height: 10),
            Text(ride.error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }
}

class _VoiceRouting extends StatelessWidget {
  const _VoiceRouting({required this.ride});

  final RideController ride;

  @override
  Widget build(BuildContext context) {
    if (ride.outputs.isEmpty) {
      return const SoftCard(
        color: AppColors.yellow,
        child: Text(
          'Connect both Bluetooth headsets to this phone, then turn on Dual Audio: '
          'Quick Settings → Media output → tick both headsets.',
        ),
      );
    }
    final listener = ride.listener;
    final routeFailed = ride.running && listener != null && ride.voiceRoute == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'Tap the headset of the person who is NOT holding the phone. Only they hear the voice, '
            'so the talker doesn\'t hear an echo of themselves.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        for (final (i, o) in ride.outputs.indexed)
          _HeadsetTile(
            output: o,
            color: const [AppColors.blue, AppColors.purple, AppColors.orange][i % 3],
            hearsVoice: listener == null || listener.address == o.address,
            selected: listener?.address == o.address,
            onTap: () => ride.setListener(o),
          ),
        if (ride.outputs.length > 1)
          _ChoiceTile(
            selected: listener == null,
            title: 'Both headsets',
            subtitle: 'Everyone hears the voice, including the person talking',
            onTap: () => ride.setListener(null),
          ),
        if (ride.wirelessHeadsets == 1)
          const _Note(
            color: AppColors.lavender,
            text: 'Only one Bluetooth headset is connected. Connect the second one for your partner.',
          ),
        if (ride.hearsOwnVoice)
          const _Note(color: AppColors.yellow, text: 'The person talking will hear themselves. Pick one headset above.'),
        if (routeFailed)
          const _Note(
            color: AppColors.pink,
            text: "This phone didn't allow sending the voice to just one headset, so both hear it. "
                'Try turning Dual Audio off and on, then restart the intercom.',
          ),
      ],
    );
  }
}

class _HeadsetTile extends StatelessWidget {
  const _HeadsetTile({
    required this.output,
    required this.color,
    required this.hearsVoice,
    required this.selected,
    required this.onTap,
  });

  final AudioOutput output;
  final Color color;
  final bool hearsVoice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: selected ? AppColors.ink : Colors.transparent, width: 2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
                    child: Icon(output.isWireless ? Icons.headphones : Icons.headset, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(output.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 4),
                        hearsVoice
                            ? const Tag('Hears the voice', color: AppColors.green)
                            : const Tag('Talker · no echo'),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? AppColors.ink : AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.selected, required this.title, required this.subtitle, required this.onTap});

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: selected ? AppColors.ink : Colors.transparent, width: 2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.groups, color: AppColors.ink),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? AppColors.ink : AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(color: color, padding: const EdgeInsets.all(14), child: Text(text)),
      );
}

class _MusicCard extends StatelessWidget {
  const _MusicCard({required this.onSpotify, required this.onYoutube});

  final VoidCallback onSpotify;
  final VoidCallback onYoutube;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: FeatureCard(
              color: AppColors.green,
              foreground: AppColors.ink,
              icon: Icons.music_note,
              height: 130,
              title: 'Spotify',
              subtitle: 'Open and play',
              onTap: onSpotify,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FeatureCard(
              color: AppColors.pink,
              foreground: AppColors.ink,
              icon: Icons.play_circle_fill,
              height: 130,
              title: 'YouTube Music',
              subtitle: 'Open and play',
              onTap: onYoutube,
            ),
          ),
        ],
      );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.title,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String title;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
            Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          ],
        ),
      );
}
