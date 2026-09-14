import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../services/ad_service.dart';
import '../../services/service_locator.dart';

/// The ad that pays for one video.
///
/// Pops true once it has run its course, which is the signal to grant the
/// credit. There is deliberately no skip and no close button: the user agreed
/// to this on the screen before, and the countdown tells them exactly how long
/// it lasts so the wait never feels open ended.
class AdBreakScreen extends StatefulWidget {
  const AdBreakScreen({super.key});

  @override
  State<AdBreakScreen> createState() => _AdBreakScreenState();
}

class _AdBreakScreenState extends State<AdBreakScreen> {
  late final AdService _ads = ServiceLocator.instance.ads;
  late int _remaining = _ads.duration.inSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    // Nothing to play. Getting the user to the scenario picker matters more
    // than the placement, so this is not treated as a failure.
    if (!_ads.available) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining = (_remaining - 1).clamp(0, 999));
      if (_remaining == 0) timer.cancel();
    });

    final watched = await _ads.show();
    // Let the countdown finish even if the network reports back early,
    // otherwise the screen flashes past and reads as a glitch.
    final left = _ads.duration - Duration(seconds: _ads.duration.inSeconds - _remaining);
    if (left > Duration.zero) await Future<void>.delayed(left);

    if (!mounted) return;
    Navigator.of(context).pop(watched);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return PopScope(
      // Backing out mid-ad would hand out a free render.
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemOverlayLight,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  // Both labels can be long once translated, and the
                  // countdown grows a digit. Neither is allowed to push the
                  // other off the screen.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            s.advertisement.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              color: Colors.white70,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          s.adSkipIn(_remaining),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: AppTypography.label.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 92,
                            width: 92,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Icon(
                              Icons.play_circle_outline_rounded,
                              size: 46,
                              color: Colors.white38,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            s.adPlaceholder,
                            textAlign: TextAlign.center,
                            style: AppTypography.body.copyWith(
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: _ads.duration.inSeconds == 0
                          ? 1
                          : 1 - (_remaining / _ads.duration.inSeconds),
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
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
