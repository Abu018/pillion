import 'package:flutter/widgets.dart';

import '../services/ducking_controller.dart';
import '../services/permissions_service.dart';
import '../services/ride/ride_controller.dart';
import '../services/session_coordinator.dart';
import '../services/settings_service.dart';
import '../services/track_service.dart';
import '../services/voice/voice_activity_service.dart';

/// Makes the app's services available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.tracks,
    required this.voice,
    required this.ducking,
    required this.permissions,
    required this.session,
    required this.ride,
    required super.child,
  });

  final RideController ride;

  final SettingsService settings;
  final TrackService tracks;
  final VoiceActivityService voice;
  final DuckingController ducking;
  final PermissionsService permissions;
  final SessionCoordinator session;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
