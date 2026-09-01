import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/templates.dart';
import '../features/capture/photo_intro_screen.dart';
import '../features/generating/generating_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../state/app_state.dart';

/// Single entry point for "make me a video".
///
/// Owns the ordering of the gates — face photo, then payment, then render —
/// so no screen has to know what comes next.
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

    // 2. Then a credit — buy one if the user has none left.
    if (!state.canGenerate) {
      final paid = await navigator.push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PaywallScreen(template: state.selectedTemplate),
        ),
      );
      if (paid != true) return;
    }

    if (!await state.consumeCredit()) return;

    // 3. Render.
    await navigator.push(
      MaterialPageRoute(builder: (_) => const GeneratingScreen()),
    );
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
