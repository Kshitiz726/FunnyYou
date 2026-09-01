import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../data/models.dart';
import '../../data/templates.dart';
import '../../state/app_state.dart';
import '../result/result_screen.dart';
import '../templates/widgets/template_tile.dart';

/// Everything the user has made, newest first.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final creations = state.creations;

    return Scaffold(
      body: AuroraBackdrop(
        baseColor: AppColors.lavender,
        animate: false,
        child: SafeArea(
          bottom: false,
          child: creations.isEmpty
              ? _EmptyState(onCreate: onCreate)
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        child: Text(context.s.myVideos,
                            style: AppTypography.display),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        132,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.7,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _CreationCard(
                            creation: creations[index],
                            facePhotoPath: state.facePhotoPath,
                          ),
                          childCount: creations.length,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CreationCard extends StatelessWidget {
  const _CreationCard({required this.creation, required this.facePhotoPath});

  final Creation creation;
  final String? facePhotoPath;

  @override
  Widget build(BuildContext context) {
    final template = TemplateCatalog.byId(creation.templateId);

    return PressableScale(
      scale: 0.96,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(creation: creation)),
      ),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        opacity: 0.42,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TemplateArtwork(
                    template: template,
                    facePhotoPath: facePhotoPath,
                    iconSize: 40,
                  ),
                  Center(
                    child: Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 26, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(_relative(context.s, creation.createdAt),
                      style: AppTypography.caption.copyWith(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relative(S s, DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return s.justNow;
    if (diff.inHours < 1) return s.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return s.hoursAgo(diff.inHours);
    if (diff.inDays < 7) return s.daysAgo(diff.inDays);
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 108,
              width: 108,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(34),
              ),
              child: const Center(
                child: Icon(Icons.video_library_rounded,
                    size: 46, color: AppColors.primaryBright),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.s.noVideosYet,
              style: AppTypography.display.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 8),
            Text(
              context.s.noVideosYetBody,
              textAlign: TextAlign.center,
              style: AppTypography.body,
            ),
            if (onCreate != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: context.s.makeAVideo,
                icon: Icons.add_rounded,
                expand: false,
                onPressed: onCreate,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
