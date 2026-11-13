import 'package:flutter/material.dart';

import '../theme.dart';

/// Dark header with a rounded light sheet underneath, used by the main screens.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    required this.children,
    this.bottomPadding = 110,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final List<Widget> children;

  /// Extra space at the end of the list, e.g. to clear a floating nav bar.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
              child: Row(
                children: [
                  if (canPop)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: CircleIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    )
                  else if (leading != null)
                    Padding(padding: const EdgeInsets.only(right: 12), child: leading),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        if (subtitle != null)
                          Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                child: ColoredBox(
                  color: AppColors.sheet,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: AppColors.inkSoft,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: Colors.white, size: 22)),
          ),
        ),
      );
}

/// Initial-letter avatar on a pastel circle.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
      child: Text(letter, style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.42, color: AppColors.ink)),
    );
  }
}

/// White rounded card with consistent padding.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: Padding(padding: padding, child: child),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            ?trailing,
          ],
        ),
      );
}

/// Small rounded label, e.g. "Step 1".
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = AppColors.lavender, this.textColor = AppColors.ink});

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
      );
}

/// Big colourful card in the style of the featured-course tiles.
class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.foreground = Colors.white,
    this.height = 170,
  });

  final Color color;
  final Color foreground;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned(
                    right: -18,
                    bottom: -18,
                    child: Icon(icon, size: height * 0.72, color: foreground.withValues(alpha: 0.22)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(color: foreground, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(subtitle, style: TextStyle(color: foreground.withValues(alpha: 0.85), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
