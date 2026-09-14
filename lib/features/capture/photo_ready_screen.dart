import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';

/// The beat between taking the selfie and the ad.
///
/// Two jobs. It tells the user the photo was good, which is the reassurance
/// this audience needs before handing over a couple of minutes. And it warns
/// them an ad is coming *before* it arrives, so the ad is something they
/// agreed to rather than something that happened to them.
///
/// Pops true to go on, false to go back and take the photo again.
class PhotoReadyScreen extends StatelessWidget {
  const PhotoReadyScreen({super.key, required this.photoPath});

  final String photoPath;

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        body: AuroraBackdrop(
          baseColor: AppColors.cream,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FadeSlideIn(child: _PhotoBubble(path: photoPath)),
                          const SizedBox(height: AppSpacing.xl),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 90),
                            child: Text(
                              s.youLookGreat,
                              textAlign: TextAlign.center,
                              style:
                                  AppTypography.display.copyWith(fontSize: 28),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 150),
                            child: _AdNotice(text: s.adThenPick),
                          ),
                        ],
                      ),
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
                      PrimaryButton(
                        label: s.letsGo,
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.of(context).pop(true);
                        },
                      ),
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: s.retake,
                        icon: Icons.replay_rounded,
                        onPressed: () => Navigator.of(context).pop(false),
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

class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 168,
      width: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 4),
        boxShadow: AppShadows.raised,
      ),
      child: ClipOval(
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          // The file is one we just wrote, but a missing frame here would
          // crash the happy path, so fall back to a plain glyph.
          errorBuilder: (context, error, stack) => const ColoredBox(
            color: AppColors.primaryTint,
            child: Icon(
              Icons.person_rounded,
              size: 66,
              color: AppColors.primaryBright,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdNotice extends StatelessWidget {
  const _AdNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.slideshow_rounded,
              size: 21,
              color: AppColors.primaryBright,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
