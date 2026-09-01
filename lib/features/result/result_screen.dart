import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/i18n/strings.dart';
import '../../core/i18n/template_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../data/models.dart';
import '../../data/templates.dart';
import '../../state/app_state.dart';
import '../templates/widgets/template_tile.dart';
import 'widgets/video_stage.dart';

/// "Your video is ready" — playback plus the three things people actually do:
/// share it, save it, make another.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.creation});

  final Creation creation;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  VideoPlayerController? _controller;
  bool _saving = false;
  bool _saved = false;

  bool get _hasVideo => (widget.creation.videoPath ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_hasVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final controller =
        VideoPlayerController.file(File(widget.creation.videoPath!));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      // Explicit, not assumed: the template clips carry their own audio and
      // the whole point of the render is hearing it. A player that starts
      // silent reads as a broken render.
      await controller.setVolume(1);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  final _shareButtonKey = GlobalKey();

  /// Where the iPad popover points. Falls back to the screen centre if the
  /// button has not been laid out, which is better than passing null.
  Rect _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final size = MediaQuery.of(context).size;
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 1,
      height: 1,
    );
  }

  Future<void> _share() async {
    HapticFeedback.lightImpact();
    final text = '${context.s.shareText(widget.creation.title)}!';

    // iPad presents the share sheet as a popover and needs something to
    // point it at. Omitting the origin is not a layout nit there — UIKit
    // raises, and the share button simply crashes the app.
    final origin = _shareOrigin();

    if (_hasVideo) {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [XFile(widget.creation.videoPath!)],
          sharePositionOrigin: origin,
        ),
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
    }
  }

  Future<void> _save() async {
    if (!_hasVideo) {
      _toast(context.s.renderNotConnected);
      return;
    }

    setState(() => _saving = true);
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putVideo(widget.creation.videoPath!, album: 'Funny You');
      if (!mounted) return;
      setState(() => _saved = true);
      HapticFeedback.mediumImpact();
      _toast(context.s.savedToPhotos);
    } on GalException catch (e) {
      if (!mounted) return;
      _toast(context.s.couldNotSave(e.type.message));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.label.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }

  void _makeAnother() {
    context.read<AppState>().clearDraft();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final template = TemplateCatalog.byId(widget.creation.templateId);
    final facePhoto = context.select<AppState, String?>((s) => s.facePhotoPath);
    final s = context.s;
    final value = _controller?.value;

    // The clip decides the card's shape. Clamped because a very tall render
    // would otherwise push the title and the buttons off the screen.
    final ratio = (value?.isInitialized ?? false)
        ? value!.aspectRatio.clamp(0.62, 1.4)
        : 0.8;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        backgroundColor: const Color(0xFF070707),
        body: AuroraBackdrop(
          baseColor: const Color(0xFF070707),
          animate: false,
          blobs: const [
            AuroraBlob(
              color: Color(0x33E11D28),
              alignment: Alignment(0, -1),
              size: 1.1,
            ),
          ],
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: AspectRatio(
                    aspectRatio: ratio,
                    child: _hasVideo
                        ? VideoStage(
                            controller: _controller,
                            onClose: () => Navigator.of(context).maybePop(),
                            onShare: _share,
                            onMore: _save,
                            onToggleFullscreen: _controller == null
                                ? null
                                : () => FullscreenPlayer.open(
                                      context,
                                      _controller!,
                                    ),
                          )
                        : ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg),
                            child: TemplateArtwork(
                              template: template,
                              facePhotoPath: facePhoto,
                              iconSize: 120,
                              showPendingState: false,
                            ),
                          ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    children: [
                      VideoMetaRow(duration: value?.duration),
                      const SizedBox(height: 10),
                      Text(
                        s.youAs(template.titleIn(s)),
                        style: AppTypography.display.copyWith(fontSize: 26),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        template.taglineIn(s) ?? template.category.labelIn(s),
                        style: AppTypography.body
                            .copyWith(color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        key: _shareButtonKey,
                        label: s.shareVideo,
                        icon: Icons.ios_share_rounded,
                        onPressed: _share,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _GlassButton(
                              label: _saved ? s.saved : s.saveVideo,
                              icon: _saved
                                  ? Icons.check_circle_rounded
                                  : Icons.download_rounded,
                              loading: _saving,
                              onPressed: _save,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _GlassButton(
                              label: s.makeAnother,
                              icon: Icons.add_rounded,
                              onPressed: _makeAnother,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onPressed: loading ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            else
              Icon(icon, size: 19, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
