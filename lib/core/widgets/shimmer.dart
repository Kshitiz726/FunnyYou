import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A light sweeping across a placeholder, the way a loading tile should look.
///
/// Used instead of a spinner on the preview tiles: a spinner says "something is
/// happening somewhere", a shimmer on the tile itself says "*this* picture is
/// coming", which is the thing the user is actually waiting for.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          // Travels from fully off one edge to fully off the other, so the
          // highlight never pops in or out mid-tile.
          final slide = _controller.value * 3 - 1;
          return LinearGradient(
            begin: Alignment(slide - 0.6, -0.4),
            end: Alignment(slide + 0.6, 0.4),
            colors: const [
              Colors.transparent,
              AppColors.shimmerHighlight,
              Colors.transparent,
            ],
            stops: const [0, 0.5, 1],
          ).createShader(bounds);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}
