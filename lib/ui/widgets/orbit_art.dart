import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Glowing centre with icons orbiting on two rings (welcome screen art).
class OrbitArt extends StatefulWidget {
  const OrbitArt({super.key, this.size = 300});

  final double size;

  @override
  State<OrbitArt> createState() => _OrbitArtState();
}

class _OrbitArtState extends State<OrbitArt> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();

  static const _inner = [
    (Icons.headphones, AppColors.pink),
    (Icons.music_note, AppColors.green),
    (Icons.two_wheeler, AppColors.yellow),
  ];
  static const _outer = [
    (Icons.graphic_eq, AppColors.blue),
    (Icons.record_voice_over, AppColors.orange),
    (Icons.bluetooth_audio, AppColors.purple),
    (Icons.favorite, AppColors.pink),
    (Icons.queue_music, AppColors.green),
  ];

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox.square(
      dimension: size,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          final t = _spin.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(size: Size.square(size), painter: _RingsPainter()),
              Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.inkSoft,
                  border: Border.all(color: AppColors.orange.withValues(alpha: 0.6), width: 2),
                  boxShadow: [
                    BoxShadow(color: AppColors.orange.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: 4),
                  ],
                ),
                child: Icon(Icons.bolt, size: size * 0.15, color: AppColors.orange),
              ),
              ..._place(_inner, size * 0.29, t, size),
              ..._place(_outer, size * 0.46, -t * 0.7, size),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _place(List<(IconData, Color)> items, double radius, double phase, double size) {
    final bubble = size * 0.13;
    return [
      for (var i = 0; i < items.length; i++)
        Transform.translate(
          offset: Offset(
            radius * math.cos(phase + i * 2 * math.pi / items.length),
            radius * math.sin(phase + i * 2 * math.pi / items.length),
          ),
          child: Container(
            width: bubble,
            height: bubble,
            decoration: BoxDecoration(shape: BoxShape.circle, color: items[i].$2),
            child: Icon(items[i].$1, size: bubble * 0.55, color: AppColors.ink),
          ),
        ),
    ];
  }
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawCircle(center, size.width * 0.29, paint);
    canvas.drawCircle(center, size.width * 0.46, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
