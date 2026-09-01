import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';
import 'strings.dart';

/// The language chooser.
///
/// A sheet rather than an inline switch: the two options are spelled out in
/// their own languages with a tick on the current one, so it works even for
/// someone who cannot read the language the app is currently in.
class LanguageSheet extends StatelessWidget {
  const LanguageSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const LanguageSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final state = context.watch<AppState>();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(s.language, style: AppTypography.headline),
              const SizedBox(height: 4),
              Text(s.languageBody, style: AppTypography.caption),
              const SizedBox(height: AppSpacing.md),
              for (final lang in AppLang.values) ...[
                _Option(
                  lang: lang,
                  selected: lang == state.lang,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    state.setLang(lang);
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  final AppLang lang;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.97,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 34,
              width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                lang.short,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.inkMuted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lang.label,
                style: AppTypography.bodyStrong.copyWith(
                  color: selected ? AppColors.ink : AppColors.inkSoft,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.primaryBright, size: 22),
          ],
        ),
      ),
    );
  }
}
