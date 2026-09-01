import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/creation_flow.dart';
import '../../core/i18n/language_sheet.dart';
import '../../core/i18n/strings.dart';
import '../../core/i18n/template_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../core/widgets/glass.dart';
import '../../services/service_locator.dart';
import '../../data/templates.dart';
import '../../state/app_state.dart';
import '../templates/widgets/template_sheet.dart';
import '../templates/template_picker_screen.dart';
import '../templates/widgets/template_tile.dart';

/// The home / create screen users land on after their first video.
///
/// Deliberately not a feed: one obvious action at the top, then the artwork.
/// Nothing here asks the user to type.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TemplateCategory? _category;

  List<VideoTemplate> get _discovery => _category == null
      ? TemplateCatalog.all
      : TemplateCatalog.byCategory(_category!);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = context.s;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        body: AuroraBackdrop(
          baseColor: AppColors.lavender,
          blobs: const [
            AuroraBlob(
              color: Color(0x44E11D28),
              alignment: Alignment(-1, -1),
              size: 0.95,
            ),
            AuroraBlob(
              color: Color(0x33E11D28),
              alignment: Alignment(1.2, -0.7),
              size: 0.7,
            ),
          ],
          child: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Greeting(
                    facePhotoPath: state.facePhotoPath,
                    credits: state.credits,
                    onAvatarTap: () => CreationFlow.retakePhoto(context),
                  ),
                ),
                const SliverToBoxAdapter(child: _PreviewBanner()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      6,
                      AppSpacing.lg,
                      0,
                    ),
                    child: FadeSlideIn(
                      child: _HeroCard(
                        facePhotoPath: state.facePhotoPath,
                        onCreate: () => _openPicker(context),
                        onChangePhoto: () =>
                            CreationFlow.retakePhoto(context),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      12,
                      AppSpacing.lg,
                      0,
                    ),
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: _QuickRow(
                        onScenarios: () => _openPicker(context),
                        onLanguage: () => LanguageSheet.show(context),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: s.chooseYourStyle,
                    action: s.viewAll,
                    onAction: () => _openPicker(context),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(
                  child: _FeaturedRail(
                    facePhotoPath: state.facePhotoPath,
                    onTap: (template) =>
                        showTemplateSheet(context, template),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: s.discovery,
                    action: s.scenarioCount(TemplateCatalog.all.length),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(
                  child: CategoryChips(
                    selected: _category,
                    onSelected: (value) => setState(() => _category = value),
                  ),
                ),
                SliverPadding(
                  // Deep enough that the last row clears the floating tab bar
                  // instead of hiding behind it.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    132,
                  ),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.74,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final template = _discovery[index];
                        return _DiscoveryCard(
                          template: template,
                          facePhotoPath: state.facePhotoPath,
                          locked: state.isTemplateLocked(template.id),
                          // Locked tiles still go into the flow — the paywall
                          // is already the next gate, so tapping one lands
                          // exactly where the padlock implies it will.
                          onTap: () =>
                              showTemplateSheet(context, template),
                        );
                      },
                      childCount: _discovery.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final template = await Navigator.of(context).push<VideoTemplate>(
      MaterialPageRoute(builder: (_) => const TemplatePickerScreen()),
    );
    if (template != null && context.mounted) {
      await showTemplateSheet(context, template);
    }
  }
}

/// Says what the GPU is doing, in words, with a real count.
///
/// Collapses to nothing when idle, so the screen is not carrying a permanent
/// status strip for something that runs once after the photo is taken.
class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = context.s;
    final store = ServiceLocator.instance.previewStore;
    final total = TemplateCatalog.previewSet.length;

    return AnimatedSize(
      duration: AppDuration.base,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !state.previewsRunning
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                4,
                AppSpacing.lg,
                4,
              ),
              child: AnimatedBuilder(
                animation: store,
                builder: (context, _) {
                  final done = TemplateCatalog.previewSet
                      .where((t) => store.pathFor(t.id) != null)
                      .length;
                  return GlassPanel(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    opacity: 0.5,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              height: 15,
                              width: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryBright,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s.makingYourPreviews,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.label.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              s.previewProgress(done, total),
                              style: AppTypography.caption.copyWith(
                                fontSize: 12,
                                color: AppColors.primaryBright,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: TweenAnimationBuilder<double>(
                            duration: AppDuration.slow,
                            curve: Curves.easeOutCubic,
                            tween: Tween(
                              begin: 0,
                              end: total == 0 ? 0 : done / total,
                            ),
                            builder: (context, value, _) =>
                                LinearProgressIndicator(
                              value: value,
                              minHeight: 5,
                              backgroundColor: AppColors.hairline,
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// The one thing the screen is for: a big, obvious way into the flow.
///
/// Backed by the featured artwork so it reads as a piece of the product rather
/// than a banner, with a scrim heavy enough to keep the headline legible over
/// whatever image lands behind it.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.facePhotoPath,
    required this.onCreate,
    required this.onChangePhoto,
  });

  final String? facePhotoPath;
  final VoidCallback onCreate;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final hero = TemplateCatalog.featured.first;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.5,
              child: TemplateArtwork(
                template: hero,
                showFace: false,
                showYouBadge: false,
                showPendingState: false,
                alignment: const Alignment(0, -0.5),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    AppColors.primaryDark.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.86),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.heroTitle,
                  style: AppTypography.display.copyWith(
                    fontSize: 30,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.heroBody,
                  style: AppTypography.body.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 18),
                PrimaryButton(
                  label: s.makeAVideo,
                  icon: Icons.auto_awesome_rounded,
                  onPressed: onCreate,
                ),
                const SizedBox(height: 10),
                _GhostButton(
                  icon: facePhotoPath == null
                      ? Icons.add_a_photo_rounded
                      : Icons.cameraswitch_rounded,
                  label: s.changeMyPhoto,
                  onPressed: onChangePhoto,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Low-emphasis action that has to sit on top of artwork, so it is glass
/// rather than a flat fill — a solid grey button here reads as a dead panel.
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.97,
      onPressed: onPressed,
      child: GlassPanel(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        opacity: 0.32,
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.button.copyWith(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three glass shortcuts under the hero: the catalogue, the library, and the
/// language switch — the last one deliberately on the first screen, because a
/// Danish user who lands in English has to be able to fix it without hunting.
class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.onScenarios, required this.onLanguage});

  final VoidCallback onScenarios;
  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lang = context.select<AppState, AppLang>((st) => st.lang);
    final creations = context.select<AppState, int>((st) => st.creations.length);

    return Row(
      children: [
        Expanded(
          child: _QuickTile(
            icon: Icons.grid_view_rounded,
            label: s.quickScenarios,
            value: '${TemplateCatalog.all.length}',
            onPressed: onScenarios,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickTile(
            icon: Icons.video_library_rounded,
            label: s.quickMyVideos,
            value: '$creations',
            onPressed: onScenarios,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickTile(
            icon: Icons.translate_rounded,
            label: s.quickLanguage,
            value: lang.short,
            onPressed: onLanguage,
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.95,
      onPressed: onPressed,
      child: GlassPanel(
        borderRadius: BorderRadius.circular(AppRadius.md),
        opacity: 0.5,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        child: Column(
          children: [
            Icon(icon, size: 21, color: AppColors.primaryBright),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyStrong.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.facePhotoPath,
    required this.credits,
    required this.onAvatarTap,
  });

  final String? facePhotoPath;
  final int credits;
  final VoidCallback onAvatarTap;

  String _timeOfDay(S s) {
    final hour = DateTime.now().hour;
    if (hour < 12) return s.goodMorning;
    if (hour < 18) return s.goodAfternoon;
    return s.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          PressableScale(
            scale: 0.92,
            onPressed: onAvatarTap,
            child: Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE11D28), AppColors.primaryDark],
                ),
                boxShadow: AppShadows.card,
              ),
              padding: const EdgeInsets.all(2.5),
              child: ClipOval(
                child: facePhotoPath != null
                    ? Image.file(
                        File(facePhotoPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _AvatarFallback(),
                      )
                    : const _AvatarFallback(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_timeOfDay(s), style: AppTypography.caption),
                const SizedBox(height: 1),
                // Danish runs longer than English and the credits pill is
                // wide, so the line shrinks rather than ellipsing away.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.readyForCloseUp,
                    maxLines: 1,
                    style: AppTypography.bodyStrong,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassPanel(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            opacity: 0.5,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.movie_creation_rounded,
                    size: 16, color: AppColors.primaryBright),
                const SizedBox(width: 6),
                Text(
                  credits == 0 ? s.noVideosLeft : s.videosLeft(credits),
                  style: AppTypography.caption.copyWith(color: AppColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: AppColors.primaryTint,
        child: Icon(Icons.person_rounded, color: AppColors.primaryBright),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.headline,
            ),
          ),
          const SizedBox(width: 12),
          if (action != null)
            PressableScale(
              onPressed: onAction,
              child: Text(
                action!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: onAction != null
                      ? AppColors.primaryBright
                      : AppColors.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeaturedRail extends StatelessWidget {
  const _FeaturedRail({required this.facePhotoPath, required this.onTap});

  final String? facePhotoPath;
  final ValueChanged<VideoTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final featured = TemplateCatalog.featured;

    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: featured.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final template = featured[index];
          return PressableScale(
            scale: 0.95,
            onPressed: () => onTap(template),
            child: SizedBox(
              width: 112,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: TemplateArtwork(
                        template: template,
                        facePhotoPath: facePhotoPath,
                        iconSize: 34,
                        locked: context.read<AppState>()
                            .isTemplateLocked(template.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    template.titleIn(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.template,
    required this.facePhotoPath,
    required this.onTap,
    this.locked = false,
  });

  final VideoTemplate template;
  final String? facePhotoPath;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    // Scenarios whose clip is not on the backend yet. The picker screen
    // already badges these; this grid did not, so the home screen offered
    // every scenario as ready and only failed once the customer had picked
    // one and waited.
    final ready = context.watch<AppState>().canRender(template.id);

    return PressableScale(
      scale: 0.96,
      onPressed: onTap,
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
                    locked: locked,
                  ),
                  if (!ready)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              s.comingSoon,
                              style: AppTypography.caption.copyWith(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      height: 32,
                      width: 32,
                      decoration: BoxDecoration(
                        color: (locked || !ready)
                            ? Colors.black.withValues(alpha: 0.6)
                            : AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.button,
                      ),
                      child: Icon(
                        !ready
                            ? Icons.schedule_rounded
                            : locked
                                ? Icons.lock_rounded
                                : Icons.play_arrow_rounded,
                        size: 19,
                        color: Colors.white,
                      ),
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
                    template.titleIn(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template.taglineIn(s) ?? template.category.labelIn(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
