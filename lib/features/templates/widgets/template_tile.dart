import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/i18n/template_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/shimmer.dart';
import '../../../data/templates.dart';
import '../../../services/preview_service.dart';
import '../../../services/service_locator.dart';
import '../../../state/app_state.dart';

/// Renders a template's artwork.
///
/// Order of preference:
/// 1. An AI preview of *this user* in the scenario, generated after they take
///    their photo (see [PreviewStore]),
/// 2. bundled reference art at `assets/templates/<id>.jpg`,
/// 3. the scenario icon on its gradient, with the user's photo inset.
///
/// Listens to the store so tiles fill in live as previews arrive.
class TemplateArtwork extends StatelessWidget {
  const TemplateArtwork({
    super.key,
    required this.template,
    this.facePhotoPath,
    this.iconSize = 34,
    this.showFace = true,
    this.locked = false,
    this.alignment = Alignment.topCenter,
    this.showYouBadge = true,
    this.showPendingState = true,
  });

  final VideoTemplate template;
  final String? facePhotoPath;
  final double iconSize;
  final bool showFace;

  /// Dim the art and show a padlock — this scenario needs a purchase.
  final bool locked;

  /// Whether this surface shows the "adding your face" state.
  ///
  /// Off for decorative backdrops — the home hero uses this artwork as a
  /// background behind its own headline, and a status pill floating over the
  /// copy there reads as a bug rather than as progress.
  final bool showPendingState;

  /// Mark a tile that is showing the user's own face rather than stock art.
  ///
  /// Off for large hero surfaces, where the picture is obviously them and a
  /// badge is just clutter.
  final bool showYouBadge;

  /// Where the crop favours when the preview and the tile disagree on shape.
  ///
  /// Previews are 3:4 with the head in the upper third, so tall tiles want
  /// [Alignment.topCenter]. Wide cards crop far more vertically and look
  /// zoomed at the top, so they pass something gentler.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final store = ServiceLocator.instance.previewStore;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: template.gradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              final preview = store.pathFor(template.id);
              if (preview != null) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(preview),
                      fit: BoxFit.cover,
                      // Centring the crop cuts the head off, which is the
                      // whole subject. See [alignment].
                      alignment: alignment,
                      // A half-written file mid-batch shouldn't blank the tile.
                      errorBuilder: (context, _, _) => _bundledOrIcon(),
                      frameBuilder: (context, child, frame, wasSync) => wasSync
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: AppDuration.base,
                              child: child,
                            ),
                    ),
                    // Says *why* this tile looks different from its neighbours.
                    if (showYouBadge && !locked)
                      const Positioned(top: 7, right: 7, child: _YouBadge()),
                  ],
                );
              }
              return _PendingArtwork(
                pending: _isPending(context),
                child: _bundledOrIcon(),
              );
            },
          ),
          if (locked) const _LockedVeil(),
        ],
      ),
    );
  }

  /// Whether this tile is waiting on a face swap that is actually in flight.
  ///
  /// Three things have to be true, and skipping any of them produces a lie: a
  /// batch is running, this scenario is one of the ones being generated, and
  /// its image has not landed yet. Shimmering all forty tiles when only five
  /// are queued is exactly the "dumb loading" this replaces.
  bool _isPending(BuildContext context) {
    if (!showPendingState || locked) return false;
    if (!TemplateCatalog.isFreePreview(template.id)) return false;
    // Read, not watch: the AnimatedBuilder above already rebuilds on store
    // changes, and `select` is illegal inside the sliver builders that host
    // these tiles.
    return Provider.of<AppState>(context, listen: true).previewsRunning;
  }

  Widget _bundledOrIcon() {
    // No face bubble under a padlock: the two circles stack into a muddle, and
    // a locked tile is not showing the user's art anyway.
    final withFace = showFace && !locked && facePhotoPath != null;

    return Image.asset(
      template.assetPath,
      fit: BoxFit.cover,
      // The bubble only earns its place on a bare gradient. Over real artwork
      // it sits squarely on the character's face — the one thing the tile is
      // there to show — so it stays inside the fallback.
      errorBuilder: (context, _, _) => _Fallback(
        template: template,
        iconSize: iconSize,
        facePhotoPath: withFace ? facePhotoPath : null,
      ),
    );
  }
}

/// Darkens a tile and marks it as needing a purchase.
///
/// Deliberately still readable — the scenario has to stay appealing enough to
/// be worth unlocking. A solid cover would just look broken.
class _LockedVeil extends StatelessWidget {
  const _LockedVeil();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
          ),
          child: const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Wraps the stock artwork while the user's own version is being generated.
///
/// The scenario stays visible and readable underneath — dimmed, shimmering,
/// with a small caption saying what is happening. A grey box would throw away
/// the one thing the tile already has: a picture worth waiting for.
class _PendingArtwork extends StatelessWidget {
  const _PendingArtwork({required this.pending, required this.child});

