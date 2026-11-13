import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'services/audio_playback_service.dart';
import 'services/ducking_controller.dart';
import 'services/permissions_service.dart';
import 'services/ride/ride_controller.dart';
import 'services/session_coordinator.dart';
import 'services/settings_service.dart';
import 'services/track_service.dart';
import 'services/voice/voice_activity_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await SettingsService.load();
  final tracks = await TrackService.load();
  final voice = VoiceActivityService();
  final ducking = DuckingController();
  final permissions = PermissionsService();
  final session = SessionCoordinator(
    settings: settings,
    tracks: tracks,
    playback: AudioPlaybackService(),
    voice: voice,
    ducking: ducking,
    permissions: permissions,
  )..init();

  runApp(AppScope(
    settings: settings,
    tracks: tracks,
    voice: voice,
    ducking: ducking,
    permissions: permissions,
    session: session,
    ride: RideController(settings: settings, permissions: permissions),
    child: const PillionApp(),
  ));
}
