import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';

/// "Just say it" input — dictation for users who would rather talk than type.
///
/// Returns the recognised text, or null if cancelled.
class VoiceSheet extends StatefulWidget {
  const VoiceSheet({super.key});

  static Future<String?> show(BuildContext context) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const VoiceSheet(),
      );

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> {
  final _speech = SpeechToText();
  String _text = '';
  double _level = 0;
  bool _available = false;
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _listening = status == 'listening');
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _error = context.s.couldNotHearYou);
        },
      );
    } catch (_) {
      _available = false;
    }

    if (!mounted) return;
    if (_available) {
      _start();
    } else {
      setState(() => _error =
          context.s.voiceUnavailable);
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _text = '';
    });
    HapticFeedback.mediumImpact();
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _text = result.recognizedWords);
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        setState(() => _level = (level.abs() / 10).clamp(0, 1));
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 45),
      ),
    );
  }

  Future<void> _stop() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 5,
                width: 44,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                _listening ? context.s.listening : context.s.tellUsYourIdea,
                style: AppTypography.title,
              ),
              const SizedBox(height: 6),
              Text(
                _error ??
                    context.s.voiceHint,
                textAlign: TextAlign.center,
                style: AppTypography.label.copyWith(
                  color: _error != null ? AppColors.danger : AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 26),
              _MicOrb(level: _level, active: _listening),
              const SizedBox(height: 26),
              AnimatedSize(
                duration: AppDuration.base,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 74),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    _text.isEmpty ? context.s.wordsAppearHere : _text,
                    style: AppTypography.body.copyWith(
                      color: _text.isEmpty
                          ? AppColors.inkMuted
                          : AppColors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: _listening ? context.s.stop : context.s.tryAgain,
                      icon: _listening
                          ? Icons.stop_rounded
                          : Icons.refresh_rounded,
                      onPressed: _available
                          ? (_listening ? _stop : _start)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: context.s.useThis,
                      icon: Icons.check_rounded,
                      onPressed: _text.trim().isEmpty
                          ? null
                          : () async {
                              await _stop();
                              if (context.mounted) {
                                Navigator.of(context).pop(_text.trim());
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicOrb extends StatelessWidget {
  const _MicOrb({required this.level, required this.active});

  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 3; i >= 1; i--)
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              height: 78 + i * 18 * (active ? 0.6 + level : 0.3),
              width: 78 + i * 18 * (active ? 0.6 + level : 0.3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.07 * i),
              ),
            ),
          Container(
            height: 78,
            width: 78,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE11D28), AppColors.primaryDark],
              ),
              boxShadow: AppShadows.button,
            ),
            child: const Icon(Icons.mic_rounded, size: 36, color: Colors.white),
          ),
          if (active)
            CustomPaint(
              size: const Size.square(150),
              painter: _WavePainter(level: level),
            ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.level});

  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.primary.withValues(alpha: 0.35);

    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(center, 44 + i * 9 + level * 14, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.level != level;
}
