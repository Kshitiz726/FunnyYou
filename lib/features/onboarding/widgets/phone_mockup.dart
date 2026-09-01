import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A lightweight iPhone frame used to illustrate each onboarding step.
///
/// Drawn with widgets rather than shipped as PNGs so it stays crisp at every
/// device scale and adds nothing to the bundle.
///
/// **Always laid out at [designWidth].** The scenes inside are composed in
/// absolute pixels — 13pt labels, a 38px shutter, an 84px progress ring — and
/// those numbers are only right at one width. Building the frame narrower does
/// not shrink them with it: the type stays the same size in a smaller phone,
/// captions ellipsise, and the whole thing reads as squashed. So callers never
/// pick a width. They wrap the finished mockup in a `FittedBox` and scale it
/// like a photograph, which keeps every proportion exactly as drawn.
class PhoneMockup extends StatelessWidget {
  const PhoneMockup({
    super.key,
    required this.child,
    this.background = AppColors.surface,
    this.showStatusBar = true,
    this.statusBarDark = false,
  });

  /// The one width every scene is composed against.
  static const double designWidth = 216;

  /// 19.5:9, the proportions of every iPhone since the X. The frame used to be
  /// 2.05, which is squatter than any real handset and was the first thing that
  /// gave the mockup away.
  static const double aspectRatio = 2.165;

  static const double designHeight = designWidth * aspectRatio;

  final Widget child;
  final Color background;
  final bool showStatusBar;
  final bool statusBarDark;

  // Every metric below is a fraction of the width, so the frame stays a true
  // scale model if the design width is ever changed.
  static const double _bezel = designWidth * 0.033;
  static const double _outerRadius = designWidth * 0.20;
  static const double _statusBarHeight = designWidth * 0.125;
  static const double _islandWidth = designWidth * 0.30;
  static const double _islandHeight = designWidth * 0.082;
  static const double _islandTop = designWidth * 0.030;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: designWidth,
      height: designHeight,
      padding: const EdgeInsets.all(_bezel),
      decoration: BoxDecoration(
        // A flat black slab reads as a drawing. Two stops and a hairline
        // highlight down the side read as a machined edge catching the light.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C2C2E), Color(0xFF0E0E0F)],
        ),
        borderRadius: BorderRadius.circular(_outerRadius),
        border: Border.all(color: const Color(0xFF48484A), width: 0.8),
        boxShadow: AppShadows.raised,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_outerRadius - _bezel),
        child: ColoredBox(
          color: background,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: showStatusBar ? _statusBarHeight : 0,
                  ),
                  child: child,
                ),
              ),
              if (showStatusBar)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(height: _statusBarHeight),
                ),
              if (showStatusBar)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _StatusBar(dark: statusBarDark),
                ),
              const Positioned(
                top: _islandTop,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: _islandWidth,
                    height: _islandHeight,
                    // Pure black alone vanishes on the dark scenes — the
                    // island was visible on two of the four cards and gone on
                    // the other two, which reads as a rendering bug. The
                    // hairline gives it an edge to catch on any background.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF000000),
                        borderRadius: BorderRadius.all(
                          Radius.circular(_islandHeight),
                        ),
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0x24FFFFFF), width: 0.7),
                        ),
                      ),
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
      padding: const EdgeInsets.fromLTRB(15, 7, 15, 0),
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
