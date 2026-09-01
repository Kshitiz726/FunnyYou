import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A press-scaling wrapper that gives every tappable surface the same iOS feel.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onPressed,
    this.scale = 0.965,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double scale;
  final bool haptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  void _setDown(bool value) {
    if (!_enabled || _down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: _enabled
          ? () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onPressed!.call();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: AppDuration.fast,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _enabled ? 1 : 0.45,
          duration: AppDuration.fast,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The single filled call-to-action used across the whole flow.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.subtitle,
    this.loading = false,
    this.expand = true,
    this.gradient = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? subtitle;
  final bool loading;
  final bool expand;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    final content = loading
        ? const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 21, color: Colors.white),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTypography.button,
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ],
          );

    return PressableScale(
      onPressed: enabled ? onPressed : null,
      child: Container(
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: expand ? 20 : 30,
          vertical: subtitle == null ? 19 : 14,
        ),
        decoration: BoxDecoration(
          gradient: gradient
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE11D28), AppColors.primaryDark],
                )
              : null,
          color: gradient ? null : AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: enabled ? AppShadows.button : null,
        ),
        child: content,
      ),
    );
  }
}

/// Low-emphasis action — used for "Retake", "Maybe later", "Make another".
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.tinted = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onPressed: onPressed,
      child: Container(
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: expand ? 20 : 26,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: tinted ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: tinted
              ? null
              : Border.all(color: AppColors.hairline, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              // Red reads as an accent here; the label itself stays white so
              // the button clears WCAG AA on a near-black fill.
              Icon(icon, size: 20, color: AppColors.primaryBright),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTypography.button.copyWith(
                  color: AppColors.ink,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular icon button used for nav bars and floating controls.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.background = AppColors.surface,
    this.foreground = AppColors.ink,
    this.elevated = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color background;
  final Color foreground;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.9,
      onPressed: onPressed,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          boxShadow: elevated ? AppShadows.card : null,
        ),
        child: Icon(icon, size: size * 0.46, color: foreground),
      ),
    );
  }
}
