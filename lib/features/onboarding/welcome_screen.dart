import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/language_sheet.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import 'widgets/step_scenes.dart';

/// First-run experience: a hero page followed by the four steps of the flow.
///
/// Shown once, straight after install. Every subsequent launch goes to the
/// home screen instead (see `AppRouter`).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  // Copy lives in [S]; a step only knows its number, its scene and its accent.
  static const _steps = <_OnboardingStep>[
    _OnboardingStep(step: 1, scene: CaptureScene(), accent: Color(0xFFE11D28)),
    _OnboardingStep(step: 2, scene: PickScene(), accent: Color(0xFFFF4B54)),
    _OnboardingStep(step: 3, scene: RenderScene(), accent: Color(0xFF8C8C8C)),
    _OnboardingStep(step: 4, scene: ShareScene(), accent: Color(0xFFFFFFFF)),
  ];

  int get _pageCount => _steps.length + 1;
  bool get _isLast => _page == _pageCount - 1;

  void _next() {
    if (_isLast) {
      widget.onFinished();
      return;
    }
    _controller.nextPage(
      duration: AppDuration.base,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayLight,
      child: Scaffold(
        body: AuroraBackdrop(
          baseColor: AppColors.cream,
          blobs: const [
            AuroraBlob(
              color: Color(0x55E11D28),
              alignment: Alignment(-1, -0.9),
              size: 1,
            ),
            AuroraBlob(
              color: Color(0x44E11D28),
              alignment: Alignment(1.1, -0.3),
              size: 0.8),
            AuroraBlob(
              color: Color(0x33FF4B54),
              alignment: Alignment(-0.6, 1.05),
              size: 0.9,
            ),
          ],
          child: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  showSkip: !_isLast,
                  onSkip: widget.onFinished,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pageCount,
                    onPageChanged: (value) {
                      HapticFeedback.selectionClick();
                      setState(() => _page = value);
                    },
                    itemBuilder: (context, index) => index == 0
                        ? const _HeroPage()
                        : _StepPage(step: _steps[index - 1]),
                  ),
                ),
                _BottomBar(
                  page: _page,
                  pageCount: _pageCount,
                  isLast: _isLast,
                  onNext: _next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.step,
    required this.scene,
    required this.accent,
  });

  final int step;
  final Widget scene;
  final Color accent;
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showSkip, required this.onSkip});

  final bool showSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Container(
              height: 30,
              width: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE11D28), AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 9),
            // Flexible, not fixed: the brand is the one thing here that can
            // give up room when a long language label and Skip both need it.
            const Flexible(
              child: Text(
                'Funny You',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyStrong,
              ),
            ),
            const Spacer(),
            // Deliberately on the very first screen: a Danish user who lands
            // in English has to be able to fix it before reading anything.
            PressableScale(
              onPressed: () => LanguageSheet.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.translate_rounded,
                        size: 15, color: AppColors.primaryBright),
                    const SizedBox(width: 5),
                    Text(
                      context.s.lang.short,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: showSkip ? 1 : 0,
              duration: AppDuration.fast,
              child: IgnorePointer(
                ignoring: !showSkip,
                child: PressableScale(
                  onPressed: onSkip,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      context.s.skip,
                      maxLines: 1,
                      style: AppTypography.label.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPage extends StatelessWidget {
  const _HeroPage();

  @override
  Widget build(BuildContext context) {
    // Centred on a normal phone; scrolls instead of overflowing on short
    // screens or at the largest accessibility text sizes.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FadeSlideIn(child: _HeroBadge()),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Column(
                children: [
                  Text(
                    context.s.welcomeTo,
                    textAlign: TextAlign.center,
                    style: AppTypography.title.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      colors: [Color(0xFFE11D28), Color(0xFFFF4B54)],
                    ).createShader(rect),
                    child: Text(
                      'Funny You!',
                      textAlign: TextAlign.center,
                      style: AppTypography.display.copyWith(
                        fontSize: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: Text(
                context.s.welcomeBody,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(fontSize: 18),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const FadeSlideIn(
              delay: Duration(milliseconds: 240),
              child: _FlowChips(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBadge extends StatefulWidget {
  const _HeroBadge();

  @override
  State<_HeroBadge> createState() => _HeroBadgeState();
}

class _HeroBadgeState extends State<_HeroBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -6 * Curves.easeInOut.transform(_controller.value)),
        child: child,
      ),
      child: Container(
        height: 148,
        width: 148,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE11D28), AppColors.primaryDark],
          ),
          shape: BoxShape.circle,
          boxShadow: AppShadows.raised,
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.movie_filter_rounded, size: 66, color: Colors.white),
            Positioned(
              top: 26,
              right: 30,
              child: Icon(Icons.auto_awesome_rounded,
                  size: 20, color: Color(0xFFFF4B54)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowChips extends StatelessWidget {
  const _FlowChips();

  static const _items = <(IconData, String)>[
    (Icons.photo_camera_rounded, 'Photo'),
    (Icons.style_rounded, 'Scenario'),
    (Icons.movie_creation_rounded, 'Video'),
    (Icons.ios_share_rounded, 'Share'),
  ];

  @override
  Widget build(BuildContext context) {
    // Fixed 2x2 rather than a Wrap: wrapping left a dangling arrow at the end
    // of the first row whenever the chips reflowed.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(_items.take(2).toList()),
        const SizedBox(height: 10),
        _row(_items.skip(2).toList()),
      ],
    );
  }

  Widget _row(List<(IconData, String)> items) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(items[i].$1, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(items[i].$2, style: AppTypography.caption),
              ],
            ),
          ),
          if (i < items.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: AppColors.inkMuted,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});

  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink the mockup on small phones so copy is never clipped.
        final mockupWidth =
            (constraints.maxHeight * 0.24).clamp(150.0, 210.0).toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FadeSlideIn(
                  key: ValueKey('scene-${step.step}'),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: mockupWidth,
                      child: step.scene,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                key: ValueKey('badge-${step.step}'),
                delay: const Duration(milliseconds: 60),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: step.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    context.s.stepOfFour(step.step),
                    style: AppTypography.caption.copyWith(
                      color: step.accent,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                key: ValueKey('title-${step.step}'),
                delay: const Duration(milliseconds: 110),
                child: Text(
                  context.s.stepTitle(step.step),
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(fontSize: 30),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FadeSlideIn(
                key: ValueKey('body-${step.step}'),
                delay: const Duration(milliseconds: 160),
                child: Text(
                  context.s.stepBody(step.step),
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.pageCount,
    required this.isLast,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pageCount; i++)
                AnimatedContainer(
                  duration: AppDuration.base,
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  height: 8,
                  width: i == page ? 26 : 8,
                  decoration: BoxDecoration(
                    color: i == page
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: isLast ? context.s.getStarted : context.s.next,
            icon: isLast ? Icons.arrow_forward_rounded : null,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
