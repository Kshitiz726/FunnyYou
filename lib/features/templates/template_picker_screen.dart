import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/strings.dart';
import '../../core/i18n/template_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/glass.dart';
import '../../data/templates.dart';
import '../../services/service_locator.dart';
import '../../state/app_state.dart';
import 'widgets/template_tile.dart';

/// The face-swap screen: a large live preview on top, the full 40-scenario
/// catalogue below, grouped into categories.
class TemplatePickerScreen extends StatefulWidget {
  const TemplatePickerScreen({super.key, this.onConfirmed});

  /// Called once the user commits to a scenario. Defaults to popping with the
  /// selected template.
  final ValueChanged<VideoTemplate>? onConfirmed;

  @override
  State<TemplatePickerScreen> createState() => _TemplatePickerScreenState();
}

class _TemplatePickerScreenState extends State<TemplatePickerScreen> {
  TemplateCategory? _category;
  late VideoTemplate _selected;

  @override
  void initState() {
    super.initState();
    _selected = context.read<AppState>().selectedTemplate ??
        TemplateCatalog.byId('superhero');
    // A launch-time check can lose the race with the network coming up; the
    // catalogue is the screen where the answer actually matters.
    unawaited(ServiceLocator.instance.backend.refreshIfUnknown());
  }

  List<VideoTemplate> get _visible => _category == null
      ? TemplateCatalog.all
      : TemplateCatalog.byCategory(_category!);

  void _select(VideoTemplate template) {
    HapticFeedback.selectionClick();
    setState(() => _selected = template);
  }

  void _shuffle() {
    final pool = _visible.where((t) => t != _selected).toList();
    if (pool.isEmpty) return;
    _select(pool[math.Random().nextInt(pool.length)]);
  }

  void _confirm() {
    context.read<AppState>().selectTemplate(_selected);
    if (widget.onConfirmed != null) {
      widget.onConfirmed!(_selected);
    } else {
      Navigator.of(context).pop(_selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facePhoto = context.select<AppState, String?>((s) => s.facePhotoPath);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        backgroundColor: AppColors.surfaceAlt,
        // The confirm bar is frosted; the grid has to run underneath it.
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _NavBar(count: TemplateCatalog.all.length),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _HeroPreview(
                        template: _selected,
                        facePhotoPath: facePhoto,
                        onShuffle: _shuffle,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.sm,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                context.s.quickScenarios,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.headline,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              context.s.toChooseFrom(_visible.length),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: CategoryChips(
                        selected: _category,
                        onSelected: (value) =>
                            setState(() => _category = value),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        140,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final template = _visible[index];
                            return TemplateTile(
                              template: template,
                              selected: template == _selected,
                              facePhotoPath: facePhoto,
                              locked: context
                                  .read<AppState>()
                                  .isTemplateLocked(template.id),
                              onTap: () => _select(template),
                            );
                          },
                          childCount: _visible.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _ConfirmBar(
          template: _selected,
          ready: context.watch<AppState>().canRender(_selected.id),
          onConfirm: _confirm,
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          CircleIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            elevated: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  context.s.pickYourFavourite,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyStrong,
                ),
                Text(
                  context.s.funScenarios(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _HeroPreview extends StatelessWidget {
  const _HeroPreview({
    required this.template,
    required this.facePhotoPath,
    required this.onShuffle,
  });

  final VideoTemplate template;
  final String? facePhotoPath;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: AspectRatio(
        aspectRatio: 1.08,
        child: AnimatedSwitcher(
          duration: AppDuration.base,
          switchInCurve: Curves.easeOutCubic,
          child: Container(
            key: ValueKey(template.id),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: AppShadows.raised,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TemplateArtwork(
                    template: template,
                    facePhotoPath: facePhotoPath,
                    iconSize: 96,
                    // This card is far wider than the 3:4 preview, so it crops
                    // hard vertically. Hugging the top would blow the face up
                    // to fill the card; a small bias keeps it in frame at a
                    // believable size.
                    alignment: const Alignment(0, -0.55),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.68),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(template.icon,
                                      size: 14, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      template.category.labelIn(context.s),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                template.titleIn(context.s),
                                style: const TextStyle(
                                  fontSize: 27,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: Colors.white,
                                ),
                              ),
                              if (template.taglineIn(context.s) != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  template.taglineIn(context.s)!,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        PressableScale(
                          onPressed: onShuffle,
                          child: GlassPanel(
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            opacity: 0.42,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.shuffle_rounded,
                                    size: 17,
                                    color: AppColors.primaryBright),
                                const SizedBox(width: 6),
                                Text(context.s.surpriseMe,
                                    style: AppTypography.caption
                                        .copyWith(color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.template,
    required this.ready,
    required this.onConfirm,
  });

  final VideoTemplate template;

  /// Whether the backend has a clip for this scenario yet.
  final bool ready;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      opacity: 0.72,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: ready
              ? PrimaryButton(
                  label: context.s
                      .turnMeInto(template.titleIn(context.s).toLowerCase()),
                  icon: Icons.auto_awesome_rounded,
                  onPressed: onConfirm,
                )
              // Disabled with a reason, not a dead button: this scenario has
              // no clip on the server yet, and finding that out *after* the
              // paywall is the worst possible moment.
              : PrimaryButton(
                  label: context.s.comingSoonBody,
                  icon: Icons.schedule_rounded,
                  onPressed: null,
                ),
        ),
      ),
    );
  }
}
