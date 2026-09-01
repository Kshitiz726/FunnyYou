import 'package:flutter/material.dart';

/// Dims everything outside an oval so the user knows exactly where to put
/// their face. Uses an even-odd path so it is a single cheap draw call.
class FaceGuideOverlay extends StatefulWidget {
  const FaceGuideOverlay({super.key});

  @override
  State<FaceGuideOverlay> createState() => _FaceGuideOverlayState();
}

class _FaceGuideOverlayState extends State<FaceGuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _FaceGuidePainter(pulse: _controller.value),
          ),
        ),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  _FaceGuidePainter({required this.pulse});

  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: size.width * 0.74,
      height: size.width * 0.98,
    );

    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);

    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final alpha = 0.55 + 0.35 * Curves.easeInOut.transform(pulse);
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: alpha),
    );

    // Corner ticks give the guide a deliberate, camera-app feel.
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    const sweep = 0.32;
    for (final start in [-1.9, -1.24, 1.24, 1.9]) {
      canvas.drawArc(oval, start, sweep, false, tick);
    }
  }

  @override
  bool shouldRepaint(_FaceGuidePainter oldDelegate) =>
      oldDelegate.pulse != pulse;
}
