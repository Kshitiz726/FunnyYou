import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/app/app.dart';
import 'package:funny_you/data/templates.dart';
import 'package:funny_you/features/home/home_shell.dart';
import 'package:funny_you/features/ads/ad_break_screen.dart';
import 'package:funny_you/features/capture/photo_intro_screen.dart';
import 'package:funny_you/features/onboarding/how_it_works_screen.dart';
import 'package:funny_you/features/onboarding/welcome_screen.dart';
import 'package:funny_you/features/templates/quick_pick_screen.dart';
import 'package:funny_you/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _state(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return AppState.load();
}

/// The default 800x600 test surface is nothing like a phone; pin it to an
/// iPhone 15 logical size so layout assertions mean something.
void _useIPhoneViewport(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1179, 2556)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('first launch shows the welcome flow', (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(FunnyYouApp(state: await _state({})));
    await tester.pump();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Funny You!'), findsOneWidget);
  });

  testWidgets('the welcome screen asks one question and nothing else',
      (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(FunnyYouApp(state: await _state({})));
    await tester.pump();

    expect(
      find.text('Are you ready to make some unbelievable scenarios?'),
      findsOneWidget,
    );
    expect(find.text('Yes!'), findsOneWidget);
    // The product tour used to live here and does not any more.
    expect(find.text('Next'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('saying yes goes straight to the selfie', (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(FunnyYouApp(state: await _state({})));
    await tester.pump();

    await tester.tap(find.text('Yes!'));
    // Not pumpAndSettle: the ambient backdrop animates forever by design, so
    // settling would never complete.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PhotoIntroScreen), findsOneWidget);
    expect(
      find.textContaining("We'll start with the photo"),
      findsOneWidget,
    );
  });

  testWidgets('the photo intro puts the permission notice on its own slide',
      (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(FunnyYouApp(state: await _state({})));
    await tester.pump();

    await tester.tap(find.text('Yes!'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Slide one sells the photo and never mentions permissions.
    expect(find.text('Are you ready to take a selfie?'), findsOneWidget);
    expect(find.textContaining('tap'), findsNothing);

    await tester.tap(find.text("I'm ready"));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('One more thing'), findsOneWidget);
    expect(find.textContaining('can use the camera'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
  });

  testWidgets('the four step tour still exists, behind How it works',
      (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(
      FunnyYouApp(state: await _state({'onboarding_complete': true})),
    );
    await tester.pump();

    await tester.tap(find.text('Me'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('See how it works again'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HowItWorksScreen), findsOneWidget);
    for (final title in [
      'Take one photo',
      'Pick your favourite',
      'We make your video',
      'Watch, save and share',
    ]) {
      // findsAtLeast, not findsOne: some step copy is echoed inside the
      // phone mockup it describes.
      expect(find.text(title), findsAtLeastNWidgets(1));
      if (title != 'Watch, save and share') {
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }
    }
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('a returning user lands on the home screen', (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(
      FunnyYouApp(state: await _state({'onboarding_complete': true})),
    );
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('with a photo on file, yes leads to the ad then the picker',
      (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(
      FunnyYouApp(
        // A face photo already on file, so the flow skips the camera.
        state: await _state({'face_photo_path': 'C:/tmp/face.jpg'}),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Yes!'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The root has been swapped for the home screen underneath and the ad is
    // stacked on top. A regression here means the hand-off lost its navigator.
    expect(find.byType(AdBreakScreen), findsOneWidget);
    expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);

    // Sit through the placeholder ad.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(QuickPickScreen), findsOneWidget);
    expect(find.text('Choose your scenario'), findsOneWidget);
    expect(find.text('More scenarios'), findsOneWidget);

    // iOS has no hardware back and this route has no nav bar, so the button is
    // the only way out. Without it the screen is a dead end on the platform
    // the app ships on.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(QuickPickScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  test('the catalogue holds 40 templates across every category', () {
    expect(TemplateCatalog.all, hasLength(40));

    final ids = TemplateCatalog.all.map((t) => t.id).toSet();
    expect(ids, hasLength(40), reason: 'template ids must be unique');

    for (final category in TemplateCategory.values) {
      expect(
        TemplateCatalog.byCategory(category),
        isNotEmpty,
        reason: '${category.label} should not be empty',
      );
    }

    // Every template needs a prompt for the render backend.
    for (final template in TemplateCatalog.all) {
      expect(template.prompt.trim(), isNotEmpty);
      expect(template.gradient, hasLength(2));
    }
  });

  test('credits gate generation', () async {
    final state = await _state({});
    expect(state.canGenerate, isFalse);

    await state.addCredits(2);
    expect(state.credits, 2);
    expect(await state.consumeCredit(), isTrue);
    expect(state.credits, 1);
  });

  test('draft prompt merges template and custom text', () async {
    final state = await _state({});
    state.selectTemplate(TemplateCatalog.byId('chef'));
    state.setCustomPrompt('wearing a silly hat');

    expect(state.draftPrompt, contains('master chef'));
    expect(state.draftPrompt, endsWith('wearing a silly hat'));
  });

  test('previews are generated only for tiles visible without scrolling', () {
    final set = TemplateCatalog.previewSet;

    // Every preview is a GPU face swap (~20s). The two home-screen sections
    // overlap, so the visible tiles cost 5 generations rather than 40 - an 8x
    // saving that has to survive anyone reordering the catalogue.
    expect(set, hasLength(5));
    expect(set.map((t) => t.id).toSet(), hasLength(set.length),
        reason: 'a duplicate would be paid for twice');

    for (final template in TemplateCatalog.featured.take(
        TemplateCatalog.styleRailPreviewCount)) {
      expect(set, contains(template), reason: 'style rail tile has no preview');
    }
    for (final template
        in TemplateCatalog.all.take(TemplateCatalog.discoveryPreviewCount)) {
      expect(set, contains(template), reason: 'discovery tile has no preview');
    }
  });

  test('the catalogue beyond the free previews is locked until purchase', () async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.load();

    // Free: the four visible tiles are real art, everything else is padlocked.
    expect(state.isTemplateLocked('superhero'), isFalse);
    expect(state.isTemplateLocked('chef'), isTrue);

    await state.addCredits(5);
    expect(state.isTemplateLocked('chef'), isFalse);

    // Spending the last credit must not take the catalogue back off a customer.
    await state.consumeCredit();
    await state.consumeCredit();
    await state.consumeCredit();
    await state.consumeCredit();
    await state.consumeCredit();
    expect(state.credits, 0);
    expect(state.isTemplateLocked('chef'), isFalse,
        reason: 're-locking a paying user reads as a bug');
  });
}
