import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../services/permissions_service.dart';
import '../theme.dart';
import '../widgets/app_page.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => AppPage(
        title: 'Settings',
        subtitle: 'Ride mode has its own controls on the Ride tab',
        children: [
          SoftCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              leading: Avatar(settings.displayName, size: 40),
              title: const Text('Display name', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(settings.displayName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editName(context),
            ),
          ),
          const SectionTitle('Rooms · voice ducking'),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.record_voice_over),
                  title: const Text('Lower music when someone talks'),
                  subtitle: const Text('Uses the microphone on this phone only'),
                  value: settings.duckingEnabled,
                  onChanged: (v) => settings.duckingEnabled = v,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.groups),
                  title: const Text('Group ducking'),
                  subtitle: const Text(
                    'Share "someone is talking" (never audio) with the room and duck when others talk. '
                    'May duck on background conversations.',
                  ),
                  value: settings.groupDucking,
                  onChanged: settings.duckingEnabled ? (v) => settings.groupDucking = v : null,
                ),
                _SliderTile(
                  title: 'Ducked volume',
                  valueLabel: '${(settings.duckLevel * 100).round()}% of your volume',
                  value: settings.duckLevel,
                  min: 0.05,
                  max: 0.8,
                  onChanged: (v) => settings.duckLevel = v,
                ),
                _SliderTile(
                  title: 'Wait before restoring',
                  valueLabel: '${settings.releaseDelayMs} ms of silence',
                  value: settings.releaseDelayMs.toDouble(),
                  min: 300,
                  max: 3000,
                  divisions: 27,
                  onChanged: (v) => settings.releaseDelayMs = v.round(),
                ),
                _SliderTile(
                  title: 'Restore duration',
                  valueLabel: '${settings.restoreRampMs} ms fade back',
                  value: settings.restoreRampMs.toDouble(),
                  min: 200,
                  max: 2000,
                  divisions: 18,
                  onChanged: (v) => settings.restoreRampMs = v.round(),
                ),
                _SliderTile(
                  title: 'Voice sensitivity',
                  valueLabel: switch (settings.vadSensitivity) {
                    < 0.34 => 'Low (only clear, loud speech)',
                    < 0.67 => 'Medium',
                    _ => 'High (reacts to quiet speech)',
                  },
                  value: settings.vadSensitivity,
                  min: 0,
                  max: 1,
                  onChanged: (v) => settings.vadSensitivity = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _MicTest(),
          const SectionTitle('Rooms · sync & connection'),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _SliderTile(
                  title: 'Drift correction threshold',
                  valueLabel: '${settings.syncThresholdMs} ms',
                  value: settings.syncThresholdMs.toDouble(),
                  min: 50,
                  max: 300,
                  divisions: 25,
                  onChanged: (v) => settings.syncThresholdMs = v.round(),
                ),
                _SliderTile(
                  title: 'Reconnect for',
                  valueLabel: '${settings.reconnectWindowSec} s after losing the host',
                  value: settings.reconnectWindowSec.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 11,
                  onChanged: (v) => settings.reconnectWindowSec = v.round(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('Pillion · open source (MIT)', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context) async {
    final settings = AppScope.of(context).settings;
    final controller = TextEditingController(text: settings.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(controller: controller, maxLength: 20, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name != null) settings.displayName = name;
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valueLabel),
        Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
      ],
    ),
  );
}

class _MicTest extends StatefulWidget {
  const _MicTest();

  @override
  State<_MicTest> createState() => _MicTestState();
}

class _MicTestState extends State<_MicTest> {
  final Object _owner = Object();
  bool _testing = false;
  late final _voice = AppScope.of(context).voice;

  Future<void> _toggle() async {
    if (_testing) {
      await _voice.release(_owner);
      setState(() => _testing = false);
      return;
    }
    final outcome = await AppScope.of(context).permissions.requestMicrophone();
    if (!mounted) return;
    if (outcome != PermissionOutcome.granted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Microphone permission is required for the test.')));
      return;
    }
    final ok = await _voice.acquire(_owner);
    if (mounted) setState(() => _testing = ok);
  }

  @override
  void dispose() {
    if (_testing) _voice.release(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = AppScope.of(context).voice;
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Microphone test', style: Theme.of(context).textTheme.titleMedium)),
                  FilledButton.tonal(onPressed: _toggle, child: Text(_testing ? 'Stop' : 'Start')),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Talk near the phone. The indicator lights up when speech is detected. Audio is not saved.'),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: voice.active ? voice.level : 0, minHeight: 10),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    voice.speaking ? Icons.record_voice_over : Icons.voice_over_off,
                    color: voice.speaking ? Colors.green : Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    !voice.active
                        ? 'Not listening'
                        : voice.speaking
                        ? 'Speech detected'
                        : 'Listening… (noise floor ${voice.noiseFloorDb.round()} dB)',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
