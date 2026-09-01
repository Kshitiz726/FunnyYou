import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/strings.dart';
import '../../core/i18n/template_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../data/models.dart';
import '../../data/templates.dart';
import '../../services/purchase_service.dart';
import '../../services/service_locator.dart';
import '../../state/app_state.dart';
import '../templates/widgets/template_tile.dart';

/// Shown right before the first render. Pops `true` once credits are granted.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.template});

  final VideoTemplate? template;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final PurchaseService _service = ServiceLocator.instance.purchases;
  late PricingPlan _plan =
      _service.plans.firstWhere((p) => p.isBestValue, orElse: () => _service.plans.first);
  bool _busy = false;

  Future<void> _buy() async {
    setState(() => _busy = true);
    final result = await _service.purchase(_plan);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.cancelled) return;

    if (!result.success) {
      _showError(result.error ?? context.s.paymentFailed);
      return;
    }

    await context.read<AppState>().addCredits(result.creditsGranted);
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop(true);
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final result = await _service.restore();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.creditsGranted > 0) {
      await context.read<AppState>().addCredits(result.creditsGranted);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      _showError(context.s.noPurchaseToRestore);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTypography.label.copyWith(
          color: Colors.white,
        )),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final template = widget.template ??
        state.selectedTemplate ??
        TemplateCatalog.byId('superhero');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        body: AuroraBackdrop(
          baseColor: AppColors.lavender,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 20, 0),
                  child: Row(
                    children: [
                      CircleIconButton(
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const Spacer(),
                      PressableScale(
                        onPressed: _busy ? null : _restore,
                        child: Text(
                          context.s.restore,
                          style: AppTypography.label.copyWith(
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FadeSlideIn(
                          child: _Header(
                            template: template,
                            facePhotoPath: state.facePhotoPath,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const FadeSlideIn(
                          delay: Duration(milliseconds: 70),
                          child: _Benefits(),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        for (var i = 0; i < _service.plans.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FadeSlideIn(
                              delay: Duration(milliseconds: 110 + i * 50),
                              child: _PlanCard(
                                plan: _service.plans[i],
                                selected: _service.plans[i] == _plan,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _plan = _service.plans[i]);
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _CheckoutBar(
                  plan: _plan,
                  busy: _busy,
                  onBuy: _buy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.template, required this.facePhotoPath});

  final VideoTemplate template;
  final String? facePhotoPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 116,
          width: 96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: TemplateArtwork(
              template: template,
              facePhotoPath: facePhotoPath,
              iconSize: 40,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.s.turnThisIntoAVideo,
                style: AppTypography.display.copyWith(fontSize: 27),
              ),
              const SizedBox(height: 6),
              Text(
                context.s.paywallBody(
                    template.titleIn(context.s).toLowerCase()),
                style: AppTypography.label,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  static const _items = [
    (Icons.hd_rounded, 'High-quality video you can keep forever'),
    (Icons.movie_filter_rounded, 'All 40 scenarios unlocked'),
    (Icons.watch_later_rounded, 'Ready in about 2 minutes'),
    (Icons.lock_rounded, 'Your photo is never shared with anyone'),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      opacity: 0.45,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (final (icon, label) in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.label.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final PricingPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.98,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: selected ? 2.4 : 1.4,
          ),
          boxShadow: selected ? AppShadows.card : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: AppDuration.fast,
              height: 24,
              width: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.hairline,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plan.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyStrong,
                        ),
                      ),
                      if (plan.badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            plan.badge!,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [plan.subtitle, plan.perVideoLabel]
                        .whereType<String>()
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              plan.priceLabel,
              maxLines: 1,
              style: AppTypography.bodyStrong.copyWith(fontSize: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.plan,
    required this.busy,
    required this.onBuy,
  });

  final PricingPlan plan;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        boxShadow: AppShadows.raised,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            children: [
              PrimaryButton(
                label: context.s.createMyVideo(plan.priceLabel),
                loading: busy,
                onPressed: onBuy,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded,
                      size: 13, color: AppColors.inkMuted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      context.s.securePayment,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
