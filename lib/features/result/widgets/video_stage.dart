import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/glass.dart';

/// The video card: the clip, with frosted controls floating over it.
///
/// Controls fade out while it plays and come back on tap, so the thing the
/// user waited two minutes for is not permanently covered by buttons.
class VideoStage extends StatefulWidget {
  const VideoStage({
    super.key,
    required this.controller,
    this.onClose,
    this.onShare,
    this.onMore,
    this.borderRadius,
    this.fullscreen = false,
    this.onToggleFullscreen,
  });

  /// Null until the file has been probed — the stage shows a poster shimmer.
  final VideoPlayerController? controller;

  final VoidCallback? onClose;
  final VoidCallback? onShare;
  final VoidCallback? onMore;
  final BorderRadius? borderRadius;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (widget.controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _tapStage() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _togglePlay() {
    final controller = widget.controller;
    if (controller == null) return;
    HapticFeedback.selectionClick();
    controller.value.isPlaying ? controller.pause() : controller.play();
    _scheduleHide();
  }

  /// Ten seconds is the phone-video convention, and it is a big enough jump to
  /// be worth a tap on a clip this short.
  void _seekBy(int seconds) {
    final controller = widget.controller;
    if (controller == null) return;
    HapticFeedback.selectionClick();
    final target = controller.value.position + Duration(seconds: seconds);
    final end = controller.value.duration;
    controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : (target > end ? end : target),
    );
    _scheduleHide();
  }

  void _toggleMute() {
    final controller = widget.controller;
    if (controller == null) return;
    HapticFeedback.selectionClick();
    final muted = controller.value.volume == 0;
    controller.setVolume(muted ? 1 : 0);
    setState(() {});
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final radius = widget.borderRadius ??
        BorderRadius.circular(widget.fullscreen ? 0 : AppRadius.lg);

    return ClipRRect(
      borderRadius: radius,
      child: GestureDetector(
        onTap: _tapStage,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            if (controller != null && controller.value.isInitialized)
              FittedBox(
                fit: widget.fullscreen ? BoxFit.contain : BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryBright,
                  strokeWidth: 2.5,
                ),
              ),

            // Only under the controls, and only while they are showing —
            // a permanent scrim on top of the render is exactly what the
            // user does not want to look at.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: AppDuration.base,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
            ),

            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: AppDuration.base,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _Controls(
                  controller: controller,
                  fullscreen: widget.fullscreen,
                  onClose: widget.onClose,
                  onShare: widget.onShare,
                  onMore: widget.onMore,
                  onPlayPause: _togglePlay,
                  onBack: () => _seekBy(-10),
                  onForward: () => _seekBy(10),
                  onMute: _toggleMute,
                  onFullscreen: widget.onToggleFullscreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.fullscreen,
    this.onClose,
    this.onShare,
    this.onMore,
    this.onPlayPause,
    this.onBack,
    this.onForward,
    this.onMute,
    this.onFullscreen,
  });

  final VideoPlayerController? controller;
  final bool fullscreen;
  final VoidCallback? onClose;
  final VoidCallback? onShare;
  final VoidCallback? onMore;
  final VoidCallback? onPlayPause;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onMute;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    final value = controller?.value;
    final playing = value?.isPlaying ?? false;
    final muted = (value?.volume ?? 1) == 0;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              if (onClose != null)
                _GlassCircle(
                  icon: fullscreen
                      ? Icons.close_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  onPressed: onClose!,
                ),
              const Spacer(),
              GlassPanel(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                opacity: 0.28,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onShare != null)
                      _BareIcon(
                          icon: Icons.ios_share_rounded, onPressed: onShare!),
                    if (onMore != null)
                      _BareIcon(
                          icon: Icons.more_horiz_rounded, onPressed: onMore!),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _GlassCircle(
                icon: Icons.replay_10_rounded,
                size: 46,
                onPressed: onBack ?? () {},
              ),
              const SizedBox(width: 22),
              _GlassCircle(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 64,
                iconSize: 32,
                onPressed: onPlayPause ?? () {},
              ),
              const SizedBox(width: 22),
              _GlassCircle(
                icon: Icons.forward_10_rounded,
                size: 46,
                onPressed: onForward ?? () {},
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              if (value != null && value.isInitialized)
                Expanded(child: _Timeline(controller: controller!))
              else
                const Spacer(),
              const SizedBox(width: 10),
              GlassPanel(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                opacity: 0.28,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BareIcon(
                      icon: muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onPressed: onMute ?? () {},
                      // The one control that has to read as *state*, not as an
                      // action: silent playback otherwise looks like a broken
                      // render rather than a muted player.
                      tint: muted ? AppColors.primaryBright : Colors.white,
                    ),
                    if (onFullscreen != null)
                      _BareIcon(
                        icon: fullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        onPressed: onFullscreen!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Scrub bar plus elapsed/remaining, sized to sit inside the control row.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.controller});

  final VideoPlayerController controller;

  String _clock(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      opacity: 0.28,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final total = value.duration.inMilliseconds;
          final position = value.position.inMilliseconds.clamp(0, total);
          return Row(
            children: [
              Text(
                _clock(value.position),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: total == 0 ? 0 : position / total,
                    onChanged: (fraction) => controller.seekTo(
                      Duration(milliseconds: (fraction * total).round()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                _clock(value.duration),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({
    required this.icon,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 21,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.9,
      onPressed: onPressed,
      child: GlassPanel(
        borderRadius: BorderRadius.circular(size),
        opacity: 0.28,
        child: SizedBox(
          height: size,
          width: size,
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}

class _BareIcon extends StatelessWidget {
  const _BareIcon({
    required this.icon,
    required this.onPressed,
    this.tint = Colors.white,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.88,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        child: Icon(icon, size: 19, color: tint),
      ),
    );
  }
}

/// Full-screen playback, landscape allowed, system chrome hidden.
class FullscreenPlayer extends StatefulWidget {
  const FullscreenPlayer({super.key, required this.controller});

  final VideoPlayerController controller;

  static Future<void> open(
    BuildContext context,
    VideoPlayerController controller,
  ) =>
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          barrierColor: Colors.black,
          pageBuilder: (_, _, _) => FullscreenPlayer(controller: controller),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: VideoStage(
        controller: widget.controller,
        fullscreen: true,
        borderRadius: BorderRadius.zero,
        onClose: () => Navigator.of(context).maybePop(),
        onToggleFullscreen: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

/// Small status line above the title, mirroring the "LIVE · 8:00 – 9:00 PM"
/// row a video app puts there.
class VideoMetaRow extends StatelessWidget {
  const VideoMetaRow({super.key, required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final seconds = duration?.inSeconds ?? 0;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 11, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                s.readyBadge,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (seconds > 0) ...[
          const SizedBox(width: 10),
          Text('·', style: AppTypography.caption),
          const SizedBox(width: 10),
          Text(s.secondsLong(seconds), style: AppTypography.caption),
        ],
      ],
    );
  }
}
