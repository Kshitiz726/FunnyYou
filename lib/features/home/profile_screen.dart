import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/creation_flow.dart';
import '../../core/i18n/language_sheet.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../state/app_state.dart';
import '../onboarding/welcome_screen.dart';
import '../paywall/paywall_screen.dart';

/// Account, photo and support. Deliberately short.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = context.s;

    return Scaffold(
      body: AuroraBackdrop(
        baseColor: AppColors.lavender,
        animate: false,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              132,
            ),
            children: [
              Text(s.tabMe, style: AppTypography.display),
              const SizedBox(height: AppSpacing.lg),
              _PhotoCard(
                path: state.facePhotoPath,
                onChange: () => CreationFlow.retakePhoto(context),
              ),
              const SizedBox(height: AppSpacing.md),
              _CreditsCard(
                credits: state.credits,
                onBuy: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const PaywallScreen(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsGroup(
                items: [
                  _SettingsItem(
                    icon: Icons.translate_rounded,
                    label: s.language,
                    // The one setting that has to work even when the user
                    // cannot read the screen it lives on, so it shows the
                    // current choice in its own language on the right.
                    trailing: state.lang.label,
                    onTap: () => LanguageSheet.show(context),
                  ),
                  _SettingsItem(
                    icon: Icons.replay_rounded,
                    label: s.seeHowItWorks,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WelcomeScreen(
                          onFinished: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),
                  _SettingsItem(
                    icon: Icons.privacy_tip_rounded,
                    label: s.privacyPolicy,
                  ),
                  _SettingsItem(
                    icon: Icons.description_rounded,
                    label: s.termsOfUse,
                  ),
                  _SettingsItem(
                    icon: Icons.mail_rounded,
                    label: s.contactSupport,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Text(
                  s.appVersion,
                  style: AppTypography.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.path, required this.onChange});

  final String? path;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      opacity: 0.45,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            height: 68,
            width: 68,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryTint,
            ),
            clipBehavior: Clip.antiAlias,
            child: path != null
                ? Image.file(
                    File(path!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.person_rounded,
                      color: AppColors.primaryBright,
                    ),
                  )
                : const Icon(Icons.person_rounded,
                    color: AppColors.primaryBright),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.s.yourPhoto, style: AppTypography.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  path == null
                      ? context.s.notAddedYet
                      : context.s.usedInEveryVideo,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          SecondaryButton(
            label: path == null ? context.s.add : context.s.change,
            expand: false,
            onPressed: onChange,
          ),
        ],
      ),
    );
  }
}

class _CreditsCard extends StatelessWidget {
  const _CreditsCard({required this.credits, required this.onBuy});

  final int credits;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE11D28), AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.button,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credits == 0
                      ? context.s.noVideosLeft
                      : context.s.videosLeftLong(credits),
                  style: AppTypography.headline.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  context.s.topUpAnyTime,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PressableScale(
            onPressed: onBuy,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                context.s.buyMore,
                style: AppTypography.label.copyWith(
                  color: AppColors.primaryBright,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.items});

  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      opacity: 0.45,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 56,
                color: AppColors.hairline,
              ),
            items[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// Current value, shown before the chevron.
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.99,
      onPressed: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 21, color: AppColors.primaryBright),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: AppTypography.label.copyWith(color: AppColors.ink),
              ),
            ),
            if (trailing != null) ...[
              Text(
                trailing!,
                style: AppTypography.caption.copyWith(
                  color: AppColors.primaryBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
