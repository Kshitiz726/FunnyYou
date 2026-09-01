import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../services/permission_service.dart';
import '../../services/service_locator.dart';
import 'capture_screen.dart';

/// Explains *why* we need the camera before the native iOS alert appears.
///
/// Priming like this is what keeps the permanent-denial rate low: the system
/// alert can only ever be shown once.
class PhotoIntroScreen extends StatefulWidget {
  const PhotoIntroScreen({super.key, this.onPhotoTaken});

  /// Called with the captured file path. When null the screen pops with the
  /// path as its result instead.
  final ValueChanged<String>? onPhotoTaken;

  @override
  State<PhotoIntroScreen> createState() => _PhotoIntroScreenState();
}

class _PhotoIntroScreenState extends State<PhotoIntroScreen> {
  bool _requesting = false;
  bool _blocked = false;

  Future<void> _continue() async {
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

    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );

    if (path == null || !mounted) return;
    if (widget.onPhotoTaken != null) {
      widget.onPhotoTaken!(path);
    } else {
      Navigator.of(context).pop(path);
    }
  }

  /// Use a photo they already have instead of taking a new one.
  ///
  /// Not only a fallback for a refused camera: this audience often has one
  /// photo of themselves they actually like, and being made to take a fresh
  /// selfie is exactly the step that loses them.
  Future<void> _chooseExisting() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 92,
    );
    if (file == null || !mounted) return;

    if (widget.onPhotoTaken != null) {
      widget.onPhotoTaken!(file.path);
    } else {
      Navigator.of(context).pop(file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      if (Navigator.of(context).canPop())
                        CircleIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
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
context.s.photoIntroBody,
                            textAlign: TextAlign.center,
                            style: AppTypography.display.copyWith(fontSize: 28),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 130),
                          child: Text(
context.s.photoIntroBody2,
                            textAlign: TextAlign.center,
                            style: AppTypography.body.copyWith(fontSize: 18),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const FadeSlideIn(
                          delay: Duration(milliseconds: 180),
                          child: _TipList(),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 230),
                          child: _blocked
                              ? const _BlockedNotice()
                              : const _PermissionNotice(),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    children: [
                      if (_blocked)
                        PrimaryButton(
                          label: context.s.openSettings,
                          icon: Icons.settings_rounded,
                          onPressed: () =>
                              ServiceLocator.instance.permissions.openSettings(),
                        )
                      else
                        PrimaryButton(
                          label: context.s.takeAPicture,
                          icon: Icons.photo_camera_rounded,
                          loading: _requesting,
                          onPressed: _continue,
                        ),
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: context.s.useAPhotoIHave,
                        icon: Icons.photo_library_rounded,
                        onPressed: _chooseExisting,
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

class _CameraGlyph extends StatelessWidget {
  const _CameraGlyph();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
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
        child: const Icon(
          Icons.photo_camera_rounded,
          size: 62,
          color: Colors.white,
        ),
      ),
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

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primaryTint, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
context.s.permissionExplainer,
              style: AppTypography.label.copyWith(color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedNotice extends StatelessWidget {
  const _BlockedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1013),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0xFF5A1A20), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, size: 20, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.s.permissionDenied,
              style: AppTypography.label.copyWith(color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
