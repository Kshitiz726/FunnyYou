import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A frosted panel: real blur of whatever sits behind it, a translucent fill
/// and a one-pixel highlight along the top edge.
///
/// The highlight is what sells the effect — without it a blurred panel on a
/// black background just reads as a slightly lighter rectangle.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.blur = 22,
    this.opacity = 0.55,
    this.border = true,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double blur;

  /// How solid the fill is. Text has to stay readable over artwork, so this
  /// runs heavier than a typical glass effect.
  final double opacity;
  final bool border;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.lg);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.surfaceAlt.withValues(alpha: opacity + 0.08),
                AppColors.surface.withValues(alpha: opacity),
              ],
            ),
            border: border
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.09),
                    width: 1,
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
