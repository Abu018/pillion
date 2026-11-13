import 'package:flutter/material.dart';

import '../ui/screens/main_shell.dart';
import '../ui/screens/welcome_screen.dart';
import '../ui/theme.dart';
import 'app_scope.dart';

class PillionApp extends StatelessWidget {
  const PillionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return MaterialApp(
      title: 'Pillion',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeMode: ThemeMode.light,
      home: settings.onboarded ? const MainShell() : const WelcomeScreen(),
    );
  }
}