  final bool pending;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!pending) return child;

    // The shimmer alone says "working on it". A spinner and a caption on top
    // of a tile this size is three things competing for the same 150 square
    // pixels, and the grid shows five of them at once.
    return Shimmer(
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0x99000000),
          BlendMode.srcATop,
        ),
        child: child,
      ),
    );
  }
}

/// Marks a tile that is showing the user rather than the stock model.
class _YouBadge extends StatelessWidget {
  const _YouBadge();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      opacity: 0.45,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 10, color: AppColors.primaryBright),
          const SizedBox(width: 4),
          Text(
            context.s.thisIsYou,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.template,
    required this.iconSize,
    this.facePhotoPath,
  });

  final VideoTemplate template;
  final double iconSize;

  /// When set, the user's photo fills the tile centre and the icon steps aside
  /// into a corner badge — otherwise the two collide in the middle.
  final String? facePhotoPath;

  @override
  Widget build(BuildContext context) {
    final asBadge = facePhotoPath != null;
    final icon = Icon(
      template.icon,
      size: asBadge ? iconSize * 0.5 : iconSize,
      color: Colors.white.withValues(alpha: asBadge ? 0.85 : 0.94),
      shadows: const [Shadow(color: Color(0x40000000), blurRadius: 12)],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Soft light sweep keeps the flat gradient from looking cheap.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.5, -0.7),
              radius: 1.2,
              colors: [
                Colors.white.withValues(alpha: 0.28),
                Colors.transparent,
              ],
            ),
          ),
        ),
        if (asBadge) ...[
          Align(
            alignment: const Alignment(0, -0.15),
            child: _FaceBubble(path: facePhotoPath!, size: iconSize * 1.7),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.all(iconSize * 0.22),
              child: icon,
            ),
          ),
        ] else
          Center(child: icon),
      ],
    );
  }
}

class _FaceBubble extends StatelessWidget {
  const _FaceBubble({required this.path, required this.size});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
        boxShadow: AppShadows.card,
      ),
      child: ClipOval(
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: AppColors.surfaceAlt),
        ),
      ),
    );
  }
}

/// Grid cell in the picker: artwork, label, selection state.
class TemplateTile extends StatelessWidget {
  const TemplateTile({
    super.key,
    required this.template,
    required this.selected,
    required this.onTap,
    this.facePhotoPath,
    this.locked = false,
  });

  final VideoTemplate template;
  final bool selected;
  final VoidCallback onTap;
  final String? facePhotoPath;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.95,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: AppDuration.fast,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(selected ? 3 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md + 3),
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: TemplateArtwork(
                        template: template,
                        facePhotoPath: facePhotoPath,
                        locked: locked,
                      ),
                    ),
                  ),
                  if (!context.watch<AppState>().canRender(template.id))
                    Positioned(
                      top: 7,
                      left: 7,
                      child: _Badge(
                        icon: Icons.schedule_rounded,
                        label: context.s.comingSoon,
                      ),
                    )
                  else if (locked)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: _Badge(
                          icon: Icons.lock_rounded, label: context.s.unlock),
                    )
                  else if (template.isPremium)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: _Badge(
                          icon: Icons.star_rounded, label: context.s.premium),
                    ),
                  Positioned(
                    top: 7,
                    right: 7,
                    child: AnimatedScale(
                      scale: selected ? 1 : 0,
                      duration: AppDuration.fast,
                      curve: Curves.easeOutBack,
                      child: const CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.primary,
                        child: Icon(Icons.check_rounded,
                            size: 17, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            template.titleIn(context.s),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: selected ? AppColors.primaryBright : AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFFFF4B54)),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal category selector used on both the picker and the home screen.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.selected,
    required this.onSelected,
    this.includeAll = true,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  /// Null means "All".
  final TemplateCategory? selected;
  final ValueChanged<TemplateCategory?> onSelected;
  final bool includeAll;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final items = <TemplateCategory?>[
      if (includeAll) null,
      ...TemplateCategory.values,
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = item == selected;
          return PressableScale(
            scale: 0.94,
            onPressed: () => onSelected(item),
            child: AnimatedContainer(
              duration: AppDuration.fast,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.hairline,
                  width: 1.4,
                ),
                boxShadow: isSelected ? AppShadows.button : null,
              ),
              child: Row(
                children: [
                  Icon(
                    item?.icon ?? Icons.apps_rounded,
                    size: 16,
                    color: isSelected ? Colors.white : AppColors.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item?.labelIn(s) ?? s.categoryAll,
                    style: AppTypography.label.copyWith(
                      color: isSelected ? Colors.white : AppColors.inkSoft,
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
