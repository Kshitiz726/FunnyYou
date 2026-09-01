import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/backdrop.dart';
import '../../data/models.dart';
import '../../data/templates.dart';
import '../../services/generation_service.dart';
import '../../services/service_locator.dart';
import '../../state/app_state.dart';
import '../result/result_screen.dart';
import '../templates/widgets/template_tile.dart';

/// The render screen. Deliberately calm: one big ring, one clear sentence,
/// and a checklist so progress is legible even to an impatient user.
class GeneratingScreen extends StatefulWidget {
  const GeneratingScreen({super.key});

  @override
  State<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends State<GeneratingScreen> {
  final _service = ServiceLocator.instance.generation;
  StreamSubscription<GenerationProgress>? _subscription;

  GenerationProgress _progress = const GenerationProgress(
    stage: GenerationStage.uploading,
    value: 0,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.cancel();
    super.dispose();
  }

  void _start() {
    final state = context.read<AppState>();
    final template = state.selectedTemplate;

    final request = GenerationRequest(
      facePhotoPath: state.facePhotoPath ?? '',
      prompt: state.draftPrompt,
      templateId: template?.id,
    );

    _subscription = _service.generate(request).listen(
      (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
        if (progress.stage == GenerationStage.done) {
          _finish(progress.videoPath);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = context.s.somethingWentWrong);
      },
    );
  }

  Future<void> _finish(String? videoPath) async {
    final state = context.read<AppState>();
    final template = state.selectedTemplate;

    final creation = Creation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      templateId: template?.id ?? 'superhero',
      title: state.draftTitle,
      createdAt: DateTime.now(),
      source: state.draftSource,
      prompt: state.draftPrompt,
      videoPath: videoPath,
    );
    await state.addCreation(creation);

    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ResultScreen(creation: creation)),
    );
  }

  Future<void> _confirmCancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(context.s.stopMakingTitle,
            style: AppTypography.headline),
        content: Text(
          context.s.stopMakingBody,
          style: AppTypography.body.copyWith(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.s.keepGoing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.s.stop,
                style: AppTypography.label.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (leave == true && mounted) {
      await _service.cancel();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final template = state.selectedTemplate ?? TemplateCatalog.byId('superhero');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemOverlayLight,
        child: Scaffold(
          body: AuroraBackdrop(
            baseColor: AppColors.primarySoft,
            child: SafeArea(
              child: _error != null
                  ? _ErrorView(
                      message: _error!,
                      onRetry: () {
                        setState(() => _error = null);
                        _start();
                      },
                      onBack: () => Navigator.of(context).pop(),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: Row(
                            children: [
                              CircleIconButton(
                                icon: Icons.close_rounded,
                                onPressed: _confirmCancel,
                              ),
                              const Spacer(),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                            ),
                            child: Column(
                              children: [
                                const SizedBox(height: AppSpacing.md),
                                _ProgressRing(
                                  progress: _progress.value,
                                  template: template,
                                  facePhotoPath: state.facePhotoPath,
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                Text(
                                  // Not "Making your video…" — that is also a
                                  // stage label, and the two read as a stutter
                                  // when the render reaches it.
                                  context.s.justAMoment,
                                  style: AppTypography.display
                                      .copyWith(fontSize: 28),
                                ),
                                const SizedBox(height: 8),
                                AnimatedSwitcher(
                                  duration: AppDuration.base,
                                  child: Text(
                                    _progress.stage.label,
                                    key: ValueKey(_progress.stage),
                                    style: AppTypography.body
                                        .copyWith(fontSize: 17),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _RenderDetail(detail: _progress.detail),
                                const SizedBox(height: AppSpacing.lg),
                                _StageChecklist(current: _progress.stage),
                                const SizedBox(height: AppSpacing.lg),
                                _TimeHint(remaining: _progress.estimatedRemaining),
                                const SizedBox(height: AppSpacing.lg),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: Text(
                            context.s.keepScreenOpen,
                            textAlign: TextAlign.center,
                            style: AppTypography.caption,
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

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.progress,
    required this.template,
    required this.facePhotoPath,
  });

  final double progress;
  final VideoTemplate template;
  final String? facePhotoPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 226,
      width: 226,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _PulseHalo(color: template.gradient.last),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0, 1)),
            duration: AppDuration.base,
            curve: Curves.easeOut,
            builder: (context, value, _) => CustomPaint(
              size: const Size.square(226),
              painter: _RingPainter(progress: value),
            ),
          ),
          ClipOval(
            child: SizedBox(
              height: 168,
              width: 168,
              child: TemplateArtwork(
                template: template,
                facePhotoPath: facePhotoPath,
                iconSize: 58,
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${(progress * 100).round()}%',
                style: AppTypography.caption.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseHalo extends StatefulWidget {
  const _PulseHalo({required this.color});

  final Color color;

  @override
  State<_PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<_PulseHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Container(
          height: 190 + 46 * t,
          width: 190 + 46 * t,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.18 * (1 - t)),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 7;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..color = Colors.white.withValues(alpha: 0.75),
    );

    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.max(progress, 0.005) * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [
            Color(0xFFE11D28),
            Color(0xFFFF4B54),
            Color(0xFFFF4B54),
            Color(0xFFE11D28),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// The renderer's own words and numbers, verbatim.
///
/// The ring above shows overall completion, which is a blend across five
/// stages and therefore moves slowly. This line is the raw truth underneath:
/// which pass, which phase, and the exact step counter the GPU is on. During
/// the first minutes -- model loading, segmentation, pose tracking -- there is
/// no fraction to report and this is the only thing that changes, which is
/// precisely when a user most needs to see that something is happening.
class _RenderDetail extends StatelessWidget {
  const _RenderDetail({required this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDuration.base,
      // Reserve the row's height even when empty, so the checklist below does
      // not jump the moment the first detail arrives.
      child: SizedBox(
        key: ValueKey(detail),
        height: 20,
        child: detail == null
            ? const SizedBox.shrink()
            : Center(
                child: Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 0.2,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
      ),
    );
  }
}

class _StageChecklist extends StatelessWidget {
  const _StageChecklist({required this.current});

  final GenerationStage current;

  static const _stages = [
    GenerationStage.uploading,
    GenerationStage.matchingFace,
    GenerationStage.buildingScene,
    GenerationStage.rendering,
    GenerationStage.finishing,
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = current == GenerationStage.done
        ? _stages.length
        : _stages.indexOf(current);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < _stages.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  _StageDot(
                    done: i < currentIndex,
                    active: i == currentIndex,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: AppDuration.base,
                      style: AppTypography.label.copyWith(
                        color: i <= currentIndex
                            ? AppColors.ink
                            : AppColors.inkMuted,
                        fontWeight: i == currentIndex
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                      child: Text(_stages[i].label),
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

class _StageDot extends StatelessWidget {
  const _StageDot({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDuration.base,
      height: 24,
      width: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppColors.success
            : active
                ? AppColors.primary
                : AppColors.surfaceAlt,
        border: Border.all(
          color: done || active ? Colors.transparent : AppColors.hairline,
          width: 2,
        ),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : active
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : null,
    );
  }
}

class _TimeHint extends StatelessWidget {
  const _TimeHint({required this.remaining});

  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final seconds = remaining?.inSeconds ?? 0;
    final label = seconds <= 0
        ? s.almostThere
        : seconds < 60
            ? s.secondsLeft(seconds)
            : s.minutesLeft((seconds / 60).ceil());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sentiment_dissatisfied_rounded,
              size: 60, color: AppColors.inkMuted),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.display.copyWith(fontSize: 25),
          ),
          const SizedBox(height: 10),
          Text(
            context.s.creditNotUsed,
            textAlign: TextAlign.center,
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: context.s.tryAgain,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
          const SizedBox(height: 10),
          SecondaryButton(label: context.s.goBack, onPressed: onBack),
        ],
      ),
    );
  }
}
