import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft, slowly drifting colour blobs behind the marketing-facing screens.
///
/// Painted rather than shipped as images so it scales to every device size and
/// costs nothing in bundle weight.
class AuroraBackdrop extends StatefulWidget {
  const AuroraBackdrop({
    super.key,
    required this.child,
    this.baseColor = AppColors.lavender,
    this.blobs = const [
      AuroraBlob(color: Color(0x66E11D28), alignment: Alignment(-0.9, -0.85), size: 0.9),
      AuroraBlob(color: Color(0x4DE11D28), alignment: Alignment(1.05, -0.55), size: 0.75),
      AuroraBlob(color: Color(0x40FF4B54), alignment: Alignment(-0.7, 0.95), size: 0.8),
    ],
    this.animate = true,
  });

  final Widget child;
  final Color baseColor;
  final List<AuroraBlob> blobs;
  final bool animate;

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class AuroraBlob {
  const AuroraBlob({
    required this.color,
    required this.alignment,
    required this.size,
  });

  final Color color;
  final Alignment alignment;

  /// Diameter as a fraction of the shortest screen edge.
  final double size;
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.baseColor,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _AuroraPainter(
                    blobs: widget.blobs,
                    t: _controller.value,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.blobs, required this.t});

  final List<AuroraBlob> blobs;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);

    for (var i = 0; i < blobs.length; i++) {
      final blob = blobs[i];
      final phase = t * 2 * math.pi + i * 2.1;
      final drift = Offset(
        math.cos(phase) * shortest * 0.06,
        math.sin(phase * 0.8) * shortest * 0.05,
      );
      final center = blob.alignment.alongSize(size) + drift;
      final radius = shortest * blob.size * 0.6;

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [blob.color, blob.color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.blobs != blobs;
}

/// Entrance animation used to stagger content on screen load.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 22,
    this.duration = AppDuration.slow,
  });

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration + delay,
      curve: Interval(
        delay.inMilliseconds / (duration + delay).inMilliseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - value) * offset),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
