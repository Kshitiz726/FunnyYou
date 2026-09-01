import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A lightweight iPhone frame used to illustrate each onboarding step.
///
/// Drawn with widgets rather than shipped as PNGs so it stays crisp at every
/// device scale and adds nothing to the bundle.
class PhoneMockup extends StatelessWidget {
  const PhoneMockup({
    super.key,
    required this.child,
    this.background = AppColors.surface,
    this.width = 216,
    this.showStatusBar = true,
    this.statusBarDark = false,
  });

  final Widget child;
  final Color background;
  final double width;
  final bool showStatusBar;
  final bool statusBarDark;

  @override
  Widget build(BuildContext context) {
    final height = width * 2.05;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(width * 0.19),
        boxShadow: AppShadows.raised,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.155),
        child: ColoredBox(
          color: background,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(top: showStatusBar ? 26 : 0),
                  child: child,
                ),
              ),
              if (showStatusBar)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _StatusBar(dark: statusBarDark),
                ),
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: width * 0.26,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '9:41',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Row(
            children: [
              Icon(Icons.signal_cellular_alt_rounded, size: 11, color: color),
              const SizedBox(width: 3),
              Icon(Icons.wifi_rounded, size: 11, color: color),
              const SizedBox(width: 3),
              Icon(Icons.battery_full_rounded, size: 12, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rounded placeholder that stands in for a person's photo inside a mockup.
class MockPortrait extends StatelessWidget {
  const MockPortrait({
    super.key,
    required this.gradient,
    this.icon = Icons.person_rounded,
    this.radius = 14,
    this.iconSize = 30,
  });

  final List<Color> gradient;
  final IconData icon;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: Colors.white.withValues(alpha: 0.94),
        ),
      ),
    );
  }
}
