import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/templates.dart';
import '../features/ads/ad_break_screen.dart';
import '../features/capture/photo_intro_screen.dart';
import '../features/generating/generating_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/templates/quick_pick_screen.dart';
import '../state/app_state.dart';

/// Single entry point for "make me a video".
///
/// Owns the ordering of the gates so no screen has to know what comes next:
///
///   1. the selfie
///   2. the ad that pays for the render
///   3. the scenario, if one was not chosen on the way in
///   4. the render
///
/// The ad sits before the scenario on purpose. The user is told an ad is
/// coming on the screen right after their photo, and choosing a scenario is
/// the reward on the other side of it, so the wait has a visible point.
/// Someone with credits already, bought on the paywall, never sees step 2.
abstract final class CreationFlow {
  static Future<void> start(
    BuildContext context, {
    VideoTemplate? template,
    String? customPrompt,
    CreationSource source = CreationSource.template,
  }) {
    return startWith(
      navigator: Navigator.of(context),
      state: context.read<AppState>(),
      template: template,
      customPrompt: customPrompt,
      source: source,
    );
  }

  /// Context-free variant. Use this when the calling widget is about to be
  /// removed from the tree (e.g. handing off from onboarding to the home
  /// screen) and its `BuildContext` can no longer be trusted.
  static Future<void> startWith({
    required NavigatorState navigator,
    required AppState state,
    VideoTemplate? template,
    String? customPrompt,
    CreationSource source = CreationSource.template,
  }) async {
    if (template != null) state.selectTemplate(template);
    if (customPrompt != null) {
      state.setCustomPrompt(customPrompt, source: source);
    }

    // 1. We need a face before anything else.
    if (!state.hasFacePhoto) {
      final path = await navigator.push<String>(
        MaterialPageRoute(builder: (_) => const PhotoIntroScreen()),
      );
      if (path == null) return;
      await state.setFacePhoto(path);
    }

    // 2. Then a credit. An ad buys one; the paywall sells them in packs for
    //    people who would rather not watch ads.
    if (!state.canGenerate) {
      final watched = await navigator.push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const AdBreakScreen(),
        ),
      );
      if (watched != true) return;
      await state.addCredits(1);
    }

    // 3. A scenario. Skipped when the user arrived by tapping one.
    if (state.selectedTemplate == null && (state.customPrompt ?? '').isEmpty) {
      final picked = await navigator.push<VideoTemplate>(
        MaterialPageRoute(builder: (_) => const QuickPickScreen()),
      );
      if (picked == null) return;
      state.selectTemplate(picked);
    }

    if (!await state.consumeCredit()) return;

    // 4. Render.
    await navigator.push(
      MaterialPageRoute(builder: (_) => const GeneratingScreen()),
    );
  }

  /// Buy credits directly, skipping the ads. Reached from the profile.
  static Future<bool> buyCredits(BuildContext context) async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaywallScreen(
          template: context.read<AppState>().selectedTemplate,
        ),
      ),
    );
    return paid == true;
  }

  /// Replaces the stored face photo (used from the home screen and settings).
  static Future<bool> retakePhoto(BuildContext context) async {
    final state = context.read<AppState>();
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PhotoIntroScreen()),
    );
    if (path == null) return false;
    await state.setFacePhoto(path);
    return true;
  }
}
