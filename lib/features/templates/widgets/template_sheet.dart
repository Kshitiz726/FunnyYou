import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/creation_flow.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/i18n/template_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../data/templates.dart';
import '../../../state/app_state.dart';
import 'template_tile.dart';

/// The confirmation step between picking a scenario and paying for a render.
///
/// Tapping a card used to launch the creation flow immediately, which put the
/// customer into a paid, several-minute job on a single tap — with no chance to
/// see what they had chosen, and no way back. For an audience of older users
/// that is the wrong default. This shows the artwork, names the scenario and
/// asks once.
///
/// It is also where "coming soon" stops being a badge and becomes an
/// explanation: a scenario whose clip is not on the backend yet opens the sheet
/// like any other, says so plainly, and offers no button to press rather than
/// failing after the customer has committed.
Future<void> showTemplateSheet(BuildContext context, VideoTemplate template) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _TemplateSheet(template: template),
  );
}

class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({required this.template});

  final VideoTemplate template;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final state = context.watch<AppState>();
    final ready = state.canRender(template.id);
    final title = template.titleIn(s);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: TemplateArtwork(
                    template: template,
                    facePhotoPath: state.facePhotoPath,
                    iconSize: 56,
                    alignment: Alignment.topCenter,
                    showYouBadge: false,
                  ),
                ),
                // Keeps the title legible over artwork of any brightness.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.surface.withValues(alpha: 0.96),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!ready)
                  Positioned(
                    top: AppSpacing.md,
                    left: AppSpacing.md,
                    child: _SoonPill(label: s.comingSoon),
                  ),
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.45),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.title.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ready
                        ? (template.taglineIn(s) ?? template.category.labelIn(s))
                        : s.comingSoonBody,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: ready ? AppColors.inkSoft : AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (ready)
                    PrimaryButton(
                      label: s.turnMeInto(title.toLowerCase()),
                      icon: Icons.auto_awesome_rounded,
                      onPressed: () {
                        Navigator.of(context).pop();
                        CreationFlow.start(context, template: template);
                      },
                    )
                  else
                    // Deliberately not a disabled PrimaryButton: a greyed-out
                    // call to action still invites tapping, and a customer who
                    // taps something that does nothing assumes the app is
                    // broken rather than the scenario unfinished.
                    SecondaryButton(
                      label: s.closeSheet,
                      onPressed: () => Navigator.of(context).pop(),
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

class _SoonPill extends StatelessWidget {
  const _SoonPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
