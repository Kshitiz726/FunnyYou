import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/language_sheet.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';

/// First-run experience: one question, one answer.
///
/// This used to be a five page carousel that toured the whole product before
/// letting anyone near it. Someone opening the app for the first time wants to
/// start, not read a tour. The tour still exists for the people who do want
/// it, behind **Me > How it works** (`HowItWorksScreen`).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  /// Fired when the user says yes. There is no other way off this screen,
  /// which is the point.
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final s = context.s;

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
              size: 0.8,
            ),
            AuroraBlob(
              color: Color(0x33FF4B54),
              alignment: Alignment(-0.6, 1.05),
              size: 0.9,
            ),
          ],
          child: SafeArea(
            child: Column(
              children: [
                const _TopBar(),
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
                          const FadeSlideIn(child: _HeroBadge()),
                          const SizedBox(height: AppSpacing.xl),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Column(
                              children: [
                                Text(
                                  s.welcomeTo,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.title.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                ShaderMask(
                                  shaderCallback: (rect) =>
                                      const LinearGradient(
                                    colors: [
                                      Color(0xFFE11D28),
                                      Color(0xFFFF4B54),
                                    ],
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
                          const SizedBox(height: AppSpacing.lg),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 160),
                            child: Text(
                              s.welcomeQuestion,
                              textAlign: TextAlign.center,
                              style: AppTypography.body.copyWith(fontSize: 20),
                            ),
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
                    AppSpacing.lg,
                  ),
                  child: FadeSlideIn(
                    delay: const Duration(milliseconds: 240),
                    child: PrimaryButton(
                      label: s.yes,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        onFinished();
                      },
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
}

class _TopBar extends StatelessWidget {
  const _TopBar();

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
