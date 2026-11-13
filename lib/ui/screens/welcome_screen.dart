import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../theme.dart';
import '../widgets/orbit_art.dart';
import 'main_shell.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController();
  bool _askName = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_askName) {
      setState(() => _askName = true);
      return;
    }
    final settings = AppScope.of(context).settings;
    if (_name.text.trim().isNotEmpty) settings.displayName = _name.text;
    settings.onboarded = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  OrbitArt(size: (width - 40).clamp(220, 340)),
                  const SizedBox(height: 8),
                  const Text('Pillion', style: TextStyle(color: AppColors.muted, letterSpacing: 1.2)),
                  const SizedBox(height: 28),
                  const Text(
                    'Ride together,\nhear together',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 32, height: 1.15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'One phone, two headsets. Share your Spotify songs and talk to each other '
                    'on the bike. The music softens when one of you speaks.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    child: _askName
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextField(
                              controller: _name,
                              autofocus: true,
                              maxLength: 20,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _continue(),
                              decoration: const InputDecoration(
                                hintText: 'Your name',
                                counterStyle: TextStyle(color: AppColors.muted),
                              ),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        minimumSize: const Size.fromHeight(58),
                      ),
                      onPressed: _continue,
                      child: Text(_askName ? 'Continue' : 'Get Started'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Microphone audio stays on this phone. Nothing is recorded.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
