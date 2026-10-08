import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/i18n/strings.dart';
import '../../core/i18n/template_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/templates.dart';

/// The scenario's own clip, with the face blacked out and locked.
///
/// This is what the client asked for: "show the preview of the video without
/// their face ... blacked out with a locked icon over the face".
///
/// The important part is what this screen does *not* do. It plays a fixed file
/// that ships with the app, identical for every user. Nothing is generated,
/// nothing is queued, nothing is paid for. Someone browsing twenty scenarios
/// costs exactly as much as someone browsing none, which is what makes
/// browsing free to offer.
///
/// Pops with the template when the user commits, or null if they back out, so
/// it slots in front of the existing pick-then-generate flow without changing
/// what the caller receives.
class ScenarioPreviewScreen extends StatefulWidget {
  const ScenarioPreviewScreen({super.key, required this.template});

  final VideoTemplate template;

  @override
  State<ScenarioPreviewScreen> createState() => _ScenarioPreviewScreenState();
}

class _ScenarioPreviewScreenState extends State<ScenarioPreviewScreen> {
  VideoPlayerController? _controller;

  /// Null while loading, false once we know there is no clip for this id.
  /// A scenario without a preview still has to be pickable, so this falls
  /// back to the poster frame rather than blocking the screen.
  bool? _ready;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller =
        VideoPlayerController.asset(widget.template.lockedPreviewPath);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // Muted and looping: this is wallpaper for a decision, not something to
      // sit through. Sound would also fight the ad that ran moments ago.
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (error) {
      debugPrint('ScenarioPreview: no clip for ${widget.template.id} ($error)');
      await controller.dispose();
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _commit() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(widget.template);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final template = widget.template;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.ink,
          title: Text(s.previewTitle, style: AppTypography.headline),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Stage(template: template, controller: _controller, ready: _ready)),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  template.titleIn(s),
                  style: AppTypography.title,
                  textAlign: TextAlign.center,
                ),
                if (template.taglineIn(s) case final tagline?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    tagline,
                    style: AppTypography.body.copyWith(color: AppColors.inkSoft),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_rounded,
                        size: 18, color: AppColors.inkMuted),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        s.previewLockedNote,
                        style: AppTypography.label
                            .copyWith(color: AppColors.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(label: s.previewMakeMine, onPressed: _commit),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: s.previewPickAnother,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The clip itself, or the poster frame if there is no clip to play.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.template,
    required this.controller,
    required this.ready,
  });

  final VideoTemplate template;
  final VideoPlayerController? controller;
  final bool? ready;

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ColoredBox(
        color: AppColors.surface,
        child: Center(
          child: switch (ready) {
            true when controller != null => AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller!),
              ),
            // No clip: the poster frame still shows the scene, and it is
            // already the image the tile used, so nothing looks broken.
            false => Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(template.assetPath, fit: BoxFit.cover),
                  Container(color: Colors.black54),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded,
                            size: 44, color: AppColors.ink),
                        const SizedBox(height: AppSpacing.sm),
                        Text(s.previewUnavailable,
                            style: AppTypography.label
                                .copyWith(color: AppColors.inkSoft)),
                      ],
                    ),
                  ),
                ],
              ),
            _ => const CircularProgressIndicator(color: AppColors.primary),
          },
        ),
      ),
    );
  }
}
