import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/i18n/strings.dart';
import '../core/theme/app_theme.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/welcome_screen.dart';
import '../state/app_state.dart';
import 'creation_flow.dart';

class FunnyYouApp extends StatelessWidget {
  const FunnyYouApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: Consumer<AppState>(
        builder: (context, state, _) => MaterialApp(
          title: 'Funny You',
          debugShowCheckedModeBanner: false,
          // Drives Flutter's own widgets — date formats, the text-selection
          // menu, semantics labels — so a Danish user never meets a stray
          // English "Paste".
          locale: state.lang.locale,
          supportedLocales: AppLang.values.map((l) => l.locale),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Black + red, dark only. Pinned so the OS light-mode setting
          // cannot flip the palette out from under the brand.
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const RootScreen(),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            // Respect the user's larger-text setting, but not so far that the
            // layout breaks — this audience often runs big system text.
            minScaleFactor: 1,
            maxScaleFactor: 1.35,
            child: child!,
          ),
        ),
      ),
    );
  }
}

/// Decides once, at launch, whether this is a first run.
///
/// Deliberately *not* reactive: swapping the root out mid-journey would yank
/// the ground from under the pushed onboarding routes.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final bool _firstRun = !context.read<AppState>().hasOnboarded;

  /// The guided first-time journey.
  ///
  /// The ordering itself lives in [CreationFlow] and nowhere else. This used
  /// to re-implement it, which is how the two drifted apart: the flow gained a
  /// step and the first run kept the old one.
  Future<void> _runFirstJourney() async {
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);

    // They have said yes. Never show the welcome again, even if they back out
    // of what follows.
    await state.completeOnboarding();

    // Swap the onboarding root for the home screen *first*, so abandoning any
    // step below lands somewhere sensible instead of on a dead route. This
    // unmounts this widget, so everything after runs off the captured
    // navigator and state rather than `context`.
    unawaited(navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    ));

    // Selfie, ad, scenario, render.
    await CreationFlow.startWith(navigator: navigator, state: state);
  }

  @override
  Widget build(BuildContext context) {
    if (!_firstRun) return const HomeShell();
    return WelcomeScreen(onFinished: _runFirstJourney);
  }
}
