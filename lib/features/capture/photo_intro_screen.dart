import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../services/permission_service.dart';
import '../../services/service_locator.dart';
import 'capture_screen.dart';
import 'photo_ready_screen.dart';

/// Explains *why* we need the camera before the native alert appears, over two
/// slides.
///
/// It used to be one screen: the pitch, three tips, and the camera permission
/// notice stacked at the bottom. The notice is the part that decides whether
/// the user taps Allow, and it was the part they had already scrolled past. It
/// gets a slide of its own now, immediately before the alert it describes.
///
/// There is no "use a photo I have" route any more. The app only ever works
/// from a selfie taken here and now, which keeps someone else's face out of
/// the pipeline.
///
/// Pops with the captured file path, or null if the user backs out.
class PhotoIntroScreen extends StatefulWidget {
  const PhotoIntroScreen({super.key, this.onPhotoTaken});

  /// Called with the captured file path. When null the screen pops with the
  /// path as its result instead.
  final ValueChanged<String>? onPhotoTaken;

  @override
  State<PhotoIntroScreen> createState() => _PhotoIntroScreenState();
}

class _PhotoIntroScreenState extends State<PhotoIntroScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _requesting = false;
  bool _blocked = false;

  bool get _onPermissionSlide => _page == 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    _controller.nextPage(
      duration: AppDuration.base,
      curve: Curves.easeOutCubic,
    );
  }

  /// One slide at a time, then out of the screen.
  ///
  /// Backing straight out from the permission slide would throw away the slide
  /// the user has just read, which is the one thing they would want to look at
  /// again.
  void _back() {
    if (_onPermissionSlide) {
      HapticFeedback.selectionClick();
      _controller.previousPage(
        duration: AppDuration.base,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _takePhoto() async {
    setState(() => _requesting = true);

    final permissions = ServiceLocator.instance.permissions;
    var access = await permissions.cameraStatus();
    if (access == CameraAccess.denied) {
      access = await permissions.requestCamera();
    }

    if (!mounted) return;
    setState(() => _requesting = false);

    if (access == CameraAccess.permanentlyDenied) {
      setState(() => _blocked = true);
      return;
    }

    await _capture();
  }

  /// Camera, then the confirmation beat, looping until the user is happy.
  ///
  /// Retaking from the confirmation screen has to come straight back to the
  /// camera rather than dropping the user out to this intro, which they have
  /// already read.
  Future<void> _capture() async {
    while (mounted) {
      final path = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const CaptureScreen()),
      );
      if (path == null || !mounted) return;

      final keep = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PhotoReadyScreen(photoPath: path)),
      );
      if (!mounted) return;
      if (keep != true) continue;

      if (widget.onPhotoTaken != null) {
        widget.onPhotoTaken!(path);
      } else {
        Navigator.of(context).pop(path);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        body: AuroraBackdrop(
          baseColor: AppColors.lavender,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                  child: Row(
                    children: [
                      if (_onPermissionSlide || Navigator.of(context).canPop())
                        CircleIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onPressed: _back,
                        ),
                      const Spacer(),
                      _PageDots(page: _page, count: 2),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (value) => setState(() => _page = value),
                    children: [
                      const _PitchSlide(),
                      _PermissionSlide(blocked: _blocked),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: _blocked
                      ? PrimaryButton(
                          label: s.openSettings,
                          icon: Icons.settings_rounded,
                          onPressed: () =>
                              ServiceLocator.instance.permissions.openSettings(),
                        )
                      : _onPermissionSlide
                          ? PrimaryButton(
                              label: s.takeAPicture,
                              icon: Icons.photo_camera_rounded,
                              loading: _requesting,
                              onPressed: _takePhoto,
                            )
                          : PrimaryButton(
                              label: s.imReady,
                              icon: Icons.arrow_forward_rounded,
                              onPressed: _next,
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

/// Slide one: what we need and why, plus how to take a good one.
class _PitchSlide extends StatelessWidget {
  const _PitchSlide();

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FadeSlideIn(child: _CameraGlyph()),
          const SizedBox(height: AppSpacing.xl),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: Text(
              s.photoIntroBody,
              textAlign: TextAlign.center,
              style: AppTypography.display.copyWith(fontSize: 26),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(
            delay: const Duration(milliseconds: 130),
            child: Text(
              s.photoIntroQuestion,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(fontSize: 18),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const FadeSlideIn(
            delay: Duration(milliseconds: 180),
            child: _TipList(),
          ),
        ],
      ),
    );
  }
}

/// Slide two: nothing but the permission alert that is about to appear.
class _PermissionSlide extends StatelessWidget {
  const _PermissionSlide({required this.blocked});

  /// Camera access was refused for good. The slide stops explaining what is
  /// about to be asked and starts explaining how to undo it.
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FadeSlideIn(child: _ShieldGlyph()),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Text(
                blocked ? s.cameraUnavailable : s.permissionTitle,
                textAlign: TextAlign.center,
                style: AppTypography.display.copyWith(fontSize: 26),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: Text(
                blocked ? s.permissionDenied : s.permissionExplainer,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(fontSize: 19, height: 1.5),
              ),
            ),
            if (!blocked) ...[
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                delay: const Duration(milliseconds: 200),
                child: _AllowChip(label: s.allowLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A stand-in for the button the user is about to be asked to tap, so the word
/// on this slide is the word they then see in the system alert.
class _AllowChip extends StatelessWidget {
  const _AllowChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.primary, width: 2),
        boxShadow: AppShadows.card,
      ),
      child: Text(
        label,
        style: AppTypography.bodyStrong.copyWith(
          color: AppColors.primaryBright,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppDuration.fast,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 7,
            width: i == page ? 20 : 7,
            decoration: BoxDecoration(
              color: i == page ? AppColors.primary : AppColors.hairline,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }
}

class _CameraGlyph extends StatelessWidget {
  const _CameraGlyph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: _Glyph(icon: Icons.photo_camera_rounded),
    );
  }
}

class _ShieldGlyph extends StatelessWidget {
  const _ShieldGlyph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: _Glyph(icon: Icons.lock_person_rounded),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      width: 132,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE11D28), AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(38),
        boxShadow: AppShadows.button,
      ),
      child: Icon(icon, size: 62, color: Colors.white),
    );
  }
}

class _TipList extends StatelessWidget {
  const _TipList();

  static List<(IconData, String, String)> _tipsFor(S s) => [
        (Icons.light_mode_rounded, s.tipLightTitle, s.tipLightBody),
        (
          Icons.face_retouching_natural_rounded,
          s.tipStraightTitle,
          s.tipStraightBody,
        ),
        (Icons.visibility_off_rounded, s.tipNoHatsTitle, s.tipNoHatsBody),
      ];

  @override
  Widget build(BuildContext context) {
    final tips = _tipsFor(context.s);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < tips.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.hairline),
              ),
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(tips[i].$1,
                      size: 21, color: AppColors.primaryBright),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tips[i].$2, style: AppTypography.bodyStrong),
                      const SizedBox(height: 1),
                      Text(tips[i].$3, style: AppTypography.caption),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
