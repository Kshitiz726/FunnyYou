import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import 'phone_mockup.dart';

/// Step 1 — the camera screen, mid-capture.
class CaptureScene extends StatelessWidget {
  const CaptureScene({super.key});

  @override
  Widget build(BuildContext context) {
    return PhoneMockup(
      background: const Color(0xFF0A0A0A),
      statusBarDark: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned.fill(
                    child: MockPortrait(
                      gradient: [Color(0xFF3F3352), Color(0xFF8C8C8C)],
                      icon: Icons.person_rounded,
                      iconSize: 56,
                      radius: 18,
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: _FaceGuidePainter()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniLabel(context.s.retake, color: Colors.white70),
                ),
                Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 3,
                    ),
                  ),
                ),
                Expanded(
                  child: _MiniLabel(
                    context.s.continueLabel,
                    color: Colors.white,
                    align: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.62,
      height: size.height * 0.42,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.85);

    final path = Path()..addOval(rect);
    // Dashed oval reads as a "line your face up here" guide.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + 8),
          paint,
        );
        distance += 15;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Step 2 — the scenario grid with one card selected.
class PickScene extends StatelessWidget {
  const PickScene({super.key});

  static const _tiles = <(IconData, List<Color>)>[
    (Icons.rocket_launch_rounded, [Color(0xFF1E3A8A), Color(0xFFB3141D)]),
    (Icons.music_note_rounded, [Color(0xFF831843), Color(0xFFFF4B54)]),
    (Icons.bolt_rounded, [Color(0xFF2563EB), Color(0xFFE11D28)]),
    (Icons.restaurant_rounded, [Color(0xFFEA580C), Color(0xFFFFFFFF)]),
    (Icons.workspace_premium_rounded, [Color(0xFF7C2D12), Color(0xFFFF4B54)]),
    (Icons.beach_access_rounded, [Color(0xFF0891B2), Color(0xFFFF4B54)]),
  ];

  @override
  Widget build(BuildContext context) {
    return PhoneMockup(
      background: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.s.pickYourFavourite,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tiles.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.86,
                ),
                itemBuilder: (context, index) {
                  final (icon, colors) = _tiles[index];
                  final selected = index == 2;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: MockPortrait(
                          gradient: colors,
                          icon: icon,
                          iconSize: 26,
                          radius: 12,
                        ),
                      ),
                      if (selected)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      if (selected)
                        const Positioned(
                          top: 5,
                          right: 5,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: AppColors.primary,
                            child: Icon(Icons.check_rounded,
                                size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  );
                },
            ),
            const Spacer(),
            _MockButton(
              label: context.s.continueLabel,
              icon: Icons.arrow_forward_rounded,
              filled: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 3 — the render screen with a live progress ring.
class RenderScene extends StatefulWidget {
  const RenderScene({super.key});

  @override
  State<RenderScene> createState() => _RenderSceneState();
}

class _RenderSceneState extends State<RenderScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PhoneMockup(
      background: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 84,
              width: 84,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(84),
                      painter: _RingPainter(progress: _controller.value),
                    ),
                    const Icon(Icons.movie_creation_rounded,
                        size: 30, color: AppColors.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.s.makingYourVideo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.s.aboutTwoMinutes,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = AppColors.primaryTint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 + progress * 2 * math.pi,
      math.pi * 1.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [AppColors.primary, Color(0xFFFF4B54), AppColors.primary],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Step 4 — the finished video, ready to watch and share.
class ShareScene extends StatelessWidget {
  const ShareScene({super.key});

  @override
  Widget build(BuildContext context) {
    return PhoneMockup(
      background: const Color(0xFF0A0A0A),
      statusBarDark: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: MockPortrait(
                      gradient: [Color(0xFF2563EB), Color(0xFFE11D28)],
                      icon: Icons.bolt_rounded,
                      iconSize: 52,
                      radius: 16,
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Row(
                      children: [
                        const Icon(Icons.pause_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: 0.35,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _MockButton(
              label: context.s.shareVideo,
              icon: Icons.ios_share_rounded,
              filled: true,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _MockButton(
                    label: context.s.save,
                    icon: Icons.download_rounded,
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: _MockButton(
                    label: context.s.makeAnother,
                    icon: Icons.add_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MockButton extends StatelessWidget {
  const _MockButton({
    required this.label,
    required this.icon,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(
    this.text, {
    required this.color,
    this.align = TextAlign.left,
  });

  final String text;
  final Color color;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      );
}
